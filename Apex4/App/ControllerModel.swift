// App-side model: what mode the pad is in, how we reach it (direct HID or via the helper), and the
// operations the views call. Everything blocking runs off the main actor.

import Foundation
import Observation
import IOKit
import FlydigiKit
import FlydigiHelperProtocol
import FlydigiTransport

@MainActor @Observable
final class ControllerModel {
    enum Connection: Equatable {
        case none
        case dinput                 // vendor HID interface, talked to directly
        case xinput                 // Apple's Xbox driver owns it; we go through the helper
    }

    var connection: Connection = .none
    var info: HelperDeviceInfo?
    var led: LEDConfig?
    var helperInstalled = false
    var busy = false
    var lastError: String?
    var uploadProgress: Double?   // 0…1 while a screen upload runs

    private var monitor: USBMonitor?
    /// Our own helper calls capture/release the pad, which re-enumerates it and fires USB notifications.
    /// Ignore notifications until this date so we never refresh in response to ourselves.
    private var suppressNotificationsUntil = Date.distantPast
    private var pendingNotification: Task<Void, Never>?

    init() {
        refreshHelperStatus()
        monitor = USBMonitor { [weak self] in Task { @MainActor in self?.usbChanged() } }
        Task { await refresh() }
    }

    /// Debounced USB attach/detach handling: update `connection`; fetch details only when a pad appears.
    private func usbChanged() {
        guard Date() >= suppressNotificationsUntil else { return }
        pendingNotification?.cancel()
        pendingNotification = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, Date() >= suppressNotificationsUntil else { return }
            let now = USBMonitor.currentConnection()
            if now != connection {
                connection = now
                if now == .none { info = nil; led = nil } else { await refresh() }
            }
        }
    }

    func refreshHelperStatus() {
        if #available(macOS 14.0, *) { helperInstalled = HelperClient.shared.status == .enabled }
    }

    // MARK: Discovery

    func refresh() async {
        connection = USBMonitor.currentConnection()
        refreshHelperStatus()
        guard connection != .none else { info = nil; led = nil; return }
        let conn = connection, installed = helperInstalled
        await run {
            switch conn {
            case .dinput:
                let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
                let i = try s.deviceInfo(), l = try s.readLED()
                return (HelperDeviceInfo(i), l)
            case .xinput:
                guard installed, #available(macOS 14.0, *) else { throw HelperError.notInstalled }
                return (try HelperClient.shared.deviceInfo(), try HelperClient.shared.readLED())
            case .none:
                throw HelperError.transport("no controller")
            }
        } onSuccess: { (i: HelperDeviceInfo, l: LEDConfig) in self.info = i; self.led = l }
    }

    // MARK: Actions

    func apply(led newLED: LEDConfig, persist: Bool = true) async {
        let conn = connection
        await run {
            switch conn {
            case .dinput:
                let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
                try s.applyLED(newLED, persist: persist)
            case .xinput:
                guard #available(macOS 14.0, *) else { throw HelperError.notInstalled }
                try HelperClient.shared.applyLED(newLED, persist: persist)
            case .none: throw HelperError.transport("no controller")
            }
            return newLED
        } onSuccess: { (l: LEDConfig) in self.led = l }
    }

    /// Screen uploads need XInput + helper (see docs/protocol.md §6).
    func uploadScreen(url: URL) async {
        uploadProgress = 0
        defer { uploadProgress = nil }
        let conn = connection
        await run {
            guard conn == .xinput else { throw HelperError.transport("Screen upload needs the controller in XInput mode. Use “Switch mode” below.") }
            guard #available(macOS 14.0, *) else { throw HelperError.notInstalled }
            let frames = try ImageLoader.frames(url: url)
            try HelperClient.shared.uploadScreen(frames: frames) { done, total in
                Task { @MainActor in self.uploadProgress = Double(done) / Double(total) }
            }
            return ()
        } onSuccess: { (_: Void) in }
    }

    func switchMode() async {
        let conn = connection
        await run {
            switch conn {
            case .dinput:
                let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
                try s.switchMode()
            case .xinput:
                guard #available(macOS 14.0, *) else { throw HelperError.notInstalled }
                try HelperClient.shared.switchMode()
            case .none: throw HelperError.transport("no controller")
            }
            return ()
        } onSuccess: { (_: Void) in }
        try? await Task.sleep(for: .seconds(4))          // re-enumeration + driver matching
        await refresh()
        if lastError != nil { try? await Task.sleep(for: .seconds(2)); await refresh() }
    }

    func installHelper() {
        guard #available(macOS 14.0, *) else { return }
        do { try HelperClient.shared.install() } catch { lastError = "\(error)" }
        refreshHelperStatus()
        if HelperClient.shared.status == .requiresApproval { HelperClient.shared.openLoginItemsSettings() }
    }

    func uninstallHelper() {
        guard #available(macOS 14.0, *) else { return }
        do { try HelperClient.shared.uninstall() } catch { lastError = "\(error)" }
        refreshHelperStatus()
    }

    // MARK: Plumbing

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T, onSuccess: @MainActor (T) -> Void) async {
        busy = true; lastError = nil
        suppressNotificationsUntil = .distantFuture
        defer { busy = false; suppressNotificationsUntil = Date().addingTimeInterval(4) }   // release + re-match takes ~1–2 s
        let result: Result<T, Error> = await Task.detached { Result { try work() } }.value
        switch result {
        case .success(let v): onSuccess(v)
        case .failure(let e): lastError = "\(e)"
        }
    }
}

/// Watches USB attach/detach for the pad (both VID/PIDs) and reports which mode is present.
final class USBMonitor: @unchecked Sendable {
    private let port: IONotificationPortRef
    private var iterators: [io_iterator_t] = []
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.global(qos: .utility))
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        for (vid, pid) in [(USBID.xinputVendor, USBID.xinputProduct), (USBID.dinputVendor, USBID.dinputProduct)] {
            for kind in [kIOMatchedNotification, kIOTerminatedNotification] {
                let match = IOServiceMatching("IOUSBHostDevice")! as NSMutableDictionary
                match["idVendor"] = Int(vid); match["idProduct"] = Int(pid)
                var it: io_iterator_t = 0
                let kr = IOServiceAddMatchingNotification(port, kind, match as CFDictionary, { ctx, iterator in
                    while case let s = IOIteratorNext(iterator), s != IO_OBJECT_NULL { IOObjectRelease(s) }   // drain (arms the notification)
                    Unmanaged<USBMonitor>.fromOpaque(ctx!).takeUnretainedValue().onChange()
                }, ctx, &it)
                if kr == kIOReturnSuccess {
                    while case let s = IOIteratorNext(it), s != IO_OBJECT_NULL { IOObjectRelease(s) }
                    iterators.append(it)
                }
            }
        }
    }

    static func currentConnection() -> ControllerModel.Connection {
        func present(_ vid: UInt16, _ pid: UInt16) -> Bool {
            let match = IOServiceMatching("IOUSBHostDevice")! as NSMutableDictionary
            match["idVendor"] = Int(vid); match["idProduct"] = Int(pid)
            let s = IOServiceGetMatchingService(kIOMainPortDefault, match as CFDictionary)
            if s != IO_OBJECT_NULL { IOObjectRelease(s); return true }
            return false
        }
        if present(USBID.dinputVendor, USBID.dinputProduct) { return .dinput }
        if present(USBID.xinputVendor, USBID.xinputProduct) { return .xinput }
        return .none
    }

    deinit { iterators.forEach { IOObjectRelease($0) }; IONotificationPortDestroy(port) }
}

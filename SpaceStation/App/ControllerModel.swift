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
    var firmwareUpdate: FlydigiAPI.FirmwareChip?      // newer main-chip firmware Flydigi offers, nil = up to date / unknown
    /// USB link is up but the pad has not answered yet — the 2.4 GHz receiver with the pad off, typically.
    var awaitingPad: Bool { connection != .none && info == nil }
    /// USB product string of the matched device ("Flydigi VADER3" is the charging dock's receiver).
    var usbProductName: String?
    var looksLikeReceiver: Bool { usbProductName?.localizedCaseInsensitiveContains("vader") == true }
    private var padPoll: Task<Void, Never>?
    var firmwareChecked = false
    var firmwareReport: [String] = []                 // dry-run log shown in Settings
    private var firmwareCheckedFor: String?

    private var monitor: USBMonitor?
    /// Staged profile edits (four on-board slots). Created in `init` (needs `self`); it is @Observable itself.
    @ObservationIgnored private(set) var profiles: ProfileStore!
    /// Our own helper calls capture/release the pad, which re-enumerates it and fires USB notifications.
    /// Ignore notifications until this date so we never refresh in response to ourselves.
    private var suppressNotificationsUntil = Date.distantPast
    private var pendingNotification: Task<Void, Never>?

    init() {
        profiles = ProfileStore(controller: self)
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
        usbProductName = USBMonitor.productName()
        refreshHelperStatus()
        guard connection != .none else { info = nil; led = nil; firmwareUpdate = nil; firmwareCheckedFor = nil; padPoll?.cancel(); padPoll = nil; return }
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
        if let fw = info?.firmware, firmwareCheckedFor != fw { firmwareCheckedFor = fw; Task { await checkFirmware() } }
        if info == nil {
            // Receiver plugged in with the pad off (or a pad that is still waking up): keep asking every few
            // seconds instead of leaving a stale error on screen; it appears by itself once it answers.
            firmwareUpdate = nil; firmwareCheckedFor = nil
            lastError = looksLikeReceiver
                ? String(localized: "Receiver connected. Turn the controller on (Home button) — it shows up by itself.")
                : String(localized: "The controller did not answer in time. Turn it on or reconnect the cable — it shows up by itself.")
            padPoll?.cancel()
            padPoll = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.awaitingPad, !self.busy else { return }
                await self.refresh()
            }
        } else {
            padPoll?.cancel(); padPoll = nil
        }
    }

    // MARK: Firmware (read-only for now — docs/firmware-update.md)

    /// Asks Flydigi whether a newer main-chip firmware exists for the installed one. Network only.
    func checkFirmware() async {
        guard let fw = info?.firmware, let id = info?.deviceId else { return }
        let r: Result<[String: FlydigiAPI.FirmwareChip], Error> = await Task.detached { Result { try FlydigiAPI.firmwareUpdates(deviceId: Int(id), mainChip: fw) } }.value
        firmwareChecked = true
        if case .success(let chips) = r, let main = chips["main_chip"], FirmwareVersion.isNewer(main.version, than: fw) { firmwareUpdate = main } else { firmwareUpdate = nil }
    }

    /// Downloads the offered image, validates it (size field, CRC32, boot mark) and, in DInput mode, reads
    /// the version the OTA interface reports. Writes nothing to the controller.
    func firmwareDryRun() async {
        guard let update = firmwareUpdate else { return }
        firmwareReport = ["Downloading \(update.url.lastPathComponent)…"]
        let conn = connection
        let r: Result<[String], Error> = await Task.detached {
            Result {
                var log: [String] = []
                let data = try FlydigiAPI.download(update.url)
                let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Space Station/firmware", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let file = dir.appendingPathComponent(update.url.lastPathComponent)
                try data.write(to: file)
                log.append("Downloaded \(data.count) bytes → \(file.path)")
                let img = try FirmwareImage(data: data)
                log.append(String(format: "Header: payload %d bytes, version field 0x%08x, boot mark %@", img.payloadSize, img.versionField, img.hasBootMark ? "KNLT ✓" : "missing"))
                log.append(String(format: "CRC32: file %08x, computed %08x → %@", img.storedCRC, img.computedCRC, img.crcMatches ? "match ✓" : "MISMATCH"))
                try img.validate()
                log.append("Image valid · \(img.packetCount) OTA packets of 16 bytes")
                if conn == .dinput {
                    if OTALink.isPresent() {
                        let ota = try OTALink(); defer { ota.close() }
                        let sizes = ota.reportSizes
                        log.append("OTA interface found (usage page FFEF) · report sizes in \(sizes.input) / out \(sizes.output) — ready for the flasher")
                    } else {
                        log.append("OTA interface (usage page FFEF) not present in this enumeration")
                    }
                } else {
                    log.append("Switch to DInput mode to probe the OTA interface (read-only)")
                }
                return log
            }
        }.value
        switch r {
        case .success(let log): firmwareReport = log + ["Dry run complete — nothing was written."]
        case .failure(let e): firmwareReport.append("Failed: \(e)")
        }
    }

    // MARK: Actions

    func apply(led newLED: LEDConfig, persist: Bool = true) async {
        let conn = connection
        await run {
            // Write, then read back and compare; a lost parcel would otherwise leave a half-applied effect.
            for attempt in 0..<2 {
                switch conn {
                case .dinput:
                    let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
                    try s.applyLED(newLED, persist: persist)
                    if try s.readLED().bytes == newLED.bytes { return newLED }
                case .xinput:
                    guard #available(macOS 14.0, *) else { throw HelperError.notInstalled }
                    try HelperClient.shared.applyLED(newLED, persist: persist)
                    if try HelperClient.shared.readLED().bytes == newLED.bytes { return newLED }
                case .none: throw HelperError.transport("no controller")
                }
                if attempt == 1 { throw HelperError.transport(String(localized: "The lighting did not apply completely. Try again.")) }
            }
            return newLED
        } onSuccess: { (l: LEDConfig) in self.led = l }
    }

    /// Screen uploads need XInput + helper (see docs/protocol.md §6).
    func uploadScreen(url: URL) async {
        guard let frames = try? ImageLoader.frames(url: url) else { lastError = "Cannot decode \(url.lastPathComponent)"; return }
        await uploadScreen(frames: frames)
    }

    /// Sends already-encoded LVGL frames (from the screen editor).
    @discardableResult
    func uploadScreen(frames: [[UInt8]]) async -> Bool {
        uploadProgress = 0
        defer { uploadProgress = nil }
        let conn = connection
        var ok = false
        await run {
            guard conn == .xinput else { throw HelperError.transport("Screen upload needs the controller in XInput mode. Use “Switch mode” below.") }
            guard #available(macOS 14.0, *) else { throw HelperError.notInstalled }
            try HelperClient.shared.uploadScreen(frames: frames) { done, total in
                Task { @MainActor in self.uploadProgress = Double(done) / Double(total) }
            }
            return ()
        } onSuccess: { (_: Void) in ok = true }
        return ok
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

    /// Borrow the pad for up to `seconds` and return the first key pressed (paddles included). In XInput the
    /// helper captures the USB interface, so games lose the pad for those seconds; in DInput it is read directly.
    func captureKey(seconds: Double = 5) async -> ControllerKey? {
        let conn = connection
        var result: ControllerKey? = nil
        await run({
            switch conn {
            case .none: return nil as UInt8?
            case .dinput:
                let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
                return try s.captureKey(timeout: seconds)?.rawValue
            case .xinput:
                return try HelperClient.shared.captureKey(timeoutMs: Int(seconds * 1000))
            }
        }, onSuccess: { raw in result = raw.flatMap(ControllerKey.init(rawValue:)) })
        return result
    }

    // MARK: Calibration & joystick hardware switches

    var joystickSettings: JoystickSettings?

    func loadJoystickSettings() async {
        let conn = connection
        await run({
            switch conn {
            case .dinput: let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }; return try s.readJoystickSettings()
            case .xinput: return try HelperClient.shared.readJoystickSettings()
            case .none: throw HelperError.transport("no controller")
            }
        }, onSuccess: { (j: JoystickSettings) in self.joystickSettings = j })
    }

    func setJoystickToggle(_ opt: DeviceSession.JoystickOption, enabled: Bool) async {
        let conn = connection
        await run({
            switch conn {
            case .dinput: let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }; try s.setJoystickToggle(opt, enabled: enabled)
            case .xinput: try HelperClient.shared.setJoystickOption(opt, value: enabled ? 0 : 1)
            case .none: throw HelperError.transport("no controller")
            }
        }, onSuccess: { (_: Void) in })
        await loadJoystickSettings()
    }

    /// Opens / closes the calibration window on the pad. Only the wizard calls this.
    func calibration(start: Bool) async -> Bool {
        let conn = connection
        var ok = false
        await run({
            switch conn {
            case .dinput: let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }; try s.calibration(start: start)
            case .xinput: try HelperClient.shared.calibration(start: start)
            case .none: throw HelperError.transport("no controller")
            }
        }, onSuccess: { (_: Void) in ok = true })
        return ok
    }

    // MARK: Game profiles (temporary changes that do not touch the user's remembered slot)

    func applySlot(_ slot: UInt8) async {
        let conn = connection
        await run({
            switch conn {
            case .dinput: let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }; try s.applyConfig(slot: slot)
            case .xinput: try HelperClient.shared.applySlot(slot)
            case .none: throw HelperError.transport("no controller")
            }
        }, onSuccess: { (_: Void) in })
        profiles.showTemporary(slot: slot)
    }

    /// ForceAdapt on both triggers (XInput only — the DInput form of `A5 30 06` is not known).
    func setForceAdapt(left: [UInt8], right: [UInt8]) async {
        guard connection == .xinput else { return }
        await run({
            try HelperClient.shared.setForceTrigger(side: 1, params: left)
            try HelperClient.shared.setForceTrigger(side: 2, params: right)
        }, onSuccess: { (_: Void) in })
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
        var result: Result<T, Error> = await Task.detached { Result { try work() } }.value
        if case .failure(let e) = result, "\(e)".contains("no matching report") || "\(e)".contains("timeout") {
            // Right after a mode switch or re-enumeration the pad ignores the first request; try once more.
            try? await Task.sleep(for: .seconds(1.5))
            result = await Task.detached { Result { try work() } }.value
        }
        switch result {
        case .success(let v): onSuccess(v)
        case .failure(let e):
            let text = "\(e)"
            lastError = text.contains("no matching report") || text.contains("timeout") ? String(localized: "The controller did not answer in time. Press refresh to try again.") : text
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

    /// "USB Product Name" of whichever pad device is present (the receiver announces itself as "Flydigi VADER3").
    static func productName() -> String? {
        for (vid, pid) in [(USBID.dinputVendor, USBID.dinputProduct), (USBID.xinputVendor, USBID.xinputProduct)] {
            let match = IOServiceMatching("IOUSBHostDevice")! as NSMutableDictionary
            match["idVendor"] = Int(vid); match["idProduct"] = Int(pid)
            let s = IOServiceGetMatchingService(kIOMainPortDefault, match as CFDictionary)
            guard s != IO_OBJECT_NULL else { continue }
            defer { IOObjectRelease(s) }
            if let n = IORegistryEntryCreateCFProperty(s, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String { return n }
        }
        return nil
    }

    deinit { iterators.forEach { IOObjectRelease($0) }; IONotificationPortDestroy(port) }
}

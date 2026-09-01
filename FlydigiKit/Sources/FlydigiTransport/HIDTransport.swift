// DInput transport: the controller's vendor HID interface (04b4:2412, interface 2, usage page 0xFFA0),
// driven with IOHIDManager. Unprivileged.

import Foundation
import IOKit.hid
import FlydigiKit

public enum TransportError: Error, CustomStringConvertible {
    case notFound(String)
    case io(String)
    case timeout(String)
    case protocolError(String)
    public var description: String {
        switch self {
        case .notFound(let s), .io(let s), .timeout(let s), .protocolError(let s): return s
        }
    }
}

/// A byte-level link to the controller: write a packet, receive reports.
public protocol Link: AnyObject, Sendable {
    var channel: Channel { get }
    func write(_ packet: [UInt8]) throws
    /// Waits up to `timeout` for a report satisfying `match`; returns its result.
    func waitForReport<T>(timeout: TimeInterval, _ match: @Sendable @escaping ([UInt8]) -> T?) throws -> T
    func close()
}

public final class HIDLink: Link, @unchecked Sendable {
    public let channel: Channel = .dinput
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let queue = DispatchQueue(label: "flydigi.hid")
    private let lock = NSLock()
    private var inbox: [[UInt8]] = []
    private let arrived = DispatchSemaphore(value: 0)
    private var reportBuffer = [UInt8](repeating: 0, count: 64)

    /// Opens the vendor interface of the first Apex 4 found in DInput mode.
    public init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Int(USBID.dinputVendor),
            kIOHIDProductIDKey: Int(USBID.dinputProduct),
            kIOHIDPrimaryUsagePageKey: Int(USBID.dinputVendorUsagePage),
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let dev = set.first else {
            throw TransportError.notFound("Apex 4 not found in DInput mode (04b4:2412). Plug it in over USB and switch to DInput.")
        }
        device = dev
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            throw TransportError.io("IOHIDDeviceOpen failed")
        }
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        reportBuffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceRegisterInputReportCallback(device, buf.baseAddress!, buf.count, { ctx, _, _, _, reportId, report, length in
                let me = Unmanaged<HIDLink>.fromOpaque(ctx!).takeUnretainedValue()
                var bytes = [UInt8](repeating: 0, count: Int(length) + 1)
                bytes[0] = UInt8(reportId)                       // keep the same layout as hidapi: report id first
                for i in 0..<Int(length) { bytes[i + 1] = report[i] }
                me.lock.lock(); me.inbox.append(bytes); me.lock.unlock(); me.arrived.signal()
            }, ctx)
        }
        // Pump the main run loop from a background thread if nobody else does (CLI use).
        RunLoopPump.ensureRunning()
    }

    public func write(_ packet: [UInt8]) throws {
        let id = CFIndex(packet[0])
        let body = Array(packet.dropFirst())
        let r = body.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, id, $0.baseAddress!, $0.count) }
        guard r == kIOReturnSuccess else { throw TransportError.io(String(format: "IOHIDDeviceSetReport failed: 0x%08x", r)) }
    }

    public func waitForReport<T>(timeout: TimeInterval, _ match: @Sendable @escaping ([UInt8]) -> T?) throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock()
            while !inbox.isEmpty {
                let r = inbox.removeFirst()
                if let v = match(r) { lock.unlock(); return v }
            }
            lock.unlock()
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { throw TransportError.timeout("no matching report within \(timeout)s") }
            _ = arrived.wait(timeout: .now() + remaining)
        }
    }

    public func close() {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

/// Keeps the main CFRunLoop spinning for IOKit callbacks when running as a command-line tool.
enum RunLoopPump {
    nonisolated(unsafe) private static var started = false
    static func ensureRunning() {
        guard !started else { return }
        started = true
        if Thread.isMainThread && !RunLoop.main.isRunningInsideApp {
            Thread { while true { CFRunLoopRunInMode(.defaultMode, 0.05, false) } }.start()
        }
    }
}

private extension RunLoop {
    /// Heuristic: inside an app the main run loop is already driven by NSApplication.
    var isRunningInsideApp: Bool { Bundle.main.bundleIdentifier != nil && ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] != nil }
}

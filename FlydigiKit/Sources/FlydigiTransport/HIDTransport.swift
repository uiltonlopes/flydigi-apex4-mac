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
    /// Close without resetting/re-enumerating the device (use right after a mode-switch command,
    /// which makes the controller re-enumerate on its own — a reset would abort the switch).
    func closeWithoutReset()
}

public extension Link { func closeWithoutReset() { close() } }

public final class HIDLink: Link, @unchecked Sendable {
    public let channel: Channel = .dinput
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let queue = DispatchQueue(label: "flydigi.hid")
    private let lock = NSLock()
    private var inbox: [[UInt8]] = []
    private let arrived = DispatchSemaphore(value: 0)
    private let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

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
        // Dispatch-queue based delivery (no run loop needed — works in the app, the CLI and the daemon).
        IOHIDDeviceSetDispatchQueue(device, queue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        do {
            IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, 64, { ctx, _, _, _, reportId, report, length in
                let me = Unmanaged<HIDLink>.fromOpaque(ctx!).takeUnretainedValue()
                // For devices with numbered reports IOHIDManager already delivers the report id as byte 0
                // (same layout as hidapi), so the buffer is used as-is.
                _ = reportId
                let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
                me.lock.lock(); me.inbox.append(bytes); if me.inbox.count > 512 { me.inbox.removeFirst() }; me.lock.unlock()
                me.arrived.signal()
            }, ctx)
        }
        IOHIDDeviceActivate(device)
    }

    public func write(_ packet: [UInt8]) throws {
        // Like hidapi on macOS: the buffer handed to IOHIDDeviceSetReport keeps the report-id byte in
        // front — that is the byte layout the Flydigi firmware expects (verified: stripping it gets no reply).
        let id = CFIndex(packet[0])
        let r = packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, id, $0.baseAddress!, $0.count) }
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
        guard !closed else { return }
        closed = true
        IOHIDDeviceCancel(device)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
    private var closed = false
}

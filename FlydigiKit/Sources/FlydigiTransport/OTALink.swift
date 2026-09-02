// The controller's OTA HID interface (DInput mode, 04b4:2412, usage page 0xFFEF, report id 5, 64-byte
// reports) — see docs/firmware-update.md. This file only implements the read-only parts (find the
// interface, ask the version). Flashing is deliberately not implemented yet.

import Foundation
import IOKit.hid
import FlydigiKit

public final class OTALink: @unchecked Sendable {
    public static let usagePageMain: UInt32 = 0xFFEF
    public static let usagePageDongle: UInt32 = 0xFFEE
    public static let reportId: UInt8 = 5
    public static let reportLength = 64

    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let queue = DispatchQueue(label: "flydigi.ota")
    private let lock = NSLock()
    private var inbox: [[UInt8]] = []
    private let arrived = DispatchSemaphore(value: 0)
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var closed = false

    /// Present without opening anything (safe to call any time).
    public static func isPresent(usagePage: UInt32 = usagePageMain) -> Bool {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: Int(USBID.dinputVendor), kIOHIDProductIDKey: Int(USBID.dinputProduct), kIOHIDPrimaryUsagePageKey: Int(usagePage)] as CFDictionary)
        let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>
        return !(set ?? []).isEmpty
    }

    public init(usagePage: UInt32 = usagePageMain) throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Int(USBID.dinputVendor), kIOHIDProductIDKey: Int(USBID.dinputProduct), kIOHIDPrimaryUsagePageKey: Int(usagePage)] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let dev = set.first else {
            throw TransportError.notFound("OTA interface (usage page \(String(usagePage, radix: 16))) not found — the controller must be in DInput mode over the cable.")
        }
        device = dev
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { throw TransportError.io("IOHIDDeviceOpen (OTA) failed") }
        IOHIDDeviceSetDispatchQueue(device, queue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { ctx, _, _, _, _, report, length in
            let me = Unmanaged<OTALink>.fromOpaque(ctx!).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
            me.lock.lock(); me.inbox.append(bytes); if me.inbox.count > 64 { me.inbox.removeFirst() }; me.lock.unlock()
            me.arrived.signal()
        }, ctx)
        IOHIDDeviceActivate(device)
    }

    /// Report descriptor sizes, for diagnostics.
    public var reportSizes: (input: Int, output: Int) {
        let i = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
        let o = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        return (i, o)
    }

    /// Builds a 64-byte OTA report (`05 02 <len> 00 payload…`) exactly like Space Station's flasher.
    public static func report(payload: [UInt8]) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: reportLength)
        r[0] = reportId; r[1] = 0x02; r[2] = UInt8(payload.count); r[3] = 0
        for (i, b) in payload.enumerated() where 4 + i < reportLength { r[4 + i] = b }
        return r
    }

    private func write(_ report: [UInt8]) throws {
        let r = report.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), $0.baseAddress!, $0.count) }
        guard r == kIOReturnSuccess else { throw TransportError.io(String(format: "OTA SetReport failed: 0x%08x", r)) }
    }

    private func read(timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock(); let r = inbox.isEmpty ? nil : inbox.removeFirst(); lock.unlock()
            if let r { return r }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return nil }
            _ = arrived.wait(timeout: .now() + remaining)
        }
    }

    /// Read-only: `0xFF00` version query. Reply `05 01 08 00 <version u32 LE> <crc u32 LE>` (Space Station's
    /// tool parses this shape but never sends the query, so the reply layout is inferred).
    public func queryVersion(timeout: TimeInterval = 1.5) throws -> (raw: [UInt8], version: UInt32?, crc: UInt32?) {
        lock.lock(); inbox.removeAll(); lock.unlock()
        try write(OTALink.report(payload: [0x00, 0xFF]))
        guard let r = read(timeout: timeout) else { throw TransportError.timeout("no reply to the OTA version query") }
        if r.count >= 12, r[0] == 5, r[1] == 1, r[2] == 8 {
            func u32(_ o: Int) -> UInt32 { UInt32(r[o]) | UInt32(r[o + 1]) << 8 | UInt32(r[o + 2]) << 16 | UInt32(r[o + 3]) << 24 }
            return (r, u32(4), u32(8))
        }
        return (r, nil, nil)
    }

    public func close() {
        guard !closed else { return }
        closed = true
        IOHIDDeviceCancel(device); IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)); IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

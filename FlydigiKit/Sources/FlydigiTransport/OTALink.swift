// The controller's OTA HID interface (DInput mode, 04b4:2412, usage page 0xFFEF, report id 5, 64-byte
// reports) — see docs/firmware-update.md. `flash` streams a Telink OTA exactly the way Space Station's
// FirmwareConsole does (START, DATA in 1–3 packets per report, END), one report in flight, ack-paced.
// Nothing here switches modes or downloads; callers gate it on an explicit user confirmation.

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

    /// 64-byte OTA report (`05 02 <len> 00 payload…`), see `OTAPacket`.
    public static func report(payload: [UInt8]) -> [UInt8] { OTAPacket.report(payload: payload) }

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

    // MARK: Flashing (docs/firmware-update.md §3)

    public enum OTAError: Error, CustomStringConvertible, Sendable {
        case noAck(stage: String)
        case deviceError(code: UInt8, stage: String)
        public var description: String {
            switch self {
            case .noAck(let st): "controller stopped answering during \(st)"
            case .deviceError(let c, let st): "controller reported OTA error \(c) (\(OTAError.name(c))) during \(st)"
            }
        }
        /// Telink OTA result codes (inferred, see docs).
        public static func name(_ c: UInt8) -> String {
            switch c {
            case 0: "success"; case 1: "packet loss"; case 2: "data CRC"; case 3: "flash write"; case 4: "incomplete"
            case 5: "flow"; case 6: "firmware check"; case 7: "version"; case 8: "PDU length"; case 9: "firmware mark"; case 10: "firmware size"
            default: "unknown"
            }
        }
    }

    public enum FlashOutcome: Sendable, Equatable {
        /// The pad answered END with the OTA result report and code 0.
        case confirmed
        /// END was sent and acknowledged but no result report arrived before the timeout (Space Station never
        /// waits for it either: the pad reboots into the new image right away).
        case sentNoResult
    }

    /// Waits for the pad's acknowledgement of the last report (any report with id 5, as Space Station does);
    /// an OTA result report with a non-zero code aborts.
    private func awaitAck(stage: String, timeout: TimeInterval, trace: ((String) -> Void)?) throws -> [UInt8] {
        guard let r = read(timeout: timeout) else { throw OTAError.noAck(stage: stage) }
        trace?("\(stage) ← " + r.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "))
        if let code = OTAPacket.resultCode(r), code != 0 { throw OTAError.deviceError(code: code, stage: stage) }
        return r
    }

    /// Streams `image` to the controller. `progress(sent, total)` is called per report. Blocking; run it off
    /// the main thread. The caller must already have validated the image and confirmed with the user.
    public func flash(_ image: FirmwareImage, packetsPerReport: Int = 3, ackTimeout: TimeInterval = 3,
                      resultTimeout: TimeInterval = 10, trace: ((String) -> Void)? = nil,
                      progress: (Int, Int) -> Void) throws -> FlashOutcome {
        let per = max(1, min(3, packetsPerReport))
        let total = image.packetCount
        lock.lock(); inbox.removeAll(); lock.unlock()

        try write(OTALink.report(payload: OTAPacket.startPayload))
        _ = try awaitAck(stage: "START", timeout: ackTimeout, trace: trace)

        var index = 0
        while index < total {
            var payload: [UInt8] = []
            let n = min(per, total - index)
            for k in 0..<n { payload += OTAPacket.packet(index: index + k, block: image.block(index + k)) }
            try write(OTALink.report(payload: payload))
            _ = try awaitAck(stage: "DATA \(index)", timeout: ackTimeout, trace: index < 3 ? trace : nil)
            index += n
            progress(index, total)
        }

        try write(OTALink.report(payload: OTAPacket.endPayload(lastIndex: total - 1)))
        // The reply to END is either a plain ack followed by the result report, or the result report itself.
        let deadline = Date().addingTimeInterval(resultTimeout)
        while let r = read(timeout: max(0.05, deadline.timeIntervalSinceNow)) {
            trace?("END ← " + r.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "))
            if let code = OTAPacket.resultCode(r) {
                if code == 0 { return .confirmed }
                throw OTAError.deviceError(code: code, stage: "END")
            }
        }
        return .sentNoResult
    }

    public func close() {
        guard !closed else { return }
        closed = true
        IOHIDDeviceCancel(device); IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)); IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

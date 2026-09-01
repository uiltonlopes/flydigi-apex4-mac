// High-level operations on a connected Apex 4, independent of channel.
// Sequencing rules come from docs/protocol.md; timeouts from what the hardware showed.

import Foundation
import FlydigiKit

public final class DeviceSession: @unchecked Sendable {
    public let link: Link
    public var channel: Channel { link.channel }
    public var configId: UInt8 = 0

    public init(link: Link) { self.link = link }

    /// Opens whichever mode the controller is currently in. XInput needs root.
    public static func open(preferring: Channel? = nil) throws -> DeviceSession {
        var errors: [String] = []
        for ch in [preferring, .dinput, .xinput].compactMap({ $0 }) where !(ch == .xinput && getuid() != 0 && preferring != .xinput) {
            do {
                switch ch {
                case .dinput: return DeviceSession(link: try HIDLink())
                case .xinput: return DeviceSession(link: try USBLink())
                }
            } catch { errors.append("\(ch): \(error)") }
        }
        throw TransportError.notFound(errors.joined(separator: "\n"))
    }

    public func close() { link.close() }

    // MARK: Info

    public func deviceInfo() throws -> DeviceInfo {
        switch channel {
        case .xinput:
            try link.write(XInput.command(XInput.Cmd.deviceInfo))
            return try link.waitForReport(timeout: 2) { XInputReply.deviceInfo($0) }
        case .dinput:
            try link.write(DInput.command(DInput.Cmd.deviceInfo))
            return try link.waitForReport(timeout: 2) { DInputReply.deviceInfo($0) }
        }
    }

    // MARK: Blobs

    public func readBlob(_ kind: BlobKind) throws -> [UInt8] {
        let length = kind == .config ? 790 : LEDConfig.length
        var asm = BlobAssembler(expectedLength: length)
        switch channel {
        case .xinput: try link.write(XInput.readBlob(kind: kind, configId: configId))
        case .dinput: try link.write(DInput.readBlob(kind: kind, configId: configId))
        }
        let deadline = Date().addingTimeInterval(4)
        while !asm.isComplete {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw TransportError.timeout("blob read incomplete") }
            let parcel: (index: Int, data: [UInt8]) = try link.waitForReport(timeout: remaining) { r in
                switch self.channel {
                case .xinput: return XInputReply.blobParcel(r, kind: kind)
                case .dinput: return DInputReply.blobParcel(r, kind: kind)
                }
            }
            asm.add(index: parcel.index, data: parcel.data)
        }
        return asm.assemble()!
    }

    /// Writes a blob parcel by parcel, waiting for each ack. Returns acks received / packets sent.
    @discardableResult
    public func writeBlob(_ blob: [UInt8], kind: BlobKind) throws -> (acks: Int, packets: Int) {
        let packets: [[UInt8]]
        switch channel {
        case .xinput: packets = XInput.writeParcels(blob, kind: kind, configId: configId)
        case .dinput: packets = DInput.writeParcels(blob, kind: kind, configId: configId)
        }
        var acks = 0
        for p in packets {
            try link.write(p)
            let ok: Bool? = try? link.waitForReport(timeout: 1) { r in
                switch self.channel {
                case .xinput: return XInputReply.writeAck(r, kind: kind).map { _ in true }
                case .dinput: return DInputReply.writeAck(r).map { _ in true }
                }
            }
            if ok == true { acks += 1 }
        }
        return (acks, packets.count)
    }

    public func readLED() throws -> LEDConfig {
        guard let cfg = LEDConfig(bytes: try readBlob(.led)) else { throw TransportError.protocolError("bad LED blob") }
        return cfg
    }

    /// Applies an LED config the way the firmware wants it on each channel and persists it.
    /// XInput: the pad ignores a standalone LED write, so the current config blob is re-written first.
    public func applyLED(_ led: LEDConfig, persist: Bool = true) throws {
        if channel == .xinput {
            let cfg = try readBlob(.config)
            try writeBlob(cfg, kind: .config)
            Thread.sleep(forTimeInterval: 0.5)
        }
        try writeBlob(led.bytes, kind: .led)
        if persist { try saveToFlash() }
    }

    // MARK: Persistence

    public func saveToFlash() throws {
        let current: (id: UInt16, configId: UInt8)
        switch channel {
        case .xinput:
            try link.write(XInput.readRandomId(configId: configId))
            current = try link.waitForReport(timeout: 2) { XInputReply.randomId($0) }
            try link.write(XInput.saveToFlash(randomId: current.id &+ 1))
            let ok: Bool = try link.waitForReport(timeout: 3) { XInputReply.saveToFlashOK($0) }
            guard ok else { throw TransportError.protocolError("save to flash rejected") }
        case .dinput:
            try link.write(DInput.readRandomId(configId: configId))
            current = try link.waitForReport(timeout: 2) { DInputReply.randomId($0) }
            try link.write(DInput.saveToFlash(randomId: current.id &+ 1))
            let ok: Bool = try link.waitForReport(timeout: 3) { DInputReply.saveToFlashOK($0) }
            guard ok else { throw TransportError.protocolError("save to flash rejected") }
        }
    }

    // MARK: Screen

    public struct UploadProgress: Sendable {
        public var frame: Int, frames: Int, bytesSent: Int, totalBytes: Int
        public var fraction: Double { totalBytes == 0 ? 0 : Double(bytesSent) / Double(totalBytes) }
    }

    /// Uploads LVGL frames to the LCD. XInput only (the DInput firmware path is broken, see protocol.md §6).
    public func uploadScreen(frames: [[UInt8]], progress: ((UploadProgress) -> Void)? = nil) throws {
        guard channel == .xinput else { throw TransportError.protocolError("screen upload requires XInput mode") }
        let plan = ScreenUploadPlan(frames: frames)
        var sent = 0
        for step in plan.steps() {
            var attempts = 0
            while true {
                attempts += 1
                try link.write(step.packet)
                let ack: ScreenAck? = try? link.waitForReport(timeout: step.expectedAck == XInput.Cmd.screenData ? 1.5 : 3) { r in
                    XInputReply.screenAck(r).flatMap { $0.cmd == step.expectedAck ? $0 : nil }
                }
                if let ack, ack.ret == 0 { break }
                if attempts >= 5 { throw TransportError.timeout("no ack for \(step) after \(attempts) attempts") }
            }
            if case let .data(frame, offset, _) = step {
                sent += min(Screen.chunk, frames[frame - 1].count - offset)
                progress?(UploadProgress(frame: frame, frames: frames.count, bytesSent: sent, totalBytes: plan.totalBytes))
            }
        }
    }

    // MARK: Mode

    /// Asks the controller to re-enumerate in the other mode. The link becomes invalid afterwards.
    public func switchMode() throws {
        switch channel {
        case .xinput: try link.write(XInput.command(XInput.Cmd.switchToDInput))
        case .dinput: try link.write(DInput.command(DInput.Cmd.switchToXInput))
        }
    }
}

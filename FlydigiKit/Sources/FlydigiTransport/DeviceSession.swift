// High-level operations on a connected Apex 4, independent of channel.
// Sequencing rules come from docs/protocol.md; timeouts from what the hardware showed.

import Foundation
import FlydigiKit

public final class DeviceSession: @unchecked Sendable {
    public let link: Link
    public var channel: Channel { link.channel }
    public var configId: UInt8 = 0

    public init(link: Link) { self.link = link }

    /// Opens the controller. DInput is tried by default; **XInput is only attempted when explicitly
    /// requested** — the IOUSBHost capture path triggered a kernel panic on macOS 26.6 (2026-09-01,
    /// see docs/architecture.md) and is being reworked. Never run it casually.
    public static func open(preferring: Channel? = nil) throws -> DeviceSession {
        var errors: [String] = []
        let candidates: [Channel] = preferring == .xinput ? [.xinput] : [.dinput]
        for ch in candidates {
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
        link.discardPending()                                   // parcels left over from a previous read must not leak in
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
        Thread.sleep(forTimeInterval: 0.03); link.discardPending()   // trailing duplicates the pad sometimes appends
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
            let ok: Bool? = try? link.waitForReport(timeout: 1) { (r: [UInt8]) -> Bool? in
                switch self.channel {
                case .xinput: return XInputReply.writeAck(r, kind: kind) == nil ? nil : true
                case .dinput: return DInputReply.writeAck(r) == nil ? nil : true
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

    /// Set APEX4_DEBUG=1 to log screen acks to stderr.
    nonisolated(unsafe) public static var debug = ProcessInfo.processInfo.environment["APEX4_DEBUG"] != nil

    public struct UploadProgress: Sendable {
        public var frame: Int, frames: Int, bytesSent: Int, totalBytes: Int
        public var fraction: Double { totalBytes == 0 ? 0 : Double(bytesSent) / Double(totalBytes) }
    }

    /// Uploads LVGL frames to the LCD. XInput only (the DInput firmware path is broken, see protocol.md §6).
    public func uploadScreen(frames: [[UInt8]], progress: ((UploadProgress) -> Void)? = nil) throws {
        let total = frames.reduce(0) { $0 + $1.count }
        var sent = 0
        for (i, frame) in frames.enumerated() {
            try uploadScreenFrame(frame, index: i + 1, of: frames.count) { bytes in
                progress?(UploadProgress(frame: i + 1, frames: frames.count, bytesSent: sent + bytes, totalBytes: total))
            }
            sent += frame.count
        }
        try finishScreenUpload(frameCount: frames.count)
    }

    /// One frame (start → data → end). The helper drives uploads frame by frame through this.
    public func uploadScreenFrame(_ frame: [UInt8], index: Int, of total: Int, progress: ((Int) -> Void)? = nil) throws {
        guard channel == .xinput else { throw TransportError.protocolError("screen upload requires XInput mode") }
        var sent = 0
        for step in ScreenUploadPlan.frameSteps(frame, index: index, of: total) {
            try perform(step)
            if case let .data(_, offset, _) = step { sent = min(offset + Screen.chunk, frame.count); progress?(sent) }
        }
    }

    public func finishScreenUpload(frameCount: Int) throws {
        try perform(ScreenUploadPlan.endAllStep(frameCount: frameCount))
    }

    private func perform(_ step: ScreenUploadPlan.Step) throws {
        var attempts = 0
        while true {
            attempts += 1
            try link.write(step.packet)
            let accepted = step.acceptedAcks
            let debug = Self.debug
            let attempt = attempts
            let t0 = Date()
            // Explicit closure type: with `try?` alone Swift may infer T = ScreenAck?, turning a
            // non-matching report into a "match" whose value is nil (instant false timeout).
            let ack: ScreenAck? = try? link.waitForReport(timeout: step.isData ? 1.5 : 3) { (r: [UInt8]) -> ScreenAck? in
                guard let a = XInputReply.screenAck(r) else { return nil }
                if debug, !step.isData || !accepted.contains(a.cmd) || a.ret != 0 {
                    FileHandle.standardError.write("  ack cmd=\(String(a.cmd, radix: 16)) ret=\(a.ret) value=\(a.value) for \(step.debugName) attempt \(attempt)\n".data(using: .utf8)!)
                }
                return accepted.contains(a.cmd) ? a : nil
            }
            if debug, ack == nil { FileHandle.standardError.write("  no ack for \(step.debugName) attempt \(attempts) (\(String(format: "%.2f", Date().timeIntervalSince(t0)))s)\n".data(using: .utf8)!) }
            if let ack, ack.ret == 0 { return }
            if attempts >= 5 { throw TransportError.timeout("no ack for \(step.debugName) after \(attempts) attempts") }
        }
    }

    // MARK: Extra device commands (XInput; confirmed in Space Station 4's SDK, exercised on hardware via `apex4 dev`)

    /// Firmware versions of the secondary modules (`A5 30 01`, decoded like SS4's `ExtraInfoCommand`).
    public struct ModuleVersions: Sendable, CustomStringConvertible {
        public var raw: [UInt8]                       // r[17..26]
        public var trigger: String?  { Self.v("0.\(raw[0]).", raw[0], raw[1]) }
        public var screen: String?   { Self.v("0.\(raw[2]).", raw[2], raw[3]) }
        public var `switch`: String? { raw[4] == 0 && raw[5] == 0 ? nil : "\(raw[4] >> 4).\(raw[4] & 0xF).\(raw[5] >> 4).\(raw[5] & 0xF)" }
        public var adc: String?      { Self.v("0.\(raw[6]).", raw[6], raw[7]) }
        public var nearLink: String? { raw[8] == 0 && raw[9] == 0 ? nil : "\(raw[8] >> 4).\(raw[8] & 0xF).\(raw[9] >> 4).\(raw[9] & 0xF)" }
        private static func v(_ prefix: String, _ a: UInt8, _ b: UInt8) -> String? { a == 0 && b == 0 ? nil : prefix + "\(b >> 4).\(b & 0xF)" }
        public var description: String {
            [("trigger", trigger), ("screen", screen), ("switch", `switch`), ("adc", adc), ("nearlink", nearLink)]
                .compactMap { n, v in v.map { "\(n) \($0)" } }.joined(separator: " · ")
        }
    }

    /// Sends an XInput command and returns the first reply whose r[15] == cmd (and r[16] == sub if given).
    func xinputQuery(_ cmd: UInt8, _ args: [UInt8], sub: UInt8? = nil, timeout: TimeInterval = 2) throws -> [UInt8] {
        guard channel == .xinput else { throw TransportError.protocolError("XInput only") }
        try link.write(XInput.command(cmd, args: args))
        return try link.waitForReport(timeout: timeout) { (r: [UInt8]) -> [UInt8]? in
            guard r.count > 27, r[14] == XInput.prefix, r[15] == cmd else { return nil }
            if let sub, r[16] != sub { return nil }
            return r
        }
    }

    public func currentConfigId() throws -> UInt8 { try xinputQuery(XInput.Cmd.currentConfigId, [])[16] }
    /// Activates an on-board config slot (0…3).
    public func applyConfig(slot: UInt8) throws {
        switch channel {
        case .xinput: _ = try xinputQuery(XInput.Cmd.subFunc, [0x05, slot], sub: 0x05)
        case .dinput: try link.write(DInput.command(DInput.Cmd.subFunc, 0x05, slot)); Thread.sleep(forTimeInterval: 0.2)   // same sub-function over the HID channel
        }
    }
    public func moduleVersions() throws -> ModuleVersions { ModuleVersions(raw: Array(try xinputQuery(XInput.Cmd.module, [0x01], sub: 0x01)[17..<27])) }
    public func screenStatusBar() throws -> Bool { try xinputQuery(XInput.Cmd.module, [0x02], sub: 0x02)[17] == 0 }
    public func setScreenStatusBar(_ on: Bool) throws { try link.write(XInput.command(XInput.Cmd.module, 0x03, on ? 0 : 1)) }
    public func screenSleepTime() throws -> UInt8 { try xinputQuery(XInput.Cmd.module, [0x04], sub: 0x04)[17] }
    public func setScreenSleepTime(_ t: UInt8) throws { try link.write(XInput.command(XInput.Cmd.module, 0x05, t)) }
    /// Waits for a key to be pressed on the pad (edge versus the first report seen) and returns its id.
    /// Works in both channels; in XInput it needs the captured link, so the pad is invisible to games meanwhile.
    public func captureKey(timeout: TimeInterval, ignoring: Set<ControllerKey> = [.lt, .rt]) throws -> ControllerKey? {
        let deadline = Date().addingTimeInterval(timeout)
        var baseline: Set<ControllerKey>? = nil
        let xinput = channel == .xinput
        while Date() < deadline {
            let state: ControllerState? = try? link.waitForReport(timeout: 0.3) { (r: [UInt8]) -> ControllerState? in
                xinput ? ControllerState(xinputReport: r) : ControllerState(dinputReport: r)
            }
            guard let state else { continue }
            guard let base = baseline else { baseline = state.pressed; continue }
            if let k = state.pressed.subtracting(base).subtracting(ignoring).min(by: { $0.rawValue < $1.rawValue }) { return k }
            baseline = state.pressed.intersection(base)      // released keys leave the baseline
        }
        return nil
    }

    // MARK: Calibration & joystick hardware switches (docs/protocol.md §11)

    /// ADC calibration window: `start` then, after the user has swept both sticks and both triggers to their
    /// limits, `stop`. Stopping early stores a bogus range — the app only calls it from the guided wizard.
    public func calibration(start: Bool) throws {
        switch channel {
        case .xinput: try link.write(XInput.command(0x14, start ? 1 : 2))
        case .dinput: try link.write(DInput.command(0xE2, start ? 1 : 2))
        }
    }

    public func readJoystickSettings() throws -> JoystickSettings {
        link.discardPending()
        switch channel {
        case .xinput:
            try link.write(XInput.command(XInput.Cmd.subFunc, 0x07))
            return try link.waitForReport(timeout: 2) { JoystickSettings.fromXInput($0) }
        case .dinput:
            try link.write(DInput.command(DInput.Cmd.screenInfo, 0x03))
            return try link.waitForReport(timeout: 2) { JoystickSettings.fromDInput($0) }
        }
    }

    public enum JoystickOption: UInt8, Sendable { case debounce = 0x08, autoCalibration = 0x09, precision = 0x0B, sensitivity = 0x0D, rebound = 0x0E }
    /// Toggles are inverted on the wire (0 = enabled, 1 = disabled); precision / sensitivity take the raw value.
    public func setJoystickOption(_ opt: JoystickOption, value: UInt8) throws {
        switch channel {
        case .xinput: try link.write(XInput.command(XInput.Cmd.subFunc, opt.rawValue, value))
        case .dinput: try link.write(DInput.command(DInput.Cmd.subFunc, opt.rawValue, value))
        }
        Thread.sleep(forTimeInterval: 0.15)
    }
    public func setJoystickToggle(_ opt: JoystickOption, enabled: Bool) throws { try setJoystickOption(opt, value: enabled ? 0 : 1) }

    public func motorTest(left: UInt8, right: UInt8) throws {
        switch channel {
        case .xinput: try link.write(XInput.command(XInput.Cmd.motorTest, left, right))
        case .dinput: try link.write(DInput.command(0x0F, left, right))          // `05 0F <L> <R>` (SS4)
        }
    }
    public func setMappingEnabled(_ on: Bool) throws { try link.write(XInput.command(XInput.Cmd.mappingEnable, on ? 2 : 1)) }

    // MARK: ForceAdapt triggers (`A5 30 06 <1=apply,0=preview> <side> <mode> <params…>`; payloads from SS4)

    public enum TriggerSide: UInt8, Sendable { case left = 1, right = 2, both = 3 }
    public enum ForceTrigger: Sendable {
        case normal
        case race(stroke: UInt8, resistance: UInt8, matchStroke: Bool)
        case sniper(stroke: UInt8, pressure: UInt8, strength: UInt8, frequency: UInt8, matchStroke: Bool)
        case recoil(stroke: UInt8, recoilStroke: UInt8, strength: UInt8, matchStroke: Bool)
        case lock(stroke: UInt8, strength: UInt8, matchStroke: Bool)
        case vibration(stroke: UInt8, pressure: UInt8, strength: UInt8, frequency: UInt8, matchStroke: Bool)

        func params(side: TriggerSide) -> [UInt8] {
            func nz(_ v: UInt8) -> UInt8 { max(1, v) }
            switch self {
            case .normal: return [side.rawValue, 0]
            case let .race(s, r, m): return [side.rawValue, 1, s, nz(r), m ? 1 : 0]
            case let .sniper(s, p, st, f, m): return [side.rawValue, 2, s, nz(p), nz(st), nz(f), m ? 1 : 0]
            case let .recoil(s, rs, st, m): return [side.rawValue, 3, s, rs, nz(st), 0, m ? 1 : 0]
            case let .lock(s, st, m): return [side.rawValue, 4, s, st, m ? 1 : 0]
            case let .vibration(s, p, st, f, m): return [side.rawValue, 5, s, nz(p), nz(st), nz(f), m ? 1 : 0]
            }
        }
    }

    /// Same as `setForceTrigger` but with a pre-built parameter list (used by the XPC helper).
    public func setForceTriggerRaw(_ params: [UInt8], side: TriggerSide, apply: Bool = true) throws {
        guard channel == .xinput else { throw TransportError.protocolError("XInput only") }
        try link.write(XInput.command(XInput.Cmd.module, args: [0x06, apply ? 1 : 0, side.rawValue] + params))
    }

    /// Applies (or previews) a ForceAdapt mode on the trigger(s). Live effect only; profile persistence goes through the config blob.
    public func setForceTrigger(_ mode: ForceTrigger, side: TriggerSide, apply: Bool = true) throws {
        guard channel == .xinput else { throw TransportError.protocolError("XInput only") }
        try link.write(XInput.command(XInput.Cmd.module, args: [0x06, apply ? 1 : 0] + mode.params(side: side)))   // params(side:) already starts with the side byte
    }

    // MARK: Mode

    /// Asks the controller to re-enumerate in the other mode and closes the link **without** resetting
    /// the device (a reset would cancel the switch). The session is unusable afterwards.
    public func switchMode() throws {
        switch channel {
        case .xinput: try link.write(XInput.command(XInput.Cmd.switchToDInput))
        case .dinput: try link.write(DInput.command(DInput.Cmd.switchToXInput))
        }
        Thread.sleep(forTimeInterval: 0.2)
        link.closeWithoutReset()
    }
}

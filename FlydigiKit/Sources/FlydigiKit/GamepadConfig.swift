// The 790-byte mapping/configuration blob ("proto 3.0"), field by field.
// Layout from Space Station 4's `MappingConfigParserV30` (docs/spacestation4-analysis.md §4.3), verified
// against blobs read from an Apex 4. Encoding patches a copy of the original bytes so every byte we do not
// model round-trips untouched.

import Foundation

/// Physical buttons / virtual targets the firmware knows (Flydigi `ControllerKey`).
public enum ControllerKey: UInt8, Sendable, Hashable, CaseIterable, CustomStringConvertible, Identifiable {
    public var id: UInt8 { rawValue }
    case up = 0, right = 1, down = 2, left = 3, a = 4, b = 5, select = 6, x = 7, y = 8, start = 9
    case lb = 10, rb = 11, lt = 12, rt = 13, thumbL = 14, thumbR = 15, c = 16, z = 17
    case m1 = 18, m2 = 19, m3 = 20, m4 = 21, m5 = 22, m6 = 23, menu = 24, turbo = 25, home = 27, back = 28
    case macro = 32
    case joystickCenter = 160, joystickUp = 161, joystickRightUp = 162, joystickRight = 163, joystickRightDown = 164
    case joystickDown = 165, joystickLeftDown = 166, joystickLeft = 167, joystickLeftUp = 168
    case jsLeft = 240, jsRight = 241, jsWheel = 242
    case keyboardMouse = 254, none = 255

    public var description: String {
        switch self {
        case .up: "D-pad Up"; case .right: "D-pad Right"; case .down: "D-pad Down"; case .left: "D-pad Left"
        case .a: "A"; case .b: "B"; case .x: "X"; case .y: "Y"; case .select: "Select"; case .start: "Start"
        case .lb: "LB"; case .rb: "RB"; case .lt: "LT"; case .rt: "RT"; case .thumbL: "L-stick click"; case .thumbR: "R-stick click"
        case .c: "C"; case .z: "Z"; case .m1: "M1"; case .m2: "M2"; case .m3: "M3"; case .m4: "M4"; case .m5: "M5"; case .m6: "M6"
        case .menu: "Menu"; case .turbo: "Turbo"; case .home: "Home"; case .back: "Back"; case .macro: "Macro"
        case .jsLeft: "Left stick"; case .jsRight: "Right stick"; case .jsWheel: "Wheel"
        case .keyboardMouse: "Keyboard/Mouse"; case .none: "—"
        default: "Stick dir \(rawValue)"
        }
    }
}

public struct GamepadConfig: Sendable, Hashable {
    public static let length = 790

    // MARK: Sub-structures

    public enum KeyMapping: Sendable, Hashable {
        case identity                                        // 0xFF: button does what it says
        case key(ControllerKey)                              // remapped to another button
        case turbo(ControllerKey, enable: TurboEnable, frequency: UInt8)   // "Continuous"
        case macro                                           // 0x20: runs the macro bound to this key
        case keyboardMouse                                   // 0xFE (needs Flydigi's Windows driver)
    }
    public enum TurboEnable: UInt8, Sendable, Hashable { case close = 0, press = 1, click = 2 }

    public struct Stick: Sendable, Hashable {
        public enum Curve: UInt8, Sendable, Hashable { case `default` = 0, quick = 1, slow = 2, custom = 3 }
        public var curve: Curve
        public var deadZone: UInt8      // "center", 0…127 scale
        public var p1x: UInt8, p1y: UInt8, p2x: UInt8, p2y: UInt8   // custom curve control points (0…127)

        /// Space Station's preset curves for the Apex 4 (renderer: Default = device point (15, 23), Instant =
        /// (64, 96), Delay = (64, 32), P2 always (127, 127); picking one clears centre and edge). Custom keeps
        /// the current points.
        public mutating func applyCurvePreset(_ c: Curve) {
            curve = c
            guard c != .custom else { return }
            deadZone = 0; end = 127; p2x = 127; p2y = 127
            switch c {
            case .default: p1x = 15; p1y = 23
            case .quick: p1x = 64; p1y = 96
            case .slow: p1x = 64; p1y = 32
            case .custom: break
            }
        }
        public var end: UInt8           // outer dead zone, 0…127
    }

    public struct Trigger: Sendable, Hashable {
        public enum Kind: UInt8, Sendable, Hashable { case normal = 0, adapter = 1, vibration = 2 }
        public var kind: Kind
        public var zero: UInt8, end: UInt8
        public var p1x: UInt8, p1y: UInt8, p2x: UInt8, p2y: UInt8
        /// ForceAdapt preset (Normal/Race/Sniper/Recoil/Lock/Vibration) + raw parameters.
        public var adapterType: UInt8
        public var adapterParams: [UInt8]       // 20 raw bytes (bind type, filter, scale, 5 bind params, mixed border, 10 params)
    }

    public struct Motion: Sendable, Hashable {
        public enum MapType: UInt8, Sendable, Hashable { case off = 0, leftStick = 1, rightStick = 2, mouse = 3 }
        public enum EnableType: UInt8, Sendable, Hashable { case click = 0, press = 1 }
        public enum UseMode: UInt8, Sendable, Hashable { case fps = 0, racer = 1 }
        public var mapType: MapType
        public var enableKey1: UInt8, enableKey2: UInt8    // ControllerKey raw (0xFF = none)
        public var enableType: EnableType
        public var deadZone: UInt8
        public var sensitivity: UInt8
        public var useMode: UseMode
    }

    public struct Vibration: Sendable, Hashable {
        public struct Motor: Sendable, Hashable { public var enabled: Bool; public var min: UInt8, max: UInt8, scale: UInt8 }
        public var enabled: Bool
        public var left: Motor, right: Motor
    }

    public struct MacroAction: Sendable, Hashable {
        public enum Event: UInt8, Sendable, Hashable { case release = 0, press = 1, leftJoystick = 2, rightJoystick = 3, hold = 5 }
        public var durationMs: Int        // delay since the previous action
        public var key: UInt8             // ControllerKey raw
        public var event: Event
        public init(durationMs: Int, key: UInt8, event: Event) { self.durationMs = durationMs; self.key = key; self.event = event }
    }
    public struct Macro: Sendable, Hashable {
        public enum Enable: UInt8, Sendable, Hashable { case none = 0, once = 1, press = 2, click = 3 }
        public var key: UInt8             // trigger button (ControllerKey raw)
        public var count: Int             // == actions.count on the wire (SS4 stores the action count here)
        public var enable: Enable
        public var actions: [MacroAction]
        public init(key: UInt8, count: Int, enable: Enable, actions: [MacroAction]) { self.key = key; self.count = count; self.enable = enable; self.actions = actions }
    }

    // MARK: Fields

    public private(set) var raw: [UInt8]
    public var protoVersion: UInt16        // LE at 0..1 (observed 0x0300 = "3.0")
    public var packageCount: UInt8         // at 2 (79)
    public var dataVersion: UInt16         // at 225..226 — the "random id" used for save-to-flash (big-endian, like `A5 50 02`)
    public var title: String               // UTF-16LE at 770..789 (≤10 chars)
    public var keys: [ControllerKey: KeyMapping]   // 32 physical keys (raw ids 0…31) → mapping
    public var leftStick: Stick, rightStick: Stick
    public var leftTrigger: Trigger, rightTrigger: Trigger
    public var motion: Motion
    public var vibration: Vibration
    public var macros: [Macro]

    // MARK: Decode

    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.length else { return nil }
        raw = bytes
        protoVersion = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        packageCount = bytes[2]
        dataVersion = UInt16(bytes[225]) << 8 | UInt16(bytes[226])   // same byte order as the `A5 50 02` reply
        let titleBytes = Array(bytes[770..<790])
        title = String(decoding: titleBytes, as: UTF16LE.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0\u{FFFF}"))

        var keys: [ControllerKey: KeyMapping] = [:]
        for i in 0..<32 {
            let o = 13 + i * 3
            let (b0, b1, b2) = (bytes[o], bytes[o + 1], bytes[o + 2])
            guard let physical = ControllerKey(rawValue: UInt8(i)) else { continue }
            if b0 == 0x20 { keys[physical] = .macro }
            else if b0 == 0xFE { keys[physical] = .keyboardMouse }
            else if b2 > 0, let target = ControllerKey(rawValue: b0) {
                keys[physical] = .turbo(target, enable: TurboEnable(rawValue: b1) ?? .close, frequency: b2)
            } else if b0 == 0xFF || b0 == UInt8(i) || b0 > 32 { keys[physical] = .identity }
            else if let target = ControllerKey(rawValue: b0) { keys[physical] = .key(target) }
            else { keys[physical] = .identity }
        }
        self.keys = keys

        func stick(_ o: Int) -> Stick {
            Stick(curve: Stick.Curve(rawValue: bytes[o]) ?? .default, deadZone: bytes[o + 1],
                  p1x: bytes[o + 2], p1y: bytes[o + 3], p2x: bytes[o + 4], p2y: bytes[o + 5], end: bytes[o + 6])
        }
        leftStick = stick(109); rightStick = stick(116)

        func trigger(_ o: Int, adapter a: Int) -> Trigger {
            Trigger(kind: Trigger.Kind(rawValue: bytes[o]) ?? .normal, zero: bytes[o + 1], end: bytes[o + 6],
                    p1x: bytes[o + 2], p1y: bytes[o + 3], p2x: bytes[o + 4], p2y: bytes[o + 5],
                    adapterType: bytes[a], adapterParams: Array(bytes[a..<(a + 20)]))
        }
        leftTrigger = trigger(123, adapter: 185); rightTrigger = trigger(130, adapter: 205)

        motion = Motion(mapType: Motion.MapType(rawValue: bytes[137]) ?? .off, enableKey1: bytes[138], enableKey2: bytes[144],
                        enableType: Motion.EnableType(rawValue: bytes[139]) ?? .click, deadZone: bytes[140],
                        sensitivity: max(bytes[141], bytes[142]), useMode: Motion.UseMode(rawValue: bytes[143]) ?? .fps)

        func motor(_ o: Int) -> Vibration.Motor { .init(enabled: bytes[o] == 0, min: min(bytes[o + 1], bytes[o + 2]), max: max(bytes[o + 1], bytes[o + 2]), scale: bytes[o + 3]) }
        vibration = Vibration(enabled: bytes[145] == 0, left: motor(146), right: motor(150))

        macros = Self.decodeMacros(Array(bytes[230..<768]), protoVersion: protoVersion)
    }

    /// Space Station's macro area (proto < x.2): `[count][offset×N] then per macro: key, count LE16, enable, N×(t LE16, key, event)`.
    static func decodeMacros(_ d: [UInt8], protoVersion: UInt16) -> [Macro] {
        let maxMacros = protoVersion >= 770 ? 10 : 5
        let tick = protoVersion >= 770 ? 1 : 10
        let n = Int(d[0]); guard n >= 1, n <= maxMacros else { return [] }
        var out: [Macro] = []
        let base = maxMacros + 1
        for i in 0..<n {
            let start = base + Int(d[i + 1]) * 4
            let end = i == n - 1 ? d.count : min(d.count, base + Int(d[i + 2]) * 4)
            guard end > start + 4 else { continue }
            let m = Array(d[start..<end])
            var actions = Int(m[1]); if m.count < actions * 4 { actions = (m.count - 4) / 4 }
            var list: [MacroAction] = []; var last = 0
            for j in 0..<actions {
                let p = 4 + 4 * j; guard p + 3 < m.count else { break }
                let t = (Int(m[p]) | Int(m[p + 1]) << 8) * tick
                list.append(MacroAction(durationMs: t - last, key: m[p + 2], event: MacroAction.Event(rawValue: m[p + 3]) ?? .press))
                last = t
            }
            out.append(Macro(key: m[0], count: Int(m[1]) | Int(m[2]) << 8, enable: Macro.Enable(rawValue: m[3]) ?? .none, actions: list))
        }
        return out
    }

    // MARK: Encode

    /// Bytes to write back. Starts from the original blob and re-serialises **only the groups that changed**
    /// since decoding, so unchanged configs round-trip byte-for-byte (the firmware stores a few fields in
    /// more than one equivalent form — e.g. 0xFF vs. the key's own id for "identity").
    public var bytes: [UInt8] {
        guard let fresh = GamepadConfig(bytes: raw) else { return raw }
        var b = raw
        if protoVersion != fresh.protoVersion { b[0] = UInt8(protoVersion & 0xFF); b[1] = UInt8(protoVersion >> 8) }
        if packageCount != fresh.packageCount { b[2] = packageCount }
        if dataVersion != fresh.dataVersion { b[225] = UInt8(dataVersion >> 8); b[226] = UInt8(dataVersion & 0xFF) }
        if title != fresh.title {
            var t = Array(title.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }.prefix(20))
            t += [UInt8](repeating: 0, count: 20 - t.count)
            b.replaceSubrange(770..<790, with: t)
        }
        for i in 0..<32 {
            guard let physical = ControllerKey(rawValue: UInt8(i)), let m = keys[physical], m != fresh.keys[physical] else { continue }
            let o = 13 + i * 3
            switch m {
            case .identity: b[o] = 0xFF; b[o + 1] = 0; b[o + 2] = 0
            case .key(let k): b[o] = k == physical ? 0xFF : k.rawValue; b[o + 1] = 0; b[o + 2] = 0
            case .turbo(let k, let en, let f): b[o] = k.rawValue; b[o + 1] = en.rawValue; b[o + 2] = f
            case .macro: b[o] = 0x20; b[o + 1] = 0; b[o + 2] = 0
            case .keyboardMouse: b[o] = 0xFE; b[o + 1] = 0; b[o + 2] = 0
            }
        }
        func put(_ s: Stick, _ o: Int) { b[o] = s.curve.rawValue; b[o + 1] = s.deadZone; b[o + 2] = s.p1x; b[o + 3] = s.p1y; b[o + 4] = s.p2x; b[o + 5] = s.p2y; b[o + 6] = s.end }
        if leftStick != fresh.leftStick { put(leftStick, 109) }
        if rightStick != fresh.rightStick { put(rightStick, 116) }
        func putT(_ t: Trigger, _ o: Int, _ a: Int) {
            b[o] = t.kind.rawValue; b[o + 1] = t.zero; b[o + 2] = t.p1x; b[o + 3] = t.p1y; b[o + 4] = t.p2x; b[o + 5] = t.p2y; b[o + 6] = t.end
            var p = Array(t.adapterParams.prefix(20)); p += [UInt8](repeating: 0xFF, count: max(0, 20 - p.count)); p[0] = t.adapterType
            b.replaceSubrange(a..<(a + 20), with: p)
        }
        if leftTrigger != fresh.leftTrigger { putT(leftTrigger, 123, 185) }
        if rightTrigger != fresh.rightTrigger { putT(rightTrigger, 130, 205) }
        if motion != fresh.motion {
            b[137] = motion.mapType.rawValue; b[138] = motion.enableKey1; b[139] = motion.enableType.rawValue; b[140] = motion.deadZone
            b[141] = motion.sensitivity; b[142] = motion.sensitivity; b[143] = motion.useMode.rawValue; b[144] = motion.enableKey2
        }
        if vibration != fresh.vibration {
            b[145] = vibration.enabled ? 0 : 0xFF
            func putM(_ m: Vibration.Motor, _ o: Int) { b[o] = m.enabled ? 0 : 0xFF; b[o + 1] = m.min; b[o + 2] = m.max; b[o + 3] = m.scale }
            putM(vibration.left, 146); putM(vibration.right, 150)
        }
        if macros != fresh.macros { b.replaceSubrange(230..<768, with: Self.encodeMacros(macros, protoVersion: protoVersion)) }
        return b
    }

    static func encodeMacros(_ macros: [Macro], protoVersion: UInt16) -> [UInt8] {
        let maxMacros = protoVersion >= 770 ? 10 : 5
        let tick = protoVersion >= 770 ? 1 : 10
        var out = [UInt8](repeating: 0xFF, count: 538)
        var head = [UInt8](repeating: 0, count: maxMacros + 1)
        head[0] = UInt8(min(macros.count, maxMacros))
        var body: [UInt8] = []; var offset = 0
        for (i, m) in macros.prefix(maxMacros).enumerated() {
            if i < macros.count - 1 { offset += m.actions.count + 1; if i + 2 < head.count { head[i + 2] = UInt8(offset) } }
            let n = m.actions.count
            body += [m.key, UInt8(n & 0xFF), UInt8(n >> 8), m.enable.rawValue]
            var t = 0
            for a in m.actions { t += a.durationMs / tick; body += [UInt8(t & 0xFF), UInt8(t >> 8 & 0xFF), a.key, a.event.rawValue] }
        }
        let all = head + body
        out.replaceSubrange(0..<min(all.count, out.count), with: all.prefix(out.count))
        return out
    }

    // MARK: Summary

    public var summary: String {
        var s = "proto \(protoVersion >> 8).\(protoVersion & 0xFF) · parcels \(packageCount) · data version \(dataVersion) · title \"\(title)\"\n"
        let remapped = keys.filter { if case .identity = $0.value { return false } else { return true } }.sorted { $0.key.rawValue < $1.key.rawValue }
        s += "keys: \(remapped.isEmpty ? "all default" : remapped.map { "\($0.key) → \($0.value)" }.joined(separator: ", "))\n"
        s += "left stick: \(leftStick)\nright stick: \(rightStick)\n"
        s += "left trigger: kind \(leftTrigger.kind) zero \(leftTrigger.zero) end \(leftTrigger.end) adapter \(leftTrigger.adapterType)\n"
        s += "right trigger: kind \(rightTrigger.kind) zero \(rightTrigger.zero) end \(rightTrigger.end) adapter \(rightTrigger.adapterType)\n"
        s += "motion: \(motion)\nvibration: \(vibration)\nmacros: \(macros.count)"
        return s
    }
}

/// Minimal UTF-16LE decoding helper for the config title.
enum UTF16LE {
    static func decode(_ bytes: [UInt8]) -> String {
        var units: [UInt16] = []
        var i = 0
        while i + 1 < bytes.count { units.append(UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8); i += 2 }
        return String(decoding: units, as: UTF16.self)
    }
}
extension String {
    init(decoding bytes: [UInt8], as _: UTF16LE.Type) { self = UTF16LE.decode(bytes) }
}

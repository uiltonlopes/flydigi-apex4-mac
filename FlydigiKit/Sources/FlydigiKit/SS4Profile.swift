// Space Station 4's profile "bean" — the protobuf message its service keeps on disk and shares by code.
// A share code resolves to `BitConverter.ToString(bean.ToByteArray())`: the protobuf bytes of
// `ControllerMappingConfigBean`, upper-case hex separated by dashes. This file is a port of the two halves
// Space Station uses: `MappingConfigParserV30` (790-byte blob ↔ bean, including its integer arithmetic) and
// the message layout of `Flydigi.SharedResources.Data.Protobuf` (field numbers below), plus a minimal
// protobuf wire codec. Nothing here talks to the controller or the network.

import Foundation

// MARK: - Protobuf wire codec (what we need: varint, length-delimited, packed repeated)

enum Protobuf {
    struct Writer {
        var bytes: [UInt8] = []
        mutating func varint(_ v: UInt64) { var v = v; while v >= 0x80 { bytes.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }; bytes.append(UInt8(v)) }
        mutating func tag(_ field: Int, wire: Int) { varint(UInt64(field << 3 | wire)) }
        /// int32 / enum / bool: proto3 skips default (0) values.
        mutating func int(_ field: Int, _ v: Int, keepZero: Bool = false) {
            guard v != 0 || keepZero else { return }
            tag(field, wire: 0); varint(UInt64(bitPattern: Int64(v)))
        }
        mutating func bool(_ field: Int, _ v: Bool) { if v { tag(field, wire: 0); varint(1) } }
        mutating func string(_ field: Int, _ s: String) { guard !s.isEmpty else { return }; bytes(field, Array(s.utf8)) }
        mutating func bytes(_ field: Int, _ b: [UInt8]) { tag(field, wire: 2); varint(UInt64(b.count)); bytes.append(contentsOf: b) }
        mutating func message(_ field: Int, _ w: Writer?) { guard let w else { return }; bytes(field, w.bytes) }
        /// Packed repeated int32 (proto3 default for scalars).
        mutating func packed(_ field: Int, _ values: [Int]) {
            guard !values.isEmpty else { return }
            var inner = Writer(); for v in values { inner.varint(UInt64(bitPattern: Int64(v))) }
            bytes(field, inner.bytes)
        }
    }

    struct Field { let number: Int; let wire: Int; let varint: UInt64; let data: [UInt8] }

    /// Splits a message into fields; unknown wire types abort (returns what was parsed so far).
    static func fields(_ b: [UInt8]) -> [Field] {
        var out: [Field] = []; var i = 0
        func readVarint() -> UInt64? {
            var v: UInt64 = 0, shift: UInt64 = 0
            while i < b.count { let c = b[i]; i += 1; v |= UInt64(c & 0x7F) << shift; if c & 0x80 == 0 { return v }; shift += 7; if shift > 63 { return nil } }
            return nil
        }
        while i < b.count {
            guard let key = readVarint() else { break }
            let number = Int(key >> 3), wire = Int(key & 7)
            switch wire {
            case 0: guard let v = readVarint() else { return out }; out.append(Field(number: number, wire: 0, varint: v, data: []))
            case 2:
                guard let n = readVarint(), n <= UInt64(b.count - i) else { return out }
                out.append(Field(number: number, wire: 2, varint: 0, data: Array(b[i..<i + Int(n)]))); i += Int(n)
            case 1: guard i + 8 <= b.count else { return out }; out.append(Field(number: number, wire: 1, varint: 0, data: Array(b[i..<i + 8]))); i += 8
            case 5: guard i + 4 <= b.count else { return out }; out.append(Field(number: number, wire: 5, varint: 0, data: Array(b[i..<i + 4]))); i += 4
            default: return out
            }
        }
        return out
    }
    static func int(_ f: Field) -> Int { Int(Int64(bitPattern: f.varint)) }
    /// Repeated int32: packed (wire 2) or one varint per occurrence (wire 0).
    static func ints(_ fs: [Field], _ number: Int) -> [Int] {
        var out: [Int] = []
        for f in fs where f.number == number {
            if f.wire == 0 { out.append(int(f)) }
            else if f.wire == 2 { var i = 0; while i < f.data.count { var v: UInt64 = 0, s: UInt64 = 0; while i < f.data.count { let c = f.data[i]; i += 1; v |= UInt64(c & 0x7F) << s; if c & 0x80 == 0 { break }; s += 7 }; out.append(Int(Int64(bitPattern: v))) } }
        }
        return out
    }
    static func first(_ fs: [Field], _ number: Int) -> Field? { fs.first { $0.number == number } }
    static func intValue(_ fs: [Field], _ number: Int, default d: Int = 0) -> Int { first(fs, number).map(int) ?? d }
    static func boolValue(_ fs: [Field], _ number: Int) -> Bool { intValue(fs, number) != 0 }
    static func stringValue(_ fs: [Field], _ number: Int) -> String { first(fs, number).map { String(decoding: $0.data, as: UTF8.self) } ?? "" }
    static func sub(_ fs: [Field], _ number: Int) -> [Field]? { first(fs, number).map { fields($0.data) } }
    static func subs(_ fs: [Field], _ number: Int) -> [[Field]] { fs.filter { $0.number == number && $0.wire == 2 }.map { fields($0.data) } }
}

// MARK: - Bean

/// `ControllerMappingConfigBean` and its sub-messages, with Space Station's field numbers.
public struct SS4Profile: Sendable, Hashable {
    public struct Point: Sendable, Hashable { public var x = 0, y = 0 }
    public struct JoystickSensitivity: Sendable, Hashable { public var type = 0; public var point1 = Point(), point2 = Point() }   // type: Default/Quick/Slow/Custom
    public struct JoystickParam: Sendable, Hashable {
        public var mapType = 0                     // Joystick/Keyboard/Mouse/DPad
        public var circularityType = 0, center = 0, edge = 0
        public var sensitivity = JoystickSensitivity()
        public var end = 0
    }
    public struct Key: Sendable, Hashable {
        public var keyId = 0
        public var mapType = 0                     // Key/Continuous/Macro/MultiFunction/Keyboard
        public var mapControllerKeyId = 0          // Key
        public var mapKeyboardKeyId: Int? = nil    // Key with a keyboard target (Space Station's local-only detail)
        public var continuousKeyId = 0, continuousEnableType = 0, frequency = 0
        public var multiFunctionKeyId = 0
    }
    public struct VibrationItem: Sendable, Hashable { public var enable = true; public var min = 0, max = 0, scale = 0 }
    public struct Vibration: Sendable, Hashable { public var enable = true; public var left = VibrationItem(), right = VibrationItem() }
    public struct TriggerVibrationTyped: Sendable, Hashable { public var type = 0, minLevel = 0, maxLevel = 0, filter = 0, minStart = 0, scale = 0, minTime = 0 }
    public struct TriggerVibration: Sendable, Hashable { public var enable = true; public var linear = TriggerVibrationTyped(), micro = TriggerVibrationTyped() }
    public struct TriggerBind: Sendable, Hashable { public var type = 0, filter = 0, scale = 0; public var param: [Int] = [] }
    public struct TriggerAdapter: Sendable, Hashable { public var type = 0; public var bind = TriggerBind(); public var mixedBorder = 0; public var param: [Int] = [] }
    public struct Trigger: Sendable, Hashable {
        public var zero = 0, end = 0, type = 0
        public var vibration: TriggerVibration? = nil
        public var adapter: TriggerAdapter? = nil
        public var point1 = Point(), point2 = Point()
    }
    public struct Motion: Sendable, Hashable {
        public var useMode = 0, mappingType = 0
        public var joystickEnableType = 0, joystickEnableKeys: [Int] = [], joystickSensitivity = 0, joystickDeadZone = 0
        public var mouseEnableType = 0, mouseEnableKeys: [Int] = [], mouseSensitivityX = 0, mouseSensitivityY = 0
    }
    public struct MacroAction: Sendable, Hashable { public var keyId = 0, duration = 0, event = 0 }
    public struct MacroItem: Sendable, Hashable { public var keyId = 0, count = 0, type = 0; public var actions: [MacroAction] = []; public var interval = 0; public var name = "" }
    public struct Macros: Sendable, Hashable { public var offsets: [Int] = [], interval: [Int] = []; public var items: [MacroItem] = []; public var version = 0 }
    public struct LedColor: Sendable, Hashable { public var r = 0, g = 0, b = 0 }
    public struct Led: Sendable, Hashable {
        public var version = 0; public var clickFeedback = false; public var loopStart = 0, loopEnd = 0, loopTime = 0, brightness = 0, rgbNum = 0, ledMode = 0
        public var groups: [[LedColor]] = []; public var gripSync = false
    }

    public var cfgId = 0, protoVersion = 0x0300, packageCount = 77, dataVersion = 0
    public var title = ""
    public var leftStick = JoystickParam(), rightStick = JoystickParam()
    public var keys: [Key] = []
    public var vibration = Vibration()
    public var leftTrigger = Trigger(), rightTrigger = Trigger()
    public var motion = Motion()
    public var led: Led? = nil
    public var macros = Macros()
    public var oldLedConfig: [Int] = []
    public var lunpan: [Int] = []

    public static func maxMacros(_ protoVersion: Int) -> Int { protoVersion >= 770 ? 10 : 5 }
    public static func minMacroInterval(_ protoVersion: Int) -> Int { protoVersion >= 770 ? 1 : 10 }
}

// MARK: - Blob ↔ bean (MappingConfigParserV30, integer arithmetic kept as in C#)

extension SS4Profile {
    /// Reads Space Station's bean out of a 790-byte (proto 3.0) config blob.
    public init(blob d: [UInt8]) {
        guard d.count >= 790 else { self.init(); return }
        self.init()
        protoVersion = Int(d[1]) << 8 | Int(d[0]); packageCount = Int(d[2]); dataVersion = Int(d[226]) << 8 | Int(d[225])
        oldLedConfig = d[3..<13].map(Int.init); lunpan = d[183..<185].map(Int.init)
        var titleBytes = Array(d[770..<790])
        if let s = String(bytes: titleBytes, encoding: .utf16LittleEndian) { title = String(s.reversed().drop { $0 == "\u{FFFF}" }.drop { $0 == "\0" }.reversed()) }
        else { titleBytes.removeAll(); title = "" }
        // vibration 145..154
        vibration.enable = d[145] == 0
        for i in 0...1 { let n = 145 + i * 4; var v = VibrationItem(); v.enable = d[n + 1] == 0; v.min = Int(min(d[n + 2], d[n + 3])); v.max = Int(max(d[n + 2], d[n + 3])); v.scale = Int(d[n + 4]); if i == 0 { vibration.left = v } else { vibration.right = v } }
        // keys 13..109
        for i in 0..<32 {
            let n = 13 + i * 3; var k = Key(); k.keyId = i
            if d[n] == 32 { k.mapType = 2 }
            else if d[n + 2] > 0 { k.mapType = 1; k.continuousKeyId = Int(d[n]); k.continuousEnableType = Int(d[n + 1]); k.frequency = Int(d[n + 2]) }
            else { k.mapType = 0; k.mapControllerKeyId = d[n] > 32 ? i : Int(d[n]) }
            keys.append(k)
        }
        // sticks 109..123 (proto 3.0 is the "old protocol" branch: values are percent-converted)
        let old = protoVersion < 769
        for i in 0...1 {
            let n = 109 + i * 7
            let c = d[n + 1] > 127 ? 127 - Int(d[n + 1]) : Int(d[n + 1])
            let e = d[n + 6] > 127 ? 127 - Int(d[n + 6]) : Int(d[n + 6])
            var p1x = Int(d[n + 2]), p1y = Int(d[n + 3]), p2x = Int(d[n + 4]), p2y = Int(d[n + 5])
            if old {
                p1x = p1x * 100 / 127; p1y = p1y * 100 / 127; p2x = p2x * 100 / 127; p2y = p2y * 100 / 127
                let span = e - c
                p1x = span == 0 ? 0 : (p1x - c) * 100 / span; p2x = span == 0 ? 0 : (p2x - c) * 100 / span
            }
            var j = JoystickParam(); j.mapType = 0; j.center = c; j.end = e
            j.sensitivity = JoystickSensitivity(type: Int(d[n]), point1: Point(x: p1x, y: p1y), point2: Point(x: p2x, y: p2y))
            if i == 0 { leftStick = j } else { rightStick = j }
        }
        // triggers 123..137, adapter 185..225, motors 154..183
        for i in 0...1 {
            let n = 123 + i * 7
            var t = Trigger(); t.zero = Int(d[n + 1]); t.end = Int(d[n + 6]); t.type = Int(d[n]); t.point1 = Point(x: Int(d[n + 2]), y: Int(d[n + 3])); t.point2 = Point(x: Int(d[n + 4]), y: Int(d[n + 5]))
            let m = 154 + i * 14
            var tv = TriggerVibration(); tv.enable = d[154] == 0
            tv.linear = TriggerVibrationTyped(type: Int(d[m + 1]), minLevel: Int(d[m + 2]), maxLevel: Int(d[m + 3]), filter: Int(d[m + 4]), minStart: Int(d[m + 5]), scale: Int(d[m + 6]), minTime: Int(d[m + 7]))
            tv.micro = TriggerVibrationTyped(type: Int(d[m + 8]), minLevel: Int(d[m + 9]), maxLevel: Int(d[m + 10]), filter: Int(d[m + 11]), minStart: Int(d[m + 12]), scale: Int(d[m + 13]), minTime: Int(d[m + 14]))
            t.vibration = tv
            let a = 185 + i * 20
            var ad = TriggerAdapter(); ad.type = Int(d[a]); ad.bind = TriggerBind(type: Int(d[a + 1]), filter: Int(d[a + 2]), scale: Int(d[a + 3]), param: d[(a + 4)..<(a + 9)].map(Int.init)); ad.mixedBorder = Int(d[a + 9]); ad.param = d[(a + 10)..<(a + 20)].map(Int.init)
            t.adapter = ad
            if i == 0 { leftTrigger = t } else { rightTrigger = t }
        }
        // motion 137..145
        motion.useMode = Int(d[143]); motion.mappingType = Int(d[137])
        motion.joystickDeadZone = Int(d[140]); motion.joystickEnableType = Int(d[139]); motion.joystickSensitivity = Int(max(d[141], d[142]))
        motion.mouseEnableType = 0; motion.mouseSensitivityX = -1; motion.mouseSensitivityY = -1
        motion.joystickEnableKeys = [Int(d[138]), Int(d[144])]; motion.mouseEnableKeys = motion.joystickEnableKeys
        // macros 230..768
        if protoVersion & 0xF < 2 { macros = Self.parseMacros(Array(d[230..<768]), protoVersion: protoVersion) }
    }

    private static func parseMacros(_ data: [UInt8], protoVersion: Int) -> Macros {
        var out = Macros()
        let count = Int(data[0]), maxCount = maxMacros(protoVersion)
        guard count >= 1, count <= maxCount else { return out }
        for i in 0..<count {
            out.offsets.append(Int(data[i + 1]))
            let base = maxCount + 1
            let start = base + Int(data[i + 1]) * 4
            var end = base + Int(data[i + 2]) * 4
            if i == count - 1 { end = data.count }
            let stop = min(end, data.count)
            guard stop > start else { continue }
            let list = Array(data[start..<stop])
            guard list.count >= 4 else { continue }
            var n3 = Int(list[1])
            if list.count < n3 * 4 { n3 = (list.count - 4) / 4 }
            var item = MacroItem(); item.keyId = Int(list[0]); item.count = Int(list[2]) << 8 | Int(list[1]); item.type = Int(list[3])
            var prev = 0
            for j in 0..<max(0, n3) {
                let p = 4 + 4 * j
                guard p + 3 < list.count else { break }
                let t = (Int(list[p]) | Int(list[p + 1]) << 8) * minMacroInterval(protoVersion)
                item.actions.append(MacroAction(keyId: Int(list[p + 2]), duration: t - prev, event: Int(list[p + 3])))
                prev = t
            }
            out.items.append(item)
        }
        return out
    }

    /// Writes the bean back as a 790-byte blob the way Space Station does (unset areas are 0xFF).
    public func blob() -> [UInt8] {
        var d = [UInt8](repeating: 0xFF, count: 790)
        for (i, v) in oldLedConfig.prefix(10).enumerated() { d[3 + i] = UInt8(truncatingIfNeeded: v) }
        for (i, v) in lunpan.prefix(2).enumerated() { d[183 + i] = UInt8(truncatingIfNeeded: v) }
        d[0] = UInt8(truncatingIfNeeded: protoVersion); d[1] = UInt8(truncatingIfNeeded: protoVersion >> 8); d[2] = UInt8(truncatingIfNeeded: packageCount)
        d[225] = UInt8(truncatingIfNeeded: dataVersion); d[226] = UInt8(truncatingIfNeeded: dataVersion >> 8)
        let t = Array(title.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }.prefix(20)
        for (i, b) in t.enumerated() { d[770 + i] = b }
        // keys
        for (i, k) in keys.prefix(32).enumerated() {
            let n = 13 + i * 3
            if k.mapType == 1 { d[n] = UInt8(truncatingIfNeeded: k.continuousKeyId); d[n + 1] = UInt8(truncatingIfNeeded: k.continuousEnableType); d[n + 2] = UInt8(truncatingIfNeeded: k.frequency); continue }
            if k.mapType == 2 { d[n] = 32 }
            else if k.mapType == 3 || k.mapKeyboardKeyId != nil { d[n] = 254 }
            else if k.mapControllerKeyId == i { d[n] = 255 }
            else { d[n] = UInt8(truncatingIfNeeded: k.mapControllerKeyId) }
            d[n + 1] = 0; d[n + 2] = 0
        }
        // vibration
        d[145] = vibration.enable ? 0 : 255
        for (i, v) in [vibration.left, vibration.right].enumerated() { let n = 145 + i * 4; d[n + 1] = v.enable ? 0 : 255; d[n + 2] = UInt8(truncatingIfNeeded: v.min); d[n + 3] = UInt8(truncatingIfNeeded: v.max); d[n + 4] = UInt8(truncatingIfNeeded: v.scale) }
        // sticks
        let old = protoVersion < 769
        for (i, j) in [leftStick, rightStick].enumerated() {
            let n = 109 + i * 7
            d[n] = UInt8(truncatingIfNeeded: j.sensitivity.type)
            var b = UInt8(truncatingIfNeeded: j.center)
            func calc(_ p: Point, _ center: Double) -> (Double, Double) {
                let pct = Double(p.x) * 100.0 / 127.0
                let pos = center + (100.0 - center) * pct / 100.0
                return (pos * 127.0 / 100.0, Double(p.y))
            }
            var (x1, y1) = calc(j.sensitivity.point1, Double(b)), (x2, y2) = calc(j.sensitivity.point2, Double(b))
            if old {
                b = UInt8(truncatingIfNeeded: Int(b) * 127 / 100)
                d[n + 1] = j.mapType == 0 ? b : 127
                x1 = x1 * Double(j.end - j.center) / 100.0; x2 = x2 * Double(j.end - j.center) / 100.0
            } else {
                d[n + 1] = j.mapType == 0 ? b : 127
            }
            func byte(_ v: Double) -> UInt8 { v.isFinite ? UInt8(min(max(v, 0), 255)) : 0 }
            d[n + 2] = byte(x1); d[n + 3] = byte(y1); d[n + 4] = byte(x2); d[n + 5] = byte(y2)
            d[n + 6] = UInt8(truncatingIfNeeded: j.end)
        }
        // triggers
        for (i, t) in [leftTrigger, rightTrigger].enumerated() {
            let n = 123 + i * 7
            d[n] = UInt8(truncatingIfNeeded: t.type); d[n + 1] = UInt8(truncatingIfNeeded: t.zero); d[n + 2] = UInt8(truncatingIfNeeded: t.point1.x); d[n + 3] = UInt8(truncatingIfNeeded: t.point1.y); d[n + 4] = UInt8(truncatingIfNeeded: t.point2.x); d[n + 5] = UInt8(truncatingIfNeeded: t.point2.y); d[n + 6] = UInt8(truncatingIfNeeded: t.end)
            let a = 185 + i * 20
            if let ad = t.adapter {
                d[a] = UInt8(truncatingIfNeeded: ad.type); d[a + 1] = ad.type == 5 ? 2 : 0; d[a + 2] = UInt8(truncatingIfNeeded: ad.bind.filter); d[a + 3] = UInt8(truncatingIfNeeded: ad.bind.scale)
                for (k, v) in ad.bind.param.prefix(5).enumerated() { d[a + 4 + k] = UInt8(truncatingIfNeeded: v) }
                d[a + 9] = UInt8(truncatingIfNeeded: ad.mixedBorder)
                for (k, v) in ad.param.prefix(10).enumerated() { d[a + 10 + k] = UInt8(truncatingIfNeeded: v) }
            }
            let m = 154 + i * 14
            if let tv = t.vibration {
                if i == 0 { d[154] = tv.enable ? 0 : 1 }
                let l = tv.linear, mi = tv.micro
                d[m + 1] = UInt8(truncatingIfNeeded: l.type); d[m + 2] = UInt8(truncatingIfNeeded: l.minLevel); d[m + 3] = UInt8(truncatingIfNeeded: l.maxLevel); d[m + 4] = UInt8(truncatingIfNeeded: l.filter); d[m + 5] = UInt8(truncatingIfNeeded: l.minStart); d[m + 6] = UInt8(truncatingIfNeeded: l.scale); d[m + 7] = UInt8(truncatingIfNeeded: l.minTime)
                d[m + 8] = UInt8(truncatingIfNeeded: mi.type); d[m + 9] = UInt8(truncatingIfNeeded: mi.minLevel); d[m + 10] = UInt8(truncatingIfNeeded: mi.maxLevel); d[m + 11] = UInt8(truncatingIfNeeded: mi.filter); d[m + 12] = UInt8(truncatingIfNeeded: mi.minStart); d[m + 13] = UInt8(truncatingIfNeeded: mi.scale); d[m + 14] = UInt8(truncatingIfNeeded: mi.minTime)
            }
        }
        // motion
        d[137] = UInt8(truncatingIfNeeded: motion.mappingType); d[139] = UInt8(truncatingIfNeeded: motion.joystickEnableType)
        d[141] = UInt8(truncatingIfNeeded: motion.joystickSensitivity); d[142] = d[141]; d[143] = UInt8(truncatingIfNeeded: motion.useMode)
        if motion.mappingType == 3 { d[138] = 255; d[140] = 0; d[144] = 255 }
        else { d[138] = UInt8(truncatingIfNeeded: motion.joystickEnableKeys.first ?? 255); d[140] = UInt8(truncatingIfNeeded: motion.joystickDeadZone); d[144] = UInt8(truncatingIfNeeded: motion.joystickEnableKeys.count > 1 ? motion.joystickEnableKeys[1] : 255) }
        // macros
        if protoVersion & 0xF < 2 {
            let m = macroBytes()
            for (i, b) in m.enumerated() where 230 + i < 768 { d[230 + i] = b }
        }
        return d
    }

    private func macroBytes() -> [UInt8] {
        var array = [UInt8](repeating: 0xFF, count: 538)
        let maxCount = Self.maxMacros(protoVersion)
        var list: [UInt8] = [0] + [UInt8](repeating: 0, count: maxCount)
        list[0] = UInt8(truncatingIfNeeded: macros.items.count)
        var num = 0
        for j in 0..<macros.items.count where j != macros.items.count - 1 {
            num += macros.items[j].actions.count + 1
            if j + 2 < list.count { list[j + 2] = UInt8(truncatingIfNeeded: num) }
        }
        for m in macros.items {
            list.append(UInt8(truncatingIfNeeded: m.keyId)); list.append(UInt8(truncatingIfNeeded: m.count)); list.append(UInt8(truncatingIfNeeded: m.count >> 8)); list.append(UInt8(truncatingIfNeeded: m.type))
            var t = 0
            for a in m.actions {
                t = min(t + a.duration / Self.minMacroInterval(protoVersion), 0xFFFF)
                list.append(UInt8(truncatingIfNeeded: t)); list.append(UInt8(truncatingIfNeeded: t >> 8)); list.append(UInt8(truncatingIfNeeded: a.keyId)); list.append(UInt8(truncatingIfNeeded: a.event))
            }
        }
        for (i, b) in list.prefix(538).enumerated() { array[i] = b }
        return array
    }
}

// MARK: - LED bean from our 500-byte LED blob

extension SS4Profile.Led {
    public init(led: LEDConfig) {
        version = Int(led.versionMajor) << 8 | Int(led.versionMinor)
        clickFeedback = led.type != 0; loopStart = Int(led.loopStart); loopEnd = Int(led.loopEnd); loopTime = Int(led.speed)
        brightness = Int(led.brightness); rgbNum = Int(led.activeGroups); ledMode = Int(led.mode.rawValue)
        groups = led.groups.map { $0.map { SS4Profile.LedColor(r: Int($0.r), g: Int($0.g), b: Int($0.b)) } }
        gripSync = false
    }
}

// MARK: - Protobuf ↔ bean

extension SS4Profile {
    private static func point(_ p: Point) -> Protobuf.Writer? { var w = Protobuf.Writer(); w.int(1, p.x); w.int(2, p.y); return w }
    private static func point(_ fs: [Protobuf.Field]?) -> Point { guard let fs else { return Point() }; return Point(x: Protobuf.intValue(fs, 1), y: Protobuf.intValue(fs, 2)) }

    public func protobuf() -> [UInt8] {
        var w = Protobuf.Writer()
        w.int(1, cfgId); w.int(2, protoVersion); w.int(3, packageCount); w.int(4, dataVersion); w.string(5, title)
        var sticks = Protobuf.Writer()
        for (n, j) in [(1, leftStick), (2, rightStick)] {
            var s = Protobuf.Writer()
            s.int(1, j.mapType)
            var mj = Protobuf.Writer(); mj.int(1, j.circularityType); mj.int(2, j.center); mj.int(3, j.edge)
            var sc = Protobuf.Writer(); sc.int(1, j.sensitivity.type); sc.message(2, Self.point(j.sensitivity.point1)); sc.message(3, Self.point(j.sensitivity.point2))
            mj.message(4, sc); s.message(2, mj); s.int(5, j.end)
            sticks.message(n, s)
        }
        w.message(6, sticks)
        var ks = Protobuf.Writer()
        for k in keys {
            var kw = Protobuf.Writer(); kw.int(1, k.keyId); kw.int(2, k.mapType)
            switch k.mapType {
            case 1: var c = Protobuf.Writer(); c.int(1, k.continuousKeyId); c.int(2, k.continuousEnableType); c.int(3, k.frequency); kw.message(4, c)
            case 2: kw.message(5, Protobuf.Writer())
            case 3: var m = Protobuf.Writer(); m.int(1, k.multiFunctionKeyId); kw.message(6, m)
            default: var kk = Protobuf.Writer(); kk.int(1, k.mapControllerKeyId); if let kb = k.mapKeyboardKeyId { kk.int(2, kb, keepZero: true) }; kw.message(3, kk)
            }
            ks.message(1, kw)
        }
        w.message(7, ks)
        var v = Protobuf.Writer(); v.bool(1, vibration.enable)
        for (n, it) in [(2, vibration.left), (3, vibration.right)] { var i = Protobuf.Writer(); i.bool(1, it.enable); i.int(2, it.min); i.int(3, it.max); i.int(4, it.scale); v.message(n, i) }
        w.message(8, v)
        var ts = Protobuf.Writer()
        for (n, t) in [(1, leftTrigger), (2, rightTrigger)] {
            var tw = Protobuf.Writer(); tw.int(1, t.zero); tw.int(2, t.end)
            if let tv = t.vibration {
                var vw = Protobuf.Writer(); vw.bool(1, tv.enable)
                for (m, typed) in [(2, tv.linear), (3, tv.micro)] { var x = Protobuf.Writer(); x.int(1, typed.type); x.int(2, typed.minLevel); x.int(3, typed.maxLevel); x.int(4, typed.filter); x.int(5, typed.minStart); x.int(6, typed.scale); x.int(7, typed.minTime); vw.message(m, x) }
                tw.message(3, vw)
            }
            if let ad = t.adapter {
                var aw = Protobuf.Writer(); aw.int(1, ad.type)
                var bw = Protobuf.Writer(); bw.int(1, ad.bind.type); bw.int(2, ad.bind.filter); bw.int(3, ad.bind.scale); bw.packed(4, ad.bind.param)
                aw.message(2, bw); aw.int(3, ad.mixedBorder); aw.packed(4, ad.param)
                tw.message(4, aw)
            }
            tw.int(5, t.type); tw.message(6, Self.point(t.point1)); tw.message(7, Self.point(t.point2))
            ts.message(n, tw)
        }
        w.message(9, ts)
        var mo = Protobuf.Writer(); mo.int(1, motion.useMode); mo.int(2, motion.mappingType)
        var mj = Protobuf.Writer(); mj.int(1, motion.joystickEnableType); mj.packed(2, motion.joystickEnableKeys); mj.int(3, motion.joystickSensitivity); mj.int(4, motion.joystickDeadZone); mo.message(3, mj)
        var mm = Protobuf.Writer(); mm.int(1, motion.mouseEnableType); mm.packed(2, motion.mouseEnableKeys); mm.int(3, motion.mouseSensitivityX); mm.int(4, motion.mouseSensitivityY); mo.message(4, mm)
        w.message(10, mo)
        if let led {
            var lw = Protobuf.Writer(); lw.int(1, led.version); lw.bool(2, led.clickFeedback); lw.int(3, led.loopStart); lw.int(4, led.loopEnd); lw.int(5, led.loopTime); lw.int(6, led.brightness); lw.int(7, led.rgbNum); lw.int(8, led.ledMode)
            for g in led.groups { var gw = Protobuf.Writer(); for c in g { var cw = Protobuf.Writer(); cw.int(1, c.r); cw.int(2, c.g); cw.int(3, c.b); gw.message(1, cw) }; lw.message(9, gw) }
            lw.bool(10, led.gripSync)
            w.message(11, lw)
        }
        var mc = Protobuf.Writer(); mc.packed(1, macros.offsets); mc.packed(2, macros.interval)
        for it in macros.items {
            var iw = Protobuf.Writer(); iw.int(1, it.keyId); iw.int(2, it.count); iw.int(3, it.type)
            for a in it.actions { var aw = Protobuf.Writer(); aw.int(1, a.keyId); aw.int(2, a.duration); aw.int(3, a.event); iw.message(4, aw) }
            iw.int(5, it.interval); iw.string(6, it.name)
            mc.message(3, iw)
        }
        mc.int(4, macros.version)
        w.message(12, mc)
        w.packed(13, oldLedConfig); w.packed(14, lunpan)
        return w.bytes
    }

    public init(protobuf b: [UInt8]) {
        self.init()
        let fs = Protobuf.fields(b)
        cfgId = Protobuf.intValue(fs, 1); protoVersion = Protobuf.intValue(fs, 2, default: 0x0300); packageCount = Protobuf.intValue(fs, 3, default: 77); dataVersion = Protobuf.intValue(fs, 4); title = Protobuf.stringValue(fs, 5)
        if let sticks = Protobuf.sub(fs, 6) {
            func stick(_ s: [Protobuf.Field]?) -> JoystickParam {
                guard let s else { return JoystickParam() }
                var j = JoystickParam(); j.mapType = Protobuf.intValue(s, 1); j.end = Protobuf.intValue(s, 5)
                if let mj = Protobuf.sub(s, 2) {
                    j.circularityType = Protobuf.intValue(mj, 1); j.center = Protobuf.intValue(mj, 2); j.edge = Protobuf.intValue(mj, 3)
                    if let sc = Protobuf.sub(mj, 4) { j.sensitivity = JoystickSensitivity(type: Protobuf.intValue(sc, 1), point1: Self.point(Protobuf.sub(sc, 2)), point2: Self.point(Protobuf.sub(sc, 3))) }
                }
                return j
            }
            leftStick = stick(Protobuf.sub(sticks, 1)); rightStick = stick(Protobuf.sub(sticks, 2))
        }
        if let ks = Protobuf.sub(fs, 7) {
            for kf in Protobuf.subs(ks, 1) {
                var k = Key(); k.keyId = Protobuf.intValue(kf, 1); k.mapType = Protobuf.intValue(kf, 2)
                if let kk = Protobuf.sub(kf, 3) { k.mapControllerKeyId = Protobuf.intValue(kk, 1); if let f = Protobuf.first(kk, 2) { k.mapKeyboardKeyId = Protobuf.int(f) } }
                if let c = Protobuf.sub(kf, 4) { k.continuousKeyId = Protobuf.intValue(c, 1); k.continuousEnableType = Protobuf.intValue(c, 2); k.frequency = Protobuf.intValue(c, 3) }
                if let m = Protobuf.sub(kf, 6) { k.multiFunctionKeyId = Protobuf.intValue(m, 1) }
                keys.append(k)
            }
        }
        if let v = Protobuf.sub(fs, 8) {
            vibration.enable = Protobuf.boolValue(v, 1)
            func item(_ i: [Protobuf.Field]?) -> VibrationItem { guard let i else { return VibrationItem() }; return VibrationItem(enable: Protobuf.boolValue(i, 1), min: Protobuf.intValue(i, 2), max: Protobuf.intValue(i, 3), scale: Protobuf.intValue(i, 4)) }
            vibration.left = item(Protobuf.sub(v, 2)); vibration.right = item(Protobuf.sub(v, 3))
        }
        if let ts = Protobuf.sub(fs, 9) {
            func trigger(_ t: [Protobuf.Field]?) -> Trigger {
                guard let t else { return Trigger() }
                var tr = Trigger(); tr.zero = Protobuf.intValue(t, 1); tr.end = Protobuf.intValue(t, 2); tr.type = Protobuf.intValue(t, 5); tr.point1 = Self.point(Protobuf.sub(t, 6)); tr.point2 = Self.point(Protobuf.sub(t, 7))
                if let vw = Protobuf.sub(t, 3) {
                    func typed(_ x: [Protobuf.Field]?) -> TriggerVibrationTyped { guard let x else { return TriggerVibrationTyped() }; return TriggerVibrationTyped(type: Protobuf.intValue(x, 1), minLevel: Protobuf.intValue(x, 2), maxLevel: Protobuf.intValue(x, 3), filter: Protobuf.intValue(x, 4), minStart: Protobuf.intValue(x, 5), scale: Protobuf.intValue(x, 6), minTime: Protobuf.intValue(x, 7)) }
                    tr.vibration = TriggerVibration(enable: Protobuf.boolValue(vw, 1), linear: typed(Protobuf.sub(vw, 2)), micro: typed(Protobuf.sub(vw, 3)))
                }
                if let aw = Protobuf.sub(t, 4) {
                    var ad = TriggerAdapter(); ad.type = Protobuf.intValue(aw, 1); ad.mixedBorder = Protobuf.intValue(aw, 3); ad.param = Protobuf.ints(aw, 4)
                    if let bw = Protobuf.sub(aw, 2) { ad.bind = TriggerBind(type: Protobuf.intValue(bw, 1), filter: Protobuf.intValue(bw, 2), scale: Protobuf.intValue(bw, 3), param: Protobuf.ints(bw, 4)) }
                    tr.adapter = ad
                }
                return tr
            }
            leftTrigger = trigger(Protobuf.sub(ts, 1)); rightTrigger = trigger(Protobuf.sub(ts, 2))
        }
        if let mo = Protobuf.sub(fs, 10) {
            motion.useMode = Protobuf.intValue(mo, 1); motion.mappingType = Protobuf.intValue(mo, 2)
            if let mj = Protobuf.sub(mo, 3) { motion.joystickEnableType = Protobuf.intValue(mj, 1); motion.joystickEnableKeys = Protobuf.ints(mj, 2); motion.joystickSensitivity = Protobuf.intValue(mj, 3); motion.joystickDeadZone = Protobuf.intValue(mj, 4) }
            if let mm = Protobuf.sub(mo, 4) { motion.mouseEnableType = Protobuf.intValue(mm, 1); motion.mouseEnableKeys = Protobuf.ints(mm, 2); motion.mouseSensitivityX = Protobuf.intValue(mm, 3); motion.mouseSensitivityY = Protobuf.intValue(mm, 4) }
        }
        if let lw = Protobuf.sub(fs, 11) {
            var l = Led(); l.version = Protobuf.intValue(lw, 1); l.clickFeedback = Protobuf.boolValue(lw, 2); l.loopStart = Protobuf.intValue(lw, 3); l.loopEnd = Protobuf.intValue(lw, 4); l.loopTime = Protobuf.intValue(lw, 5); l.brightness = Protobuf.intValue(lw, 6); l.rgbNum = Protobuf.intValue(lw, 7); l.ledMode = Protobuf.intValue(lw, 8); l.gripSync = Protobuf.boolValue(lw, 10)
            l.groups = Protobuf.subs(lw, 9).map { g in Protobuf.subs(g, 1).map { c in LedColor(r: Protobuf.intValue(c, 1), g: Protobuf.intValue(c, 2), b: Protobuf.intValue(c, 3)) } }
            led = l
        }
        if let mc = Protobuf.sub(fs, 12) {
            macros.offsets = Protobuf.ints(mc, 1); macros.interval = Protobuf.ints(mc, 2); macros.version = Protobuf.intValue(mc, 4)
            for iw in Protobuf.subs(mc, 3) {
                var it = MacroItem(); it.keyId = Protobuf.intValue(iw, 1); it.count = Protobuf.intValue(iw, 2); it.type = Protobuf.intValue(iw, 3); it.interval = Protobuf.intValue(iw, 5); it.name = Protobuf.stringValue(iw, 6)
                it.actions = Protobuf.subs(iw, 4).map { a in MacroAction(keyId: Protobuf.intValue(a, 1), duration: Protobuf.intValue(a, 2), event: Protobuf.intValue(a, 3)) }
                macros.items.append(it)
            }
        }
        oldLedConfig = Protobuf.ints(fs, 13); lunpan = Protobuf.ints(fs, 14)
        sanitize()
    }

    // MARK: Share string ("0A-1B-…", what the code resolves to)

    public var shareString: String { protobuf().map { String(format: "%02X", $0) }.joined(separator: "-") }

    /// Untrusted input (a downloaded code) must never crash the app: every byte-valued field is clamped to what the
    /// blob can hold before any arithmetic, macro lists are capped to what fits.
    public mutating func sanitize() {
        func b(_ v: inout Int) { v = min(max(v, 0), 255) }
        func bs(_ a: inout [Int], _ n: Int) { a = a.prefix(n).map { min(max($0, 0), 255) } }
        protoVersion = min(max(protoVersion, 0), 0xFFFF); packageCount = min(max(packageCount, 0), 255); dataVersion = min(max(dataVersion, 0), 0xFFFF)
        title = String(title.prefix(10))
        for s in [\SS4Profile.leftStick, \SS4Profile.rightStick] {
            b(&self[keyPath: s].center); b(&self[keyPath: s].end); b(&self[keyPath: s].edge); b(&self[keyPath: s].sensitivity.type)
            b(&self[keyPath: s].sensitivity.point1.x); b(&self[keyPath: s].sensitivity.point1.y); b(&self[keyPath: s].sensitivity.point2.x); b(&self[keyPath: s].sensitivity.point2.y)
        }
        keys = Array(keys.prefix(32))
        for i in keys.indices { b(&keys[i].keyId); b(&keys[i].mapType); b(&keys[i].mapControllerKeyId); b(&keys[i].continuousKeyId); b(&keys[i].continuousEnableType); b(&keys[i].frequency); b(&keys[i].multiFunctionKeyId) }
        for v in [\SS4Profile.vibration.left, \SS4Profile.vibration.right] { b(&self[keyPath: v].min); b(&self[keyPath: v].max); b(&self[keyPath: v].scale) }
        for t in [\SS4Profile.leftTrigger, \SS4Profile.rightTrigger] {
            b(&self[keyPath: t].zero); b(&self[keyPath: t].end); b(&self[keyPath: t].type)
            b(&self[keyPath: t].point1.x); b(&self[keyPath: t].point1.y); b(&self[keyPath: t].point2.x); b(&self[keyPath: t].point2.y)
            if var ad = self[keyPath: t].adapter { b(&ad.type); b(&ad.bind.type); b(&ad.bind.filter); b(&ad.bind.scale); bs(&ad.bind.param, 5); b(&ad.mixedBorder); bs(&ad.param, 10); self[keyPath: t].adapter = ad }
            if var tv = self[keyPath: t].vibration {
                for k in [\SS4Profile.TriggerVibration.linear, \SS4Profile.TriggerVibration.micro] { b(&tv[keyPath: k].type); b(&tv[keyPath: k].minLevel); b(&tv[keyPath: k].maxLevel); b(&tv[keyPath: k].filter); b(&tv[keyPath: k].minStart); b(&tv[keyPath: k].scale); b(&tv[keyPath: k].minTime) }
                self[keyPath: t].vibration = tv
            }
        }
        b(&motion.useMode); b(&motion.mappingType); b(&motion.joystickEnableType); b(&motion.joystickSensitivity); b(&motion.joystickDeadZone); bs(&motion.joystickEnableKeys, 2); bs(&motion.mouseEnableKeys, 2)
        macros.items = Array(macros.items.prefix(Self.maxMacros(protoVersion)))
        for i in macros.items.indices {
            b(&macros.items[i].keyId); b(&macros.items[i].type); macros.items[i].count = min(max(macros.items[i].count, 0), 0xFFFF)
            macros.items[i].actions = Array(macros.items[i].actions.prefix(128))
            for j in macros.items[i].actions.indices { b(&macros.items[i].actions[j].keyId); b(&macros.items[i].actions[j].event); macros.items[i].actions[j].duration = min(max(macros.items[i].actions[j].duration, 0), 60_000) }
        }
        bs(&oldLedConfig, 10); bs(&lunpan, 2)
    }

    public init?(shareString s: String) {
        var text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 { text = String(text.dropFirst().dropLast()) }
        let parts = text.split(separator: "-")
        var bytes: [UInt8] = []; bytes.reserveCapacity(parts.count)
        for p in parts { guard let b = UInt8(p, radix: 16) else { return nil }; bytes.append(b) }
        guard !bytes.isEmpty else { return nil }
        self.init(protobuf: bytes)
    }
}

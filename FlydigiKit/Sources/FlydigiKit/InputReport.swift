// Live controller state decoded from the pad's own reports, in both USB modes. Bit layout matches Space
// Station's `OperatorDataParser`; verified on an Apex 4 (docs/protocol.md §9).
//
// - DInput: vendor-interface input report id 4, 32 bytes including the id (`04 FE …`).
// - XInput: the 32-byte interrupt report Apple's driver also receives. Bytes 0…13 are the standard Xbox 360
//   report; bytes 14…26 carry Flydigi's extra state (every key incl. paddles, sticks, triggers).

import Foundation

public struct ControllerState: Sendable, Hashable {
    public var pressed: Set<ControllerKey>
    public var leftX: Float, leftY: Float          // −1…1, up = +Y
    public var rightX: Float, rightY: Float
    public var leftTrigger: Float, rightTrigger: Float   // 0…1

    /// DInput status report (`04 FE …`); `nil` for anything else (command replies use `04 FF`).
    public init?(dinputReport r: [UInt8]) {
        guard r.count >= 32, r[0] == 4, r[1] == 0xFE else { return nil }
        self.init(keys1: r[9], keys2: r[10], keysExtra: r[7], keysSystem: r[8],
                  lx: r[17], ly: r[19], rx: r[21], ry: r[22], lt: r[23], rt: r[24], centre: 127.5)
    }

    /// XInput interrupt report (`00 14 …`, 32 bytes) with Flydigi's appended state.
    public init?(xinputReport r: [UInt8]) {
        guard r.count >= 32, r[0] == 0x00, r[1] == 0x14 else { return nil }
        self.init(keys1: r[17], keys2: r[18], keysExtra: r[19], keysSystem: r[20],
                  lx: r[21], ly: r[22], rx: r[23], ry: r[24], lt: r[25], rt: r[26], centre: 128)
    }

    private init(keys1 b1: UInt8, keys2 b2: UInt8, keysExtra b3: UInt8, keysSystem b4: UInt8,
                 lx: UInt8, ly: UInt8, rx: UInt8, ry: UInt8, lt: UInt8, rt: UInt8, centre: Float) {
        var keys: Set<ControllerKey> = []
        if b1 & 0x01 != 0 { keys.insert(.up) }; if b1 & 0x02 != 0 { keys.insert(.right) }
        if b1 & 0x04 != 0 { keys.insert(.down) }; if b1 & 0x08 != 0 { keys.insert(.left) }
        if b1 & 0x10 != 0 { keys.insert(.a) }; if b1 & 0x20 != 0 { keys.insert(.b) }
        if b1 & 0x40 != 0 { keys.insert(.select) }; if b1 & 0x80 != 0 { keys.insert(.x) }
        if b2 & 0x01 != 0 { keys.insert(.y) }; if b2 & 0x02 != 0 { keys.insert(.start) }
        if b2 & 0x04 != 0 { keys.insert(.lb) }; if b2 & 0x08 != 0 { keys.insert(.rb) }
        if b2 & 0x10 != 0 { keys.insert(.lt) }; if b2 & 0x20 != 0 { keys.insert(.rt) }
        if b2 & 0x40 != 0 { keys.insert(.thumbL) }; if b2 & 0x80 != 0 { keys.insert(.thumbR) }
        if b3 & 0x01 != 0 { keys.insert(.c) }; if b3 & 0x02 != 0 { keys.insert(.z) }
        if b3 & 0x04 != 0 { keys.insert(.m1) }; if b3 & 0x08 != 0 { keys.insert(.m2) }
        if b3 & 0x10 != 0 { keys.insert(.m3) }; if b3 & 0x20 != 0 { keys.insert(.m4) }
        if b3 & 0x40 != 0 { keys.insert(.m5) }; if b3 & 0x80 != 0 { keys.insert(.m6) }
        if b4 & 0x01 != 0 { keys.insert(.menu) }; if b4 & 0x02 != 0 { keys.insert(.turbo) }
        if b4 & 0x08 != 0 { keys.insert(.home) }; if b4 & 0x10 != 0 { keys.insert(.back) }
        pressed = keys
        func axis(_ v: UInt8) -> Float { max(-1, min(1, (Float(v) - centre) / 127.5)) }
        leftX = axis(lx); leftY = -axis(ly)
        rightX = axis(rx); rightY = -axis(ry)
        leftTrigger = Float(lt) / 255; rightTrigger = Float(rt) / 255
    }
}

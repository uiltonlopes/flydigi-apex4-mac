// Live controller state from the DInput vendor-interface input report (report id 4, 32 bytes including
// the id). Bit layout matches Space Station's `OperatorDataParser` shifted by one for the report-id byte;
// verified on an Apex 4 (docs/protocol.md §9).

import Foundation

public struct DInputState: Sendable, Hashable {
    public static let reportId: UInt8 = 4
    public static let length = 32

    public var pressed: Set<ControllerKey>
    public var leftX: Float, leftY: Float          // −1…1, up = +Y
    public var rightX: Float, rightY: Float
    public var leftTrigger: Float, rightTrigger: Float   // 0…1

    /// `nil` when the bytes are not a status report.
    public init?(report r: [UInt8]) {
        guard r.count >= DInputState.length, r[0] == DInputState.reportId, r[1] == 0xFE else { return nil }
        var keys: Set<ControllerKey> = []
        let b9 = r[9], b10 = r[10], b7 = r[7], b8 = r[8]
        if b9 & 0x01 != 0 { keys.insert(.up) }; if b9 & 0x02 != 0 { keys.insert(.right) }
        if b9 & 0x04 != 0 { keys.insert(.down) }; if b9 & 0x08 != 0 { keys.insert(.left) }
        if b9 & 0x10 != 0 { keys.insert(.a) }; if b9 & 0x20 != 0 { keys.insert(.b) }
        if b9 & 0x40 != 0 { keys.insert(.select) }; if b9 & 0x80 != 0 { keys.insert(.x) }
        if b10 & 0x01 != 0 { keys.insert(.y) }; if b10 & 0x02 != 0 { keys.insert(.start) }
        if b10 & 0x04 != 0 { keys.insert(.lb) }; if b10 & 0x08 != 0 { keys.insert(.rb) }
        if b10 & 0x10 != 0 { keys.insert(.lt) }; if b10 & 0x20 != 0 { keys.insert(.rt) }
        if b10 & 0x40 != 0 { keys.insert(.thumbL) }; if b10 & 0x80 != 0 { keys.insert(.thumbR) }
        if b7 & 0x01 != 0 { keys.insert(.c) }; if b7 & 0x02 != 0 { keys.insert(.z) }
        if b7 & 0x04 != 0 { keys.insert(.m1) }; if b7 & 0x08 != 0 { keys.insert(.m2) }
        if b7 & 0x10 != 0 { keys.insert(.m3) }; if b7 & 0x20 != 0 { keys.insert(.m4) }
        if b7 & 0x40 != 0 { keys.insert(.m5) }; if b7 & 0x80 != 0 { keys.insert(.m6) }
        if b8 & 0x01 != 0 { keys.insert(.menu) }; if b8 & 0x02 != 0 { keys.insert(.turbo) }
        if b8 & 0x08 != 0 { keys.insert(.home) }; if b8 & 0x10 != 0 { keys.insert(.back) }
        pressed = keys
        func axis(_ v: UInt8) -> Float { max(-1, min(1, (Float(v) - 127.5) / 127.5)) }
        leftX = axis(r[17]); leftY = -axis(r[19])
        rightX = axis(r[21]); rightY = -axis(r[22])
        leftTrigger = Float(r[23]) / 255; rightTrigger = Float(r[24]) / 255
    }
}

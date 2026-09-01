// The 500-byte LED configuration blob (docs/protocol.md §5).

import Foundation

public struct LEDConfig: Sendable, Hashable {
    public static let length = 500
    public static let groupCount = 16
    public static let unitsPerGroup = 10
    static let groupsOffset = 20

    public enum Mode: UInt8, Sendable, CaseIterable, Hashable {
        case off = 0, streamlined = 1, breathing = 2, gradient = 3, feedback = 4, steady = 5
    }

    /// One colour step of a group. Channels are **percent** (0–100), not 0–255.
    public struct Unit: Sendable, Hashable {
        public var r: UInt8, g: UInt8, b: UInt8
        public init(r: UInt8, g: UInt8, b: UInt8) { (self.r, self.g, self.b) = (min(r, 100), min(g, 100), min(b, 100)) }
        public static let off = Unit(r: 0, g: 0, b: 0)
        public var isOff: Bool { r == 0 && g == 0 && b == 0 }
        /// From 8-bit sRGB.
        public init(rgb8 r: UInt8, _ g: UInt8, _ b: UInt8) {
            self.init(r: UInt8(Int(r) * 100 / 255), g: UInt8(Int(g) * 100 / 255), b: UInt8(Int(b) * 100 / 255))
        }
    }

    public var versionMajor: UInt8, versionMinor: UInt8
    public var type: UInt8
    public var loopStart: UInt8
    public var loopEnd: UInt8
    public var speed: UInt8          // 0–100
    public var brightness: UInt8     // 0–100
    public var activeGroups: UInt8   // Apex 4: 4
    public var mode: Mode
    public var reserved: [UInt8]     // 11 bytes, FF
    public var groups: [[Unit]]      // 16 × 10

    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.length, let mode = Mode(rawValue: bytes[8]) else { return nil }
        versionMajor = bytes[0]; versionMinor = bytes[1]; type = bytes[2]; loopStart = bytes[3]; loopEnd = bytes[4]
        speed = bytes[5]; brightness = bytes[6]; activeGroups = bytes[7]; self.mode = mode
        reserved = Array(bytes[9..<20])
        groups = (0..<Self.groupCount).map { g in
            (0..<Self.unitsPerGroup).map { u in
                let o = Self.groupsOffset + g * 30 + u * 3
                return Unit(r: bytes[o], g: bytes[o + 1], b: bytes[o + 2])
            }
        }
    }

    public var bytes: [UInt8] {
        var out: [UInt8] = [versionMajor, versionMinor, type, loopStart, loopEnd, speed, brightness, activeGroups, mode.rawValue]
        out += reserved
        for g in groups { for u in g { out += [u.r, u.g, u.b] } }
        precondition(out.count == Self.length)
        return out
    }

    // MARK: Convenience edits (mirror Space Station behaviour)

    /// Solid colour on every active group.
    public mutating func setSteady(_ colour: Unit) {
        mode = .steady
        for g in 0..<Int(activeGroups) {
            groups[g] = [colour] + Array(repeating: .off, count: Self.unitsPerGroup - 1)
        }
    }

    /// Multi-colour cycle (gradient/breathing/streamlined) on every active group.
    public mutating func setCycle(_ colours: [Unit], mode: Mode) {
        precondition(!colours.isEmpty && colours.count <= Self.unitsPerGroup)
        self.mode = mode
        let padded = colours + Array(repeating: .off, count: Self.unitsPerGroup - colours.count)
        for g in 0..<Int(activeGroups) { groups[g] = padded }
    }

    public func colours(ofGroup g: Int) -> [Unit] { groups[g].filter { !$0.isOff } }
}

// The 500-byte LED configuration blob (docs/protocol.md §5).

import Foundation

public struct LEDConfig: Sendable, Hashable {
    public static let length = 500
    public static let groupCount = 16
    public static let unitsPerGroup = 10
    static let groupsOffset = 20

    /// Space Station's `LedType` (Unknown 0, FLOW 1, BREATH 2, GRADIENT 3, FEEDBACK 4, ON 5, Close 6, Default 7).
    public enum Mode: UInt8, Sendable, CaseIterable, Hashable {
        case unknown = 0, streamlined = 1, breathing = 2, gradient = 3, feedback = 4, steady = 5, off = 6, factoryDefault = 7
        /// Modes the user can pick.
        public static let selectable: [Mode] = [.off, .steady, .breathing, .gradient, .streamlined, .feedback]
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
    public var type: UInt8           // Space Station "ClickFeedback" flag (1 only in Feedback mode)
    public var loopStart: UInt8      // always 0
    public var loopEnd: UInt8        // last unit index the firmware cycles through — depends on the mode (see setCycle)
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

    // MARK: Convenience edits (mirror Space Station's `ConvertLedConfigToBean` for k2)
    //
    // The firmware plays units `loopStart…loopEnd` of each group. Space Station encodes:
    //   On (steady)  → every unit = the colour, loopEnd 0
    //   Gradient     → units 0…n-1 = colours, loopEnd n-1
    //   Breath       → units 0,2,4… = colours with black in between, loopEnd 2n-1 (the black is the dip)
    //   Feedback     → units 0…n-1 = colours, loopEnd n, ClickFeedback flag = 1
    //   Flow         → colours untouched, loopEnd = number of LED groups
    //   Close        → mode 6

    /// Solid colour on every active group.
    public mutating func setSteady(_ colour: Unit) {
        mode = .steady; type = 0; loopStart = 0; loopEnd = 0
        for g in 0..<Int(activeGroups) { groups[g] = Array(repeating: colour, count: Self.unitsPerGroup) }
    }

    /// Multi-colour effect (gradient / breathing / streamlined / feedback) on every active group.
    public mutating func setCycle(_ colours: [Unit], mode: Mode) {
        precondition(!colours.isEmpty)
        let n = min(colours.count, mode == .breathing ? Self.unitsPerGroup / 2 : Self.unitsPerGroup)
        let cs = Array(colours.prefix(n))
        self.mode = mode; loopStart = 0; type = mode == .feedback ? 1 : 0
        var units = [Unit](repeating: .off, count: Self.unitsPerGroup)
        switch mode {
        case .breathing:
            for (i, c) in cs.enumerated() { units[i * 2] = c }
            loopEnd = UInt8(n * 2 - 1)
        case .feedback:
            for (i, c) in cs.enumerated() { units[i] = c }
            loopEnd = UInt8(n)
        case .streamlined:
            loopEnd = activeGroups
            return                                  // Space Station leaves the colours as they are
        default:                                    // gradient
            for (i, c) in cs.enumerated() { units[i] = c }
            loopEnd = UInt8(n - 1)
        }
        for g in 0..<Int(activeGroups) { groups[g] = units }
    }

    public mutating func setOff() { mode = .off; type = 0 }

    /// The user-facing colour list of a group, undoing the per-mode layout above.
    public func colours(ofGroup g: Int) -> [Unit] {
        let u = groups[g]
        switch mode {
        case .steady: return u.first.map { [$0] } ?? []
        case .breathing: return stride(from: 0, to: u.count, by: 2).map { u[$0] }.filter { !$0.isOff }
        default: return u.filter { !$0.isOff }
        }
    }
}

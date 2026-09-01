// LCD image encoding (LVGL v8, RGB565 big-endian) and the upload plan (docs/protocol.md §6).

import Foundation

public enum Screen {
    public static let width = 160
    public static let height = 80
    public static let maxFrames = 35
    public static let frameLength = 4 + width * height * 2   // 25 604
    public static let chunk = 26                              // payload bytes per data packet

    /// Encode one frame from tightly packed 8-bit RGB (width*height*3 bytes) into the controller's
    /// LVGL binary: header `cf=4 | w<<10 | h<<21` (LE) + RGB565 **big-endian** pixels.
    /// Channel quantisation mirrors Flydigi's converter: round(x/8) for R/B, round(x/4) for G.
    public static func encodeFrame(rgb: [UInt8], width w: Int = width, height h: Int = height) -> [UInt8] {
        precondition(rgb.count == w * h * 3, "expected \(w)x\(h) RGB8")
        var out = [UInt8](repeating: 0, count: 4 + w * h * 2)
        let header = UInt32(4) | UInt32(w) << 10 | UInt32(h) << 21
        out[0] = UInt8(header & 0xFF); out[1] = UInt8(header >> 8 & 0xFF)
        out[2] = UInt8(header >> 16 & 0xFF); out[3] = UInt8(header >> 24)
        var o = 4
        var i = 0
        while i < rgb.count {
            let r5 = min(31, (Int(rgb[i]) + 4) / 8)
            let g6 = min(63, (Int(rgb[i + 1]) + 2) / 4)
            let b5 = min(31, (Int(rgb[i + 2]) + 4) / 8)
            let px = UInt16(r5) << 11 | UInt16(g6) << 5 | UInt16(b5)
            out[o] = UInt8(px >> 8); out[o + 1] = UInt8(px & 0xFF)   // big-endian
            o += 2; i += 3
        }
        return out
    }

    /// Decode a frame header back to (cf, w, h) — handy for tests and validation.
    public static func header(of frame: [UInt8]) -> (cf: Int, width: Int, height: Int)? {
        guard frame.count >= 4 else { return nil }
        let v = UInt32(frame[0]) | UInt32(frame[1]) << 8 | UInt32(frame[2]) << 16 | UInt32(frame[3]) << 24
        return (Int(v & 0x1F), Int(v >> 10 & 0x7FF), Int(v >> 21 & 0x7FF))
    }
}

/// The exact packet sequence for an animation upload over XInput, as a resumable plan.
/// Each step is a packet to send plus the ack we expect back.
public struct ScreenUploadPlan: Sendable {
    public enum Step: Sendable, Hashable {
        case start(frame: Int, packet: [UInt8])
        case data(frame: Int, offset: Int, packet: [UInt8])
        case end(frame: Int, packet: [UInt8])
        case endAll(packet: [UInt8])

        public var packet: [UInt8] {
            switch self {
            case let .start(_, p), let .data(_, _, p), let .end(_, p), let .endAll(p): return p
            }
        }
        /// Screen-ack command bytes that complete this step. The firmware answers EndAll (D3) with a D2 ack.
        public var acceptedAcks: Set<UInt8> {
            switch self {
            case .start: return [XInput.Cmd.screenStart]
            case .data: return [XInput.Cmd.screenData]
            case .end: return [XInput.Cmd.screenEnd]
            case .endAll: return [XInput.Cmd.screenEnd, XInput.Cmd.screenEndAll]
            }
        }
        public var isData: Bool { if case .data = self { return true } else { return false } }
        public var debugName: String {
            switch self {
            case let .start(f, _): return "start(frame \(f))"
            case let .data(f, o, _): return "data(frame \(f), offset \(o))"
            case let .end(f, _): return "end(frame \(f))"
            case .endAll: return "endAll"
            }
        }
    }

    public let frames: [[UInt8]]
    public let gifType: UInt8 = 1

    public init(frames: [[UInt8]]) {
        precondition(!frames.isEmpty && frames.count <= Screen.maxFrames)
        self.frames = frames
    }

    public var totalBytes: Int { frames.reduce(0) { $0 + $1.count } }
    public var packetCount: Int { frames.reduce(1) { $0 + 2 + ($1.count + Screen.chunk - 1) / Screen.chunk } }

    /// Every step in order: per-frame steps for each frame, then EndAll. Frame numbers are 1-based.
    public func steps() -> [Step] {
        var out: [Step] = []
        for (idx, frame) in frames.enumerated() { out += Self.frameSteps(frame, index: idx + 1, of: frames.count) }
        out.append(Self.endAllStep(frameCount: frames.count))
        return out
    }

    /// start → data… → end for one frame (`index` 1-based, `total` = number of frames in the animation).
    public static func frameSteps(_ frame: [UInt8], index: Int, of total: Int, gifType: UInt8 = 1) -> [Step] {
        precondition((1...total).contains(index) && total <= Screen.maxFrames)
        var out: [Step] = []
        let n = UInt8(total), num = UInt8(index), size = frame.count
        // A5 D0 09 01 gifType N num 02 sizeHi sizeLo crc(1..9)
        var start: [UInt8] = [XInput.prefix, XInput.Cmd.screenStart, 0x09, 0x01, gifType, n, num, 0x02,
                              UInt8(size >> 8), UInt8(size & 0xFF), 0, 0, 0, 0, 0]
        start[10] = start[1...9].reduce(0) { $0 &+ $1 }
        out.append(.start(frame: index, packet: start))
        var offset = 0
        while offset < size {
            let end = min(offset + Screen.chunk, size)
            var p: [UInt8] = [XInput.prefix, XInput.Cmd.screenData, UInt8(offset >> 8), UInt8(offset & 0xFF)]
            p += frame[offset..<end]
            p += [UInt8](repeating: 0xFF, count: Screen.chunk - (end - offset))
            p.append(0)
            out.append(.data(frame: index, offset: offset, packet: Checksum.apply(p, from: 1)))
            offset = end
        }
        // A5 D2 07 01 num sentHi sentLo 00 crc(1..7)
        var endPkt: [UInt8] = [XInput.prefix, XInput.Cmd.screenEnd, 0x07, 0x01, num, UInt8(size >> 8), UInt8(size & 0xFF), 0, 0, 0, 0, 0, 0, 0, 0]
        endPkt[8] = endPkt[1...7].reduce(0) { $0 &+ $1 }
        out.append(.end(frame: index, packet: endPkt))
        return out
    }

    public static func endAllStep(frameCount: Int) -> Step {
        var all: [UInt8] = [XInput.prefix, XInput.Cmd.screenEndAll, 0x07, 0x01, UInt8(frameCount), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        all[8] = all[1...7].reduce(0) { $0 &+ $1 }
        return .endAll(packet: all)
    }
}

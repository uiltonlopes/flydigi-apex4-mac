// Telink firmware image as Space Station's flasher reads it (docs/firmware-update.md §4). Pure parsing and
// checks — nothing here talks to hardware.

import Foundation

public struct FirmwareImage: Sendable {
    public let data: Data
    /// Bytes the OTA actually transmits (u32 LE at 0x18).
    public let payloadSize: Int
    /// u32 LE at 0x02 — informational in Space Station's tool.
    public let versionField: UInt32
    /// Trailing CRC32 (u32 LE at payloadSize − 4) as stored in the file.
    public let storedCRC: UInt32
    /// CRC32 (IEEE, reflected) computed over `0 ..< payloadSize − 4`.
    public let computedCRC: UInt32
    /// "KNLT" boot mark at 0x08 (Telink convention).
    public let hasBootMark: Bool

    public var crcMatches: Bool { storedCRC == computedCRC }
    /// OTA packets of 16 bytes the flasher will send.
    public var packetCount: Int { (payloadSize + 15) / 16 }

    public enum Problem: Error, CustomStringConvertible, Sendable {
        case tooSmall, sizeFieldInvalid(Int), crcPlaceholder, crcMismatch(stored: UInt32, computed: UInt32), noBootMark
        public var description: String {
            switch self {
            case .tooSmall: "file too small to be a firmware image"
            case .sizeFieldInvalid(let n): "size field (\(n)) does not fit the file"
            case .crcPlaceholder: "trailing CRC is a placeholder (0 / FFFFFFFF)"
            case .crcMismatch(let s, let c): String(format: "CRC32 mismatch: file %08x, computed %08x", s, c)
            case .noBootMark: "missing Telink boot mark (KNLT) at 0x08"
            }
        }
    }

    public init(data: Data) throws {
        guard data.count >= 0x20 + 4 else { throw Problem.tooSmall }
        func u32(_ o: Int) -> UInt32 { UInt32(data[o]) | UInt32(data[o + 1]) << 8 | UInt32(data[o + 2]) << 16 | UInt32(data[o + 3]) << 24 }
        let size = Int(u32(0x18))
        guard size >= 0x20, size <= data.count, size <= 2 * 1024 * 1024 else { throw Problem.sizeFieldInvalid(size) }
        self.data = data
        payloadSize = size
        versionField = u32(0x02)
        storedCRC = u32(size - 4)
        computedCRC = FirmwareImage.crc32(data.subdata(in: 0..<(size - 4)))
        hasBootMark = data[8..<12].elementsEqual("KNLT".utf8)
    }

    /// Full validation the way we want it (stricter than Space Station, which only checks the CRC is not a placeholder).
    public func validate() throws {
        if storedCRC == 0 || storedCRC == 0xFFFF_FFFF { throw Problem.crcPlaceholder }
        if !crcMatches { throw Problem.crcMismatch(stored: storedCRC, computed: computedCRC) }
        if !hasBootMark { throw Problem.noBootMark }
    }

    /// Payload as the OTA sends it: 16-byte blocks, last one padded with 0xFF.
    public func block(_ index: Int) -> [UInt8] {
        let start = index * 16
        var b = [UInt8](repeating: 0xFF, count: 16)
        for i in 0..<16 where start + i < payloadSize { b[i] = data[start + i] }
        return b
    }

    // MARK: CRCs used by the OTA

    public static func crc32(_ d: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in d {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    /// CRC-16/MODBUS (init 0xFFFF, reflected poly 0xA001) over a 20-byte OTA packet's first 18 bytes.
    public static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in bytes {
            crc ^= UInt16(b)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        return crc
    }
}

/// Version strings the way the firmware reports them: two bytes, nibble-wise ("6.8.3.7" ⇔ 0x68 0x37).
public enum FirmwareVersion {
    public static func string(hi: UInt8, lo: UInt8) -> String { "\(hi >> 4).\(hi & 0xF).\(lo >> 4).\(lo & 0xF)" }
    /// Numeric compare of dotted versions ("6.8.3.7" > "6.8.3.0").
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }, pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

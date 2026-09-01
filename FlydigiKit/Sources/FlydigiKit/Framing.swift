// Wire framing for the Flydigi Apex 4 vendor channel.
// See docs/protocol.md §2–3. Everything here is pure: bytes in, bytes out.

import Foundation

/// The two USB personalities of the controller that expose a vendor channel.
public enum Channel: Sendable, Hashable {
    /// `045e:028e`, interface 0, interrupt OUT ep5 / IN ep1. Needs root on macOS.
    case xinput
    /// `04b4:2412`, HID interface 2 (usage page 0xFFA0), output report id 5. Unprivileged.
    case dinput
}

public enum USBID {
    public static let xinputVendor: UInt16 = 0x045E
    public static let xinputProduct: UInt16 = 0x028E
    public static let dinputVendor: UInt16 = 0x04B4
    public static let dinputProduct: UInt16 = 0x2412
    public static let dinputVendorInterface = 2
    public static let dinputVendorUsagePage: UInt32 = 0xFFA0
}

/// Byte-sum checksum used everywhere in the protocol: `sum(bytes[start..<end-1]) & 0xFF`
/// written into the last byte.
public enum Checksum {
    @inlinable
    public static func apply(_ packet: [UInt8], from start: Int = 0) -> [UInt8] {
        var out = packet
        let sum = out[start..<(out.count - 1)].reduce(0) { $0 &+ $1 }
        out[out.count - 1] = sum
        return out
    }
}

// MARK: - XInput framing

public enum XInput {
    /// Command packets are 15 bytes: `A5 cmd args… crc`.
    public static let commandLength = 15
    public static let prefix: UInt8 = 0xA5
    static let parcelPayload = 10
    static let specifyConfigId: UInt8 = 0xA0

    public enum Cmd {
        public static let deviceInfo: UInt8 = 0x10
        public static let dongleInfo: UInt8 = 0x11
        public static let motorTest: UInt8 = 0x12         // A5 12 <L> <R>
        public static let switchToDInput: UInt8 = 0x17
        public static let mappingEnable: UInt8 = 0x18      // A5 18 <1=off,2=on>
        public static let currentConfigId: UInt8 = 0x20    // reply r[15]=20, cfg r[16]
        public static let module: UInt8 = 0x30             // A5 30 01 versions · 02/03 status bar get/set · 04/05 sleep get/set · 06 ForceAdapt
        public static let readConfig: UInt8 = 0x21        // reply 0x22
        public static let configReply: UInt8 = 0x22
        public static let configStartAck: UInt8 = 0x23
        public static let writeConfigData: UInt8 = 0x24
        public static let writeConfigStart: UInt8 = 0x25
        public static let readLED: UInt8 = 0x26           // reply 0x27
        public static let ledReply: UInt8 = 0x27
        public static let writeLEDData: UInt8 = 0x29
        public static let writeLEDStart: UInt8 = 0x2A
        public static let subFunc: UInt8 = 0x50           // 0x50 02 = read random id, 0x50 03 = save flash
        public static let screenStart: UInt8 = 0xD0
        public static let screenData: UInt8 = 0xD1
        public static let screenEnd: UInt8 = 0xD2
        public static let screenEndAll: UInt8 = 0xD3
    }

    public static func command(_ cmd: UInt8, _ args: UInt8...) -> [UInt8] {
        command(cmd, args: args)
    }

    public static func command(_ cmd: UInt8, args: [UInt8]) -> [UInt8] {
        precondition(args.count <= commandLength - 3)
        var p = [UInt8](repeating: 0, count: commandLength)
        p[0] = prefix
        p[1] = cmd
        p.replaceSubrange(2..<(2 + args.count), with: args)
        return Checksum.apply(p)
    }

    /// Full-blob write: one start packet followed by 10-byte parcels.
    /// - config: start `25 N A0 cfg`, data `24 …`
    /// - LED:    start `2A cfg N`,    data `29 …`
    public static func writeParcels(_ blob: [UInt8], kind: BlobKind, configId: UInt8) -> [[UInt8]] {
        let n = UInt8((blob.count + parcelPayload - 1) / parcelPayload)
        var packets: [[UInt8]] = []
        switch kind {
        case .config: packets.append(command(Cmd.writeConfigStart, n, specifyConfigId, configId))
        case .led: packets.append(command(Cmd.writeLEDStart, configId, n))
        }
        let dataCmd = kind == .config ? Cmd.writeConfigData : Cmd.writeLEDData
        for i in 0..<Int(n) {
            var p = [UInt8](repeating: 0, count: commandLength)
            p[0] = prefix
            p[1] = dataCmd
            let chunk = blob[(i * parcelPayload)..<min((i + 1) * parcelPayload, blob.count)]
            p.replaceSubrange(2..<(2 + chunk.count), with: chunk)
            p[12] = specifyConfigId
            p[13] = UInt8(i)
            packets.append(Checksum.apply(p))
        }
        return packets
    }

    public static func readBlob(kind: BlobKind, configId: UInt8) -> [UInt8] {
        command(kind == .config ? Cmd.readConfig : Cmd.readLED, configId)
    }

    public static func readRandomId(configId: UInt8) -> [UInt8] { command(Cmd.subFunc, 0x02, configId) }
    public static func saveToFlash(randomId: UInt16) -> [UInt8] {
        command(Cmd.subFunc, 0x03, UInt8(randomId >> 8), UInt8(randomId & 0xFF))
    }
}

// MARK: - DInput framing

public enum DInput {
    /// Output HID report id. Every command starts with this byte.
    public static let reportId: UInt8 = 5
    public static let inputReportId: UInt8 = 4
    static let parcelPayload = 10
    static let specifyConfigId: UInt8 = 0xA0

    public enum Cmd {
        public static let dongleInfo: UInt8 = 0x11
        public static let readLED: UInt8 = 229          // 0xE5, reply tagged 229
        public static let writeLEDStart: UInt8 = 231    // 0xE7
        public static let writeLEDData: UInt8 = 51      // 0x33
        public static let writeConfigStart: UInt8 = 234 // 0xEA
        public static let writeConfigData: UInt8 = 34   // 0x22
        public static let readConfig: UInt8 = 235       // 0xEB
        public static let deviceInfo: UInt8 = 236       // 0xEC
        public static let switchToXInput: UInt8 = 237   // 0xED
        public static let screenInfo: UInt8 = 242       // 0xF2 03 / 0xF2 02 sleep
        public static let subFunc: UInt8 = 0x50
    }

    /// Short command: `05 cmd args…` (12 bytes, zero padded, no checksum).
    public static func command(_ cmd: UInt8, _ args: UInt8...) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 12)
        p[0] = reportId
        p[1] = cmd
        p.replaceSubrange(2..<(2 + args.count), with: args)
        return p
    }

    /// Full-blob write: header `05 <start> …` (14 B) then parcels `05 <data> <10 B> A0 idx` (14 B).
    public static func writeParcels(_ blob: [UInt8], kind: BlobKind, configId: UInt8) -> [[UInt8]] {
        let n = UInt8((blob.count + parcelPayload - 1) / parcelPayload)
        var header = [UInt8](repeating: 0, count: 14)
        header[0] = reportId
        switch kind {
        case .config: header[1] = Cmd.writeConfigStart; header[2] = n; header[3] = specifyConfigId; header[4] = configId
        case .led: header[1] = Cmd.writeLEDStart; header[2] = configId; header[3] = n
        }
        var packets = [header]
        let dataCmd = kind == .config ? Cmd.writeConfigData : Cmd.writeLEDData
        for i in 0..<Int(n) {
            var p = [UInt8](repeating: 0, count: 14)
            p[0] = reportId
            p[1] = dataCmd
            let chunk = blob[(i * parcelPayload)..<min((i + 1) * parcelPayload, blob.count)]
            p.replaceSubrange(2..<(2 + chunk.count), with: chunk)
            p[12] = specifyConfigId
            p[13] = UInt8(i)
            packets.append(p)
        }
        return packets
    }

    public static func readBlob(kind: BlobKind, configId: UInt8) -> [UInt8] {
        command(kind == .config ? Cmd.readConfig : Cmd.readLED, configId)
    }

    /// `05 50 02 cfg crc 00…` — DInput commands must be zero-padded to 12 bytes (a 5-byte report is
    /// ignored by the firmware); the checksum byte is kept for parity with Space Station.
    public static func readRandomId(configId: UInt8) -> [UInt8] {
        pad(Checksum.apply([reportId, Cmd.subFunc, 0x02, configId, 0]))
    }
    /// `05 50 03 hi lo crc 00…`
    public static func saveToFlash(randomId: UInt16) -> [UInt8] {
        pad(Checksum.apply([reportId, Cmd.subFunc, 0x03, UInt8(randomId >> 8), UInt8(randomId & 0xFF), 0]))
    }
    static func pad(_ p: [UInt8], to n: Int = 12) -> [UInt8] { p + [UInt8](repeating: 0, count: max(0, n - p.count)) }
}

public enum BlobKind: Sendable, Hashable {
    case config   // 790 bytes on the Apex 4
    case led      // 500 bytes on the Apex 4
}

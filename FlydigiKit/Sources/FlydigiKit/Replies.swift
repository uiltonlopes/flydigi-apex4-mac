// Parsers for what the controller sends back. Pure functions over raw reports.

import Foundation

public struct DeviceInfo: Sendable, Hashable {
    public var deviceId: UInt8
    public var mac: [UInt8]           // 4 bytes as reported
    public var firmware: String       // "6.8.3.0"
    public var batteryRaw: UInt8
    public var cpuType: UInt8
    public var connection: UInt8      // 1 = wired
    public var motionSensor: UInt8

    public var isApex4Family: Bool { [84, 86, 87, 92, 93, 102, 103, 104].contains(deviceId) }
    public var isWired: Bool { connection == 1 }

    static func firmwareString(low: UInt8, high: UInt8) -> String {
        "\(high >> 4).\(high & 0xF).\(low >> 4).\(low & 0xF)"
    }
}

/// One acknowledged screen-upload step.
public struct ScreenAck: Sendable, Hashable {
    public var cmd: UInt8      // D0…D3
    public var ret: UInt8      // 0 = ok, 1 = resend
    public var value: UInt16   // bytes acknowledged so far / offset (BE)
}

public enum XInputReply {
    /// Vendor payload lives at offset 14 of the 64-byte input report.
    public static func deviceInfo(_ r: [UInt8]) -> DeviceInfo? {
        guard r.count > 26, r[14] == XInput.prefix, r[15] == XInput.Cmd.deviceInfo else { return nil }
        return DeviceInfo(deviceId: r[16], mac: Array(r[17..<21]),
                          firmware: DeviceInfo.firmwareString(low: r[21], high: r[22]),
                          batteryRaw: r[23], cpuType: r[24], connection: r[25], motionSensor: r[26])
    }

    /// Blob read reply: `(parcelIndex, 10 bytes)` for config (0x22) or LED (0x27).
    public static func blobParcel(_ r: [UInt8], kind: BlobKind) -> (index: Int, data: [UInt8])? {
        let tag = kind == .config ? XInput.Cmd.configReply : XInput.Cmd.ledReply
        guard r.count > 26, r[14] == XInput.prefix, r[15] == tag else { return nil }
        return (Int(r[16]), Array(r[17..<27]))
    }

    /// Ack of a write parcel: returns the acknowledged parcel index.
    public static func writeAck(_ r: [UInt8], kind: BlobKind) -> Int? {
        guard r.count > 16, r[14] == XInput.prefix else { return nil }
        switch (kind, r[15]) {
        case (.config, XInput.Cmd.writeConfigData), (.led, XInput.Cmd.writeLEDData): return Int(r[16])
        case (.config, XInput.Cmd.configStartAck), (.config, XInput.Cmd.writeConfigStart), (.led, XInput.Cmd.writeLEDStart): return -1
        default: return nil
        }
    }

    public static func randomId(_ r: [UInt8]) -> (id: UInt16, configId: UInt8)? {
        guard r.count > 19, r[14] == XInput.prefix, r[15] == XInput.Cmd.subFunc, r[16] == 0x02 else { return nil }
        return (UInt16(r[17]) << 8 | UInt16(r[18]), r[19])
    }

    public static func saveToFlashOK(_ r: [UInt8]) -> Bool? {
        guard r.count > 17, r[14] == XInput.prefix, r[15] == XInput.Cmd.subFunc, r[16] == 0x03 else { return nil }
        return r[17] == 1
    }

    /// Screen replies are tagged `5A A5` at offset 14.
    public static func screenAck(_ r: [UInt8]) -> ScreenAck? {
        guard r.count > 20, r[14] == 0x5A, r[15] == 0xA5, (0xD0...0xD3).contains(r[16]) else { return nil }
        return ScreenAck(cmd: r[16], ret: r[18], value: UInt16(r[19]) << 8 | UInt16(r[20]))
    }
}

public enum DInputReply {
    /// Input report id 4; payload starts at offset 3; command tag at offset 15.
    public static func deviceInfo(_ r: [UInt8]) -> DeviceInfo? {
        guard r.count > 15, r[15] == DInput.Cmd.deviceInfo else { return nil }
        return DeviceInfo(deviceId: r[3], mac: Array(r[5..<9]),
                          firmware: DeviceInfo.firmwareString(low: r[9], high: r[10]),
                          batteryRaw: r[11], cpuType: r[12], connection: r[13], motionSensor: r[14])
    }

    public static func blobParcel(_ r: [UInt8], kind: BlobKind) -> (index: Int, data: [UInt8])? {
        let tag = kind == .config ? DInput.Cmd.readConfig : DInput.Cmd.readLED
        guard r.count > 15, r[15] == tag else { return nil }
        return (Int(r[3]), Array(r[5..<15]))
    }

    /// Any of 234/231/51 acknowledges a write parcel. r[3] is the parcel index **1-based** for data parcels
    /// (0xFF for the start header). Verified on hardware 2026-09-01.
    public static func writeAck(_ r: [UInt8]) -> Int? {
        guard r.count > 15, [DInput.Cmd.writeConfigStart, DInput.Cmd.writeLEDStart, DInput.Cmd.writeLEDData, DInput.Cmd.writeConfigData].contains(r[15]) else { return nil }
        return Int(r[3])
    }

    public static func randomId(_ r: [UInt8]) -> (id: UInt16, configId: UInt8)? {
        guard r.count > 7, r[3] == 0x50, r[4] == 0x02 else { return nil }
        return (UInt16(r[5]) << 8 | UInt16(r[6]), r[7])
    }

    public static func saveToFlashOK(_ r: [UInt8]) -> Bool? {
        guard r.count > 5, r[3] == 0x50, r[4] == 0x03 else { return nil }
        return r[5] == 1
    }

    public static func screenAck(_ r: [UInt8]) -> ScreenAck? {
        guard r.count > 9, r[3] == 0x5A, r[4] == 0xA5, (0xD0...0xD3).contains(r[5]) else { return nil }
        return ScreenAck(cmd: r[5], ret: r[7], value: UInt16(r[8]) << 8 | UInt16(r[9]))
    }
}

/// Reassembles a blob from out-of-order 10-byte parcels.
public struct BlobAssembler: Sendable {
    public let expectedLength: Int
    private var parcels: [Int: [UInt8]] = [:]

    public init(expectedLength: Int) { self.expectedLength = expectedLength }

    public var parcelCount: Int { (expectedLength + 9) / 10 }
    public var isComplete: Bool { parcels.count >= parcelCount }

    public mutating func add(index: Int, data: [UInt8]) { parcels[index] = data }

    public func assemble() -> [UInt8]? {
        guard isComplete else { return nil }
        var out: [UInt8] = []
        for i in 0..<parcelCount { guard let p = parcels[i] else { return nil }; out += p }
        return Array(out.prefix(expectedLength))
    }
}

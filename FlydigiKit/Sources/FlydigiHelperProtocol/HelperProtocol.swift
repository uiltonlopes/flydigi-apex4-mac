// Messages exchanged between the app and the privileged helper over XPC (Codable, Swift-native XPC API).
// Anything that needs the XInput channel (root) goes through here; DInput work stays inside the app.

import Foundation
import FlydigiKit

public enum HelperConstants {
    /// launchd label == MachServices name == daemon plist file name (minus .plist).
    public static let machService = "com.uiltonlopes.apex4.helper"
    public static let plistName = "com.uiltonlopes.apex4.helper.plist"
    public static let protocolVersion = 1
    public static let appBundleId = "com.uiltonlopes.apex4"
}

public enum HelperRequest: Codable, Sendable {
    case ping
    case deviceInfo
    case readLED
    case applyLED(bytes: [UInt8], persist: Bool)
    case readBlob(kind: BlobKindCode)
    case writeBlob(kind: BlobKindCode, bytes: [UInt8], persist: Bool)
    /// Screen upload is chunked per frame so the app can show progress and the message stays small.
    case beginScreenUpload(frameCount: Int)
    case uploadScreenFrame(index: Int, lvgl: [UInt8])      // 1-based index
    case finishScreenUpload
    case switchMode
}

public enum BlobKindCode: Codable, Sendable { case config, led }

public struct HelperDeviceInfo: Codable, Sendable, Hashable {
    public var deviceId: UInt8, firmware: String, mac: String, wired: Bool, batteryRaw: UInt8
    public init(_ i: DeviceInfo) {
        deviceId = i.deviceId; firmware = i.firmware; wired = i.isWired; batteryRaw = i.batteryRaw
        mac = i.mac.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}

public enum HelperReply: Codable, Sendable {
    case ok
    case pong(version: Int, uid: UInt32)
    case deviceInfo(HelperDeviceInfo)
    case blob([UInt8])
    case frameDone(index: Int)
    case error(String)
}

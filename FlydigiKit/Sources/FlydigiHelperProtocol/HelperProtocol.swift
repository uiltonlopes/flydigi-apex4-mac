// Messages exchanged between the app and the privileged helper over XPC (Codable, Swift-native XPC API).
// Anything that needs the XInput channel (root) goes through here; DInput work stays inside the app.

import Foundation
import FlydigiKit

public enum HelperConstants {
    /// launchd label == MachServices name == daemon plist file name (minus .plist).
    public static let machService = "com.uiltonlopes.spacestation.helper"
    public static let plistName = "com.uiltonlopes.spacestation.helper.plist"
    public static let protocolVersion = 1
}

public enum HelperRequest: Codable, Sendable {
    case ping
    case deviceInfo
    case readLED(slot: UInt8)                                 // lighting is stored per profile slot (A5 26/2A <cfgId>)
    case applyLED(slot: UInt8, bytes: [UInt8], persist: Bool)
    /// Screen upload is chunked per frame so the app can show progress and the message stays small.
    case beginScreenUpload(frameCount: Int, period: UInt8)   // period = frame interval in 100 ms units
    case uploadScreenFrame(index: Int, lvgl: [UInt8])      // 1-based index
    case finishScreenUpload
    case switchMode
    // profiles (config slots 0…3)
    case currentSlot
    case applySlot(UInt8)
    case readConfig(slot: UInt8)
    case writeConfig(slot: UInt8, bytes: [UInt8], persist: Bool)
    case setForceTrigger(side: UInt8, mode: [UInt8])          // raw params (see DeviceSession.ForceTrigger)
    case motorTest(left: UInt8, right: UInt8)
    case captureKey(timeoutMs: Int)                            // wait for a key press on the pad (raw report), nil on timeout
    case calibration(start: Bool)                              // ADC calibration window (see DeviceSession.calibration)
    case readJoystickSettings
    case setJoystickOption(sub: UInt8, value: UInt8)
    case readSleepTime
    case setSleepTime(minutes: UInt8)
    case setQuickSwitch(Bool)
    case setTurboSwitch(Bool)
}


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
    case slot(UInt8)
    case key(UInt8?)
    case value(UInt8)
    case joystickSettings(raw: [UInt8], debounce: Bool, autoCalibration: Bool, rebound: Bool, precision: UInt8, sensitivity: UInt8, reportRate: UInt8, sleepTime: UInt8)
    case error(String)
}

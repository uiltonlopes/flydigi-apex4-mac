// SpaceStationHelper — launchd daemon (root) registered by the app with SMAppService.
// Owns the XInput/IOUSBLib link to the controller; serves Codable requests over XPC.

import Foundation
import XPC
import FlydigiKit
import FlydigiHelperProtocol
import FlydigiTransport

@available(macOS 14.0, *)
final class HelperService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "apex4.helper.device")
    private var session: DeviceSession?            // kept open across a screen upload
    private var uploadFrames: Int = 0
    var uploadPeriod: UInt8 = 2

    /// Opens (or reuses) an XInput session. Every request runs serially on `queue`.
    private func withSession<T>(_ body: (DeviceSession) throws -> T) throws -> T {
        if session == nil { session = try DeviceSession.open(preferring: .xinput) }
        do { return try body(session!) } catch {
            // Drop a broken link so the next request re-captures the device.
            session?.close(); session = nil
            throw error
        }
    }

    private var idleTimer: DispatchWorkItem?
    private static let idleHold: TimeInterval = 3   // keep the capture briefly so bursts of requests don't re-enumerate the pad each time

    private func releaseIfIdle() {
        guard uploadFrames == 0 else { return }
        idleTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.uploadFrames == 0 else { return }
            self.session?.close(); self.session = nil        // gives the pad back to Apple's driver
        }
        idleTimer = work
        queue.asyncAfter(deadline: .now() + Self.idleHold, execute: work)
    }

    func handle(_ request: HelperRequest) -> HelperReply {
        queue.sync { self.idleTimer?.cancel(); return self.handleLocked(request) }
    }

    /// Development convenience: if the app was rebuilt (our executable changed on disk), exit once idle;
    /// launchd starts the new binary on the next XPC connection.
    func watchForRebuild() {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let original = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkRebuild(path: path, original: original) }
    }
    private func checkRebuild(path: String, original: Date?) {
        let now = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
        if let original, let now, now != original, session == nil, uploadFrames == 0 { exit(0) }
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkRebuild(path: path, original: original) }
    }

    private func handleLocked(_ request: HelperRequest) -> HelperReply {
        do {
            switch request {
            case .ping:
                return .pong(version: HelperConstants.protocolVersion, uid: getuid())
            case .deviceInfo:
                let info = try withSession { try $0.deviceInfo() }
                releaseIfIdle(); return .deviceInfo(HelperDeviceInfo(info))
            case let .readLED(slot):
                let led = try withSession { s in s.configId = slot; defer { s.configId = 0 }; return try s.readBlob(.led) }
                releaseIfIdle(); return .blob(led)
            case let .applyLED(slot, bytes, persist):
                guard let led = LEDConfig(bytes: bytes) else { return .error("invalid LED blob") }
                try withSession { s in s.configId = slot; defer { s.configId = 0 }; try s.applyLED(led, persist: persist) }
                releaseIfIdle(); return .ok
            case let .readBlob(kind):
                let b = try withSession { try $0.readBlob(kind == .config ? .config : .led) }
                releaseIfIdle(); return .blob(b)
            case let .writeBlob(kind, bytes, persist):
                try withSession { s in
                    try s.writeBlob(bytes, kind: kind == .config ? .config : .led)
                    if persist { try s.saveToFlash() }
                }
                releaseIfIdle(); return .ok
            case let .beginScreenUpload(frameCount, period):
                guard (1...Screen.maxFrames).contains(frameCount) else { return .error("frame count must be 1…\(Screen.maxFrames)") }
                _ = try withSession { $0 }                     // capture now, hold until finish
                uploadFrames = frameCount; uploadPeriod = period
                return .ok
            case let .uploadScreenFrame(index, lvgl):
                guard uploadFrames > 0 else { return .error("no upload in progress") }
                guard lvgl.count == Screen.frameLength else { return .error("frame must be \(Screen.frameLength) bytes") }
                try withSession { try $0.uploadScreenFrame(lvgl, index: index, of: uploadFrames, period: uploadPeriod) }
                return .frameDone(index: index)
            case .finishScreenUpload:
                guard uploadFrames > 0 else { return .error("no upload in progress") }
                try withSession { try $0.finishScreenUpload(frameCount: uploadFrames) }
                uploadFrames = 0; releaseIfIdle(); return .ok
            case .currentSlot:
                let id = try withSession { try $0.currentConfigId() }
                releaseIfIdle(); return .slot(id)
            case let .applySlot(slot):
                try withSession { try $0.applyConfig(slot: slot) }
                releaseIfIdle(); return .ok
            case let .readConfig(slot):
                let b = try withSession { s in s.configId = slot; defer { s.configId = 0 }; return try s.readBlob(.config) }
                releaseIfIdle(); return .blob(b)
            case let .writeConfig(slot, bytes, persist):
                try withSession { s in
                    s.configId = slot; defer { s.configId = 0 }
                    try s.writeBlob(bytes, kind: .config)
                    if persist { try s.saveToFlash() }
                }
                releaseIfIdle(); return .ok
            case let .setForceTrigger(side, params):
                try withSession { s in
                    guard let sd = DeviceSession.TriggerSide(rawValue: side) else { throw TransportError.protocolError("bad side") }
                    try s.setForceTriggerRaw(params, side: sd)
                }
                releaseIfIdle(); return .ok
            case let .motorTest(l, r):
                try withSession { try $0.motorTest(left: l, right: r) }
                releaseIfIdle(); return .ok
            case .calibration(let start):
                try withSession { try $0.calibration(start: start) }; return .ok
            case .readJoystickSettings:
                let j = try withSession { try $0.readJoystickSettings() }
                releaseIfIdle()
                return .joystickSettings(raw: j.raw, debounce: j.debounce, autoCalibration: j.autoCalibration, rebound: j.rebound, precision: j.precision, sensitivity: j.sensitivity, reportRate: j.reportRate, sleepTime: j.sleepTime)
            case let .setJoystickOption(sub, value):
                try withSession { s in
                    guard let o = DeviceSession.JoystickOption(rawValue: sub) else { throw TransportError.protocolError("bad option") }
                    try s.setJoystickOption(o, value: value)
                }
                return .ok
            case .readSleepTime:
                let t = try withSession { try $0.screenSleepTime() }
                releaseIfIdle(); return .value(t)
            case let .setSleepTime(minutes):
                try withSession { try $0.setScreenSleepTime(minutes) }
                releaseIfIdle(); return .ok
            case let .setQuickSwitch(on):
                try withSession { try $0.setQuickSwitch(on) }
                releaseIfIdle(); return .ok
            case let .setTurboSwitch(on):
                try withSession { try $0.setTurboSwitch(on) }
                releaseIfIdle(); return .ok
            case .captureKey(let ms):
                let k = try withSession { try $0.captureKey(timeout: Double(ms) / 1000) }
                return .key(k?.rawValue)
            case .switchMode:
                let s = try (session ?? DeviceSession.open(preferring: .xinput))
                session = nil                                   // switchMode() closes the link itself, without reset
                try s.switchMode()
                return .ok
            }
        } catch {
            uploadFrames = 0
            return .error("\(error)")
        }
    }
}

guard #available(macOS 14.0, *) else { fatalError("macOS 14+ required") }
let service = HelperService()
service.watchForRebuild()
do {
    let handler: @Sendable (XPCListener.IncomingSessionRequest) -> XPCListener.IncomingSessionRequest.Decision = { request in
        request.accept { (message: XPCReceivedMessage) -> (any Encodable)? in
            do {
                let req = try message.decode(as: HelperRequest.self)
                return service.handle(req)
            } catch {
                return HelperReply.error("bad request: \(error)")
            }
        }
    }
    // Only code signed by our team (the app, or the `apex4` CLI signed with the same identity) may talk
    // to the daemon. The Swift peer-requirement API is macOS 26+; on 14/15 the listener is unrestricted
    // (local processes only) — TODO: audit-token based check for older systems.
    let listener: XPCListener
    if #available(macOS 26.0, *) {
        listener = try XPCListener(service: HelperConstants.machService,
                                   requirement: .isFromSameTeam(),
                                   incomingSessionHandler: handler)
    } else {
        listener = try XPCListener(service: HelperConstants.machService, incomingSessionHandler: handler)
    }
    _ = listener
    dispatchMain()
} catch {
    FileHandle.standardError.write("SpaceStationHelper: listener failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}

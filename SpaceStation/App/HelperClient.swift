// XPC client for the privileged helper + SMAppService lifecycle.

import Foundation
import XPC
import ServiceManagement
import FlydigiKit
import FlydigiHelperProtocol
import FlydigiTransport

enum HelperError: Error, CustomStringConvertible {
    case notInstalled, remote(String), transport(String)
    var description: String {
        switch self {
        case .notInstalled: return "Helper not installed. Install it from Settings."
        case .remote(let s), .transport(let s): return s
        }
    }
}

/// Talks to SpaceStationHelper. One request at a time; long uploads are chunked per frame so the UI can report progress.
@available(macOS 14.0, *)
final class HelperClient: @unchecked Sendable {
    static let shared = HelperClient()
    private let queue = DispatchQueue(label: "apex4.helper.client")
    private var session: XPCSession?

    // MARK: SMAppService

    var service: SMAppService { SMAppService.daemon(plistName: HelperConstants.plistName) }
    var status: SMAppService.Status { service.status }

    func install() throws { try service.register() }
    func uninstall() throws { try service.unregister(); dropSession() }
    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    // MARK: Requests

    func send(_ request: HelperRequest) throws -> HelperReply {
        try queue.sync {
            guard status == .enabled else { throw HelperError.notInstalled }
            var lastError: Error?
            // The daemon restarts itself when its binary changes (dev builds) and launchd may recycle it when
            // idle; a cached session then fails with "canceled session". Reconnect once before giving up.
            for attempt in 0..<2 {
                if session == nil {
                    session = try XPCSession(machService: HelperConstants.machService, targetQueue: nil, options: [], cancellationHandler: nil)
                }
                do {
                    let received = try session!.sendSync(request)
                    let reply = try received.decode(as: HelperReply.self)
                    if case let .error(msg) = reply { throw HelperError.remote(msg) }
                    return reply
                } catch let e as HelperError {
                    throw e
                } catch {
                    dropSession()
                    lastError = error
                    if attempt == 0 { Thread.sleep(forTimeInterval: 0.3) }
                }
            }
            throw HelperError.transport("\(lastError!)")
        }
    }

    func ping() -> Bool {
        if case .pong = try? send(.ping) { return true } else { return false }
    }

    func deviceInfo() throws -> HelperDeviceInfo {
        guard case let .deviceInfo(i) = try send(.deviceInfo) else { throw HelperError.transport("unexpected reply") }
        return i
    }

    func readLED(slot: UInt8) throws -> LEDConfig {
        guard case let .blob(b) = try send(.readLED(slot: slot)), let led = LEDConfig(bytes: b) else { throw HelperError.transport("bad LED blob") }
        return led
    }

    func applyLED(_ led: LEDConfig, slot: UInt8, persist: Bool = true) throws { _ = try send(.applyLED(slot: slot, bytes: led.bytes, persist: persist)) }

    /// Uploads frames one by one; `progress` gets (framesDone, total).
    func uploadScreen(frames: [[UInt8]], period: UInt8 = 2, progress: @escaping @Sendable (Int, Int) -> Void) throws {
        _ = try send(.beginScreenUpload(frameCount: frames.count, period: period))
        do {
            for (i, f) in frames.enumerated() {
                _ = try send(.uploadScreenFrame(index: i + 1, lvgl: f))
                progress(i + 1, frames.count)
            }
            _ = try send(.finishScreenUpload)
        } catch {
            _ = try? send(.finishScreenUpload)   // best effort: release the device
            throw error
        }
    }

    func switchMode() throws { _ = try send(.switchMode) }

    func currentSlot() throws -> UInt8 { guard case let .slot(s) = try send(.currentSlot) else { throw HelperError.transport("unexpected reply") }; return s }
    func applySlot(_ slot: UInt8) throws { _ = try send(.applySlot(slot)) }
    func readConfig(slot: UInt8) throws -> [UInt8] { guard case let .blob(b) = try send(.readConfig(slot: slot)) else { throw HelperError.transport("unexpected reply") }; return b }
    func writeConfig(slot: UInt8, bytes: [UInt8], persist: Bool = true) throws { _ = try send(.writeConfig(slot: slot, bytes: bytes, persist: persist)) }
    func setForceTrigger(side: UInt8, params: [UInt8]) throws { _ = try send(.setForceTrigger(side: side, mode: params)) }
    func motorTest(left: UInt8, right: UInt8) throws { _ = try send(.motorTest(left: left, right: right)) }
    func calibration(start: Bool) throws { _ = try send(.calibration(start: start)) }
    func readJoystickSettings() throws -> JoystickSettings {
        guard case let .joystickSettings(raw, d, a, r, p, s, rr, st) = try send(.readJoystickSettings) else { throw HelperError.transport("unexpected reply") }
        return JoystickSettings(debounce: d, autoCalibration: a, rebound: r, precision: p, sensitivity: s, reportRate: rr, sleepTime: st, raw: raw)
    }
    func setJoystickOption(_ opt: DeviceSession.JoystickOption, value: UInt8) throws { _ = try send(.setJoystickOption(sub: opt.rawValue, value: value)) }
    func readSleepTime() throws -> UInt8 { guard case let .value(v) = try send(.readSleepTime) else { throw HelperError.transport("unexpected reply") }; return v }
    func setSleepTime(_ m: UInt8) throws { _ = try send(.setSleepTime(minutes: m)) }
    func setQuickSwitch(_ on: Bool) throws { _ = try send(.setQuickSwitch(on)) }
    func setTurboSwitch(_ on: Bool) throws { _ = try send(.setTurboSwitch(on)) }
    func captureKey(timeoutMs: Int) throws -> UInt8? { guard case let .key(k) = try send(.captureKey(timeoutMs: timeoutMs)) else { throw HelperError.transport("unexpected reply") }; return k }

    private func dropSession() { session?.cancel(reason: "reset"); session = nil }
}

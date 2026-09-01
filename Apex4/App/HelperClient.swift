// XPC client for the privileged helper + SMAppService lifecycle.

import Foundation
import XPC
import ServiceManagement
import FlydigiKit
import FlydigiHelperProtocol

enum HelperError: Error, CustomStringConvertible {
    case notInstalled, remote(String), transport(String)
    var description: String {
        switch self {
        case .notInstalled: return "Helper not installed. Install it from Settings."
        case .remote(let s), .transport(let s): return s
        }
    }
}

/// Talks to Apex4Helper. One request at a time; long uploads are chunked per frame so the UI can report progress.
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
                throw HelperError.transport("\(error)")
            }
        }
    }

    func ping() -> Bool {
        if case .pong = try? send(.ping) { return true } else { return false }
    }

    func deviceInfo() throws -> HelperDeviceInfo {
        guard case let .deviceInfo(i) = try send(.deviceInfo) else { throw HelperError.transport("unexpected reply") }
        return i
    }

    func readLED() throws -> LEDConfig {
        guard case let .blob(b) = try send(.readLED), let led = LEDConfig(bytes: b) else { throw HelperError.transport("bad LED blob") }
        return led
    }

    func applyLED(_ led: LEDConfig, persist: Bool = true) throws { _ = try send(.applyLED(bytes: led.bytes, persist: persist)) }

    /// Uploads frames one by one; `progress` gets (framesDone, total).
    func uploadScreen(frames: [[UInt8]], progress: @escaping @Sendable (Int, Int) -> Void) throws {
        _ = try send(.beginScreenUpload(frameCount: frames.count))
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

    private func dropSession() { session?.cancel(reason: "reset"); session = nil }
}

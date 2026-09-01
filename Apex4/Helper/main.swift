// Apex4Helper — launchd daemon (root) registered by the app with SMAppService.
// Owns the XInput/IOUSBLib link to the controller; serves Codable requests over XPC.

import Foundation
import XPC
import FlydigiKit
import FlydigiTransport

@available(macOS 14.0, *)
final class HelperService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "apex4.helper.device")
    private var session: DeviceSession?            // kept open across a screen upload
    private var uploadFrames: Int = 0

    /// Opens (or reuses) an XInput session. Every request runs serially on `queue`.
    private func withSession<T>(_ body: (DeviceSession) throws -> T) throws -> T {
        if session == nil { session = try DeviceSession.open(preferring: .xinput) }
        do { return try body(session!) } catch {
            // Drop a broken link so the next request re-captures the device.
            session?.close(); session = nil
            throw error
        }
    }

    private func releaseIfIdle() {
        guard uploadFrames == 0 else { return }
        session?.close(); session = nil          // gives the pad back to Apple's driver
    }

    func handle(_ request: HelperRequest) -> HelperReply {
        queue.sync { self.handleLocked(request) }
    }

    private func handleLocked(_ request: HelperRequest) -> HelperReply {
        do {
            switch request {
            case .ping:
                return .pong(version: HelperConstants.protocolVersion, uid: getuid())
            case .deviceInfo:
                let info = try withSession { try $0.deviceInfo() }
                releaseIfIdle(); return .deviceInfo(HelperDeviceInfo(info))
            case .readLED:
                let led = try withSession { try $0.readBlob(.led) }
                releaseIfIdle(); return .blob(led)
            case let .applyLED(bytes, persist):
                guard let led = LEDConfig(bytes: bytes) else { return .error("invalid LED blob") }
                try withSession { try $0.applyLED(led, persist: persist) }
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
            case let .beginScreenUpload(frameCount):
                guard (1...Screen.maxFrames).contains(frameCount) else { return .error("frame count must be 1…\(Screen.maxFrames)") }
                _ = try withSession { $0 }                     // capture now, hold until finish
                uploadFrames = frameCount
                return .ok
            case let .uploadScreenFrame(index, lvgl):
                guard uploadFrames > 0 else { return .error("no upload in progress") }
                guard lvgl.count == Screen.frameLength else { return .error("frame must be \(Screen.frameLength) bytes") }
                try withSession { try $0.uploadScreenFrame(lvgl, index: index, of: uploadFrames) }
                return .frameDone(index: index)
            case .finishScreenUpload:
                guard uploadFrames > 0 else { return .error("no upload in progress") }
                try withSession { try $0.finishScreenUpload(frameCount: uploadFrames) }
                uploadFrames = 0; releaseIfIdle(); return .ok
            case .switchMode:
                try withSession { try $0.switchMode() }
                session?.close(); session = nil; return .ok
            }
        } catch {
            uploadFrames = 0
            return .error("\(error)")
        }
    }
}

guard #available(macOS 14.0, *) else { fatalError("macOS 14+ required") }
let service = HelperService()
do {
    let listener = try XPCListener(service: HelperConstants.machService) { request in
        // TODO(security): restrict peers to our app's code signature (XPCPeerRequirement on macOS 26 /
        // audit-token + SecCode checks on 14/15) before shipping.
        request.accept { (message: XPCReceivedMessage) -> (any Encodable)? in
            do {
                let req = try message.decode(as: HelperRequest.self)
                return service.handle(req)
            } catch {
                return HelperReply.error("bad request: \(error)")
            }
        }
    }
    _ = listener
    dispatchMain()
} catch {
    FileHandle.standardError.write("Apex4Helper: listener failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}

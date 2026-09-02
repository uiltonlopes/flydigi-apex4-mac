// Staged edits for the four on-board profiles: load slots, edit a draft locally, Apply (⌘S) writes and
// saves, Revert discards. Reading a slot moves the pad's "current" cursor, so the store re-applies the
// user's chosen slot after every enumeration (docs/protocol.md §4).

import Foundation
import Observation
import FlydigiKit
import FlydigiTransport
import FlydigiHelperProtocol

@MainActor @Observable
final class ProfileStore {
    struct Slot: Identifiable { let index: UInt8; var config: GamepadConfig; var id: UInt8 { index } }

    var slots: [Slot] = []
    var activeSlot: UInt8 = 0                 // what the user chose / the pad reports on first load
    var draft: GamepadConfig?                 // edited copy of the active slot
    var isDirty: Bool { guard let d = draft, let s = slots.first(where: { $0.index == activeSlot }) else { return false }; return d.bytes != s.config.bytes }
    var lastError: String?
    var busy = false
    var selectedKey: ControllerKey?           // inspector target

    private unowned let controller: ControllerModel
    init(controller: ControllerModel) { self.controller = controller }

    // MARK: Load

    func loadAll() async {
        guard controller.connection != .none else { slots = []; draft = nil; return }
        busy = true; defer { busy = false }
        let conn = controller.connection
        let result: Result<(UInt8, [(UInt8, [UInt8])]), Error> = await Task.detached {
            Result {
                switch conn {
                case .dinput:
                    let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
                    var out: [(UInt8, [UInt8])] = []
                    for i in 0..<4 { s.configId = UInt8(i); out.append((UInt8(i), try s.readBlob(.config))) }
                    return (0, out)
                case .xinput:
                    guard #available(macOS 14.0, *) else { throw HelperError.notInstalled }
                    let h = HelperClient.shared
                    let current = try h.currentSlot()
                    var out: [(UInt8, [UInt8])] = []
                    for i in 0..<4 { out.append((UInt8(i), try h.readConfig(slot: UInt8(i)))) }
                    try h.applySlot(current)                       // undo the cursor move
                    return (current, out)
                case .none: throw HelperError.transport("no controller")
                }
            }
        }.value
        switch result {
        case .success(let (current, blobs)):
            slots = blobs.compactMap { i, b in GamepadConfig(bytes: b).map { Slot(index: i, config: $0) } }
            if slots.isEmpty { lastError = "Could not decode the controller's profiles"; return }
            activeSlot = current
            draft = slots.first { $0.index == activeSlot }?.config
            lastError = nil
        case .failure(let e): lastError = "\(e)"
        }
    }

    // MARK: Edit

    func select(slot: UInt8) {
        guard !isDirty || slot == activeSlot else { return }   // UI asks before discarding
        activeSlot = slot
        draft = slots.first { $0.index == slot }?.config
        Task { await activateOnPad(slot) }
    }

    func revert() { draft = slots.first { $0.index == activeSlot }?.config }

    func setMapping(_ key: ControllerKey, _ mapping: GamepadConfig.KeyMapping) { draft?.keys[key] = mapping }

    // MARK: Apply

    func apply() async {
        guard let draft, isDirty else { return }
        busy = true; defer { busy = false }
        let conn = controller.connection, slot = activeSlot, bytes = draft.bytes
        let result: Result<Void, Error> = await Task.detached {
            Result {
                switch conn {
                case .dinput:
                    let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
                    s.configId = slot
                    try s.writeBlob(bytes, kind: .config); try s.saveToFlash()
                case .xinput:
                    guard #available(macOS 14.0, *) else { throw HelperError.notInstalled }
                    try HelperClient.shared.writeConfig(slot: slot, bytes: bytes, persist: true)
                    try HelperClient.shared.applySlot(slot)
                case .none: throw HelperError.transport("no controller")
                }
            }
        }.value
        switch result {
        case .success:
            if let i = slots.firstIndex(where: { $0.index == slot }), let cfg = GamepadConfig(bytes: bytes) { slots[i].config = cfg; self.draft = cfg }
            lastError = nil
        case .failure(let e): lastError = "\(e)"
        }
    }

    private func activateOnPad(_ slot: UInt8) async {
        let conn = controller.connection
        _ = await Task.detached {
            Result {
                switch conn {
                case .dinput: let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }; try s.applyConfig(slot: slot)
                case .xinput: if #available(macOS 14.0, *) { try HelperClient.shared.applySlot(slot) }
                case .none: break
                }
            }
        }.value
    }
}

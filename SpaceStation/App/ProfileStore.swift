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
    /// The slot the pad should run. Remembered per controller because `A5 20` reports the last slot *read*
    /// (a cursor), not the active one — trusting it after reads would silently activate the wrong profile.
    var activeSlot: UInt8 = 0 { didSet { UserDefaults.standard.set(Int(activeSlot), forKey: "activeSlot"); temporarySlot = nil } }
    /// Slot currently on the pad (a game rule may have moved it temporarily).
    var shownSlot: UInt8 { temporarySlot ?? activeSlot }
    var draft: GamepadConfig?                 // edited copy of the active slot
    var isDirty: Bool { guard let d = draft, let s = slots.first(where: { $0.index == activeSlot }) else { return false }; return d.bytes != s.config.bytes }
    var lastError: String?
    var busy = false
    var selectedKey: ControllerKey?           // inspector target

    private unowned let controller: ControllerModel
    init(controller: ControllerModel) { self.controller = controller }

    // MARK: Load

    func loadAll() async {
        // Nothing to read while the pad has not answered (receiver with the pad off): stay quiet.
        guard controller.info != nil else { lastError = nil; return }
        guard controller.connection != .none else { slots = []; draft = nil; return }
        busy = true; defer { busy = false }
        let conn = controller.connection
        let wanted = UInt8(clamping: UserDefaults.standard.integer(forKey: "activeSlot"))
        let result: Result<(UInt8, [(UInt8, [UInt8])]), Error> = await Task.detached {
            Result {
                switch conn {
                case .dinput:
                    let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
                    var out: [(UInt8, [UInt8])] = []
                    for i in 0..<4 { s.configId = UInt8(i); out.append((UInt8(i), try s.readBlob(.config))) }
                    try? s.applyConfig(slot: wanted)               // reads move the pad's cursor; put the chosen profile back
                    return (wanted, out)
                case .xinput:
                    guard #available(macOS 14.0, *) else { throw HelperError.notInstalled }
                    let h = HelperClient.shared
                    var out: [(UInt8, [UInt8])] = []
                    for i in 0..<4 { out.append((UInt8(i), try h.readConfig(slot: UInt8(i)))) }
                    try h.applySlot(wanted)                        // reads move the pad's cursor; put the chosen profile back
                    return (wanted, out)
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
        case .failure(let e): report(e)
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

    /// Reflect a slot the game-profile watcher activated without changing the remembered choice.
    func showTemporary(slot: UInt8) {
        guard !isDirty else { return }
        temporarySlot = slot
        draft = slots.first { $0.index == slot }?.config
    }
    var temporarySlot: UInt8?

    func setMapping(_ key: ControllerKey, _ mapping: GamepadConfig.KeyMapping) { draft?.keys[key] = mapping }

    // MARK: Macros (on-board; the trigger button's mapping becomes 0x20 "macro", like Space Station does)

    var maxMacros: Int { (draft?.protoVersion ?? 0x0300) >= 770 ? 10 : 5 }
    var macroTick: Int { (draft?.protoVersion ?? 0x0300) >= 770 ? 1 : 10 }      // ms resolution of the timeline

    func macroIndex(for key: ControllerKey) -> Int? { draft?.macros.firstIndex { $0.key == key.rawValue } }

    /// Creates an empty macro bound to `key` (or returns the existing one). `nil` when the slot is full.
    @discardableResult
    func addMacro(for key: ControllerKey) -> Int? {
        if let i = macroIndex(for: key) { return i }
        guard let d = draft, d.macros.count < maxMacros else { return nil }
        draft?.macros.append(.init(key: key.rawValue, count: 0, enable: .once, actions: []))
        draft?.keys[key] = .macro
        return draft!.macros.count - 1
    }

    func removeMacro(at i: Int) {
        guard let m = draft?.macros[safe: i] else { return }
        draft?.macros.remove(at: i)
        if let k = ControllerKey(rawValue: m.key), case .macro? = draft?.keys[k] { draft?.keys[k] = .identity }
    }

    func updateMacro(at i: Int, _ change: (inout GamepadConfig.Macro) -> Void) {
        guard var m = draft?.macros[safe: i] else { return }
        let oldKey = m.key
        change(&m)
        m.count = m.actions.count
        draft?.macros[i] = m
        if m.key != oldKey {                                     // re-bind the trigger button
            if let k = ControllerKey(rawValue: oldKey), case .macro? = draft?.keys[k] { draft?.keys[k] = .identity }
            if let k = ControllerKey(rawValue: m.key) { draft?.keys[k] = .macro }
        }
    }

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
        case .failure(let e): report(e)
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

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }

    /// Same wording as ControllerModel for timeouts, so the banner never shows raw transport text.
    private func report(_ e: Error) {
        let text = "\(e)"
        lastError = text.contains("no matching report") || text.contains("timeout")
            ? String(localized: "The controller did not answer in time. Turn it on or reconnect the cable — it shows up by itself.")
            : text
    }

}

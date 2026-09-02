// Per-app game profiles: when a chosen app comes to the front, switch the controller to a profile slot
// and/or a ForceAdapt trigger preset; put everything back when it goes away. This is the macOS take on
// Space Station's "Adapt Trigger" (whose Windows game mods cannot exist here).

import SwiftUI
import AppKit
import FlydigiKit
import FlydigiTransport

/// A ForceAdapt preset expressed the way the Trigger tab does (see `ForceAdaptPanel`).
struct ForceAdaptPreset: Codable, Hashable {
    var mode = 0            // 0 general 1 race 2 sniper 3 recoil 4 lock 5 vibration
    var stroke = 50, strength = 8, pressure = 5, frequency = 5
    var matchStroke = true
    static let modes: [(Int, String)] = [(0, "General"), (1, "Race"), (2, "Sniper"), (3, "Recoil"), (4, "Lock"), (5, "Vibration")]
    var isNormal: Bool { mode == 0 }
    var params: [UInt8] {
        let s = UInt8(clamping: stroke), st = UInt8(clamping: strength), p = UInt8(clamping: pressure), f = UInt8(clamping: frequency), m: UInt8 = matchStroke ? 1 : 0
        switch mode {
        case 1: return [1, s, st, m]
        case 2: return [2, s, p, st, f, m]
        case 3: return [3, s, s / 2, st, 0, m]
        case 4: return [4, s, st, m]
        case 5: return [5, s, p, st, f, m]
        default: return [0]
        }
    }
}

struct GameRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String                    // shown in the list (game name)
    var bundleId: String?               // matched against the frontmost app's bundle identifier
    var processName: String?            // fallback: frontmost app's localized name contains this (case-insensitive)
    var slot: Int?                      // profile slot 0…3 to activate, nil = keep current
    var left = ForceAdaptPreset()
    var right = ForceAdaptPreset()
    var enabled = true
    var flydigiId: Int?                 // origin in Flydigi's list, if any

    func matches(_ app: NSRunningApplication) -> Bool {
        if let bundleId, let b = app.bundleIdentifier, b.caseInsensitiveCompare(bundleId) == .orderedSame { return true }
        if let processName, !processName.isEmpty, let n = app.localizedName, n.localizedCaseInsensitiveContains(processName) { return true }
        return false
    }
}

@MainActor @Observable
final class GameProfileStore {
    var rules: [GameRule] = [] { didSet { save() } }
    var enabled: Bool = UserDefaults.standard.object(forKey: "gameProfilesEnabled") as? Bool ?? true { didSet { UserDefaults.standard.set(enabled, forKey: "gameProfilesEnabled") } }
    private(set) var activeRule: GameRule?
    private(set) var lastEvent: String?
    private unowned let model: ControllerModel
    private var observers: [NSObjectProtocol] = []

    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Space Station", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("game-profiles.json")
    }

    init(model: ControllerModel) {
        self.model = model
        if let d = try? Data(contentsOf: Self.file), let r = try? JSONDecoder().decode([GameRule].self, from: d) { rules = r }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.ApplicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.frontmostChanged(app) }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.frontmostChanged(NSWorkspace.shared.frontmostApplication) }
        })
    }

    private func save() {
        if let d = try? JSONEncoder().encode(rules) { try? d.write(to: Self.file) }
    }

    // MARK: Matching

    private func frontmostChanged(_ app: NSRunningApplication?) {
        guard enabled, model.connection != .none else { return }
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }   // ignore ourselves
        if let rule = rules.first(where: { $0.enabled && $0.matches(app) }) {
            if activeRule?.id != rule.id { Task { await apply(rule, appName: app.localizedName ?? rule.name) } }
        } else if activeRule != nil {
            Task { await restore() }
        }
    }

    func apply(_ rule: GameRule, appName: String) async {
        activeRule = rule
        lastEvent = "\(rule.name) → \(appName)"
        if let slot = rule.slot { await model.applySlot(UInt8(slot)) }
        if !rule.left.isNormal || !rule.right.isNormal {
            await model.setForceAdapt(left: rule.left.params, right: rule.right.params)
        }
    }

    func restore() async {
        guard let rule = activeRule else { return }
        activeRule = nil
        lastEvent = "back to normal"
        if rule.slot != nil { await model.applySlot(UInt8(clamping: UserDefaults.standard.integer(forKey: "activeSlot"))) }
        if !rule.left.isNormal || !rule.right.isNormal { await model.setForceAdapt(left: [0], right: [0]) }
    }

    /// Manual test from the editor.
    func test(_ rule: GameRule) async { await apply(rule, appName: "test") }
}

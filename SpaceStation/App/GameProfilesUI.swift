// UI for per-app game profiles (Adaptive Trigger page): rules list, editor sheet, status.

import SwiftUI
import AppKit
import FlydigiKit

struct GameRulesSection: View {
    @Environment(GameProfileStore.self) private var games
    @Environment(ControllerModel.self) private var model
    @Environment(ProfileStore.self) private var profiles
    @State private var editing: GameRule?
    @State private var creating = false

    var body: some View {
        @Bindable var games = games
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("My game profiles", icon: "gamecontroller.fill")
                Spacer()
                SwitchRow(title: "Automatic switching", isOn: $games.enabled).frame(width: 220)
            }
            Text("When one of these apps comes to the front, the controller switches to the chosen profile slot and trigger preset, and goes back to normal when the app leaves.")
                .font(.system(size: 12)).foregroundStyle(SS.n300)
            if let r = games.activeRule {
                HStack(spacing: 8) {
                    Circle().fill(SS.green).frame(width: 7, height: 7)
                    Text("Active now: \(r.name)").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    if let e = games.lastEvent { Text("· \(e)").font(.system(size: 12)).foregroundStyle(SS.n400) }
                }
            }
            if games.rules.isEmpty {
                Text("No game profiles yet. Add one, or pick a game from Flydigi's list below and press “Use as base”.")
                    .font(.system(size: 12)).foregroundStyle(SS.n400)
            } else {
                VStack(spacing: 6) {
                    ForEach(games.rules) { rule in
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(get: { rule.enabled }, set: { v in update(rule) { $0.enabled = v } })).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(SS.brand)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                Text(summary(rule)).font(.system(size: 11)).foregroundStyle(SS.n400).lineLimit(1)
                            }
                            Spacer()
                            if games.activeRule?.id == rule.id { Text("active").font(.system(size: 10, weight: .semibold)).foregroundStyle(SS.green) }
                            GhostButton(title: "Test", enabled: model.connection != .none) { Task { await games.test(rule) } }
                            GhostButton(title: "Edit") { editing = rule }
                            Button { games.rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash").foregroundStyle(SS.n300) }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12).frame(height: 44)
                        .background(SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            HStack(spacing: 8) {
                PrimaryButton(title: "Add game profile", icon: "plus") { creating = true }
                if games.activeRule != nil { GhostButton(title: "Back to normal now") { Task { await games.restore() } } }
            }
        }
        .sheet(isPresented: $creating) { GameRuleEditor(rule: GameRule(name: "")) { games.rules.append($0) } }
        .sheet(item: $editing) { r in GameRuleEditor(rule: r) { new in update(r) { $0 = new } } }
    }

    private func update(_ rule: GameRule, _ f: (inout GameRule) -> Void) {
        guard let i = games.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        var r = games.rules[i]; f(&r); games.rules[i] = r
    }

    private func summary(_ r: GameRule) -> String {
        var parts: [String] = []
        if let b = r.bundleId { parts.append(b) } else if let p = r.processName { parts.append("“\(p)”") }
        if let s = r.slot { let t = profiles.slots.first { Int($0.index) == s }?.config.title ?? ""; parts.append("slot \(s + 1)\(t.isEmpty ? "" : " · \(t)")") }
        if !r.left.isNormal || !r.right.isNormal { parts.append("triggers " + ForceAdaptPreset.modes.first { $0.0 == r.left.mode }!.1 + " / " + ForceAdaptPreset.modes.first { $0.0 == r.right.mode }!.1) }
        return parts.joined(separator: " · ")
    }
}

struct GameRuleEditor: View {
    @State var rule: GameRule
    let onSave: (GameRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileStore.self) private var profiles
    @Environment(ControllerModel.self) private var model
    @State private var matchByName = false
    @State private var running: [NSRunningApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(rule.name.isEmpty ? "New game profile" : rule.name).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            Field("Name") { TextField("Game name", text: $rule.name).textFieldStyle(.roundedBorder).frame(width: 320) }

            Field("App to watch") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(running, id: \.processIdentifier) { app in
                                Button(app.localizedName ?? app.bundleIdentifier ?? "?") { rule.bundleId = app.bundleIdentifier; rule.processName = nil; if rule.name.isEmpty { rule.name = app.localizedName ?? "" } }
                            }
                        } label: {
                            HStack { Image(systemName: "list.bullet"); Text("Running apps") }.font(.system(size: 13)).foregroundStyle(.white)
                                .padding(.horizontal, 12).frame(height: 32).background(SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SS.n500))
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                        .onAppear { running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") } }
                        GhostButton(title: "Choose app…", icon: "folder") { chooseApp() }
                    }
                    if let b = rule.bundleId {
                        HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill").foregroundStyle(SS.green); Text(b).font(.system(size: 12, design: .monospaced)).foregroundStyle(SS.n300) }
                    }
                    HStack(spacing: 8) {
                        Text("or match by window/app name containing").font(.system(size: 12)).foregroundStyle(SS.n300)
                        TextField("e.g. Forza", text: Binding(get: { rule.processName ?? "" }, set: { rule.processName = $0.isEmpty ? nil : $0 })).textFieldStyle(.roundedBorder).frame(width: 180)
                    }
                    Text("Steam and Epic games run as their own app on the Mac; launch the game once, then pick it from Running apps.").font(.system(size: 11)).foregroundStyle(SS.n400)
                }
            }

            Field("Profile slot") {
                DarkSelect(selection: Binding(get: { rule.slot ?? -1 }, set: { rule.slot = $0 < 0 ? nil : $0 }), options: slotOptions, width: 320)
            }

            HStack(alignment: .top, spacing: 24) {
                presetEditor("Left trigger", $rule.left)
                presetEditor("Right trigger", $rule.right)
            }
            if model.connection == .dinput { Text("Trigger presets apply in XInput mode only.").font(.system(size: 12)).foregroundStyle(SS.yellow) }

            HStack {
                GhostButton(title: "Cancel") { dismiss() }
                Spacer()
                PrimaryButton(title: "Save", icon: "checkmark", enabled: !rule.name.isEmpty && (rule.bundleId != nil || !(rule.processName ?? "").isEmpty)) { onSave(rule); dismiss() }
            }
        }
        .padding(24).frame(width: 720)
        .background(SS.n800).preferredColorScheme(.dark)
    }

    private var slotOptions: [(Int, String)] {
        var out: [(Int, String)] = [(-1, "Keep current")]
        for i in 0..<4 {
            let title = profiles.slots.first { Int($0.index) == i }?.config.title ?? ""
            out.append((i, title.isEmpty ? "Slot \(i + 1)" : "Slot \(i + 1) · \(title)"))
        }
        return out
    }

    private func presetEditor(_ title: String, _ p: Binding<ForceAdaptPreset>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Field(title) { DarkSelect(selection: p.mode, options: ForceAdaptPreset.modes, width: 320) }
            if p.wrappedValue.mode != 0 {
                Field("Stroke") { StepSlider(value: Binding(get: { Double(p.wrappedValue.stroke) }, set: { p.wrappedValue.stroke = Int($0) }), range: 10...100) }
                Field(p.wrappedValue.mode == 1 ? "Resistance" : "Strength") { StepSlider(value: Binding(get: { Double(p.wrappedValue.strength) }, set: { p.wrappedValue.strength = Int($0) }), range: 1...10) }
                if p.wrappedValue.mode == 2 || p.wrappedValue.mode == 5 {
                    Field("Pressure level") { StepSlider(value: Binding(get: { Double(p.wrappedValue.pressure) }, set: { p.wrappedValue.pressure = Int($0) }), range: 1...10) }
                    Field("Frequency") { StepSlider(value: Binding(get: { Double(p.wrappedValue.frequency) }, set: { p.wrappedValue.frequency = Int($0) }), range: 1...10) }
                }
            }
        }
        .frame(width: 320)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url) {
            rule.bundleId = bundle.bundleIdentifier
            rule.processName = nil
            if rule.name.isEmpty { rule.name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String) ?? (bundle.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent }
        }
    }
}

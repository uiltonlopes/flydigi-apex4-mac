// Macros: on-board sequences the firmware plays when a bound button is pressed (docs/protocol.md §4,
// blob bytes 230..767). Left: the profile's macros. Right: the step editor with a live recorder that
// captures presses from the pad through GameController.

import SwiftUI
import FlydigiKit

struct MacrosPage: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(LiveInput.self) private var live
    @State private var selected: Int?

    var body: some View {
        if profiles.draft == nil {
            ContentUnavailableView("No profile loaded", systemImage: "list.number", description: Text("Connect the controller and press Refresh.")).frame(maxWidth: .infinity, maxHeight: .infinity).background(SS.n800)
        } else {
            HStack(spacing: 0) {
                macroList.frame(width: 280).background(SS.n700)
                Group {
                    if let i = selected, profiles.draft?.macros[safe: i] != nil {
                        MacroEditor(index: i)
                    } else {
                        ContentUnavailableView("Select a macro", systemImage: "list.number",
                                               description: Text("Pick one on the left or press + to bind a new macro to a button. Steps play on the pad itself, so they work in any game and on any platform."))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onChange(of: profiles.draft?.macros.count) { _, n in if let s = selected, s >= (n ?? 0) { selected = nil } }
        }
    }

    private var macroList: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(Array((profiles.draft?.macros ?? []).enumerated()), id: \.offset) { i, m in
                    HStack {
                        Image(systemName: "\(shortName(m.key).lowercased()).circle.fill").font(.title3).foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortName(m.key)).font(.headline)
                            Text("\(m.actions.count) step\(m.actions.count == 1 ? "" : "s") · \(enableName(m.enable))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(i)
                    .listRowBackground(selected == i ? SS.n500 : Color.clear)
                    .contextMenu { Button("Delete", role: .destructive) { profiles.removeMacro(at: i) } }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            Divider()
            HStack {
                Menu {
                    ForEach(availableKeys, id: \.self) { k in Button(String(describing: k)) { selected = profiles.addMacro(for: k) } }
                } label: { Image(systemName: "plus") }
                .menuIndicator(.hidden).fixedSize()
                .disabled((profiles.draft?.macros.count ?? 0) >= profiles.maxMacros || availableKeys.isEmpty)
                .help("Bind a new macro to a button")
                Button { if let s = selected { profiles.removeMacro(at: s) } } label: { Image(systemName: "minus") }
                    .disabled(selected == nil)
                Spacer()
                Text("\(profiles.draft?.macros.count ?? 0)/\(profiles.maxMacros)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .buttonStyle(.borderless).padding(8)
        }
    }

    /// Buttons that can still receive a macro: physical keys without one.
    private var availableKeys: [ControllerKey] {
        let used = Set(profiles.draft?.macros.map(\.key) ?? [])
        return Apex4Render.mappableKeys.filter { !used.contains($0.rawValue) }
    }
}

private func shortName(_ raw: UInt8) -> String {
    guard let k = ControllerKey(rawValue: raw) else { return "?" }
    return Apex4Render.shortLabel(k)
}
private func enableName(_ e: GamepadConfig.Macro.Enable) -> String {
    switch e { case .none: "disabled"; case .once: "plays once"; case .press: "repeats while held"; case .click: "toggles" }
}

// MARK: - Editor

struct MacroEditor: View {
    let index: Int
    @Environment(ProfileStore.self) private var profiles
    @Environment(LiveInput.self) private var live
    @State private var recorder = MacroRecorder()

    private var macro: GamepadConfig.Macro { profiles.draft!.macros[index] }
    private func update(_ f: (inout GamepadConfig.Macro) -> Void) { profiles.updateMacro(at: index, f) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Bound to", selection: Binding(get: { ControllerKey(rawValue: macro.key) ?? .a }, set: { k in update { $0.key = k.rawValue } })) {
                        ForEach(bindableKeys, id: \.self) { Text(String(describing: $0)).tag($0) }
                    }
                    Picker("Playback", selection: Binding(get: { macro.enable }, set: { e in update { $0.enable = e } })) {
                        Text("Once per press").tag(GamepadConfig.Macro.Enable.once)
                        Text("Repeat while held").tag(GamepadConfig.Macro.Enable.press)
                        Text("Toggle on / off").tag(GamepadConfig.Macro.Enable.click)
                        Text("Disabled").tag(GamepadConfig.Macro.Enable.none)
                    }
                    LabeledContent("Total time", value: Duration.milliseconds(totalMs).formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))
                } header: { Text("Macro") }

                Section {
                    timeline
                    ForEach(macro.actions.indices, id: \.self) { j in
                        MacroStepRow(step: Binding(get: { macro.actions[j] }, set: { v in update { $0.actions[j] = v } }), tick: profiles.macroTick) {
                            update { $0.actions.remove(at: j) }
                        }
                    }
                    .onMove { from, to in update { $0.actions.move(fromOffsets: from, toOffset: to) } }
                    HStack {
                        Menu("Add step") {
                            Button("Press a button") { append(.init(durationMs: 50, key: ControllerKey.a.rawValue, event: .press)) }
                            Button("Release a button") { append(.init(durationMs: 50, key: ControllerKey.a.rawValue, event: .release)) }
                            Button("Hold a button") { append(.init(durationMs: 50, key: ControllerKey.a.rawValue, event: .hold)) }
                            Divider()
                            Button("Left stick direction") { append(.init(durationMs: 50, key: ControllerKey.joystickUp.rawValue, event: .leftJoystick)) }
                            Button("Right stick direction") { append(.init(durationMs: 50, key: ControllerKey.joystickUp.rawValue, event: .rightJoystick)) }
                            Divider()
                            Button("Tap (press + release)") {
                                append(.init(durationMs: 50, key: ControllerKey.a.rawValue, event: .press))
                                append(.init(durationMs: 50, key: ControllerKey.a.rawValue, event: .release))
                            }
                        }.fixedSize()
                        Spacer()
                        Button("Clear all", role: .destructive) { update { $0.actions.removeAll() } }.disabled(macro.actions.isEmpty)
                    }
                } header: {
                    HStack {
                        Text("Steps")
                        Spacer()
                        recordButton
                    }
                } footer: {
                    Text("Times are the delay since the previous step (\(profiles.macroTick) ms resolution). Drag rows to reorder. Recording captures presses from the pad itself — enable the live readout in Sticks & Triggers if nothing arrives.")
                }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden)
        }
        .background(SS.n800)
        .onChange(of: live.pressedKeys) { old, new in
            guard recorder.isRecording else { return }
            for a in recorder.consume(old: old, new: new) { append(a) }
        }
        .onDisappear { recorder.stop() }
    }

    private var bindableKeys: [ControllerKey] {
        let used = Set(profiles.draft?.macros.enumerated().filter { $0.offset != index }.map(\.element.key) ?? [])
        return Apex4Render.mappableKeys.filter { !used.contains($0.rawValue) }
    }
    private var totalMs: Int { macro.actions.reduce(0) { $0 + $1.durationMs } }
    private func append(_ a: GamepadConfig.MacroAction) {
        var a = a; a.durationMs = max(0, a.durationMs / profiles.macroTick * profiles.macroTick)
        update { $0.actions.append(a) }
    }

    private var recordButton: some View {
        Button {
            if recorder.isRecording { recorder.stop() } else { recorder.start(initial: live.pressedKeys) }
        } label: {
            Label(recorder.isRecording ? "Stop" : "Record from pad", systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                .symbolEffect(.pulse, isActive: recorder.isRecording)
                .foregroundStyle(recorder.isRecording ? Color.red : Color.accentColor)
        }
        .buttonStyle(.borderless).controlSize(.small)
        .disabled(!live.connected && !recorder.isRecording)
        .help(live.connected ? "Press buttons on the controller; each press and release becomes a step with its real timing." : "No game controller visible to the system.")
    }

    /// Compact horizontal picture of the sequence: one chip per step, spaced by its delay.
    private var timeline: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(macro.actions.indices, id: \.self) { j in
                    let a = macro.actions[j]
                    HStack(spacing: 0) {
                        if j > 0 {
                            Rectangle().fill(.separator).frame(width: max(4, CGFloat(a.durationMs) / 12), height: 1)
                        }
                        Text(stepLabel(a)).font(.caption2.monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(chipColour(a.event).opacity(0.18), in: Capsule())
                            .overlay(Capsule().strokeBorder(chipColour(a.event).opacity(0.6)))
                    }
                }
                if macro.actions.isEmpty { Text("No steps yet").font(.caption).foregroundStyle(.tertiary) }
            }
            .padding(.vertical, 6)
        }
    }
    private func stepLabel(_ a: GamepadConfig.MacroAction) -> String {
        switch a.event {
        case .press: "↓\(shortName(a.key))"; case .release: "↑\(shortName(a.key))"; case .hold: "⇣\(shortName(a.key))"
        case .leftJoystick: "L\(directionArrow(a.key))"; case .rightJoystick: "R\(directionArrow(a.key))"
        }
    }
    private func chipColour(_ e: GamepadConfig.MacroAction.Event) -> Color {
        switch e { case .press: .green; case .release: .orange; case .hold: .purple; case .leftJoystick, .rightJoystick: .cyan }
    }
}

// MARK: - Step row

struct MacroStepRow: View {
    @Binding var step: GamepadConfig.MacroAction
    let tick: Int
    let onDelete: () -> Void

    private var isStick: Bool { step.event == .leftJoystick || step.event == .rightJoystick }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                TextField("ms", value: Binding(get: { step.durationMs }, set: { step.durationMs = max(0, min(60_000, $0 / tick * tick)) }), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 64).multilineTextAlignment(.trailing)
                Text("ms").foregroundStyle(.secondary)
            }
            Picker("", selection: Binding(get: { step.event }, set: { e in
                let wasStick = isStick
                step.event = e
                let nowStick = e == .leftJoystick || e == .rightJoystick
                if wasStick != nowStick { step.key = nowStick ? ControllerKey.joystickUp.rawValue : ControllerKey.a.rawValue }
            })) {
                Text("Press").tag(GamepadConfig.MacroAction.Event.press)
                Text("Release").tag(GamepadConfig.MacroAction.Event.release)
                Text("Hold").tag(GamepadConfig.MacroAction.Event.hold)
                Text("Left stick").tag(GamepadConfig.MacroAction.Event.leftJoystick)
                Text("Right stick").tag(GamepadConfig.MacroAction.Event.rightJoystick)
            }
            .labelsHidden().frame(width: 120)
            if isStick {
                Picker("", selection: Binding(get: { ControllerKey(rawValue: step.key) ?? .joystickCenter }, set: { step.key = $0.rawValue })) {
                    ForEach(stickDirections, id: \.self) { Text(directionName($0)).tag($0) }
                }.labelsHidden().frame(width: 140)
            } else {
                Picker("", selection: Binding(get: { ControllerKey(rawValue: step.key) ?? .a }, set: { step.key = $0.rawValue })) {
                    ForEach(Apex4Render.mappableKeys, id: \.self) { Text(String(describing: $0)).tag($0) }
                }.labelsHidden().frame(width: 140)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.secondary)
        }
    }
}

private let stickDirections: [ControllerKey] = [.joystickCenter, .joystickUp, .joystickRightUp, .joystickRight, .joystickRightDown,
                                                 .joystickDown, .joystickLeftDown, .joystickLeft, .joystickLeftUp]
private func directionName(_ k: ControllerKey) -> String {
    switch k {
    case .joystickCenter: "Center (release)"; case .joystickUp: "Up"; case .joystickRightUp: "Up-right"; case .joystickRight: "Right"
    case .joystickRightDown: "Down-right"; case .joystickDown: "Down"; case .joystickLeftDown: "Down-left"; case .joystickLeft: "Left"
    case .joystickLeftUp: "Up-left"; default: String(describing: k)
    }
}
private func directionArrow(_ raw: UInt8) -> String {
    switch ControllerKey(rawValue: raw) {
    case .joystickCenter: "·"; case .joystickUp: "↑"; case .joystickRightUp: "↗"; case .joystickRight: "→"; case .joystickRightDown: "↘"
    case .joystickDown: "↓"; case .joystickLeftDown: "↙"; case .joystickLeft: "←"; case .joystickLeftUp: "↖"; default: "?"
    }
}

// MARK: - Recorder

/// Turns edges in the live pressed-key set into timed press/release steps.
@Observable
final class MacroRecorder {
    private(set) var isRecording = false
    private var lastEdge: Date?
    private var held: Set<ControllerKey> = []

    func start(initial: Set<ControllerKey>) { held = initial; lastEdge = nil; isRecording = true }
    func stop() { isRecording = false }

    func consume(old: Set<ControllerKey>, new: Set<ControllerKey>) -> [GamepadConfig.MacroAction] {
        let now = Date()
        let delay = lastEdge.map { Int($0.distance(to: now) * 1000) } ?? 0
        var out: [GamepadConfig.MacroAction] = []
        for k in new.subtracting(old).sorted(by: { $0.rawValue < $1.rawValue }) where !held.contains(k) {
            out.append(.init(durationMs: out.isEmpty ? delay : 0, key: k.rawValue, event: .press)); held.insert(k)
        }
        for k in old.subtracting(new).sorted(by: { $0.rawValue < $1.rawValue }) {
            out.append(.init(durationMs: out.isEmpty ? delay : 0, key: k.rawValue, event: .release)); held.remove(k)
        }
        if !out.isEmpty { lastEdge = now }
        return out
    }
}

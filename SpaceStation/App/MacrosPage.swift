// Macros: on-board sequences the firmware plays when a bound button is pressed (docs/protocol.md §4,
// blob bytes 230..767). Left: the profile's macros. Right: the step editor with a live recorder that
// captures presses from the pad through GameController. Styled like the rest of the app (dark cards).

import SwiftUI
import FlydigiKit

struct MacrosPage: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(LiveInput.self) private var live
    @Environment(MacroLibrary.self) private var library
    @State private var selected: Int?
    @State private var showLibrary = false

    var body: some View {
        if profiles.draft == nil {
            ContentUnavailableView("No profile loaded", systemImage: "list.number", description: Text("Connect the controller and press Refresh.")).frame(maxWidth: .infinity, maxHeight: .infinity).background(SS.n800)
        } else {
            HStack(alignment: .top, spacing: 20) {
                macroList.frame(width: 300)
                Group {
                    if let i = selected, profiles.draft?.macros[safe: i] != nil {
                        MacroEditor(index: i)
                    } else {
                        DarkCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Select a macro").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                Text("Pick one on the left or press “New macro” to bind a sequence to a button. Steps play on the pad itself, so they work in any game and on any platform.").font(.system(size: 12)).foregroundStyle(SS.n300)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SS.n800)
            .onChange(of: profiles.draft?.macros.count) { _, n in if let s = selected, s >= (n ?? 0) { selected = nil } }
            .onAppear { if let i = profiles.macroToOpen { selected = i; profiles.macroToOpen = nil } }
            .onChange(of: profiles.macroToOpen) { _, i in if let i { selected = i; profiles.macroToOpen = nil } }
            // After Apply (or Revert) the editor closes, so it is obvious the change went through; it reopens
            // when a macro is clicked or a new one is created.
            .onChange(of: profiles.isDirty) { was, now in if was && !now { selected = nil } }
            .sheet(isPresented: $showLibrary) { MacroLibrarySheet(onAdded: { selected = $0 }).environment(profiles).environment(library) }
        }
    }

    private var macroList: some View {
        DarkCard(padding: 12) {
            VStack(spacing: 10) {
                HStack {
                    Text("Macros").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Text("\(profiles.draft?.macros.count ?? 0)/\(profiles.maxMacros)").font(.system(size: 12).monospacedDigit()).foregroundStyle(SS.n300)
                }
                .padding(.horizontal, 4)
                if (profiles.draft?.macros ?? []).isEmpty {
                    VStack(spacing: 6) {
                        Text("No macros in this profile").font(.system(size: 13)).foregroundStyle(SS.n300)
                        Text("Bind one to a button and record steps from the pad.").font(.system(size: 12)).foregroundStyle(SS.n400).multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 24).frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array((profiles.draft?.macros ?? []).enumerated()), id: \.offset) { i, m in
                            Button { selected = i } label: {
                                HStack(spacing: 10) {
                                    KeyBadge(label: shortName(m.key), size: 30, highlighted: selected == i)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(shortName(m.key)).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                        Text("\(m.actions.count) steps · \(enableName(m.enable))").font(.system(size: 11)).foregroundStyle(SS.n400)
                                    }
                                    Spacer()
                                    if selected == i { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(SS.n300) }
                                }
                                .padding(.horizontal, 10).frame(height: 48)
                                .background(selected == i ? SS.n500 : SS.n600, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Save to library") { library.save(m, name: String(localized: "Macro") + " " + shortName(m.key)) }
                                Button("Delete", role: .destructive) { profiles.removeMacro(at: i) }
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Menu {
                        ForEach(availableKeys, id: \.self) { k in Button(String(describing: k)) { selected = profiles.addMacro(for: k) } }
                    } label: {
                        HStack(spacing: 6) { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)); Text("New macro").font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize() }
                            .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 32)
                            .background(SS.brand500, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                    .disabled((profiles.draft?.macros.count ?? 0) >= profiles.maxMacros || availableKeys.isEmpty)
                    .help("Bind a new macro to a button")
                    GhostButton(title: "", icon: "books.vertical") { showLibrary = true }.frame(width: 40).help("Macro library")
                    GhostButton(title: "", icon: "trash", enabled: selected != nil, destructive: true) { if let s = selected { profiles.removeMacro(at: s) } }.frame(width: 40)
                }
            }
        }
    }

    private var availableKeys: [ControllerKey] {
        let used = Set((profiles.draft?.macros ?? []).map(\.key))
        return Apex4Render.mappableKeys.filter { !used.contains($0.rawValue) }
    }
}


private func shortName(_ raw: UInt8) -> String {
    guard let k = ControllerKey(rawValue: raw) else { return "?" }
    return Apex4Render.shortLabel(k)
}
private func enableName(_ e: GamepadConfig.Macro.Enable) -> String {
    switch e {
    case .none: String(localized: "disabled"); case .once: String(localized: "plays once")
    case .press: String(localized: "repeats while held"); case .click: String(localized: "toggles")
    }
}

// MARK: - Editor

struct MacroEditor: View {
    let index: Int
    @Environment(ProfileStore.self) private var profiles
    @Environment(LiveInput.self) private var live
    @State private var recorder = MacroRecorder()

    // Safe against stale indices: SwiftUI can evaluate bindings for a row after the macro or a step was removed.
    private var macro: GamepadConfig.Macro { profiles.draft?.macros[safe: index] ?? .init(key: 0xFF, count: 0, enable: .none, actions: []) }
    private func update(_ f: (inout GamepadConfig.Macro) -> Void) { profiles.updateMacro(at: index, f) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DarkCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Macro").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        HStack(alignment: .top, spacing: 24) {
                            Field("Bound to") {
                                DarkSelect(selection: Binding(get: { ControllerKey(rawValue: macro.key) ?? .a }, set: { k in update { $0.key = k.rawValue } }),
                                           options: bindableKeys.map { ($0, String(describing: $0)) }, width: 200)
                            }
                            Field("Playback") {
                                DarkSelect(selection: Binding(get: { macro.enable }, set: { e in update { $0.enable = e } }),
                                           options: [(.once, "Once per press"), (.press, "Repeat while held"), (.click, "Toggle on / off"), (.none, "Disabled")], width: 200)
                            }
                            Field("Total time") {
                                Text(Duration.milliseconds(totalMs).formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))
                                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(.white).frame(height: 36)
                            }
                        }
                    }
                }
                DarkCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Text("Steps").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            Spacer()
                            recordButton
                            Menu {
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
                            } label: {
                                HStack(spacing: 6) { Image(systemName: "plus"); Text("Add step").lineLimit(1).fixedSize() }.font(.system(size: 13))
                                    .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 32)
                                    .background(SS.n600, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SS.n500))
                                    .contentShape(Rectangle())
                            }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                            GhostButton(title: "Clear all", icon: "xmark", enabled: !macro.actions.isEmpty, destructive: true) { update { $0.actions.removeAll() } }
                        }
                        timeline
                        if macro.actions.isEmpty {
                            Text("No steps yet. Record from the pad or add steps by hand.").font(.system(size: 12)).foregroundStyle(SS.n400)
                        } else {
                            HStack(spacing: 12) {
                                Text("#").frame(width: 24)
                                Text("Delay before").frame(width: 120, alignment: .leading)
                                Text("Action").frame(width: 130, alignment: .leading)
                                Text("Button / direction").frame(width: 160, alignment: .leading)
                                Spacer()
                            }
                            .font(.system(size: 11)).foregroundStyle(SS.n400).padding(.horizontal, 10)
                            VStack(spacing: 6) {
                                ForEach(macro.actions.indices, id: \.self) { j in
                                    MacroStepRow(number: j + 1,
                                                 step: Binding(get: { macro.actions[safe: j] ?? .init(durationMs: 0, key: 0, event: .press) },
                                                               set: { v in update { if $0.actions.indices.contains(j) { $0.actions[j] = v } } }),
                                                 tick: profiles.macroTick,
                                                 canMoveUp: j > 0, canMoveDown: j < macro.actions.count - 1,
                                                 onMove: { up in update { let k = up ? j - 1 : j + 1; if $0.actions.indices.contains(j), $0.actions.indices.contains(k) { $0.actions.swapAt(j, k) } } },
                                                 onDelete: { update { if $0.actions.indices.contains(j) { $0.actions.remove(at: j) } } })
                                }
                            }
                        }
                        Text("Times are the delay since the previous step (\(profiles.macroTick) ms resolution). Recording captures presses from the pad itself — enable the live readout if nothing arrives.")
                            .font(.system(size: 11)).foregroundStyle(SS.n400)
                    }
                }
            }
        }
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
            HStack(spacing: 6) {
                Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle").symbolEffect(.pulse, isActive: recorder.isRecording)
                Text(recorder.isRecording ? "Stop" : "Record from pad").lineLimit(1).fixedSize()
            }
            .font(.system(size: 13)).foregroundStyle(recorder.isRecording ? .white : SS.red)
            .padding(.horizontal, 14).frame(height: 32)
            .background(recorder.isRecording ? SS.red : SS.n600, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(recorder.isRecording ? SS.red : SS.n500))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!live.connected && !recorder.isRecording)
        .help(live.connected ? "Press buttons on the controller; each press and release becomes a step with its real timing." : "No game controller visible to the system.")
    }

    /// Compact horizontal picture of the sequence: one chip per step, spaced by its delay.
    private var timeline: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(macro.actions.indices, id: \.self) { j in
                    if let a = macro.actions[safe: j] {
                        HStack(spacing: 0) {
                            if j > 0 { Rectangle().fill(SS.n500).frame(width: max(4, CGFloat(a.durationMs) / 12), height: 1) }
                            Text(stepLabel(a)).font(.system(size: 10, weight: .semibold).monospaced()).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(chipColour(a.event).opacity(0.25), in: Capsule())
                                .overlay(Capsule().strokeBorder(chipColour(a.event).opacity(0.7)))
                        }
                    }
                }
                if macro.actions.isEmpty { Text("Timeline").font(.system(size: 11)).foregroundStyle(SS.n400) }
            }
            .padding(.vertical, 4)
        }
    }
    private func stepLabel(_ a: GamepadConfig.MacroAction) -> String {
        switch a.event {
        case .press: "↓\(shortName(a.key))"; case .release: "↑\(shortName(a.key))"; case .hold: "⇣\(shortName(a.key))"
        case .leftJoystick: "L\(directionArrow(a.key))"; case .rightJoystick: "R\(directionArrow(a.key))"
        }
    }
    private func chipColour(_ e: GamepadConfig.MacroAction.Event) -> Color {
        switch e { case .press: SS.green; case .release: SS.yellow; case .hold: Color(hex: 0xA678F5); case .leftJoystick, .rightJoystick: Color(hex: 0x4FC3F7) }
    }
}

// MARK: - Step row

struct MacroStepRow: View {
    let number: Int
    @Binding var step: GamepadConfig.MacroAction
    let tick: Int
    var canMoveUp = false, canMoveDown = false
    var onMove: (Bool) -> Void = { _ in }
    let onDelete: () -> Void

    private var isStick: Bool { step.event == .leftJoystick || step.event == .rightJoystick }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)").font(.system(size: 12).monospacedDigit()).foregroundStyle(SS.n400).frame(width: 24)
            HStack(spacing: 6) {
                TextField("", value: Binding(get: { step.durationMs }, set: { step.durationMs = max(0, min(60_000, $0 / tick * tick)) }), format: .number)
                    .textFieldStyle(.plain).font(.system(size: 13).monospacedDigit()).foregroundStyle(.white).multilineTextAlignment(.trailing)
                    .padding(.horizontal, 8).frame(width: 74, height: 30)
                    .background(SS.n800, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("ms").font(.system(size: 12)).foregroundStyle(SS.n400)
            }
            .frame(width: 120, alignment: .leading)
            DarkSelect(selection: Binding(get: { step.event }, set: { e in
                let wasStick = isStick
                step.event = e
                let nowStick = e == .leftJoystick || e == .rightJoystick
                if wasStick != nowStick { step.key = nowStick ? ControllerKey.joystickUp.rawValue : ControllerKey.a.rawValue }
            }), options: [(.press, "Press"), (.release, "Release"), (.hold, "Hold"), (.leftJoystick, "Left stick"), (.rightJoystick, "Right stick")], width: 130)
            if isStick {
                DarkSelect(selection: Binding(get: { ControllerKey(rawValue: step.key) ?? .joystickCenter }, set: { step.key = $0.rawValue }),
                           options: stickDirections.map { ($0, directionName($0)) }, width: 160)
            } else {
                DarkSelect(selection: Binding(get: { ControllerKey(rawValue: step.key) ?? .a }, set: { step.key = $0.rawValue }),
                           options: Apex4Render.mappableKeys.map { ($0, String(describing: $0)) }, width: 160)
            }
            Spacer()
            HStack(spacing: 2) {
                iconButton("chevron.up", enabled: canMoveUp) { onMove(true) }
                iconButton("chevron.down", enabled: canMoveDown) { onMove(false) }
                iconButton("trash", enabled: true, tint: SS.red, action: onDelete)
            }
        }
        .padding(.horizontal, 10).frame(height: 46)
        .background(SS.n600, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func iconButton(_ name: String, enabled: Bool, tint: Color = SS.n300, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 12, weight: .semibold)).foregroundStyle(enabled ? tint : SS.n500).frame(width: 26, height: 26).contentShape(Rectangle()) }
            .buttonStyle(.plain).disabled(!enabled)
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

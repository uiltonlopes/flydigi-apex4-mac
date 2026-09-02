import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case status, profiles, sticks, motion, macros, lighting, screen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .status: "Status"; case .profiles: "Profiles & Buttons"; case .sticks: "Sticks & Triggers"
        case .motion: "Motion"; case .macros: "Macros"; case .lighting: "Lighting"; case .screen: "Screen"
        }
    }
    var symbol: String {
        switch self {
        case .status: "gamecontroller"; case .profiles: "square.grid.2x2"; case .sticks: "dial.medium"
        case .motion: "gyroscope"; case .macros: "list.number"; case .lighting: "light.max"; case .screen: "photo.on.rectangle"
        }
    }
}

@main
struct SpaceStationApp: App {
    @State private var model = ControllerModel()
    @State private var live = LiveInput()
    @State private var games: GameProfileStore
    init() { let m = ControllerModel(); _model = State(initialValue: m); _games = State(initialValue: GameProfileStore(model: m)) }

    var body: some Scene {
        Window("Space Station", id: "main") {
            MainWindow()
                .environment(model)
                .environment(model.profiles)
                .environment(live)
                .environment(games)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Apply to Controller") { Task { await model.profiles.apply() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.profiles.isDirty)
                Button("Revert Changes") { model.profiles.revert() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.profiles.isDirty)
                Button("Refresh Controller") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView().environment(model)
        }

        MenuBarExtra {
            MenuBarView().environment(model).environment(model.profiles).environment(live).environment(games)
        } label: {
            Image(systemName: model.connection == .none ? "gamecontroller" : "gamecontroller.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

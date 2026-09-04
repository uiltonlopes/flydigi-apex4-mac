import SwiftUI

/// Closing the window keeps the app in the menu bar unless the user asked to quit instead (Settings › App).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { UserDefaults.standard.bool(forKey: "quitOnClose") }
    func applicationWillTerminate(_ notification: Notification) { KeyboardMouseEngine.shared.releaseAll() }
}

@main
struct SpaceStationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var updates = AppUpdateChecker()
    @State private var model = ControllerModel()
    @State private var live = LiveInput()
    @State private var games: GameProfileStore
    @State private var library = ProfileLibrary()
    @State private var macroLibrary = MacroLibrary()
    @State private var keyboardMouse = KeyboardMouseStore()
    init() { let m = ControllerModel(); _model = State(initialValue: m); _games = State(initialValue: GameProfileStore(model: m)) }

    var body: some Scene {
        Window("Space Station", id: "main") {
            MainWindow()
                .environment(model)
                .environment(model.profiles)
                .environment(live)
                .environment(games)
                .environment(library)
                .environment(macroLibrary)
                .environment(keyboardMouse)
                .environment(updates)
                .frame(minWidth: 1100, minHeight: 720)
                .task { await updates.checkIfDue() }
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
            MenuBarView().environment(model).environment(model.profiles).environment(live).environment(games).environment(updates)
        } label: {
            Image(systemName: model.connection == .none ? "gamecontroller" : "gamecontroller.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

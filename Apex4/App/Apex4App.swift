import SwiftUI

@main
struct Apex4App: App {
    @State private var model = ControllerModel()

    var body: some Scene {
        Window("Apex 4", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 620, minHeight: 440)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: model.connection == .none ? "gamecontroller" : "gamecontroller.fill")
        }
    }
}

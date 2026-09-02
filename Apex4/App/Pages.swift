// Sidebar routes: Screen (upload + official library), Adaptive Trigger (game presets), Settings.

import SwiftUI
import UniformTypeIdentifiers
import FlydigiKit
import FlydigiTransport
import FlydigiHelperProtocol

// MARK: - Screen

struct ScreenPage: View {
    let back: () -> Void
    @Environment(ControllerModel.self) private var model
    @State private var editor = ScreenEditorState()
    @State private var importing = false
    @State private var library: [FlydigiAPI.ScreenPic] = []
    @State private var libraryError: String?
    @State private var downloading: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Screen", back: back)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Screen Settings").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    DarkCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 14) {
                                Text("Custom\nAnimation").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                                PrimaryButton(title: editor.isEmpty ? "Upload" : "Choose another…", enabled: !model.busy) { importing = true }
                                Text("GIF, PNG or JPEG · drop a file here · the screen is 160 × 80, up to \(Screen.maxFrames) frames").font(.system(size: 12)).foregroundStyle(SS.n300)
                                Spacer()
                                if let u = editor.url { Text(u.lastPathComponent).font(.system(size: 12)).foregroundStyle(SS.n400).lineLimit(1) }
                            }
                            if !editor.isEmpty {
                                ScreenEditorView(state: editor)
                                HStack(spacing: 12) {
                                    if let p = model.uploadProgress {
                                        ProgressView(value: p).tint(SS.brand500).frame(width: 260)
                                        Text("Sending… \(Int(p * 100)) % — about \(Int((1 - p) * Double(max(1, editor.outputCount)) * 3.5)) s left").font(.system(size: 12)).foregroundStyle(SS.n300)
                                    } else {
                                        PrimaryButton(title: "Send to controller", icon: "arrow.up.circle", enabled: !model.busy && model.connection == .xinput && model.info?.wired != false) {
                                            let frames = editor.encode(viewport: ScreenEditorView.viewportSize)
                                            Task { await model.uploadScreen(frames: frames) }
                                        }
                                        if model.connection != .xinput { Text("Needs XInput mode.").font(.system(size: 12)).foregroundStyle(SS.yellow) }
                                        else if model.info?.wired == false { Text("Needs the USB cable (the receiver does not forward screen data).").font(.system(size: 12)).foregroundStyle(SS.yellow) }
                                        else { Text("About \(Int(Double(editor.outputCount) * 3.5)) s for \(editor.outputCount) frame\(editor.outputCount == 1 ? "" : "s").").font(.system(size: 12)).foregroundStyle(SS.n400) }
                                    }
                                }
                            }
                        }
                    }
                    .dropDestination(for: URL.self) { urls, _ in if let u = urls.first { load(u) }; return true }

                    HStack(spacing: 0) {
                        VStack(spacing: 6) {
                            Text("Official selection").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            Rectangle().fill(SS.brand500).frame(height: 2)
                        }.fixedSize()
                        Spacer()
                        if let e = libraryError { Text(e).font(.system(size: 12)).foregroundStyle(SS.n400) }
                    }
                    .padding(.top, 8)

                    if library.isEmpty && libraryError == nil {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading Flydigi's library…").font(.system(size: 12)).foregroundStyle(SS.n300) }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 176), spacing: 14)], spacing: 14) {
                            ForEach(library) { pic in libraryCell(pic) }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.gif, .png, .jpeg]) { if case let .success(u) = $0 { load(u) } }
        .task { await loadLibrary() }
    }

    private func libraryCell(_ pic: FlydigiAPI.ScreenPic) -> some View {
        Button { Task { await pick(pic) } } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    AsyncImage(url: pic.imagePath) { phase in
                        if let img = phase.image { img.resizable().aspectRatio(2, contentMode: .fill) } else { Color.black }
                    }
                    .frame(height: 88).clipped()
                    if downloading == pic.id { ProgressView().controlSize(.small) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                HStack {
                    Text(displayTitle(pic)).font(.system(size: 12)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Text(pic.isGIF ? "GIF" : "JPG").font(.system(size: 10, weight: .semibold)).foregroundStyle(SS.n300)
                        .padding(.horizontal, 5).frame(height: 16).background(SS.n500, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(8)
            .background(SS.n700, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Load this animation into the preview")
    }

    /// Flydigi names them "精选动画N" (featured) / "第三方无版权N" (third-party, royalty-free).
    private func displayTitle(_ pic: FlydigiAPI.ScreenPic) -> String {
        let t = pic.title
        if t.hasPrefix("精选动画") { return "Featured \(t.dropFirst(4))" }
        if t.hasPrefix("第三方无版权") { return "Community \(t.dropFirst(6))" }
        return t.isEmpty ? "#\(pic.id)" : t
    }

    private func loadLibrary() async {
        let r: Result<[FlydigiAPI.ScreenPic], Error> = await Task.detached { Result { try FlydigiAPI.screenPictures() } }.value
        switch r {
        case .success(let l): library = l.sorted { ($0.isRecomment, $0.id) > ($1.isRecomment, $1.id) }
        case .failure: libraryError = "Library unavailable offline."
        }
    }

    private func pick(_ pic: FlydigiAPI.ScreenPic) async {
        downloading = pic.id
        defer { downloading = nil }
        let url = pic.imagePath
        let r: Result<URL, Error> = await Task.detached {
            Result {
                let data = try FlydigiAPI.download(url)
                let dst = FileManager.default.temporaryDirectory.appendingPathComponent("flydigi-\(pic.id).\(pic.isGIF ? "gif" : "jpg")")
                try data.write(to: dst)
                return dst
            }
        }.value
        if case .success(let u) = r { load(u) }
    }

    private func load(_ url: URL) { editor.load(url) }
}

// MARK: - Adaptive Trigger (game presets from Flydigi's list)

struct AdaptiveTriggerPage: View {
    let back: () -> Void
    @State private var games: [FlydigiAPI.GamePreset] = []
    @State private var error: String?
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Adaptive Trigger", back: back)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Flydigi's per-game trigger presets. Automatic switching when a game launches is planned; for now this is the reference list.")
                        .font(.system(size: 12)).foregroundStyle(SS.n300)
                    TextField("Search games", text: $query).textFieldStyle(.roundedBorder).frame(width: 280)
                    if games.isEmpty && error == nil {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading…").font(.system(size: 12)).foregroundStyle(SS.n300) }
                    } else if let error {
                        Text(error).font(.system(size: 12)).foregroundStyle(SS.n400)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                            ForEach(filtered) { g in card(g) }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .task {
            let r: Result<[FlydigiAPI.GamePreset], Error> = await Task.detached { Result { try FlydigiAPI.gamePresets() } }.value
            switch r { case .success(let g): games = g; case .failure: error = "Game list unavailable offline." }
        }
    }

    private var filtered: [FlydigiAPI.GamePreset] {
        guard !query.isEmpty else { return games }
        return games.filter { $0.enGameName.localizedCaseInsensitiveContains(query) || $0.gameName.localizedCaseInsensitiveContains(query) }
    }

    private func card(_ g: FlydigiAPI.GamePreset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: g.imagePath) { phase in
                if let img = phase.image { img.resizable().aspectRatio(16 / 9, contentMode: .fill) } else { SS.n800 }
            }
            .frame(height: 100).clipped().clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(g.enGameName.isEmpty ? g.gameName : g.enGameName).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
            HStack(spacing: 4) {
                ForEach(g.platforms.prefix(4), id: \.self) { p in
                    Text(p.capitalized).font(.system(size: 10)).foregroundStyle(SS.n300)
                        .padding(.horizontal, 5).frame(height: 16).background(SS.n500, in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                if g.isVibration == 1 { Image(systemName: "waveform").font(.system(size: 10)).foregroundStyle(SS.brand500) }
            }
        }
        .padding(10)
        .background(SS.n700, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Settings

struct SettingsPage: View {
    let back: () -> Void
    @Environment(ControllerModel.self) private var model
    @State private var firmwareNote: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Settings", back: back)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    navGroup("App Settings", ["Privileged helper", "About"])
                    navGroup("Controller Settings", ["USB mode", "Firmware"])
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Space Station for Mac \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")").font(.system(size: 11)).foregroundStyle(SS.n400)
                        if let i = model.info { Text("Device firmware: \(i.firmware)").font(.system(size: 11)).foregroundStyle(SS.n400) }
                    }
                }
                .padding(16).frame(width: 220).frame(maxHeight: .infinity)
                .background(SS.n700)

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text("App Settings").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        section("Privileged helper") {
                            Text(model.helperInstalled ? "Installed and registered with launchd." : "Not installed.").font(.system(size: 13)).foregroundStyle(.white)
                            Text("Runs as root only while talking to the controller in XInput mode, because Apple's Xbox driver owns the USB interface. Required for screen uploads and trigger previews.")
                                .font(.system(size: 12)).foregroundStyle(SS.n300)
                            HStack(spacing: 8) {
                                PrimaryButton(title: "Install helper", enabled: !model.helperInstalled) { model.installHelper() }
                                GhostButton(title: "Remove helper", enabled: model.helperInstalled, destructive: true) { model.uninstallHelper() }
                            }
                        }
                        section("About") {
                            Text("Space Station for Mac \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") — open-source (MIT), unofficial. Ported to macOS by Uilton Lopes.")
                                .font(.system(size: 13)).foregroundStyle(.white)
                            HStack(spacing: 10) {
                                Link(destination: URL(string: "https://github.com/uiltonlopes/flydigi-space-station-mac")!) { Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                                Link(destination: URL(string: "https://github.com/uiltonlopes")!) { Label("@uiltonlopes", systemImage: "person.crop.circle") }
                                Link(destination: URL(string: "https://www.linkedin.com/in/uiltonlopes")!) { Label("LinkedIn", systemImage: "link") }
                            }
                            .font(.system(size: 12)).tint(SS.brand500)
                            Text("Not affiliated with Flydigi. Controller artwork and app icon © Flydigi, used for interoperability (see NOTICE.md in the app bundle).")
                                .font(.system(size: 12)).foregroundStyle(SS.n300)
                        }
                        Text("Controller Settings").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).padding(.top, 8)
                        section("USB mode") {
                            Text(model.connection == .none ? "Not connected." : (model.connection == .xinput ? "XInput — what games expect; the screen and trigger previews need it." : "DInput — the app talks to the pad directly, no helper needed."))
                                .font(.system(size: 13)).foregroundStyle(.white)
                            GhostButton(title: model.connection == .xinput ? "Switch to DInput" : "Switch to XInput", icon: "arrow.left.arrow.right", enabled: model.connection != .none && !model.busy) { Task { await model.switchMode() } }
                        }
                        section("Firmware") {
                            Text("Installed: \(model.info?.firmware ?? "—")").font(.system(size: 13)).foregroundStyle(.white)
                            if let firmwareNote { Text(firmwareNote).font(.system(size: 12)).foregroundStyle(SS.n300) }
                            GhostButton(title: checking ? "Checking…" : "Check Flydigi for updates", icon: "arrow.down.circle", enabled: model.info != nil && !checking) { Task { await checkFirmware() } }
                            Text("Flashing is not implemented yet: updating still requires Space Station on Windows.").font(.system(size: 12)).foregroundStyle(SS.n400)
                        }
                    }
                    .padding(28).frame(maxWidth: 720, alignment: .leading)
                }
            }
        }
    }

    private func navGroup(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).padding(.vertical, 8)
            ForEach(items, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(SS.n300).padding(.vertical, 5) }
        }
        .padding(.bottom, 8)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            content()
        }
    }

    private func checkFirmware() async {
        guard let fw = model.info?.firmware else { return }
        checking = true; defer { checking = false }
        let r: Result<[String: FlydigiAPI.FirmwareChip], Error> = await Task.detached { Result { try FlydigiAPI.firmwareUpdates(mainChip: fw) } }.value
        switch r {
        case .success(let chips):
            if let main = chips["main_chip"], main.version != fw { firmwareNote = "Flydigi offers \(main.version). \(main.info.replacingOccurrences(of: "\n", with: " "))" }
            else { firmwareNote = "You are on the latest firmware Flydigi publishes." }
        case .failure: firmwareNote = "Could not reach Flydigi's update service."
        }
    }
}

// MARK: - Settings scene (⌘,) and menu bar extra

struct SettingsView: View {
    @Environment(ControllerModel.self) private var model
    var body: some View {
        Form {
            Section("Privileged helper") {
                LabeledContent("Status", value: model.helperInstalled ? "Installed" : "Not installed")
                HStack {
                    Button("Install helper") { model.installHelper() }.disabled(model.helperInstalled)
                    Button("Remove helper", role: .destructive) { model.uninstallHelper() }.disabled(!model.helperInstalled)
                }
            }
            Section("About") {
                Text("Open-source, MIT. Not affiliated with Flydigi.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(width: 440, height: 240)
    }
}

struct MenuBarView: View {
    @Environment(ControllerModel.self) private var model
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: model.connection == .none ? "gamecontroller" : "gamecontroller.fill").foregroundStyle(model.connection == .none ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                Text(model.connection == .none ? "Apex 4 not connected" : "Apex 4 · \(model.connection == .dinput ? "DInput" : "XInput")").font(.headline)
            }
            if !profiles.slots.isEmpty {
                Picker("Profile", selection: Binding(get: { profiles.activeSlot }, set: { profiles.select(slot: $0) })) {
                    ForEach(profiles.slots) { s in Text("\(s.index + 1) · \(s.config.title.isEmpty ? "Unnamed" : s.config.title)").tag(s.index) }
                }
                .disabled(profiles.isDirty)
            }
            if let l = model.led { Text("Lighting: \(String(describing: l.mode)) · \(l.brightness)%").font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack {
                Button("Open Apex 4…") { openWindow(id: "main"); NSApp.activate() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12).frame(width: 280)
    }
}

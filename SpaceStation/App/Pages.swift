// Sidebar routes: Screen (upload + official library), Adaptive Trigger (game presets), Settings.

import SwiftUI
import UniformTypeIdentifiers
import FlydigiKit
import FlydigiTransport
import FlydigiHelperProtocol
@preconcurrency import Translation

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
    @State private var checking = false
    @State private var dryRunning = false
    @State private var language = AppLanguage.current
    @State private var needsRestart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Settings", back: back)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    navGroup("Controller Settings", ["Firmware Update", "USB mode"])
                    navGroup("App Settings", ["Language", "Privileged helper"])
                    navGroup("About", [])
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Space Station for Mac \(appVersion)").font(.system(size: 11)).foregroundStyle(SS.n400)
                        if let i = model.info { Text("Device firmware: \(i.firmware)").font(.system(size: 11)).foregroundStyle(SS.n400) }
                    }
                }
                .padding(16).frame(width: 220).frame(maxHeight: .infinity)
                .background(SS.n700)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Controller Settings").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        section("Firmware Update") { firmware }
                        section("USB mode") {
                            Text(model.connection == .none ? "Not connected." : (model.connection == .xinput ? "XInput — what games expect; the screen and trigger previews need it." : "DInput — the app talks to the pad directly, no helper needed."))
                                .font(.system(size: 13)).foregroundStyle(.white)
                            GhostButton(title: model.connection == .xinput ? "Switch to DInput" : "Switch to XInput", icon: "arrow.left.arrow.right", enabled: model.connection != .none && !model.busy) { Task { await model.switchMode() } }
                        }
                        Text("App Settings").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).padding(.top, 8)
                        section("Language") {
                            Text("Choose a language").font(.system(size: 13)).foregroundStyle(SS.n300)
                            DarkSelect(selection: $language, options: AppLanguage.allCases.map { ($0, $0.title) }, width: 260)
                                .onChange(of: language) { _, l in l.apply(); needsRestart = true }
                            if needsRestart {
                                HStack(spacing: 10) {
                                    Text("Takes effect after restarting the app").font(.system(size: 12)).foregroundStyle(SS.yellow)
                                    GhostButton(title: "Restart now", icon: "arrow.clockwise") { AppLanguage.relaunch() }
                                }
                            }
                        }
                        section("Privileged helper") {
                            Text(model.helperInstalled ? "Installed and registered with launchd." : "Not installed.").font(.system(size: 13)).foregroundStyle(.white)
                            Text("Runs as root only while talking to the controller in XInput mode, because Apple's Xbox driver owns the USB interface. Required for screen uploads, trigger previews and key capture in XInput.")
                                .font(.system(size: 12)).foregroundStyle(SS.n300)
                            HStack(spacing: 8) {
                                PrimaryButton(title: "Install helper", enabled: !model.helperInstalled) { model.installHelper() }
                                GhostButton(title: "Remove helper", enabled: model.helperInstalled, destructive: true) { model.uninstallHelper() }
                            }
                        }
                        Text("About").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).padding(.top, 8)
                        section("Space Station for Mac") {
                            Text("Version \(appVersion) — open-source (MIT), unofficial. Ported to macOS by Uilton Lopes.")
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
                        section("Support the project") {
                            Text("Space Station for Mac is free and open source, built in my spare time by reverse-engineering the controller. If it saved you a Windows install, you can buy me a coffee.")
                                .font(.system(size: 12)).foregroundStyle(SS.n300)
                            Link(destination: URL(string: "https://buymeacoffee.com/uiltonlopes")!) {
                                HStack(spacing: 8) {
                                    Image(systemName: "cup.and.saucer.fill").font(.system(size: 13))
                                    Text("Buy me a coffee").font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(.black).padding(.horizontal, 14).frame(height: 32)
                                .background(Color(hex: 0xFFDD00), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            HStack(spacing: 6) {
                                Text("Made by").font(.system(size: 12)).foregroundStyle(SS.n300)
                                Link("Uilton Lopes", destination: URL(string: "https://github.com/uiltonlopes")!).font(.system(size: 12, weight: .semibold)).tint(SS.brand500)
                                Text("· Issues and pull requests are welcome on GitHub.").font(.system(size: 12)).foregroundStyle(SS.n300)
                            }
                        }
                    }
                    .padding(.horizontal, 28).padding(.vertical, 20).frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    @ViewBuilder private var firmware: some View {
        if let i = model.info {
            HStack(spacing: 14) {
                Text("Device Firmware").font(.system(size: 13)).foregroundStyle(SS.n300)
                Text(i.firmware).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                if let u = model.firmwareUpdate {
                    Text("Update available: \(u.version)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).frame(height: 22).background(SS.brand500, in: Capsule())
                } else if model.firmwareChecked {
                    Text("Up to date").font(.system(size: 12)).foregroundStyle(SS.green)
                }
            }
            if let u = model.firmwareUpdate {
                DarkCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("New firmware available, please update the firmware").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        if !u.info.isEmpty { ReleaseNote(text: u.info) }
                        Text("How to update today").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).padding(.top, 4)
                        Text("Flashing from the Mac is being validated step by step (see the dry run below). Until it ships, update with Flydigi Space Station on a Windows PC: connect the controller with the USB cable, open Settings → Firmware Update → Update. Keep it plugged in until it restarts.")
                            .font(.system(size: 12)).foregroundStyle(SS.n300)
                        HStack(spacing: 8) {
                            GhostButton(title: dryRunning ? "Verifying…" : "Download and verify (dry run)", icon: "checkmark.shield", enabled: !dryRunning) {
                                dryRunning = true
                                Task { await model.firmwareDryRun(); dryRunning = false }
                            }
                            PrimaryButton(title: "Update", icon: "arrow.up.circle", enabled: false) {}
                                .help("Flashing is not enabled yet")
                        }
                        if !model.firmwareReport.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(model.firmwareReport.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(SS.n300).textSelection(.enabled)
                                }
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(SS.n800, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                GhostButton(title: checking ? "Checking…" : "Check for updates", icon: "arrow.down.circle", enabled: !checking) {
                    checking = true; Task { await model.checkFirmware(); checking = false }
                }
                Text("Checked automatically when the controller connects.").font(.system(size: 12)).foregroundStyle(SS.n400)
            }
        } else {
            Text("Connect the controller to see its firmware.").font(.system(size: 13)).foregroundStyle(SS.n300)
        }
    }

    private func navGroup(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).padding(.vertical, 8)
            ForEach(items, id: \.self) { Text(LocalizedStringKey($0)).font(.system(size: 12)).foregroundStyle(SS.n300).padding(.vertical, 5) }
        }
        .padding(.bottom, 8)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            content()
        }
    }
}

/// Flydigi's release note: original (Chinese) plus an on-device translation into the app's language
/// (Apple's Translation framework; macOS asks once to download the language pair).
struct ReleaseNote: View {
    let text: String
    @State private var translated: String?
    @State private var config: TranslationSession.Configuration?

    private var targetIsChinese: Bool { Locale.current.language.languageCode?.identifier == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Flydigi's release note").font(.system(size: 12)).foregroundStyle(SS.n300)
            if let translated, !targetIsChinese {
                Text(verbatim: translated).font(.system(size: 12)).foregroundStyle(.white)
                Text(verbatim: text).font(.system(size: 11)).foregroundStyle(SS.n400)
            } else {
                Text(verbatim: text).font(.system(size: 12)).foregroundStyle(.white)
                if !targetIsChinese { Text("Translating…").font(.system(size: 11)).foregroundStyle(SS.n400) }
            }
        }
        .onAppear { if !targetIsChinese { config = TranslationSession.Configuration(source: Locale.Language(identifier: "zh-Hans"), target: Locale.current.language) } }
        .translationTask(config) { session in
            nonisolated(unsafe) let s = session
            let out: String? = await Task.detached { (try? await s.translate(text))?.targetText }.value
            translated = out
        }
    }
}

/// In-app language override (SS4 has the same setting). Stored in `AppleLanguages`; needs a relaunch.
enum AppLanguage: String, CaseIterable, Hashable {
    case system, en, ptBR = "pt-BR", zhHans = "zh-Hans"
    var title: String {
        switch self { case .system: "System"; case .en: "English"; case .ptBR: "Português (Brasil)"; case .zhHans: "简体中文" }
    }
    static var current: AppLanguage {
        guard let first = UserDefaults.standard.array(forKey: "AppleLanguages")?.first as? String, UserDefaults.standard.bool(forKey: "LanguageOverride") else { return .system }
        return AppLanguage(rawValue: first) ?? (first.hasPrefix("pt") ? .ptBR : first.hasPrefix("zh") ? .zhHans : first.hasPrefix("en") ? .en : .system)
    }
    func apply() {
        if self == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages"); UserDefaults.standard.set(false, forKey: "LanguageOverride") }
        else { UserDefaults.standard.set([rawValue], forKey: "AppleLanguages"); UserDefaults.standard.set(true, forKey: "LanguageOverride") }
    }
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let cfg = NSWorkspace.OpenConfiguration(); cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in DispatchQueue.main.async { NSApp.terminate(nil) } }
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
    @Environment(LiveInput.self) private var live
    @Environment(\.openWindow) private var openWindow

    private var connected: Bool { model.connection != .none }
    private var name: String { model.info.flatMap { DeviceCatalog.descriptor(for: $0.deviceId)?.name } ?? "Flydigi controller" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let img = Apex4Render.productImage(deviceId: model.info?.deviceId), connected {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 48, height: 34)
                } else {
                    Image(systemName: "gamecontroller").font(.system(size: 26)).foregroundStyle(.secondary).frame(width: 56, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(connected ? name : "No controller").font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if connected, let i = model.info {
                    let b = Battery(raw: i.batteryRaw, system: live.battery)
                    HStack(spacing: 4) {
                        Image(systemName: b.symbol).foregroundStyle(b.charging ? .green : .secondary)
                        Text(b.description).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if let u = model.firmwareUpdate {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("Firmware \(u.version) available").font(.caption.weight(.medium))
                    Spacer()
                    Button("Details") { openWindow(id: "main"); NSApp.activate() }.controlSize(.mini)
                }
                .foregroundStyle(SS.brand500).padding(.horizontal, 8).frame(height: 24)
                .background(SS.brand.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            if connected, let i = model.info {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { Text("Mode").foregroundStyle(.secondary); Text(model.connection == .xinput ? "XInput (Xbox)" : "DInput") }
                    GridRow { Text("Link").foregroundStyle(.secondary); Text(i.wired ? "USB cable" : "2.4 GHz receiver") }
                    GridRow { Text("Firmware").foregroundStyle(.secondary); Text(verbatim: i.firmware) }
                    if let l = model.led { GridRow { Text("Lighting").foregroundStyle(.secondary); Text(verbatim: "\(NSLocalizedString(lightingName(l.mode), comment: "")) · \(l.brightness) %") } }
                    GridRow { Text("Helper").foregroundStyle(.secondary); Text(model.helperInstalled ? "Installed" : "Not installed") }
                }
                .font(.caption)
            }
            if !profiles.slots.isEmpty {
                Picker("Profile", selection: Binding(get: { profiles.activeSlot }, set: { profiles.select(slot: $0) })) {
                    ForEach(profiles.slots) { s in Text("\(s.index + 1) · \(s.config.title.isEmpty ? "Unnamed" : s.config.title)").tag(s.index) }
                }
                .disabled(profiles.isDirty)
                if profiles.isDirty { Text("Unsaved changes in the app — apply or revert there first.").font(.caption).foregroundStyle(.orange) }
            }
            Divider()
            HStack(spacing: 8) {
                Button("Open") { openWindow(id: "main"); NSApp.activate() }
                Button(model.connection == .xinput ? "Switch to DInput" : "Switch to XInput") { Task { await model.switchMode() } }.disabled(!connected || model.busy)
                Button { Task { await model.refresh(); await profiles.loadAll() } } label: { Image(systemName: "arrow.trianglehead.2.clockwise") }.disabled(model.busy)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
            HStack(spacing: 6) {
                Text("Space Station for Mac · by Uilton Lopes").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Link("Buy me a coffee", destination: URL(string: "https://buymeacoffee.com/uiltonlopes")!).font(.caption2)
            }
        }
        .padding(12).frame(width: 340)
    }

    private var subtitle: String {
        guard connected else { return "Plug in over USB-C or power on with the receiver" }
        var parts: [String] = []
        if let d = profiles.draft { parts.append("Slot \(profiles.activeSlot + 1)\(d.title.isEmpty ? "" : " · \(d.title)")") }
        if model.busy { parts.append("working…") }
        return parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
    }
    private func lightingName(_ m: LEDConfig.Mode) -> String {
        switch m { case .off: "Off"; case .streamlined: "Streamlined"; case .breathing: "Breathing"; case .gradient: "Gradient"; case .feedback: "Feedback"; case .steady: "Steady" }
    }
}

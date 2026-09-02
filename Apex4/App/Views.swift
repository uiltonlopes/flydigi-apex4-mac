import SwiftUI
import UniformTypeIdentifiers
import FlydigiKit
import FlydigiHelperProtocol
import FlydigiTransport

// MARK: - Window shell (docs/design.md §2)

struct MainWindow: View {
    @Environment(ControllerModel.self) private var model
    @Environment(ProfileStore.self) private var profiles
    @State private var section: AppSection? = .status
    @State private var showInspector = false
    @State private var pendingSlot: UInt8?

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { s in
                Label(s.title, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { ControllerStatusFooter() }
        } detail: {
            ScrollView {
                switch section ?? .status {
                case .status: StatusPage()
                case .profiles: ProfilesPage(showInspector: $showInspector)
                case .sticks: ComingSoon(section: .sticks, note: "Dead zones, sensitivity curves and ForceAdapt modes are already decoded; the editor lands next.")
                case .motion: ComingSoon(section: .motion, note: "Gyro to stick mapping, curve and dead-zone compensation.")
                case .macros: ComingSoon(section: .macros, note: "Onboard macros: recorder and step editor.")
                case .lighting: LightingPage()
                case .screen: ScreenPage()
                }
            }
            .hardScrollEdge()
            .navigationTitle(section?.title ?? "Apex 4")
            .navigationSubtitle(subtitle)
            .inspector(isPresented: $showInspector) { InspectorHost(section: section ?? .status).inspectorColumnWidth(min: 260, ideal: 300) }
        }
        .toolbar { MainToolbar(showInspector: $showInspector, pendingSlot: $pendingSlot) }
        .confirmationDialog("Discard unsaved changes to this profile?", isPresented: Binding(get: { pendingSlot != nil }, set: { if !$0 { pendingSlot = nil } })) {
            Button("Discard and Switch", role: .destructive) { if let s = pendingSlot { profiles.revert(); profiles.select(slot: s) }; pendingSlot = nil }
            Button("Cancel", role: .cancel) { pendingSlot = nil }
        }
        .overlay(alignment: .bottom) {
            if let e = model.lastError ?? profiles.lastError {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.callout).padding(10)
                    .background(.background.secondary, in: .rect(cornerRadius: 10)).padding()
            }
        }
        .task(id: model.connection) { await profiles.loadAll() }
    }

    private var subtitle: String {
        guard model.connection != .none else { return "Not connected" }
        var parts = ["Slot \(profiles.activeSlot + 1)"]
        if let t = profiles.draft?.title, !t.isEmpty { parts.append("“\(t)”") }
        if profiles.isDirty { parts.append("unsaved changes") }
        return parts.joined(separator: " · ")
    }
}

struct MainToolbar: ToolbarContent {
    @Environment(ControllerModel.self) private var model
    @Environment(ProfileStore.self) private var profiles
    @Binding var showInspector: Bool
    @Binding var pendingSlot: UInt8?

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Profile slot", selection: Binding(get: { profiles.activeSlot }, set: { new in
                if profiles.isDirty { pendingSlot = new } else { profiles.select(slot: new) }
            })) {
                ForEach(0..<4, id: \.self) { i in Text("\(i + 1)").tag(UInt8(i)) }
            }
            .pickerStyle(.segmented).controlSize(.regular)
            .disabled(profiles.slots.isEmpty || profiles.busy)
            .help("On-board profile slot")
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Button { Task { await model.refresh(); await profiles.loadAll() } } label: { Label("Refresh", systemImage: "arrow.trianglehead.2.clockwise") }
                .disabled(model.busy || profiles.busy)
            Button { profiles.revert() } label: { Label("Revert", systemImage: "arrow.uturn.backward") }
                .disabled(!profiles.isDirty)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await profiles.apply() } } label: { Label("Apply to Controller", systemImage: "checkmark.circle.fill") }
                .prominentGlassButton()
                .disabled(!profiles.isDirty || profiles.busy)
                .help("Write this profile to the controller and save it (⌘S)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
        }
    }
}

struct ControllerStatusFooter: View {
    @Environment(ControllerModel.self) private var model
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.connection == .none ? "gamecontroller" : "gamecontroller.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.connection == .none ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            VStack(alignment: .leading, spacing: 1) {
                Text(model.connection == .none ? "Not connected" : (model.info.flatMap { DeviceCatalog.descriptor(for: $0.deviceId)?.name } ?? "Flydigi controller"))
                    .font(.callout.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.busy { ProgressView().controlSize(.mini) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }
    private var subtitle: String {
        switch model.connection {
        case .none: "Plug in or power on"
        case .dinput: model.info?.wired == false ? "2.4 GHz · DInput" : "USB · DInput"
        case .xinput: model.info?.wired == false ? "2.4 GHz · XInput" : "USB · XInput"
        }
    }
}

struct ComingSoon: View {
    let section: AppSection; let note: String
    var body: some View {
        ContentUnavailableView { Label(section.title, systemImage: section.symbol) } description: { Text(note) }
            .frame(maxWidth: .infinity, minHeight: 400)
    }
}

// MARK: - Status

struct StatusPage: View {
    @Environment(ControllerModel.self) private var model
    var body: some View {
        VStack(spacing: 16) {
            StageView(height: 260) {
                Apex4BodyShape().frame(width: 380, height: 280).offset(y: 20)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                PropertyCard(title: "Connection", systemImage: "cable.connector") {
                    switch model.connection {
                    case .none: Text("Not connected").foregroundStyle(.secondary)
                    case .dinput: Text("DInput · talking to the pad directly")
                    case .xinput: Text("XInput · via the privileged helper")
                    }
                }
                if let i = model.info {
                    PropertyCard(title: "Model", systemImage: "gamecontroller") {
                        Text(DeviceCatalog.descriptor(for: i.deviceId)?.name ?? "Flydigi controller (id \(i.deviceId))")
                        Text("Firmware \(i.firmware) · MAC \(i.mac)").font(.caption).foregroundStyle(.secondary)
                    }
                    PropertyCard(title: "Link", systemImage: i.wired ? "cable.connector" : "dot.radiowaves.left.and.right") {
                        Text(i.wired ? "USB cable" : "2.4 GHz receiver")
                        if !i.wired { Text("Screen uploads need the cable.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                PropertyCard(title: "USB mode", systemImage: "arrow.left.arrow.right") {
                    Button("Switch XInput ⇄ DInput") { Task { await model.switchMode() } }.disabled(model.connection == .none || model.busy)
                    Text("XInput is what games expect and what the screen needs; DInput lets the app talk without the helper.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom)
    }
}

// MARK: - Profiles & Buttons

struct ProfilesPage: View {
    @Environment(ProfileStore.self) private var profiles
    @Binding var showInspector: Bool

    var body: some View {
        VStack(spacing: 16) {
            StageView(height: 320) {
                ZStack {
                    Apex4BodyShape().frame(width: 460, height: 340).offset(y: 10)
                    HotspotLayer(showInspector: $showInspector).frame(width: 460, height: 340).offset(y: 10)
                }
            }
            if let draft = profiles.draft {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Profile name").font(.headline).foregroundStyle(.secondary)
                        TextField("Unnamed profile", text: Binding(get: { draft.title }, set: { profiles.draft?.title = String($0.prefix(10)) }))
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                        Spacer()
                        Text("\(remapped(draft)) remapped · \(draft.macros.count) macros").font(.caption).foregroundStyle(.secondary)
                    }
                    MappingTable(config: draft, selected: Binding(get: { profiles.selectedKey }, set: { profiles.selectedKey = $0; if $0 != nil { showInspector = true } }))
                        .frame(minHeight: 320)
                }
                .padding(.horizontal)
            } else {
                ContentUnavailableView("No profiles loaded", systemImage: "square.grid.2x2", description: Text("Connect the controller and press Refresh."))
                    .frame(minHeight: 200)
            }
        }
        .padding(.bottom)
    }

    private func remapped(_ c: GamepadConfig) -> Int { c.keys.values.filter { if case .identity = $0 { false } else { true } }.count }
}

/// Button hotspots floating over the stage — the one place with custom glass (docs/design.md §5).
struct HotspotLayer: View {
    @Environment(ProfileStore.self) private var profiles
    @Binding var showInspector: Bool

    var body: some View {
        GeometryReader { g in
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: 10) { chips(in: g.size) }
            } else {
                chips(in: g.size)
            }
        }
    }

    private func isChanged(_ k: ControllerKey) -> Bool {
        guard let m = profiles.draft?.keys[k] else { return false }
        if case .identity = m { return false }
        return true
    }

    @ViewBuilder private func chips(in size: CGSize) -> some View {
        ForEach(Apex4Render.hotspots) { h in
            let selected = profiles.selectedKey == h.key
            let changed = isChanged(h.key)
            Button {
                profiles.selectedKey = h.key; showInspector = true
            } label: {
                Text(h.label).font(.caption.weight(.semibold)).monospaced()
                    .frame(minWidth: 28, minHeight: 22).padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .floatingChip(tint: selected ? Color.accentColor : (changed ? Stage.glow.opacity(0.6) : nil))
            .position(x: h.x * size.width, y: h.y * size.height)
            .accessibilityLabel("\(h.key) button\(changed ? ", remapped" : "")")
        }
    }
}

struct MappingTable: View {
    let config: GamepadConfig
    @Binding var selected: ControllerKey?
    private var rows: [ControllerKey] { Apex4Render.hotspots.map(\.key) }
    var body: some View {
        Table(rows, selection: Binding<Set<UInt8>>(get: { selected.map { Set([$0.id]) } ?? [] }, set: { selected = $0.first.flatMap(ControllerKey.init(rawValue:)) })) {
            TableColumn("Button") { k in Text(String(describing: k)) }.width(min: 120)
            TableColumn("Does") { k in
                Text(describeMapping(config.keys[k] ?? .identity, for: k)).foregroundStyle(isDefault(config.keys[k]) ? .secondary : .primary)
            }
        }
        .cardShape()
    }
    private func isDefault(_ m: GamepadConfig.KeyMapping?) -> Bool { if case .identity? = m { return true }; return m == nil }
}

func describeMapping(_ m: GamepadConfig.KeyMapping, for k: ControllerKey) -> String {
    switch m {
    case .identity: "\(k) (default)"
    case .key(let t): "\(t)"
    case .turbo(let t, let en, let f): "Turbo → \(t), \(en == .press ? "hold" : "toggle"), \(f) Hz"
    case .macro: "Macro"
    case .keyboardMouse: "Keyboard/Mouse (Windows driver)"
    }
}

// MARK: - Inspector

struct InspectorHost: View {
    let section: AppSection
    @Environment(ProfileStore.self) private var profiles
    var body: some View {
        switch section {
        case .profiles:
            if let key = profiles.selectedKey, let draft = profiles.draft { ButtonInspector(key: key, mapping: draft.keys[key] ?? .identity) }
            else { ContentUnavailableView("Select a button", systemImage: "hand.tap", description: Text("Click a button on the controller or in the table.")) }
        default:
            ContentUnavailableView("Nothing to inspect", systemImage: "sidebar.trailing", description: Text("This page has no per-item details."))
        }
    }
}

struct ButtonInspector: View {
    let key: ControllerKey
    let mapping: GamepadConfig.KeyMapping
    @Environment(ProfileStore.self) private var profiles

    private enum Kind: Hashable { case `default`, remap, turbo, macro }
    private var kind: Kind { switch mapping { case .identity: .default; case .key: .remap; case .turbo: .turbo; case .macro, .keyboardMouse: .macro } }
    private var target: ControllerKey { switch mapping { case .key(let t), .turbo(let t, _, _): t; default: key } }
    private var turboHold: Bool { if case .turbo(_, let en, _) = mapping { return en == .press }; return true }
    private var turboFreq: Double { if case .turbo(_, _, let f) = mapping { return Double(f) }; return 10 }

    var body: some View {
        Form {
            Section(String(describing: key)) {
                Picker("Behaviour", selection: Binding(get: { kind }, set: { setKind($0) })) {
                    Text("Default").tag(Kind.default); Text("Another button").tag(Kind.remap); Text("Turbo").tag(Kind.turbo); Text("Macro").tag(Kind.macro)
                }
                .pickerStyle(.segmented)
                if kind == .remap || kind == .turbo {
                    Picker("Acts as", selection: Binding(get: { target }, set: { setTarget($0) })) {
                        ForEach(Apex4Render.hotspots.map(\.key), id: \.self) { Text(String(describing: $0)).tag($0) }
                    }
                }
                if kind == .turbo {
                    Picker("Activate", selection: Binding(get: { turboHold }, set: { profiles.setMapping(key, .turbo(target, enable: $0 ? .press : .click, frequency: UInt8(turboFreq))) })) {
                        Text("Hold for turbo").tag(true); Text("Press to toggle").tag(false)
                    }
                    LabeledContent("Rate") {
                        Slider(value: Binding(get: { turboFreq }, set: { profiles.setMapping(key, .turbo(target, enable: turboHold ? .press : .click, frequency: UInt8($0))) }), in: 1...30, step: 1)
                        Text("\(Int(turboFreq)) Hz").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                if kind == .macro { Text("Bound to the on-board macro for this button. The macro editor lands with the Macros page.").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped).controlSize(.small)
    }

    private func setKind(_ k: Kind) {
        switch k {
        case .default: profiles.setMapping(key, .identity)
        case .remap: profiles.setMapping(key, .key(target == key ? .a : target))
        case .turbo: profiles.setMapping(key, .turbo(target, enable: .press, frequency: 10))
        case .macro: profiles.setMapping(key, .macro)
        }
    }
    private func setTarget(_ t: ControllerKey) {
        if case .turbo(_, let en, let f) = mapping { profiles.setMapping(key, .turbo(t, enable: en, frequency: f)) } else { profiles.setMapping(key, t == key ? .identity : .key(t)) }
    }
}

// MARK: - Lighting

struct LightingPage: View {
    @Environment(ControllerModel.self) private var model
    @State private var colours: [Color] = [.blue, .red, .green]
    @State private var mode: LEDConfig.Mode = .gradient
    @State private var brightness: Double = 50
    @State private var speed: Double = 50

    var body: some View {
        VStack(spacing: 16) {
            StageView(height: 220) {
                VStack(spacing: 14) {
                    Apex4BodyShape().frame(width: 300, height: 220).offset(y: 30).opacity(0.7)
                    HStack(spacing: 6) { ForEach(colours.indices, id: \.self) { i in Capsule().fill(colours[i]).frame(width: 60, height: 8).shadow(color: colours[i].opacity(0.8), radius: 8) } }
                        .opacity(mode == .off ? 0.15 : brightness / 100 * 0.8 + 0.2)
                }
            }
            Form {
                if model.led == nil {
                    ContentUnavailableView("No lighting data", systemImage: "light.max", description: Text("Connect the controller."))
                } else {
                    Picker("Mode", selection: $mode) { ForEach(LEDConfig.Mode.allCases, id: \.self) { Text(name($0)).tag($0) } }
                    if mode != .off {
                        Section("Colours") {
                            ForEach(colours.indices, id: \.self) { i in ColorPicker("Colour \(i + 1)", selection: $colours[i], supportsOpacity: false) }
                            HStack {
                                Button("Add") { if colours.count < LEDConfig.unitsPerGroup { colours.append(.white) } }.disabled(mode == .steady || colours.count >= LEDConfig.unitsPerGroup)
                                Button("Remove") { if colours.count > 1 { colours.removeLast() } }.disabled(colours.count <= 1)
                            }
                        }
                        Slider(value: $brightness, in: 0...100, step: 1) { Text("Brightness \(Int(brightness))%") }
                        if mode != .steady { Slider(value: $speed, in: 0...100, step: 1) { Text("Speed \(Int(speed))%") } }
                    }
                    Button("Apply and save lighting") { Task { await apply() } }.prominentGlassButton().disabled(model.busy)
                }
            }
            .formStyle(.grouped).frame(maxWidth: 640)
        }
        .padding(.bottom)
        .onAppear(perform: load)
        .onChange(of: model.led) { _, _ in load() }
    }

    private func name(_ m: LEDConfig.Mode) -> String {
        switch m { case .off: "Off"; case .streamlined: "Streamlined"; case .breathing: "Breathing"; case .gradient: "Gradient"; case .feedback: "Feedback"; case .steady: "Steady" }
    }
    private func load() {
        guard let led = model.led else { return }
        mode = led.mode; brightness = Double(led.brightness); speed = Double(led.speed)
        let cs = led.colours(ofGroup: 0)
        if !cs.isEmpty { colours = cs.map { Color(red: Double($0.r) / 100, green: Double($0.g) / 100, blue: Double($0.b) / 100) } }
    }
    private func apply() async {
        guard var led = model.led else { return }
        let units = colours.map { c -> LEDConfig.Unit in
            let n = NSColor(c).usingColorSpace(.sRGB) ?? .white
            return LEDConfig.Unit(rgb8: UInt8(n.redComponent * 255), UInt8(n.greenComponent * 255), UInt8(n.blueComponent * 255))
        }
        switch mode { case .steady: led.setSteady(units.first ?? .off); case .off: led.mode = .off; default: led.setCycle(units, mode: mode) }
        led.brightness = UInt8(brightness); led.speed = UInt8(speed)
        await model.apply(led: led)
    }
}

// MARK: - Screen

struct ScreenPage: View {
    @Environment(ControllerModel.self) private var model
    @State private var file: URL?
    @State private var preview: [NSImage] = []
    @State private var frameIndex = 0
    @State private var importing = false
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            StageView(height: 260) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.black).frame(width: 480, height: 240)
                    if preview.isEmpty {
                        Text("Drop a GIF, PNG or JPEG\n160 × 80 · up to \(Screen.maxFrames) frames").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    } else {
                        Image(nsImage: preview[min(frameIndex, preview.count - 1)]).interpolation(.none).resizable().aspectRatio(2, contentMode: .fit).frame(width: 468)
                    }
                }
                .onReceive(timer) { _ in if preview.count > 1 { frameIndex = (frameIndex + 1) % preview.count } }
                .dropDestination(for: URL.self) { urls, _ in if let u = urls.first { load(u) }; return true }
            }
            Form {
                LabeledContent("Image") {
                    HStack { Button("Choose…") { importing = true }; if let file { Text(file.lastPathComponent).foregroundStyle(.secondary).lineLimit(1) } }
                }
                if !preview.isEmpty { LabeledContent("Frames", value: "\(preview.count)") }
                if let p = model.uploadProgress {
                    ProgressView(value: p) { Text("Uploading… \(Int(p * 100))% — about \(Int((1 - p) * Double(preview.count) * 3.5)) s left") }
                } else {
                    Button("Upload to controller") { if let file { Task { await model.uploadScreen(url: file) } } }
                        .prominentGlassButton().disabled(file == nil || model.busy || model.connection != .xinput)
                    if model.connection == .dinput { Text("Screen uploads only work in XInput mode — switch it in Status.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .formStyle(.grouped).frame(maxWidth: 640)
        }
        .padding(.bottom)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.gif, .png, .jpeg]) { if case let .success(u) = $0 { load(u) } }
    }

    private func load(_ url: URL) {
        file = url
        guard let frames = try? ImageLoader.frames(url: url) else { preview = []; return }
        preview = frames.map { lvgl in
            let w = Screen.width, h = Screen.height
            var rgba = [UInt8](repeating: 255, count: w * h * 4)
            for i in 0..<(w * h) {
                let px = UInt16(lvgl[4 + i * 2]) << 8 | UInt16(lvgl[5 + i * 2])
                rgba[i * 4] = UInt8((px >> 11) & 0x1F) << 3; rgba[i * 4 + 1] = UInt8((px >> 5) & 0x3F) << 2; rgba[i * 4 + 2] = UInt8(px & 0x1F) << 3
            }
            let provider = CGDataProvider(data: Data(rgba) as CFData)!
            let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                             provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        }
        frameIndex = 0
    }
}

// MARK: - Settings scene

struct SettingsView: View {
    @Environment(ControllerModel.self) private var model
    var body: some View {
        TabView {
            Form {
                Section("Privileged helper") {
                    LabeledContent("Status", value: model.helperInstalled ? "Installed" : "Not installed")
                    Text("Runs as root only while talking to the controller in XInput mode (Apple's Xbox driver owns the USB interface). Required for screen uploads.").font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Button("Install helper") { model.installHelper() }.disabled(model.helperInstalled)
                        Button("Remove helper", role: .destructive) { model.uninstallHelper() }.disabled(!model.helperInstalled)
                    }
                }
            }
            .formStyle(.grouped).tabItem { Label("Helper", systemImage: "lock.shield") }
            Form {
                Text("Open-source, MIT. Protocol reverse-engineered and documented at github.com/uiltonlopes/flydigi-apex4-mac. Not affiliated with Flydigi.").font(.footnote).foregroundStyle(.secondary)
            }
            .formStyle(.grouped).tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 300)
    }
}

// MARK: - Menu bar extra

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

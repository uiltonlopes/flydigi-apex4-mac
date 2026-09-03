import SwiftUI
import FlydigiKit
import FlydigiHelperProtocol
import FlydigiTransport

// MARK: - Routes

enum Route: Hashable { case deviceCenter, home, screen, adaptiveTrigger, settings }

enum HomeTab: String, CaseIterable, Identifiable {
    case common, button, joystick, gyro, trigger, macros
    var id: String { rawValue }
    var title: String {
        switch self { case .common: "Common"; case .button: "Button"; case .joystick: "Joystick"; case .gyro: "Gyro"; case .trigger: "Trigger"; case .macros: "Macros" }
    }
    var symbol: String {
        switch self { case .common: "slider.horizontal.3"; case .button: "circle.grid.2x2"; case .joystick: "dot.circle.and.hand.point.up.left.fill"; case .gyro: "gyroscope"; case .trigger: "rectangle.portrait.bottomhalf.filled"; case .macros: "list.number" }
    }
}

// MARK: - Window shell (SS4 layout: 248 pt sidebar + main)

struct MainWindow: View {
    @Environment(ControllerModel.self) private var model
    @Environment(ProfileStore.self) private var profiles
    @Environment(LiveInput.self) private var live
    @State private var route: Route = .deviceCenter
    @State private var tab: HomeTab = .common
    @State private var pendingSlot: UInt8?

    var body: some View {
        HStack(spacing: 0) {
            if route != .deviceCenter { Sidebar(route: $route) }
            ZStack {
                SS.n800
                switch route {
                case .deviceCenter: DeviceCenterPage(route: $route)
                case .home: HomeView(tab: $tab, pendingSlot: $pendingSlot)
                case .screen: ScreenPage { route = .home }
                case .adaptiveTrigger: AdaptiveTriggerPage { route = .home }
                case .settings: SettingsPage { route = .home }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SS.n800)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .confirmationDialog("Discard unsaved changes to this profile?", isPresented: Binding(get: { pendingSlot != nil }, set: { if !$0 { pendingSlot = nil } })) {
            Button("Discard and Switch", role: .destructive) { if let s = pendingSlot { profiles.revert(); profiles.select(slot: s) }; pendingSlot = nil }
            Button("Cancel", role: .cancel) { pendingSlot = nil }
        }
        .overlay(alignment: .bottom) {
            if let e = model.lastError ?? profiles.lastError {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(SS.n500, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: model.connection) {
            live.setRawMonitoring(model.connection == .dinput)
            profiles.setPadSlotWatch(model.connection == .dinput)
            await profiles.loadAll()
        }
        // The receiver can be there before the pad answers: load the profiles once it does.
        .onChange(of: model.info == nil) { _, isNil in if !isNil { Task { await profiles.loadAll() } } }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(ControllerModel.self) private var model
    @Environment(ProfileStore.self) private var profiles
    @Environment(LiveInput.self) private var live
    @Binding var route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title row on its own line under the traffic lights, aligned with the card; like SS4, it goes
            // back to the device center.
            Button { route = .deviceCenter } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(SS.n400)
                    Image(systemName: "gamecontroller.fill").font(.system(size: 13)).foregroundStyle(SS.brand500)
                    Text("Space Station for Mac").font(.system(size: 13, weight: .medium)).foregroundStyle(SS.n300).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).frame(height: 28).padding(.top, 34)

            deviceCard.padding(.horizontal, 12).padding(.top, 10)

            infoList.padding(.horizontal, 12).padding(.top, 14)

            Spacer()

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    RailButton(title: "Adaptive Trigger", icon: "slider.horizontal.below.square.and.square.filled", active: route == .adaptiveTrigger) { route = .adaptiveTrigger }
                    RailButton(title: "Screen", icon: "photo.tv", active: route == .screen) { route = .screen }
                }
                RailButton(title: "Settings", icon: "gearshape", active: route == .settings, wide: true) { route = .settings }
            }
            .padding(12)
        }
        .frame(width: SS.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(SS.n700)
    }

    private var connected: Bool { model.connection != .none }
    private var deviceName: String {
        if !model.nickname.isEmpty { return model.nickname }
        return model.info.flatMap { DeviceCatalog.descriptor(for: $0.deviceId)?.name } ?? "Flydigi Apex 4"
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("My Device").font(.system(size: 12)).foregroundStyle(SS.n300)
                Spacer()
                Button { Task { await model.refresh(); await profiles.loadAll() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)).foregroundStyle(SS.n400)
                        .frame(width: 18, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(model.busy).help("Refresh")
                if connected, let i = model.info {
                    Image(systemName: i.wired ? "cable.connector" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 11)).foregroundStyle(SS.n400)
                        .help(i.wired ? "USB cable" : "2.4 GHz receiver")
                    let b = Battery(raw: i.batteryRaw, system: live.battery)
                    Image(systemName: b.symbol).font(.system(size: 11)).foregroundStyle(b.charging ? SS.green : SS.n400)
                        .help(b.description)
                }
            }
            HStack(spacing: 8) {
                Circle().fill(model.awaitingPad ? SS.yellow : (connected ? SS.green : SS.n400)).frame(width: 7, height: 7)
                Text(model.awaitingPad ? "Waiting for controller" : (connected ? deviceName : "Not connected")).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Spacer()
            }
            if let u = model.firmwareUpdate {
                // Short label so it never truncates in the sidebar; the full story is in Settings.
                Button { route = .settings } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 12))
                        Text("Update to \(u.version)").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 26)
                    .background(SS.brand, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Firmware \(u.version) available — open Settings to see the release notes")
            }
        }
        .padding(12)
        .background(SS.n800, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(route == .home ? SS.brand500.opacity(0.7) : SS.n500))
        .contentShape(Rectangle())
        .onTapGesture { route = .home }
    }

    private var infoList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Mode").font(.system(size: 12)).foregroundStyle(SS.n400)
                Spacer()
                if connected {
                    // Click to switch; no chevron, the swap icon says it all.
                    Button { Task { await model.switchMode() } } label: {
                        HStack(spacing: 4) {
                            Text(model.connection == .xinput ? "XInput" : "DInput").font(.system(size: 12)).foregroundStyle(SS.n300)
                            Image(systemName: "arrow.left.arrow.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(SS.n400)
                        }
                        .padding(.horizontal, 6).frame(height: 20)
                        .background(SS.n600, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(model.busy)
                    .help(model.connection == .xinput ? "Switch to DInput mode" : "Switch to XInput mode")
                } else {
                    Text("—").font(.system(size: 12)).foregroundStyle(SS.n300)
                }
            }
            .frame(height: 26)
            row("Link", model.info.map { $0.wired ? "USB cable" : "2.4 GHz receiver" } ?? (model.looksLikeReceiver ? "2.4 GHz receiver" : "—"))
            row("Firmware", model.info.map { $0.firmware + (model.firmwareUpdate != nil ? "  ↑" : "") } ?? "—")
            if let i = model.info { let b = Battery(raw: i.batteryRaw, system: live.battery); if b.known { row("Battery", b.description) } }
            row("Helper", model.helperInstalled ? "Installed" : "Not installed")
            if let d = profiles.draft {
                row("Profile", "Slot \(profiles.activeSlot + 1)\(d.title.isEmpty ? "" : " · \(d.title)")")
            }
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(LocalizedStringKey(k)).font(.system(size: 12)).foregroundStyle(SS.n400)
            Spacer()
            Text(LocalizedStringKey(v)).font(.system(size: 12)).foregroundStyle(SS.n300).lineLimit(1)
        }
        .frame(height: 26)
    }
}

// MARK: - Home: hero + tabs

struct HomeView: View {
    @Environment(ControllerModel.self) private var model
    @Environment(ProfileStore.self) private var profiles
    @Binding var tab: HomeTab
    @Binding var pendingSlot: UInt8?

    var body: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                HeroView(pendingSlot: $pendingSlot) { key in
                    profiles.selectedKey = key
                    withAnimation(.easeOut(duration: 0.18)) { tab = .button }
                }
                .frame(height: max(300, min(460, g.size.height * 0.48)))

                TabBarView(selection: $tab, tabs: HomeTab.allCases.map { ($0, $0.title, $0.symbol) })

                if tab == .macros {
                    MacrosPage().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Group {
                            if profiles.draft == nil && tab != .common {
                                noProfile
                            } else {
                                switch tab {
                                case .common: CommonTab()
                                case .button: ButtonTab(tab: $tab)
                                case .joystick: JoystickTab()
                                case .gyro: GyroTab()
                                case .trigger: TriggerTab()
                                case .macros: EmptyView()
                                }
                            }
                        }
                        .padding(.horizontal, tab == .common ? 20 : 36).padding(.vertical, tab == .common ? 20 : 32)
                        .frame(maxWidth: tab == .common ? .infinity : 1100)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .background(SS.n800)
    }

    private var noProfile: some View {
        VStack(spacing: 10) {
            Image(systemName: "gamecontroller").font(.system(size: 28)).foregroundStyle(SS.n400)
            Text(model.connection == .none ? "Connect the controller to edit its profiles." : "Loading profiles…").font(.system(size: 13)).foregroundStyle(SS.n300)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

struct HeroView: View {
    @Environment(ControllerModel.self) private var model
    @Environment(ProfileStore.self) private var profiles
    @Environment(ProfileLibrary.self) private var library
    @Binding var pendingSlot: UInt8?
    let onSelect: (ControllerKey) -> Void
    @State private var renaming = false
    @State private var confirmReset = false
    @State private var showLibrary = false
    @State private var confirmNS = false

    var body: some View {
        GeometryReader { g in
            ZStack {
                SS.n900
                // Blue glow rising from the bottom, like SS4's `.equipe-light-bg`.
                Ellipse().fill(SS.brand.opacity(0.55)).frame(width: g.size.width * 0.9, height: g.size.height * 0.9)
                    .blur(radius: 90).offset(y: g.size.height * 0.55)
                ZStack {
                    Apex4Wireframe()
                    HeroHotspots(onSelect: onSelect).aspectRatio(Apex4Render.canvas, contentMode: .fit)
                }
                .frame(height: g.size.height * 0.86)
                .offset(y: g.size.height * 0.04)

                controls.padding(20)
            }
            .clipped()
        }
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 8) {
                Spacer()
                IconPill(icon: "arrow.trianglehead.2.clockwise", help: "Read everything again from the controller", enabled: !model.busy && !profiles.busy) {
                    Task { await model.refresh(); await profiles.loadAll() }
                }
                if profiles.isDirty {
                    IconPill(icon: "arrow.uturn.backward", help: "Revert unsaved changes (⌘⇧Z)") { profiles.revert() }
                    PrimaryButton(title: "Apply", icon: "checkmark", enabled: !profiles.busy) { Task { await profiles.apply() } }
                        .help("Write this profile to the controller and save it (⌘S)")
                }
                profileMenu
            }
            Spacer()
        }
    }

    private var profileMenu: some View {
        Menu {
            ForEach(profiles.slots) { s in
                Button {
                    if profiles.isDirty { pendingSlot = s.index } else { profiles.select(slot: s.index) }
                } label: {
                    let name = s.config.title.isEmpty ? "Slot \(s.index + 1)" : "\(s.index + 1) · \(s.config.title)"
                    if s.index == profiles.activeSlot { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Divider()
            Button("Rename profile…") { renaming = true }.disabled(profiles.draft == nil)
            Button("Restore default configuration…") { confirmReset = true }.disabled(profiles.draft == nil)
            Button("Apply to NS mode…") { confirmNS = true }.disabled(profiles.draft == nil || model.connection == .none)
            Divider()
            Button("Saved profiles…") { showLibrary = true }
        } label: {
            HStack(spacing: 8) {
                Text(profileTitle).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(SS.n300)
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(SS.n700.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SS.n500))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .confirmationDialog("Restore this profile to Flydigi's factory settings?", isPresented: $confirmReset) {
                Button("Restore defaults", role: .destructive) { profiles.resetToFactory() }
            } message: { Text("Mappings, sticks, triggers, gyro, vibration and macros go back to their defaults in the editor. Nothing is written to the controller until you Apply.") }
            .sheet(isPresented: $showLibrary) { ProfileLibrarySheet().environment(profiles).environment(library) }
            .confirmationDialog("Copy this profile to the controller's Nintendo Switch mode?", isPresented: $confirmNS) {
                Button("Apply to NS mode") { Task { await profiles.applyToSwitchMode() } }
            } message: { Text("The Apex 4 keeps a separate set of four profiles for Switch mode (slots 5–8 inside the controller). This copies the profile in the editor, and its lighting, into the matching Switch slot — keyboard/mouse mappings are dropped, as Space Station does.") }
        .disabled(profiles.slots.isEmpty)
        .popover(isPresented: $renaming, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Profile name (up to 10 characters)").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Unnamed", text: Binding(get: { profiles.draft?.title ?? "" }, set: { profiles.draft?.title = String($0.prefix(10)) }))
                    .textFieldStyle(.roundedBorder).frame(width: 220)
                    .onSubmit { renaming = false }
            }
            .padding(14)
        }
    }

    private var profileTitle: String {
        guard profiles.draft != nil else { return String(localized: "No profile") }
        let t = profiles.draft?.title ?? ""
        let base = t.isEmpty ? "Slot \(profiles.shownSlot + 1)" : t
        return profiles.temporarySlot != nil ? "\(base) · game" : base
    }
}

/// Key chips on the hero, SS4 geometry and look (dark fill, grey stroke; blue when selected).
struct HeroHotspots: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(LiveInput.self) private var live
    let onSelect: (ControllerKey) -> Void

    var body: some View {
        GeometryReader { g in
            let s = g.size.width / Apex4Render.canvas.width
            ZStack {
                ForEach(Apex4Render.stickWells.indices, id: \.self) { i in
                    let r = Apex4Render.stickWells[i]
                    StickWell()
                        .frame(width: r.width * s, height: r.height * s)
                        .position(x: r.midX * s, y: r.midY * s)
                }
                ForEach(Apex4Render.hotspots) { h in chip(h, scale: s) }
            }
        }
    }

    private func isChanged(_ k: ControllerKey) -> Bool {
        guard let m = profiles.draft?.keys[k] else { return false }
        if case .identity = m { return false }
        return true
    }

    private func chipShape(_ h: Hotspot, scale s: CGFloat) -> AnyShape {
        if let sil = KeySilhouette.shape(for: h.key) { return AnyShape(sil) }
        switch h.shape {
        case .circle: return AnyShape(Circle())
        case .roundRect: return AnyShape(Capsule())
        case .rect: return AnyShape(RoundedRectangle(cornerRadius: 6 * s, style: .continuous))
        }
    }

    private func chip(_ h: Hotspot, scale s: CGFloat) -> some View {
        let selected = profiles.selectedKey == h.key
        let changed = isChanged(h.key)
        let pressed = live.pressedKeys.contains(h.key)
        let isThumb = h.key == .thumbL || h.key == .thumbR
        let silhouette = KeySilhouette.shape(for: h.key) != nil
        // Silhouettes are drawn a little larger than the hit rect, like SS4's icons.
        let grow: CGFloat = silhouette ? 1.08 : 1
        let size = CGSize(width: h.rect.width * s * grow, height: h.rect.height * s * grow)
        let shape = chipShape(h, scale: s)
        let stroke: Color = selected ? SS.brand500 : (changed ? SS.brand.opacity(0.9) : SS.n400)
        let fill: Color = pressed ? SS.brand500.opacity(0.85) : (silhouette ? SS.n600 : SS.chipFill.opacity(0.95))
        return Button { if h.clickable { onSelect(h.key) } } label: {
            ZStack {
                if !isThumb {
                    shape.fill(fill)
                    shape.stroke(stroke, lineWidth: selected ? 2 : (silhouette ? 1.5 : 1))
                    if silhouette && !selected {
                        // SS4's faint vertical highlight on the outline.
                        shape.stroke(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.35), .white.opacity(0)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                    }
                } else if selected || pressed {
                    Circle().stroke(pressed ? SS.brand500 : SS.brand500, lineWidth: 2).frame(width: size.width, height: size.height)
                }
                Text(h.label)
                    .font(.system(size: max(8, min(12, size.height * (silhouette ? 0.3 : 0.42))), weight: .semibold, design: .rounded))
                    .foregroundStyle(h.clickable ? (isThumb ? SS.n300 : .white) : SS.n400)
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .offset(y: h.key == .m1 || h.key == .m2 ? size.height * 0.04 : 0)
            }
            .frame(width: size.width, height: size.height)
            .shadow(color: selected ? SS.brand500.opacity(0.7) : .clear, radius: 8)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(h.rotation))
        .position(x: h.center.x * s, y: h.center.y * s)
        .allowsHitTesting(h.clickable)
        .opacity(h.clickable ? 1 : 0.6)
        .accessibilityLabel("\(h.key) button\(changed ? ", remapped" : "")")
        .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

// MARK: - Common tab (Light + Vibration)

struct CommonTab: View {
    var body: some View {
        // Three equal cards filling the tab, like the Macros page.
        HStack(alignment: .top, spacing: 20) {
            DarkCard(fillHeight: true) { LightPanel() }
            DarkCard(fillHeight: true) { VibrationPanel() }
            DarkCard(fillHeight: true) { ControllerPanel() }
        }
        .fixedSize(horizontal: false, vertical: true)   // row height = tallest card; the others stretch to match
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Pad-level switches that live in Space Station's settings page; here they sit next to lighting and
/// vibration so everything about the controller itself is on one tab.
struct ControllerPanel: View {
    @Environment(ControllerModel.self) private var model
    private var mac: String { model.info?.mac ?? "" }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle("Controller", icon: "gamecontroller")
            Field("Sleep time") {
                DarkSelect(selection: Binding(get: { Int(model.sleepMinutes ?? 15) }, set: { v in Task { await model.setSleepTime(UInt8(v)) } }),
                           options: [(1, "1 min"), (5, "5 min"), (15, "15 min"), (60, "1 h"), (180, "3 h"), (0, "Never")], disabled: model.connection == .none || model.busy)
                Text("Idle time before the controller sleeps; Home wakes it.").font(.system(size: 11)).foregroundStyle(SS.n400)
            }
            Field("Fast swap") {
                SwitchRow(title: "SELECT + A / B / X / Y switches profiles", isOn: Binding(get: { UserDefaults.standard.bool(forKey: "quickSwitch.\(mac)") }, set: { on in Task { await model.setQuickSwitch(on) } }))
                    .disabled(model.connection == .none || model.busy)
            }
            Field("Turbo shortcut") {
                SwitchRow(title: "Turbo + button auto-fires that button", isOn: Binding(get: { UserDefaults.standard.bool(forKey: "turboSwitch.\(mac)") }, set: { on in Task { await model.setTurboSwitch(on) } }))
                    .disabled(model.connection == .none || model.busy)
                Text("Turbo + Turbo clears. The controller does not report these two switches back; shown is the last value set from this Mac.").font(.system(size: 11)).foregroundStyle(SS.n400)
            }
        }
        .task(id: model.connection) { await model.loadSleepTime() }
    }
}

struct LightPanel: View {
    @Environment(ControllerModel.self) private var model
    @State private var colours: [Color] = [.blue, .red, .green]
    @State private var mode: LEDConfig.Mode = .gradient
    @State private var brightness: Double = 50
    @State private var speed: Double = 50
    @State private var loaded = false
    @State private var pending: Task<Void, Never>?

    // Space Station offers exactly these for the Apex 4 (`GetDefaultLedConfigsByDevice`: no Flow, no Feedback on k2).
    private let modes: [(LEDConfig.Mode, String)] = [(.factoryDefault, "Default"), (.steady, "Steady"), (.breathing, "Breathing"), (.gradient, "Gradient"), (.off, "Off")]
    private var cycleDisabled: Bool { mode == .steady || mode == .off || mode == .factoryDefault }
    private var colourDisabled: Bool { mode == .off || mode == .factoryDefault }
    private var minColours: Int { mode == .gradient ? 2 : 1 }
    private var maxColours: Int { mode == .steady ? 1 : 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle("Light", icon: "lightbulb")
            if model.led == nil {
                Text(model.connection == .none ? "Connect the controller to edit its lighting." : "Reading lighting…").font(.system(size: 13)).foregroundStyle(SS.n300)
            } else {
                // Stacked so every control spans the column: select, colours, then the two sliders side by side.
                Field("Light mode") { DarkSelect(selection: $mode, options: modes) }
                Field("Color") { colourRow }
                HStack(alignment: .top, spacing: 20) {
                    Field("Brightness") { StepSlider(value: $brightness, range: 0...100) }.frame(maxWidth: .infinity)
                    Field("Cycle time") { StepSlider(value: $speed, range: 1...100) }.opacity(cycleDisabled ? 0.4 : 1).disabled(cycleDisabled).frame(maxWidth: .infinity)
                }
                if model.busy { HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Applying…").font(.system(size: 12)).foregroundStyle(SS.n300) } }
            }
        }
        .onAppear(perform: load)
        .onChange(of: model.led) { _, _ in load() }
        .onChange(of: mode) { _, m in
            // keep the colour list within what the mode accepts
            if m == .steady, colours.count > 1 { colours = [colours[0]] }
            if m == .gradient, colours.count < 2 { colours.append(.white) }
            if colours.count > 5 { colours = Array(colours.prefix(5)) }
            schedule()
        }
        .onChange(of: brightness) { _, _ in schedule() }
        .onChange(of: speed) { _, _ in schedule() }
        .onChange(of: colours) { _, _ in schedule() }
    }

    private var colourRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ForEach(colours.indices, id: \.self) { i in
                    ColourChip(colour: $colours[i], removable: colours.count > minColours && !colourDisabled) { colours.remove(at: i) }
                }
                if colours.count < maxColours {
                    Button { colours.append(.white) } label: {
                        Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(SS.n300)
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SS.n500, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(colourDisabled).help("Add a color")
                }
            }
            Text(mode == .steady ? "One color. Click the swatch to change it." : (mode == .gradient ? "2 to 5 colors. Click a swatch to change it; hover to remove." : "Up to 5 colors. Click a swatch to change it; hover to remove."))
                .font(.system(size: 11)).foregroundStyle(SS.n400)
        }
        .opacity(colourDisabled ? 0.4 : 1)
        .disabled(colourDisabled)
    }

    private func load() {
        guard let led = model.led else { return }
        loaded = false
        mode = led.mode; brightness = Double(led.brightness); speed = Double(led.speed)
        let cs = led.colours(ofGroup: 0)
        if !cs.isEmpty { colours = cs.map { Color(red: Double($0.r) / 100, green: Double($0.g) / 100, blue: Double($0.b) / 100) } }
        // The state changes above fire their onChange handlers on the next render pass; keep auto-apply
        // off until well after that, so loading a slot's lighting can never write it (or stale state) back.
        loadToken &+= 1
        let token = loadToken
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); if token == loadToken { loaded = true } }
    }
    @State private var loadToken = 0

    /// Debounced live apply (the pad saves to flash on every write, so wait for the slider to settle).
    private func schedule() {
        guard loaded, model.led != nil else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await apply()
        }
    }

    private func apply() async {
        guard var led = model.led else { return }
        let units = colours.map { c -> LEDConfig.Unit in
            let n = NSColor(c).usingColorSpace(.sRGB) ?? .white
            func pct(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(100, (v * 100).rounded()))) }
            return LEDConfig.Unit(r: pct(n.redComponent), g: pct(n.greenComponent), b: pct(n.blueComponent))
        }
        switch mode {
        case .steady: led.setSteady(units.first ?? .off)
        case .off: led.setOff()
        case .factoryDefault: led.setFactoryDefault()
        default: led.setCycle(units.isEmpty ? [.init(r: 100, g: 100, b: 100)] : units, mode: mode)
        }
        led.brightness = UInt8(brightness); led.speed = UInt8(speed)
        guard led.bytes != model.led?.bytes else { return }   // nothing changed: never rewrite what was just read
        loaded = false                                   // model.led will change back → don't re-trigger
        await model.apply(led: led)
        loaded = true
    }
}

struct VibrationPanel: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(ControllerModel.self) private var model

    private var vib: GamepadConfig.Vibration? { profiles.draft?.vibration }
    private func set(_ f: (inout GamepadConfig.Vibration) -> Void) { guard var v = vib else { return }; f(&v); profiles.draft?.vibration = v }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle("Vibration", icon: "waveform")
            if let vib {
                SwitchRow(title: "Grip vibration", isOn: Binding(get: { vib.enabled }, set: { v in set { $0.enabled = v } }))
                Field("Grip vibration intensity") {
                    StepSlider(value: Binding(get: { Double(max(vib.left.scale, vib.right.scale)) }, set: { v in set { $0.left.scale = UInt8(v); $0.right.scale = UInt8(v) } }),
                               range: 0...100, format: { "\(Int($0)) %" })
                }
                .opacity(vib.enabled ? 1 : 0.4).disabled(!vib.enabled)
                GhostButton(title: "Vibration test", icon: "waveform.path", enabled: model.connection == .xinput && !model.busy) { Task { await test() } }
                if model.connection == .dinput { Text("The test needs XInput mode.").font(.system(size: 12)).foregroundStyle(SS.n400) }
            } else {
                Text("Connect the controller to edit vibration.").font(.system(size: 13)).foregroundStyle(SS.n300)
            }
        }
    }
    private func test() async {
        guard #available(macOS 14.0, *) else { return }
        _ = await Task.detached { Result { try HelperClient.shared.motorTest(left: 200, right: 200); Thread.sleep(forTimeInterval: 0.5); try HelperClient.shared.motorTest(left: 0, right: 0) } }.value
    }
}

// MARK: - Button tab

struct ButtonTab: View {
    @Environment(ProfileStore.self) private var profiles
    @Binding var tab: HomeTab
    var body: some View {
        if let key = profiles.selectedKey, let mapping = profiles.draft?.keys[key] {
            KeyEditor(key: key, mapping: mapping, tab: $tab)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "hand.tap").font(.system(size: 18)).foregroundStyle(.white)
                Text("Click any button on the controller image above to modify its mapping.").font(.system(size: 13)).foregroundStyle(.white)
            }
            .padding(.horizontal, 20).frame(height: 44)
            .background(SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: .infinity)
        }
    }
}

struct KeyEditor: View {
    let key: ControllerKey
    let mapping: GamepadConfig.KeyMapping
    @Binding var tab: HomeTab
    @Environment(ProfileStore.self) private var profiles
    @Environment(LiveInput.self) private var live
    @Environment(ControllerModel.self) private var model
    @State private var armed = false          // waiting for a pad press (or a pick) to set the target
    @State private var capture: Task<Void, Never>?

    enum Kind: Hashable { case click, turbo, macro, special }
    private var kind: Kind { switch mapping { case .identity, .key: .click; case .turbo: .turbo; case .macro: .macro; case .keyboardMouse: .special } }
    private var target: ControllerKey { switch mapping { case .key(let t), .turbo(let t, _, _): t; default: key } }
    private var turboEnable: GamepadConfig.TurboEnable { if case .turbo(_, let en, _) = mapping { return en }; return .press }
    private var turboFreq: Double { if case .turbo(_, _, let f) = mapping { return Double(f) }; return 15 }

    var body: some View {
        VStack(spacing: 28) {
            PillSegmented(selection: Binding(get: { kind }, set: { setKind($0) }),
                          options: [(.click, "Click"), (.turbo, "Turbo"), (.macro, "Macro"), (.special, "Special")])
            switch kind {
            case .click: clickEditor
            case .turbo: turboEditor
            case .macro: macroEditor
            case .special: specialEditor
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: live.pressedKeys) { old, new in
            guard armed, let k = new.subtracting(old).first, Apex4Render.mappableKeys.contains(k) else { return }
            setTarget(k); armed = false
        }
        .onChange(of: armed) { _, on in
            capture?.cancel(); capture = nil
            // In XInput the system driver hides paddles/Fn, so borrow the pad through the helper for a few seconds.
            guard on, model.connection == .xinput, live.raw == nil else { return }
            capture = Task { @MainActor in
                let k = await model.captureKey(seconds: 6)
                guard !Task.isCancelled, armed else { return }
                if let k, Apex4Render.mappableKeys.contains(k) { setTarget(k) }
                armed = false
            }
        }
        .onChange(of: key) { _, _ in armed = false }
    }

    private var inputColumn: some View {
        VStack(spacing: 8) {
            KeyBadge(label: Apex4Render.shortLabel(key), size: 32)
            Text("Input").font(.system(size: 12)).foregroundStyle(SS.n300)
        }
    }

    private var outputBox: some View {
        Button { armed.toggle() } label: {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SS.n700)
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(armed ? SS.brand500 : SS.n500, lineWidth: armed ? 2 : 1)
                    KeyBadge(label: Apex4Render.shortLabel(target), size: 34, highlighted: target != key)
                }
                .frame(width: 240, height: 100)
                if armed {
                    Text(model.connection == .xinput ? "Listening on the controller for 6 s — press a button (paddles too), or pick one" : "Press the button on the controller or pick one")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white).multilineTextAlignment(.center)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(SS.brand500, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .offset(y: -6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $armed, arrowEdge: .bottom) { keyGrid }
    }

    private var keyGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Acts as").font(.system(size: 12)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 6), spacing: 8) {
                ForEach(Apex4Render.mappableKeys, id: \.self) { k in
                    Button { setTarget(k); armed = false } label: {
                        KeyBadge(label: Apex4Render.shortLabel(k), size: 36, highlighted: k == target)
                    }.buttonStyle(.plain).help(String(describing: k))
                }
            }
            GhostButton(title: "Reset to default") { setTarget(key); armed = false }
        }
        .padding(14)
    }

    private var clickEditor: some View {
        HStack(alignment: .center, spacing: 24) {
            inputColumn
            Text("=").font(.system(size: 18)).foregroundStyle(SS.n300)
            outputBox
        }
    }

    private var turboEditor: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Button").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                HStack(spacing: 20) { inputColumn; Text("=").foregroundStyle(SS.n300); outputBox }
            }
            Field("Activate method") {
                RadioList(selection: Binding(get: { turboEnable }, set: { en in profiles.setMapping(key, .turbo(target, enable: en, frequency: UInt8(turboFreq))) }),
                          options: [(.press, "Hold for turbo"), (.click, "Press to toggle turbo"), (.close, "Close")])
            }
            .frame(width: 220)
            Field("Shots per second") {
                StepSlider(value: Binding(get: { turboFreq }, set: { f in profiles.setMapping(key, .turbo(target, enable: turboEnable, frequency: UInt8(f))) }), range: 1...30)
            }
            .frame(width: 200)
        }
    }

    private var macroEditor: some View {
        let i = profiles.macroIndex(for: key)
        let m = i.flatMap { profiles.draft?.macros[safe: $0] }
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                profiles.addMacro(for: key)
                withAnimation(.easeOut(duration: 0.18)) { tab = .macros }
            } label: {
                HStack {
                    Text(m == nil ? "Click to set macro" : "Edit macro").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(SS.n300)
                        .frame(width: 20, height: 20).background(SS.n500, in: RoundedRectangle(cornerRadius: 4))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Preview").font(.system(size: 12)).foregroundStyle(SS.n300)
            HStack(spacing: 6) {
                if let m, !m.actions.isEmpty {
                    ForEach(Array(m.actions.prefix(12).enumerated()), id: \.offset) { _, a in
                        Text("\(a.event == .release ? "↑" : "↓")\(Apex4Render.shortLabel(ControllerKey(rawValue: a.key) ?? .none))")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white)
                            .padding(.horizontal, 6).frame(height: 22).background(SS.n500, in: Capsule())
                    }
                    if m.actions.count > 12 { Text("…").foregroundStyle(SS.n300) }
                } else {
                    Text("No steps yet").font(.system(size: 12)).foregroundStyle(SS.n400)
                }
            }
            .frame(height: 30).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .background(SS.n800, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(16)
        .frame(width: 320)
        .background(SS.n700, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SS.n500))
    }

    private var specialEditor: some View {
        VStack(spacing: 24) {
            Notice("Keyboard and mouse mapping needs a companion driver on the Mac. It arrives in a later release.")
            HStack(spacing: 24) {
                inputColumn
                Text("=").foregroundStyle(SS.n300)
                DarkSelect(selection: .constant(0), options: [(0, "Disabled")], width: 260, disabled: true)
            }
        }
    }

    private func setKind(_ k: Kind) {
        switch k {
        case .click: profiles.setMapping(key, target == key ? .identity : .key(target))
        case .turbo: profiles.setMapping(key, .turbo(target, enable: .press, frequency: 15))
        case .macro: if profiles.addMacro(for: key) == nil { profiles.setMapping(key, .macro) }
        case .special: profiles.setMapping(key, .keyboardMouse)
        }
    }
    private func setTarget(_ t: ControllerKey) {
        if case .turbo(_, let en, let f) = mapping { profiles.setMapping(key, .turbo(t, enable: en, frequency: f)) } else { profiles.setMapping(key, t == key ? .identity : .key(t)) }
    }
}

// MARK: - Joystick tab

struct JoystickTab: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(LiveInput.self) private var live
    @Environment(ControllerModel.self) private var model
    @State private var side: Side = .left
    @State private var calibrating = false
    @State private var circularity = false

    private var stick: GamepadConfig.Stick { profiles.draft![stick: side] }
    private func set(_ f: (inout GamepadConfig.Stick) -> Void) { var s = stick; f(&s); profiles.draft?[stick: side] = s }
    private var liveStick: LiveInput.Stick {
        if let r = live.raw { return side == .left ? .init(x: r.leftX, y: r.leftY) : .init(x: r.rightX, y: r.rightY) }
        return side == .left ? live.left : live.right
    }

    var body: some View {
        VStack(spacing: 28) {
            PillSegmented(selection: $side, options: [(.left, "Left joystick"), (.right, "Right joystick")])
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 20) {
                    Field("Sensitivity curve") {
                        // SS4's tabs: picking a preset also clears the dead zone and edge; touching anything makes it Custom.
                        PillSegmented(selection: Binding(get: { stick.curve }, set: { c in set { $0.applyCurvePreset(c) } }),
                                      options: [(.default, "Default"), (.quick, "Instant"), (.slow, "Delay"), (.custom, "Custom")], compact: true, fill: true)
                            .padding(2).frame(maxWidth: .infinity).background(SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    SensitivityCurve(p1: Binding(get: { (stick.p1x, stick.p1y) }, set: { v in set { $0.p1x = v.0; $0.p1y = v.1 } }),
                                     p2: Binding(get: { (stick.p2x, stick.p2y) }, set: { v in set { $0.p2x = v.0; $0.p2y = v.1 } }),
                                     deadZone: stick.deadZone, edge: stick.end, editable: stick.curve == .custom,
                                     live: live.connected ? Double(min(1, hypot(liveStick.x, liveStick.y))) : nil,
                                     onEdit: { set { $0.curve = .custom } }, size: 360)
                        .padding(.top, -6)
                    Text(stick.curve == .custom ? "Drag nodes to adjust curve" : (stick.curve == .default ? "Flydigi's factory curve: a slight lift near the centre (23 % output at 15 % travel), then linear. X: stick position, Y: output." : "Curve cannot be adjusted in current mode — X: stick position, Y: output"))
                        .font(.system(size: 11)).foregroundStyle(SS.n400)
                }
                .frame(width: 360)
                VStack(alignment: .leading, spacing: 20) {
                    Field("Center dead zone") {
                        StepSlider(value: Binding(get: { Double(stick.deadZone) }, set: { v in set { $0.deadZone = UInt8(v); $0.curve = .custom } }), range: 0...60, format: { "\(Int($0 / 127 * 100)) %" })
                    }
                    Field("Edge (active range)") {
                        StepSlider(value: Binding(get: { Double(stick.end) }, set: { v in set { $0.end = UInt8(v); $0.curve = .custom } }), range: 80...127, format: { "\(Int($0 / 127 * 100)) %" })
                    }
                }
                .frame(width: 300)
                VStack(spacing: 8) {
                    Text("Live").font(.system(size: 13)).foregroundStyle(SS.n300)
                    StickGauge(title: side == .left ? "Left stick" : "Right stick", stick: liveStick, config: stick)
                    if !live.connected { Text("No game controller visible to the system.").font(.system(size: 11)).foregroundStyle(SS.n400) }
                    if let hz = live.rawReportRate { Text("Report rate \(hz) Hz").font(.system(size: 11).monospacedDigit()).foregroundStyle(SS.n400) }
                    else if model.connection == .xinput { Text("Report rate: available in DInput mode").font(.system(size: 11)).foregroundStyle(SS.n400) }
                    GhostButton(title: "Circularity test…", icon: "circle.dotted", enabled: live.connected) { circularity = true }
                }
            }
            HDivider().padding(.vertical, 4)
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calibration").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text("Drifting centre or a stick that never reaches 100 %? Re-teach the controller its centre and limits.").font(.system(size: 12)).foregroundStyle(SS.n300)
                }
                Spacer()
                GhostButton(title: "Calibrate sticks…", icon: "scope", enabled: model.connection != .none) { calibrating = true }
            }
            .frame(maxWidth: 1000)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $calibrating) { CalibrationWizard().environment(model).environment(profiles).environment(live) }
        .sheet(isPresented: $circularity) { CircularityTestSheet(side: side).environment(live) }
    }
}

// MARK: - Gyro tab

struct GyroTab: View {
    @Environment(ProfileStore.self) private var profiles
    private var m: GamepadConfig.Motion { profiles.draft!.motion }
    private func set(_ f: (inout GamepadConfig.Motion) -> Void) { var v = m; f(&v); profiles.draft?.motion = v }

    var body: some View {
        VStack(spacing: 24) {
            Notice("Enabling gyro mapping will reduce controller polling rate")
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 20) {
                    Field("Mapping to") {
                        DarkSelect(selection: Binding(get: { m.mapType }, set: { v in set { $0.mapType = v } }),
                                   options: [(.off, "Close"), (.leftStick, "Left joystick (racing games)"), (.rightStick, "Right joystick (shooting games)")])
                    }
                    if m.mapType != .off {
                        Field("How to activate") {
                            DarkSelect(selection: Binding(get: { m.enableType }, set: { v in set { $0.enableType = v } }),
                                       options: [(.click, "Press to toggle"), (.press, "Hold to enable")])
                        }
                        Field("Activate key") {
                            DarkSelect(selection: Binding(get: { m.enableKey1 }, set: { v in set { $0.enableKey1 = v } }),
                                       options: [(UInt8(255), "Always on")] + Apex4Render.mappableKeys.map { ($0.rawValue, String(describing: $0)) })
                        }
                        if m.enableKey1 != 255 {
                            Field("Second key (optional)") {
                                DarkSelect(selection: Binding(get: { m.enableKey2 }, set: { v in set { $0.enableKey2 = v } }),
                                           options: [(UInt8(255), "None")] + Apex4Render.mappableKeys.map { ($0.rawValue, String(describing: $0)) })
                            }
                        }
                    }
                }
                .frame(width: 300)
                if m.mapType != .off {
                    VStack(alignment: .leading, spacing: 20) {
                        Field("Sensitivity") {
                            StepSlider(value: Binding(get: { Double(m.sensitivity) }, set: { v in set { $0.sensitivity = UInt8(v) } }), range: 1...100)
                        }
                        Field("Dead zone") {
                            StepSlider(value: Binding(get: { Double(m.deadZone) }, set: { v in set { $0.deadZone = UInt8(v) } }), range: 0...30)
                        }
                        Field("Use mode") {
                            PillSegmented(selection: Binding(get: { m.useMode }, set: { v in set { $0.useMode = v } }), options: [(.fps, "Shooting"), (.racer, "Racing")])
                        }
                    }
                    .frame(width: 300)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Trigger tab

struct TriggerTab: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(LiveInput.self) private var live
    @State private var side: Side = .left

    private var trig: GamepadConfig.Trigger { profiles.draft![trigger: side] }
    private func set(_ f: (inout GamepadConfig.Trigger) -> Void) { var t = trig; f(&t); profiles.draft?[trigger: side] = t }

    var body: some View {
        VStack(spacing: 28) {
            PillSegmented(selection: $side, options: [(.left, "Left trigger"), (.right, "Right trigger")])
            HStack(alignment: .top, spacing: 36) {
                ForceAdaptPanel(side: side).frame(width: 320).id(side)
                VStack(alignment: .leading, spacing: 20) {
                    Field("Start (dead zone)") {
                        StepSlider(value: Binding(get: { Double(trig.zero) }, set: { v in set { $0.zero = UInt8(v) } }), range: 0...120, format: { "\(Int($0 / 255 * 100)) %" })
                    }
                    Field("End (full press)") {
                        StepSlider(value: Binding(get: { Double(trig.end) }, set: { v in set { $0.end = UInt8(v) } }), range: 120...255, format: { "\(Int($0 / 255 * 100)) %" })
                    }
                }
                .frame(width: 300)
                VStack(spacing: 8) {
                    Text("Live").font(.system(size: 13)).foregroundStyle(SS.n300)
                    TriggerGauge(title: side == .left ? "LT" : "RT", value: live.raw.map { side == .left ? $0.leftTrigger : $0.rightTrigger } ?? (side == .left ? live.leftTrigger : live.rightTrigger), config: trig)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}


/// Battery: prefers what macOS reports through GameController (Apple's driver polls it), otherwise the
/// byte from the device-info reply decoded the way Space Station does (`HeartBeatCommandFactory`:
/// high nibble 1 → charging, low nibble = 0…5 bars; 0 right after connecting means "not read yet").
struct Battery: CustomStringConvertible {
    let raw: UInt8
    var system: LiveInput.BatteryInfo? = nil
    var charging: Bool { system?.charging == true || raw >> 4 == 1 }
    var known: Bool { (system?.level ?? 0) > 0 || raw != 0 }
    var percent: Int {
        if let s = system, s.level > 0 { return Int((s.level * 100).rounded()) }
        return min(5, Int(raw & 0xF)) * 20
    }
    var symbol: String {
        if charging { return "battery.100percent.bolt" }
        guard known else { return "battery.0percent" }
        switch percent { case 0..<13: return "battery.0percent"; case 13..<38: return "battery.25percent"; case 38..<63: return "battery.50percent"; case 63..<88: return "battery.75percent"; default: return "battery.100percent" }
    }
    var description: String { charging ? "Charging" : (known ? "\(percent) %" : "—") }
}


/// One lighting colour: a flat swatch that opens the system colour panel, with a small remove badge on hover.
struct ColourChip: View {
    @Binding var colour: Color
    var removable: Bool
    var onRemove: () -> Void
    @State private var hover = false
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(colour)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .frame(width: 36, height: 36)
                // The system well is hard to restyle, so it sits on top almost invisible and just takes the click.
                .overlay(ColorPicker("", selection: $colour, supportsOpacity: false).labelsHidden().opacity(0.02))
            if removable && hover {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 16, height: 16).background(SS.n900, in: Circle())
                        .overlay(Circle().strokeBorder(SS.n500, lineWidth: 1))
                }
                .buttonStyle(.plain).offset(x: 6, y: -6).help("Remove this color")
            }
        }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

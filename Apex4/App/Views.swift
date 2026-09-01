import SwiftUI
import UniformTypeIdentifiers
import FlydigiKit
import FlydigiTransport

// MARK: - Main window

struct ContentView: View {
    @Environment(ControllerModel.self) private var model

    var body: some View {
        TabView {
            StatusView().tabItem { Label("Status", systemImage: "info.circle") }
            LightingView().tabItem { Label("Lighting", systemImage: "light.max") }
            ScreenView().tabItem { Label("Screen", systemImage: "photo.on.rectangle") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .padding()
        .overlay(alignment: .bottom) {
            if let e = model.lastError {
                Text(e).font(.callout).foregroundStyle(.red).padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8)).padding()
            }
        }
        .toolbar {
            if model.busy { ProgressView().controlSize(.small) }
            Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        }
    }
}

struct StatusView: View {
    @Environment(ControllerModel.self) private var model
    var body: some View {
        Form {
            LabeledContent("Controller") {
                switch model.connection {
                case .none: Text("Not connected").foregroundStyle(.secondary)
                case .dinput: Text("Connected — DInput mode (direct)")
                case .xinput: Text("Connected — XInput mode (via helper)")
                }
            }
            if let i = model.info {
                LabeledContent("Model", value: i.deviceId == 84 ? "Flydigi Apex 4" : "Flydigi (id \(i.deviceId))")
                LabeledContent("Firmware", value: i.firmware)
                LabeledContent("Link", value: i.wired ? "USB cable" : "2.4 GHz receiver")
                LabeledContent("MAC", value: i.mac)
            }
            Section {
                Button("Switch USB mode (XInput ⇄ DInput)") { Task { await model.switchMode() } }
                    .disabled(model.connection == .none || model.busy)
                Text("XInput is what games expect and what the screen upload needs; DInput lets the app talk to the pad without the helper.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Lighting

struct LightingView: View {
    @Environment(ControllerModel.self) private var model
    @State private var draft: LEDConfig?
    @State private var colours: [Color] = [.blue, .red, .green]
    @State private var mode: LEDConfig.Mode = .gradient
    @State private var brightness: Double = 50
    @State private var speed: Double = 50

    var body: some View {
        Form {
            if model.led == nil {
                ContentUnavailableView("No lighting data", systemImage: "light.max", description: Text("Connect the controller."))
            } else {
                Picker("Mode", selection: $mode) {
                    ForEach(LEDConfig.Mode.allCases, id: \.self) { Text(name($0)).tag($0) }
                }
                if mode != .off {
                    Section("Colours") {
                        ForEach(colours.indices, id: \.self) { i in
                            ColorPicker("Colour \(i + 1)", selection: $colours[i], supportsOpacity: false)
                        }
                        HStack {
                            Button("Add") { if colours.count < LEDConfig.unitsPerGroup { colours.append(.white) } }.disabled(mode == .steady || colours.count >= LEDConfig.unitsPerGroup)
                            Button("Remove") { if colours.count > 1 { colours.removeLast() } }.disabled(colours.count <= 1)
                        }
                    }
                    Slider(value: $brightness, in: 0...100, step: 1) { Text("Brightness \(Int(brightness))%") }
                    if mode != .steady { Slider(value: $speed, in: 0...100, step: 1) { Text("Speed \(Int(speed))%") } }
                }
                Button("Apply and save to controller") { Task { await apply() } }
                    .keyboardShortcut(.defaultAction).disabled(model.busy)
            }
        }
        .formStyle(.grouped)
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
        switch mode {
        case .steady: led.setSteady(units.first ?? .off)
        case .off: led.mode = .off
        default: led.setCycle(units, mode: mode)
        }
        led.brightness = UInt8(brightness); led.speed = UInt8(speed)
        await model.apply(led: led)
    }
}

// MARK: - Screen

struct ScreenView: View {
    @Environment(ControllerModel.self) private var model
    @State private var file: URL?
    @State private var preview: [NSImage] = []
    @State private var frameIndex = 0
    @State private var importing = false
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.black)
                if preview.isEmpty {
                    Text("Drop a GIF, PNG or JPEG\n160 × 80 · up to \(Screen.maxFrames) frames").multilineTextAlignment(.center).foregroundStyle(.secondary)
                } else {
                    Image(nsImage: preview[min(frameIndex, preview.count - 1)]).interpolation(.none).resizable().aspectRatio(2, contentMode: .fit).padding(6)
                }
            }
            .frame(width: 480, height: 240)
            .onReceive(timer) { _ in if preview.count > 1 { frameIndex = (frameIndex + 1) % preview.count } }
            .dropDestination(for: URL.self) { urls, _ in if let u = urls.first { load(u) }; return true }

            HStack {
                Button("Choose image…") { importing = true }
                if let file { Text(file.lastPathComponent).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                if !preview.isEmpty { Text("\(preview.count) frame\(preview.count == 1 ? "" : "s")").foregroundStyle(.secondary) }
            }
            if let p = model.uploadProgress {
                ProgressView(value: p) { Text("Uploading… \(Int(p * 100))% — about \(Int((1 - p) * Double(preview.count) * 3.5)) s left") }
            } else {
                Button("Upload to controller") { if let file { Task { await model.uploadScreen(url: file) } } }
                    .disabled(file == nil || model.busy || model.connection != .xinput)
                    .keyboardShortcut(.defaultAction)
                if model.connection == .dinput {
                    Text("Screen uploads only work in XInput mode — switch it in Status.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.gif, .png, .jpeg]) { if case let .success(u) = $0 { load(u) } }
    }

    /// Shows exactly what the controller will display: our LVGL encoding decoded back to pixels.
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

// MARK: - Settings

struct SettingsView: View {
    @Environment(ControllerModel.self) private var model
    var body: some View {
        Form {
            Section("Privileged helper") {
                LabeledContent("Status", value: model.helperInstalled ? "Installed" : "Not installed")
                Text("The helper runs as root only while talking to the controller in XInput mode (Apple's Xbox driver owns the USB interface). It is required for screen uploads.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("Install helper") { model.installHelper() }.disabled(model.helperInstalled)
                    Button("Remove helper") { model.uninstallHelper() }.disabled(!model.helperInstalled)
                }
            }
            Section("About") {
                Text("Open-source, MIT. Protocol reverse-engineered and documented at github.com/uiltonlopes/flydigi-apex4-mac. Not affiliated with Flydigi.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @Environment(ControllerModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        switch model.connection {
        case .none: Text("Apex 4 not connected")
        case .dinput: Text("Apex 4 · DInput")
        case .xinput: Text("Apex 4 · XInput")
        }
        if let l = model.led { Text("Lighting: \(String(describing: l.mode)) · \(l.brightness)%") }
        Divider()
        Button("Open Apex 4…") { openWindow(id: "main"); NSApp.activate() }
        Button("Refresh") { Task { await model.refresh() } }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

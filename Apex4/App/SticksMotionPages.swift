import SwiftUI
import FlydigiKit
import FlydigiTransport
import FlydigiHelperProtocol

// MARK: - Sticks & Triggers

struct SticksPage: View {
    @Environment(ControllerModel.self) private var model
    @Environment(ProfileStore.self) private var profiles
    @Environment(LiveInput.self) private var live

    var body: some View {
        VStack(spacing: 16) {
            StageView(height: 240) {
                HStack(spacing: 40) {
                    StickGauge(title: "Left stick", stick: live.left, config: profiles.draft?.leftStick)
                    TriggerGauge(title: "LT", value: live.leftTrigger, config: profiles.draft?.leftTrigger)
                    TriggerGauge(title: "RT", value: live.rightTrigger, config: profiles.draft?.rightTrigger)
                    StickGauge(title: "Right stick", stick: live.right, config: profiles.draft?.rightStick)
                }
                .padding(.horizontal, 24)
            }
            if profiles.draft != nil {
                Form {
                    Section("Left stick") { StickForm(side: .left) }
                    Section("Right stick") { StickForm(side: .right) }
                    Section("Left trigger") { TriggerForm(side: .left) }
                    Section("Right trigger") { TriggerForm(side: .right) }
                    Section("Grip vibration") { VibrationForm() }
                }
                .formStyle(.grouped).frame(maxWidth: 720)
                if !live.connected {
                    Text("Live readout appears when the system sees the pad as a game controller (both USB modes).").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("No profile loaded", systemImage: "dial.medium", description: Text("Connect the controller and press Refresh.")).frame(minHeight: 200)
            }
        }
        .padding(.bottom)
    }
}

enum Side { case left, right }

private extension GamepadConfig {
    subscript(stick s: Side) -> Stick { get { s == .left ? leftStick : rightStick } set { if s == .left { leftStick = newValue } else { rightStick = newValue } } }
    subscript(trigger s: Side) -> Trigger { get { s == .left ? leftTrigger : rightTrigger } set { if s == .left { leftTrigger = newValue } else { rightTrigger = newValue } } }
}

struct StickGauge: View {
    let title: String; let stick: LiveInput.Stick; let config: GamepadConfig.Stick?
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                if let c = config {
                    Circle().stroke(Stage.glow.opacity(0.7), lineWidth: 1).scaleEffect(CGFloat(c.deadZone) / 127)           // centre dead zone
                    Circle().stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3])).scaleEffect(CGFloat(c.end) / 127) // active range
                }
                Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                    .offset(x: CGFloat(stick.x) * 60, y: -CGFloat(stick.y) * 60)
                    .shadow(color: Color.accentColor.opacity(0.8), radius: 6)
            }
            .frame(width: 130, height: 130)
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.7))
            Text(String(format: "%+.2f  %+.2f", stick.x, stick.y)).font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
        }
    }
}

struct TriggerGauge: View {
    let title: String; let value: Float; let config: GamepadConfig.Trigger?
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.18), lineWidth: 1)
                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.85)).frame(height: max(2, CGFloat(value) * 130))
                    .shadow(color: Color.accentColor.opacity(0.6), radius: 6)
            }
            .frame(width: 34, height: 130)
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.7))
            Text(String(format: "%3.0f %%", value * 100)).font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
        }
    }
}

struct StickForm: View {
    let side: Side
    @Environment(ProfileStore.self) private var profiles
    private var stick: GamepadConfig.Stick { profiles.draft![stick: side] }
    private func set(_ f: (inout GamepadConfig.Stick) -> Void) { var s = stick; f(&s); profiles.draft?[stick: side] = s }

    var body: some View {
        Picker("Sensitivity curve", selection: Binding(get: { stick.curve }, set: { v in set { $0.curve = v } })) {
            Text("Default").tag(GamepadConfig.Stick.Curve.default); Text("Quick").tag(GamepadConfig.Stick.Curve.quick)
            Text("Slow").tag(GamepadConfig.Stick.Curve.slow); Text("Custom").tag(GamepadConfig.Stick.Curve.custom)
        }.pickerStyle(.segmented)
        PercentSlider("Center dead zone", value: Binding(get: { stick.deadZone }, set: { v in set { $0.deadZone = v } }), range: 0...60)
        PercentSlider("Edge (active range)", value: Binding(get: { stick.end }, set: { v in set { $0.end = v } }), range: 80...127)
        if stick.curve == .custom {
            CurveEditor(p1: Binding(get: { (stick.p1x, stick.p1y) }, set: { v in set { $0.p1x = v.0; $0.p1y = v.1 } }),
                        p2: Binding(get: { (stick.p2x, stick.p2y) }, set: { v in set { $0.p2x = v.0; $0.p2y = v.1 } }))
        } else {
            Text("Drag the curve's points in Custom mode.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TriggerForm: View {
    let side: Side
    @Environment(ProfileStore.self) private var profiles
    @Environment(ControllerModel.self) private var model
    private var trig: GamepadConfig.Trigger { profiles.draft![trigger: side] }
    private func set(_ f: (inout GamepadConfig.Trigger) -> Void) { var t = trig; f(&t); profiles.draft?[trigger: side] = t }

    var body: some View {
        PercentSlider("Start (zero)", value: Binding(get: { trig.zero }, set: { v in set { $0.zero = v } }), range: 0...120, max: 255)
        PercentSlider("End", value: Binding(get: { trig.end }, set: { v in set { $0.end = v } }), range: 120...255, max: 255)
        ForceAdaptForm(side: side)
    }
}

/// ForceAdapt (adaptive trigger resistance). Live preview goes straight to the pad; the chosen mode is
/// also stored in the profile blob (type + parameters, layout per SS4 — parameter mapping partly inferred).
struct ForceAdaptForm: View {
    let side: Side
    @Environment(ProfileStore.self) private var profiles
    @Environment(ControllerModel.self) private var model
    @State private var mode: Int = 0            // 0 normal 1 race 2 sniper 3 recoil 4 lock 5 vibration
    @State private var stroke: Double = 50
    @State private var strength: Double = 8
    @State private var pressure: Double = 5
    @State private var frequency: Double = 5
    @State private var matchStroke = true
    @State private var previewing = false

    private var trig: GamepadConfig.Trigger { profiles.draft![trigger: side] }

    var body: some View {
        Picker("ForceAdapt", selection: $mode) {
            Text("Normal").tag(0); Text("Race").tag(1); Text("Sniper").tag(2); Text("Recoil").tag(3); Text("Lock").tag(4); Text("Vibration").tag(5)
        }
        .onAppear { mode = Int(trig.adapterType); load() }
        if mode != 0 {
            LabeledContent("Stroke") { Slider(value: $stroke, in: 10...100, step: 1); Text("\(Int(stroke))").monospacedDigit().frame(width: 36, alignment: .trailing) }
            if mode == 1 || mode == 2 || mode == 3 || mode == 4 || mode == 5 {
                LabeledContent(mode == 1 ? "Resistance" : "Strength") { Slider(value: $strength, in: 1...10, step: 1); Text("\(Int(strength))").monospacedDigit().frame(width: 36, alignment: .trailing) }
            }
            if mode == 2 || mode == 5 {
                LabeledContent("Pressure level") { Slider(value: $pressure, in: 1...10, step: 1); Text("\(Int(pressure))").monospacedDigit().frame(width: 36, alignment: .trailing) }
                LabeledContent("Frequency") { Slider(value: $frequency, in: 1...10, step: 1); Text("\(Int(frequency))").monospacedDigit().frame(width: 36, alignment: .trailing) }
            }
            Toggle("Match stroke", isOn: $matchStroke)
        }
        HStack {
            Button(previewing ? "Stop preview" : "Preview on controller") { Task { await preview(!previewing) } }
                .disabled(model.connection != .xinput || model.busy)
            Button("Keep in profile") { store() }.disabled(mode == Int(trig.adapterType) && mode == 0)
            Spacer()
            if model.connection != .xinput { Text("Preview needs XInput mode.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var liveParams: [UInt8] {
        let s = UInt8(stroke), st = UInt8(strength), p = UInt8(pressure), f = UInt8(frequency), m: UInt8 = matchStroke ? 1 : 0
        switch mode {
        case 1: return [1, s, st, m]
        case 2: return [2, s, p, st, f, m]
        case 3: return [3, s, s / 2, st, 0, m]
        case 4: return [4, s, st, m]
        case 5: return [5, s, p, st, f, m]
        default: return [0]
        }
    }

    private func load() {
        let p = trig.adapterParams
        guard p.count >= 20, trig.adapterType != 0 else { return }
        stroke = Double(max(10, p[10])); strength = Double(max(1, p[11])); pressure = Double(max(1, p[12])); frequency = Double(max(1, p[13]))
    }

    /// Persist into the blob following SS4's `ParseTriggerConfigToArray` (type, bind type, filter, scale, bind params, mixed border, params).
    private func store() {
        var t = trig
        var params = [UInt8](repeating: 0xFF, count: 20)
        params[0] = UInt8(mode); params[1] = mode == 5 ? 2 : 0
        params[2] = t.adapterParams.count >= 20 ? t.adapterParams[2] : 0xFF   // bind filter (untouched)
        params[3] = t.adapterParams.count >= 20 ? t.adapterParams[3] : 0xFF   // bind scale (untouched)
        let live = Array(liveParams.dropFirst())                               // mode-specific values, inferred to be the `Param` list
        for (i, v) in live.enumerated() where i < 10 { params[10 + i] = v }
        t.adapterType = UInt8(mode); t.adapterParams = params
        t.kind = mode == 0 ? .normal : .adapter
        profiles.draft?[trigger: side] = t
    }

    private func preview(_ on: Bool) async {
        previewing = on
        guard #available(macOS 14.0, *) else { return }
        let params = on ? liveParams : [0]
        let sideByte: UInt8 = side == .left ? 1 : 2
        _ = await Task.detached { Result { try HelperClient.shared.setForceTrigger(side: sideByte, params: params) } }.value
    }
}

struct VibrationForm: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(ControllerModel.self) private var model
    private var vib: GamepadConfig.Vibration { profiles.draft!.vibration }
    private func set(_ f: (inout GamepadConfig.Vibration) -> Void) { var v = vib; f(&v); profiles.draft?.vibration = v }

    var body: some View {
        Toggle("Grip vibration", isOn: Binding(get: { vib.enabled }, set: { v in set { $0.enabled = v } }))
        if vib.enabled {
            motor("Left motor", Binding(get: { vib.left }, set: { v in set { $0.left = v } }))
            motor("Right motor", Binding(get: { vib.right }, set: { v in set { $0.right = v } }))
        }
        HStack {
            Button("Test motors") { Task { await test() } }.disabled(model.connection == .none || model.busy)
            Text("50 % intensity ≈ Xbox feel.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func motor(_ title: String, _ m: Binding<GamepadConfig.Vibration.Motor>) -> some View {
        Toggle(title, isOn: m.enabled)
        if m.wrappedValue.enabled {
            PercentSlider("\(title) · intensity", value: m.scale, range: 0...100, max: 100)
            PercentSlider("\(title) · minimum", value: m.min, range: 0...200, max: 255)
            PercentSlider("\(title) · maximum", value: m.max, range: 60...255, max: 255)
        }
    }
    private func test() async {
        guard #available(macOS 14.0, *) else { return }
        _ = await Task.detached { Result { try HelperClient.shared.motorTest(left: 200, right: 200); Thread.sleep(forTimeInterval: 0.5); try HelperClient.shared.motorTest(left: 0, right: 0) } }.value
    }
}

/// Slider over a UInt8 field shown as a percentage of `max`.
struct PercentSlider: View {
    let title: String
    @Binding var value: UInt8
    let range: ClosedRange<Double>
    var max: Double = 127
    init(_ title: String, value: Binding<UInt8>, range: ClosedRange<Double>, max: Double = 127) { self.title = title; _value = value; self.range = range; self.max = max }
    var body: some View {
        LabeledContent(title) {
            Slider(value: Binding(get: { Double(value) }, set: { value = UInt8($0) }), in: range, step: 1)
            Text("\(Int(Double(value) / max * 100)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}

/// Two-point response curve editor (x = physical position, y = output), 0…127 both axes.
struct CurveEditor: View {
    @Binding var p1: (UInt8, UInt8)
    @Binding var p2: (UInt8, UInt8)
    var body: some View {
        GeometryReader { g in
            let s = g.size
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: s.height)); p.addLine(to: pt(p1, s)); p.addLine(to: pt(p2, s)); p.addLine(to: CGPoint(x: s.width, y: 0))
                }.stroke(Color.accentColor, lineWidth: 2)
                Path { p in p.move(to: CGPoint(x: 0, y: s.height)); p.addLine(to: CGPoint(x: s.width, y: 0)) }.stroke(.separator, style: StrokeStyle(lineWidth: 1, dash: [4]))
                handle(pt(p1, s)) { p1 = clamp($0, s) }
                handle(pt(p2, s)) { p2 = clamp($0, s) }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 8))
        }
        .frame(height: 160)
        .accessibilityLabel("Sensitivity curve; two draggable points")
    }
    private func pt(_ p: (UInt8, UInt8), _ s: CGSize) -> CGPoint { CGPoint(x: CGFloat(p.0) / 127 * s.width, y: s.height - CGFloat(p.1) / 127 * s.height) }
    private func clamp(_ p: CGPoint, _ s: CGSize) -> (UInt8, UInt8) {
        (UInt8(Swift.max(0, Swift.min(127, p.x / s.width * 127))), UInt8(Swift.max(0, Swift.min(127, (s.height - p.y) / s.height * 127))))
    }
    private func handle(_ at: CGPoint, _ move: @escaping (CGPoint) -> Void) -> some View {
        Circle().fill(Color.accentColor).frame(width: 14, height: 14).position(at)
            .gesture(DragGesture(minimumDistance: 0).onChanged { move($0.location) })
    }
}

// MARK: - Motion

struct MotionPage: View {
    @Environment(ProfileStore.self) private var profiles
    var body: some View {
        VStack(spacing: 16) {
            StageView(height: 160) {
                Label("Gyro", systemImage: "gyroscope").font(.title2).foregroundStyle(.white.opacity(0.8))
            }
            if let m = profiles.draft?.motion {
                Form {
                    Picker("Map gyro to", selection: Binding(get: { m.mapType }, set: { v in profiles.draft?.motion.mapType = v })) {
                        Text("Off").tag(GamepadConfig.Motion.MapType.off)
                        Text("Left stick (racing)").tag(GamepadConfig.Motion.MapType.leftStick)
                        Text("Right stick (shooting)").tag(GamepadConfig.Motion.MapType.rightStick)
                    }
                    if m.mapType != .off {
                        Picker("Use mode", selection: Binding(get: { m.useMode }, set: { v in profiles.draft?.motion.useMode = v })) {
                            Text("FPS").tag(GamepadConfig.Motion.UseMode.fps); Text("Racing").tag(GamepadConfig.Motion.UseMode.racer)
                        }.pickerStyle(.segmented)
                        Picker("Enable with", selection: Binding(get: { m.enableKey1 }, set: { v in profiles.draft?.motion.enableKey1 = v })) {
                            Text("Always").tag(UInt8(255))
                            ForEach(Apex4Render.hotspots) { h in Text(String(describing: h.key)).tag(h.key.rawValue) }
                        }
                        if m.enableKey1 != 255 {
                            Picker("Enable type", selection: Binding(get: { m.enableType }, set: { v in profiles.draft?.motion.enableType = v })) {
                                Text("Toggle on click").tag(GamepadConfig.Motion.EnableType.click); Text("While held").tag(GamepadConfig.Motion.EnableType.press)
                            }.pickerStyle(.segmented)
                        }
                        PercentSlider("Dead zone", value: Binding(get: { m.deadZone }, set: { v in profiles.draft?.motion.deadZone = v }), range: 0...30, max: 127)
                        PercentSlider("Sensitivity", value: Binding(get: { m.sensitivity }, set: { v in profiles.draft?.motion.sensitivity = v }), range: 1...100, max: 100)
                        Text("Enabling gyro mapping reduces the controller's polling rate.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped).frame(maxWidth: 640)
            } else {
                ContentUnavailableView("No profile loaded", systemImage: "gyroscope").frame(minHeight: 200)
            }
        }
        .padding(.bottom)
    }
}

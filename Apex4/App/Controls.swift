// Shared controls for the Joystick / Trigger tabs: live gauges, curve editor, ForceAdapt panel.

import SwiftUI
import FlydigiKit
import FlydigiTransport
import FlydigiHelperProtocol

enum Side: Hashable { case left, right }

extension GamepadConfig {
    subscript(stick s: Side) -> Stick { get { s == .left ? leftStick : rightStick } set { if s == .left { leftStick = newValue } else { rightStick = newValue } } }
    subscript(trigger s: Side) -> Trigger { get { s == .left ? leftTrigger : rightTrigger } set { if s == .left { leftTrigger = newValue } else { rightTrigger = newValue } } }
}

struct StickGauge: View {
    let title: String; let stick: LiveInput.Stick; let config: GamepadConfig.Stick?
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(SS.n700)
                Circle().stroke(SS.n500, lineWidth: 1)
                if let c = config {
                    Circle().stroke(SS.brand500.opacity(0.7), lineWidth: 1).scaleEffect(CGFloat(c.deadZone) / 127)
                    Circle().stroke(SS.n400, style: StrokeStyle(lineWidth: 1, dash: [3])).scaleEffect(CGFloat(c.end) / 127)
                }
                Circle().fill(SS.brand500).frame(width: 12, height: 12)
                    .offset(x: CGFloat(stick.x) * 60, y: -CGFloat(stick.y) * 60)
                    .shadow(color: SS.brand500.opacity(0.8), radius: 6)
            }
            .frame(width: 130, height: 130)
            Text(title).font(.system(size: 12)).foregroundStyle(SS.n300)
            Text(String(format: "%+.2f  %+.2f", stick.x, stick.y)).font(.system(size: 11).monospacedDigit()).foregroundStyle(SS.n400)
        }
    }
}

struct TriggerGauge: View {
    let title: String; let value: Float; let config: GamepadConfig.Trigger?
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6).fill(SS.n700)
                RoundedRectangle(cornerRadius: 6).stroke(SS.n500, lineWidth: 1)
                RoundedRectangle(cornerRadius: 6).fill(SS.brand500.opacity(0.9)).frame(height: max(2, CGFloat(value) * 130))
                    .shadow(color: SS.brand500.opacity(0.6), radius: 6)
            }
            .frame(width: 34, height: 130)
            Text(title).font(.system(size: 12)).foregroundStyle(SS.n300)
            Text(String(format: "%3.0f %%", value * 100)).font(.system(size: 11).monospacedDigit()).foregroundStyle(SS.n400)
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
                }.stroke(SS.brand500, lineWidth: 2)
                Path { p in p.move(to: CGPoint(x: 0, y: s.height)); p.addLine(to: CGPoint(x: s.width, y: 0)) }.stroke(SS.n500, style: StrokeStyle(lineWidth: 1, dash: [4]))
                handle(pt(p1, s)) { p1 = clamp($0, s) }
                handle(pt(p2, s)) { p2 = clamp($0, s) }
            }
            .background(SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(height: 160)
        .accessibilityLabel("Sensitivity curve; two draggable points")
    }
    private func pt(_ p: (UInt8, UInt8), _ s: CGSize) -> CGPoint { CGPoint(x: CGFloat(p.0) / 127 * s.width, y: s.height - CGFloat(p.1) / 127 * s.height) }
    private func clamp(_ p: CGPoint, _ s: CGSize) -> (UInt8, UInt8) {
        (UInt8(Swift.max(0, Swift.min(127, p.x / s.width * 127))), UInt8(Swift.max(0, Swift.min(127, (s.height - p.y) / s.height * 127))))
    }
    private func handle(_ at: CGPoint, _ move: @escaping (CGPoint) -> Void) -> some View {
        Circle().fill(.white).frame(width: 14, height: 14).overlay(Circle().strokeBorder(SS.brand500, lineWidth: 2)).position(at)
            .gesture(DragGesture(minimumDistance: 0).onChanged { move($0.location) })
    }
}

/// ForceAdapt (adaptive trigger resistance) — "Trigger mode" in SS4. Live preview goes straight to the
/// pad; "Keep in profile" stores type + parameters in the profile blob (layout per SS4, partly inferred).
struct ForceAdaptPanel: View {
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
    private let modes: [(Int, String)] = [(0, "General"), (1, "Race"), (2, "Sniper"), (3, "Recoil"), (4, "Lock"), (5, "Vibration")]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Field("Trigger mode") { DarkSelect(selection: $mode, options: modes) }
            if mode != 0 {
                Field("Stroke") { StepSlider(value: $stroke, range: 10...100) }
                Field(mode == 1 ? "Resistance" : "Strength") { StepSlider(value: $strength, range: 1...10) }
                if mode == 2 || mode == 5 {
                    Field("Pressure level") { StepSlider(value: $pressure, range: 1...10) }
                    Field("Frequency") { StepSlider(value: $frequency, range: 1...10) }
                }
                SwitchRow(title: "Match stroke", isOn: $matchStroke)
            }
            HStack(spacing: 8) {
                GhostButton(title: previewing ? "Stop preview" : "Preview on controller", icon: "play.fill", enabled: model.connection == .xinput && !model.busy) { Task { await preview(!previewing) } }
                PrimaryButton(title: "Keep in profile", enabled: !(mode == Int(trig.adapterType) && mode == 0)) { store() }
            }
            if model.connection != .xinput { Text("Preview needs XInput mode.").font(.system(size: 12)).foregroundStyle(SS.n400) }
        }
        .onAppear { mode = Int(trig.adapterType); load() }
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
        params[2] = t.adapterParams.count >= 20 ? t.adapterParams[2] : 0xFF
        params[3] = t.adapterParams.count >= 20 ? t.adapterParams[3] : 0xFF
        let live = Array(liveParams.dropFirst())
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

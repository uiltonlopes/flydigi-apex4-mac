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
    @State private var cfg = ForceAdapt()
    @State private var previewing = false

    private var trig: GamepadConfig.Trigger { profiles.draft![trigger: side] }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForceAdaptEditor(cfg: $cfg)
            HStack(spacing: 8) {
                GhostButton(title: previewing ? "Stop preview" : "Preview on controller", icon: "play.fill", enabled: model.connection == .xinput && !model.busy) { Task { await preview(!previewing) } }
                PrimaryButton(title: "Keep in profile", enabled: cfg != ForceAdapt(adapterBlock: trig.adapterParams)) { store() }
            }
            if model.connection != .xinput { Text("Preview needs XInput mode.").font(.system(size: 12)).foregroundStyle(SS.n400) }
        }
        .onAppear { cfg = ForceAdapt(adapterBlock: trig.adapterParams) }
    }

    /// Persist into the profile blob the way SS4's `SaveTriggerAdapterConfig` does.
    private func store() {
        var t = trig
        t.adapterParams = cfg.adapterBlock(previous: t.adapterParams)
        t.adapterType = UInt8(cfg.mode.rawValue)
        t.kind = cfg.isNormal ? .normal : .adapter
        profiles.draft?[trigger: side] = t
    }

    private func preview(_ on: Bool) async {
        previewing = on
        guard #available(macOS 14.0, *) else { return }
        let params = on ? cfg.liveParams : [0]
        let sideByte: UInt8 = side == .left ? 1 : 2
        _ = await Task.detached { Result { try HelperClient.shared.setForceTrigger(side: sideByte, params: params) } }.value
    }
}

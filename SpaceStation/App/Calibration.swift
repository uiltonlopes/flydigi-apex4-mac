// Guided stick / trigger calibration. The firmware exposes a raw "ADC calibration window" (`A5 14 01` … `02`,
// docs/protocol.md §11); closing it before the sticks have been swept to their limits stores a bogus range,
// so this wizard tracks coverage live and only enables Finish once every axis has been reached.

import SwiftUI
import FlydigiKit

struct CalibrationWizard: View {
    @Environment(ControllerModel.self) private var model
    @Environment(LiveInput.self) private var live
    @Environment(\.dismiss) private var dismiss

    enum Step { case intro, running, finishing, done, failed }
    @State private var step: Step = .intro
    @State private var coverage = Coverage()
    @State private var confirmCancel = false

    struct Coverage: Equatable {
        var lMin = CGPoint(x: 0, y: 0), lMax = CGPoint(x: 0, y: 0)
        var rMin = CGPoint(x: 0, y: 0), rMax = CGPoint(x: 0, y: 0)
        var lt: Float = 0, rt: Float = 0
        static let target: CGFloat = 0.9
        var stickLeftDone: Bool { lMin.x <= -Self.target && lMax.x >= Self.target && lMin.y <= -Self.target && lMax.y >= Self.target }
        var stickRightDone: Bool { rMin.x <= -Self.target && rMax.x >= Self.target && rMin.y <= -Self.target && rMax.y >= Self.target }
        var triggersDone: Bool { lt >= Float(Self.target) && rt >= Float(Self.target) }
        var complete: Bool { stickLeftDone && stickRightDone && triggersDone }
        mutating func feed(l: LiveInput.Stick, r: LiveInput.Stick, lt: Float, rt: Float) {
            lMin.x = min(lMin.x, CGFloat(l.x)); lMax.x = max(lMax.x, CGFloat(l.x)); lMin.y = min(lMin.y, CGFloat(l.y)); lMax.y = max(lMax.y, CGFloat(l.y))
            rMin.x = min(rMin.x, CGFloat(r.x)); rMax.x = max(rMax.x, CGFloat(r.x)); rMin.y = min(rMin.y, CGFloat(r.y)); rMax.y = max(rMax.y, CGFloat(r.y))
            self.lt = max(self.lt, lt); self.rt = max(self.rt, rt)
        }
    }

    private var left: LiveInput.Stick { live.raw.map { .init(x: $0.leftX, y: $0.leftY) } ?? live.left }
    private var right: LiveInput.Stick { live.raw.map { .init(x: $0.rightX, y: $0.rightY) } ?? live.right }
    private var lt: Float { live.raw?.leftTrigger ?? live.leftTrigger }
    private var rt: Float { live.raw?.rightTrigger ?? live.rightTrigger }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Stick calibration").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                if step == .running { Text("Calibration window open").font(.system(size: 12, weight: .medium)).foregroundStyle(SS.yellow) }
            }
            switch step {
            case .intro: intro
            case .running, .finishing: running
            case .done: done
            case .failed: failed
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(SS.n800)
        .preferredColorScheme(.dark)
        .onChange(of: live.pressedKeys) { _, _ in }
        .onChange(of: left) { _, _ in track() }
        .onChange(of: right) { _, _ in track() }
        .onChange(of: lt) { _, _ in track() }
        .onChange(of: rt) { _, _ in track() }
        .confirmationDialog("Stop calibration now?", isPresented: $confirmCancel) {
            Button("Finish with what was captured", role: .destructive) { Task { await finish() } }
            Button("Keep calibrating", role: .cancel) {}
        } message: {
            Text("The sticks and triggers have not reached all their limits yet. Finishing now may store a wrong range — you can always run the calibration again.")
        }
    }

    private func track() { guard step == .running else { return }; coverage.feed(l: left, r: right, lt: lt, rt: rt) }

    // MARK: Steps

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Re-teaches the controller the centre and the limits of both sticks and both triggers. Takes about a minute.")
                .font(.system(size: 13)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 8) {
                bullet("1", "Keep the controller still with the sticks and triggers released, then press Start.")
                bullet("2", "Rotate each stick slowly along its outer edge three or four times, then press each trigger fully three times.")
                bullet("3", "When every axis shows a check mark, press Finish. The controller stores the result itself.")
            }
            if !live.connected {
                Text("No live input from the controller is visible yet — the wizard needs it to show progress.").font(.system(size: 12)).foregroundStyle(SS.yellow)
            }
            if model.info?.wired == false {
                Text("Use the USB cable for calibration.").font(.system(size: 12)).foregroundStyle(SS.yellow)
            }
            HStack {
                GhostButton(title: "Cancel") { dismiss() }
                Spacer()
                PrimaryButton(title: "Start", icon: "play.fill", enabled: model.connection != .none && !model.busy && live.connected && model.info?.wired != false) {
                    Task {
                        coverage = Coverage()
                        if await model.calibration(start: true) { step = .running } else { step = .failed }
                    }
                }
            }
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rotate each stick slowly along its edge, then press both triggers all the way. The rings fill in as you reach the limits.")
                .font(.system(size: 13)).foregroundStyle(.white)
            HStack(alignment: .top, spacing: 28) {
                CoverageGauge(title: "Left stick", stick: left, minP: coverage.lMin, maxP: coverage.lMax, done: coverage.stickLeftDone)
                CoverageGauge(title: "Right stick", stick: right, minP: coverage.rMin, maxP: coverage.rMax, done: coverage.stickRightDone)
                VStack(spacing: 10) {
                    HStack(spacing: 16) {
                        TriggerCoverage(title: "LT", value: lt, peak: coverage.lt)
                        TriggerCoverage(title: "RT", value: rt, peak: coverage.rt)
                    }
                    Label(coverage.triggersDone ? "Triggers reached" : "Press both triggers fully", systemImage: coverage.triggersDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12)).foregroundStyle(coverage.triggersDone ? SS.green : SS.n300)
                }
            }
            HStack {
                GhostButton(title: "Cancel", enabled: step == .running) { if coverage.complete { Task { await finish() } } else { confirmCancel = true } }
                Spacer()
                if !coverage.complete { Text("Finish unlocks when every limit has been reached.").font(.system(size: 12)).foregroundStyle(SS.n400) }
                PrimaryButton(title: step == .finishing ? "Saving…" : "Finish", icon: "checkmark", enabled: coverage.complete && step == .running) { Task { await finish() } }
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Calibration stored on the controller.", systemImage: "checkmark.seal.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(SS.green)
            Text("Move the sticks in the Joystick tab and check that the dot rests at the centre and reaches the ring on every side. If anything feels off, run the calibration again.")
                .font(.system(size: 13)).foregroundStyle(SS.n300)
            HStack { Spacer(); PrimaryButton(title: "Done", icon: "checkmark") { dismiss() } }
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("The controller did not accept the command.", systemImage: "exclamationmark.triangle.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(SS.yellow)
            Text(model.lastError ?? "").font(.system(size: 12)).foregroundStyle(SS.n300)
            HStack { GhostButton(title: "Close") { dismiss() }; Spacer(); PrimaryButton(title: "Try again") { step = .intro } }
        }
    }

    private func finish() async {
        step = .finishing
        step = await model.calibration(start: false) ? .done : .failed
    }

    private func bullet(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(width: 20, height: 20).background(SS.brand500, in: Circle())
            Text(LocalizedStringKey(text)).font(.system(size: 13)).foregroundStyle(SS.n300)
        }
    }
}

/// Stick gauge that fills the ring where the stick has already reached the edge.
struct CoverageGauge: View {
    let title: String; let stick: LiveInput.Stick; let minP: CGPoint; let maxP: CGPoint; let done: Bool
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(SS.n700)
                Circle().stroke(SS.n500, lineWidth: 1)
                // reached extents per side
                arc(from: -30, to: 30, on: maxP.x)      // right
                arc(from: 60, to: 120, on: -minP.y)     // down (y positive = up in our space; screen y flipped)
                arc(from: 150, to: 210, on: -minP.x)    // left
                arc(from: 240, to: 300, on: maxP.y)     // up
                Circle().stroke(SS.n400, style: StrokeStyle(lineWidth: 1, dash: [3])).scaleEffect(CoverageGauge.target)
                Circle().fill(done ? SS.green : SS.brand500).frame(width: 12, height: 12)
                    .offset(x: CGFloat(stick.x) * 60, y: -CGFloat(stick.y) * 60)
            }
            .frame(width: 130, height: 130)
            Label(title, systemImage: done ? "checkmark.circle.fill" : "circle").font(.system(size: 12)).foregroundStyle(done ? SS.green : SS.n300)
        }
    }
    static let target: CGFloat = 0.9
    private func arc(from a: Double, to b: Double, on reached: CGFloat) -> some View {
        let filled = reached >= CoverageGauge.target
        return Circle().trim(from: a / 360, to: b / 360).stroke(filled ? SS.green : SS.n500.opacity(0.6), lineWidth: filled ? 4 : 2)
            .rotationEffect(.degrees(0)).scaleEffect(0.97)
    }
}

struct TriggerCoverage: View {
    let title: String; let value: Float; let peak: Float
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6).fill(SS.n700)
                RoundedRectangle(cornerRadius: 6).stroke(SS.n500, lineWidth: 1)
                RoundedRectangle(cornerRadius: 6).fill(SS.brand500.opacity(0.9)).frame(height: max(2, CGFloat(value) * 130))
                Rectangle().fill(peak >= 0.9 ? SS.green : SS.yellow).frame(height: 2).offset(y: -CGFloat(peak) * 130)
            }
            .frame(width: 30, height: 130)
            Text(title).font(.system(size: 12)).foregroundStyle(SS.n300)
        }
    }
}

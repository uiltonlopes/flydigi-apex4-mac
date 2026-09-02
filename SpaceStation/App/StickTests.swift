// Space Station's "advanced test" pieces that make sense here: the stick circularity test (rotate the stick
// along its rim; we keep the outermost sample per angle and report the average error from a perfect circle)
// and the report-rate meter (see LiveInput.rawReportRate).

import SwiftUI

struct CircularityTestSheet: View {
    @Environment(LiveInput.self) private var live
    @Environment(\.dismiss) private var dismiss
    let side: Side
    private static let bins = 72                            // 5° each
    @State private var radii = [Double](repeating: 0, count: 72)
    @State private var running = true

    private var stick: LiveInput.Stick {
        if let r = live.raw { return side == .left ? .init(x: r.leftX, y: r.leftY) : .init(x: r.rightX, y: r.rightY) }
        return side == .left ? live.left : live.right
    }
    private var covered: Int { radii.filter { $0 > 0.5 }.count }
    /// Mean |r − 1| over covered bins, in percent (SS4's "average error").
    private var averageError: Double? {
        let c = radii.filter { $0 > 0.5 }
        guard c.count >= Self.bins / 2 else { return nil }
        return c.map { abs($0 - 1) }.reduce(0, +) / Double(c.count) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Circularity test").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Text("Push the stick to its edge and roll it around slowly, two or three full turns. The outer trace is what the controller reports; the dashed circle is a perfect 100 %.").font(.system(size: 12)).foregroundStyle(SS.n300)
            HStack(alignment: .top, spacing: 24) {
                ZStack {
                    Circle().fill(SS.n700)
                    Circle().stroke(SS.n400, style: StrokeStyle(lineWidth: 1, dash: [3]))
                    Path { p in
                        var started = false
                        for i in 0..<Self.bins {
                            let r = radii[i]; guard r > 0 else { continue }
                            let a = Double(i) / Double(Self.bins) * 2 * .pi
                            let pt = CGPoint(x: 110 + 100 * r * cos(a), y: 110 - 100 * r * sin(a))
                            if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                        }
                    }
                    .stroke(SS.brand500, lineWidth: 2)
                    Circle().fill(.white).frame(width: 8, height: 8)
                        .offset(x: CGFloat(stick.x) * 100, y: -CGFloat(stick.y) * 100)
                }
                .frame(width: 220, height: 220)
                VStack(alignment: .leading, spacing: 10) {
                    row("Coverage", "\(covered * 100 / Self.bins) %")
                    row("Average error", averageError.map { String(format: "%.1f %%", $0) } ?? "—")
                    row("Max", String(format: "%.0f %%", (radii.max() ?? 0) * 100))
                    row("Min (covered)", String(format: "%.0f %%", (radii.filter { $0 > 0.5 }.min() ?? 0) * 100))
                    Text(averageError.map { $0 < 3 ? String(localized: "Excellent — the path is a circle.") : ($0 < 8 ? String(localized: "Good. Small deviations are normal.") : String(localized: "Large deviation: try calibrating the sticks.")) } ?? String(localized: "Keep rolling until coverage passes 50 %."))
                        .font(.system(size: 12)).foregroundStyle(SS.n300).frame(width: 260, alignment: .leading)
                }
            }
            HStack {
                GhostButton(title: "Reset", icon: "arrow.counterclockwise") { radii = [Double](repeating: 0, count: Self.bins) }
                Spacer()
                GhostButton(title: "Close") { dismiss() }
            }
        }
        .padding(20).frame(width: 560)
        .background(SS.n800)
        .onChange(of: stick) { _, s in
            let r = min(1.5, Double(hypot(s.x, s.y)))
            guard r > 0.3 else { return }
            var a = atan2(Double(s.y), Double(s.x)); if a < 0 { a += 2 * .pi }
            let i = Int(a / (2 * .pi) * Double(Self.bins)) % Self.bins
            if r > radii[i] { radii[i] = r }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(LocalizedStringKey(k)).font(.system(size: 12)).foregroundStyle(SS.n400); Spacer(); Text(v).font(.system(size: 12).monospacedDigit()).foregroundStyle(.white) }.frame(width: 260)
    }
}

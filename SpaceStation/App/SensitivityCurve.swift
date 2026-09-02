// Stick sensitivity curve, drawn the way Space Station 4 draws it (renderer component `Oi` + its 280 × 280
// grid SVG): plot area x 14…274 / y 6…266, 10 % grid, 0–100 labels on both axes, the centre dead zone as a
// grey band on the left, the edge zone as a blue band on the right, a faint diagonal for reference, and the
// curve as four points — start (after the dead zone) → P1 → P2 → end (before the edge). P1/P2 are stored
// 0…127 and are *fractions of the active range*, exactly like SS4 maps them. We add a live dot for the
// current stick deflection, which SS4 does not have.

import SwiftUI
import FlydigiKit

struct SensitivityCurve: View {
    @Binding var p1: (UInt8, UInt8)
    @Binding var p2: (UInt8, UInt8)
    var deadZone: UInt8          // 0…127, centre dead zone
    var edge: UInt8              // 0…127, "end": output saturates here
    var editable: Bool
    var live: Double? = nil      // current deflection 0…1, nil = no controller
    var onEdit: () -> Void = {}

    // SS4 geometry (280 × 280, plot x 14…274 / y 6…266), scaled to `size`
    var size: CGFloat = 280
    private var k: CGFloat { size / 280 }
    private var x0: CGFloat { 14 * k }
    private var x1: CGFloat { size - 6 * k }
    private var y0: CGFloat { size - 14 * k }           // bottom (input 0)
    private var y1: CGFloat { 6 * k }                   // top (output 100)
    @State private var dragging: Int? = nil             // 1 or 2 while a handle is held
    @State private var dragPos: CGPoint = .zero

    private var deadFrac: CGFloat { CGFloat(deadZone) / 127 }
    private var edgeFrac: CGFloat { CGFloat(127 - min(edge, 127)) / 127 }
    private var startPt: CGPoint { CGPoint(x: x0 + (x1 - x0) * deadFrac, y: y0) }
    private var endPt: CGPoint { CGPoint(x: x1 - (x1 - x0) * edgeFrac, y: y1) }

    /// Control point (0…127 fractions of the active range) → plot coordinates.
    private func plot(_ p: (UInt8, UInt8)) -> CGPoint {
        let fx = CGFloat(p.0) / 127, fy = CGFloat(p.1) / 127
        return CGPoint(x: startPt.x + (endPt.x - startPt.x) * fx, y: startPt.y + (endPt.y - startPt.y) * fy)
    }
    /// Plot coordinates → control point, clamped to the active range.
    private func unplot(_ q: CGPoint) -> (UInt8, UInt8) {
        let w = max(1, endPt.x - startPt.x), h = max(1, startPt.y - endPt.y)
        let fx = min(1, max(0, (q.x - startPt.x) / w)), fy = min(1, max(0, (startPt.y - q.y) / h))
        return (UInt8((fx * 127).rounded()), UInt8((fy * 127).rounded()))
    }

    /// Output (0…1) for an input deflection (0…1) along the 4-point polyline — for the live dot.
    private func output(for input: CGFloat) -> CGPoint {
        let x = x0 + (x1 - x0) * input
        let pts = [startPt, plot(p1), plot(p2), endPt]
        if x <= pts[0].x { return CGPoint(x: x, y: y0) }
        if x >= pts[3].x { return CGPoint(x: x, y: y1) }
        for i in 0..<3 {
            let a = pts[i], b = pts[i + 1]
            if x >= a.x && x <= b.x {
                let t = b.x - a.x < 0.001 ? 1 : (x - a.x) / (b.x - a.x)
                return CGPoint(x: x, y: a.y + (b.y - a.y) * t)
            }
        }
        return CGPoint(x: x, y: y1)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // grid + axis labels
            Canvas { ctx, _ in
                for i in 0...10 {
                    let f = CGFloat(i) / 10
                    let gx = x0 + (x1 - x0) * f, gy = y0 - (y0 - y1) * f
                    ctx.stroke(Path { $0.move(to: CGPoint(x: gx, y: y1)); $0.addLine(to: CGPoint(x: gx, y: y0)) }, with: .color(SS.n500), lineWidth: 0.8)
                    ctx.stroke(Path { $0.move(to: CGPoint(x: x0, y: gy)); $0.addLine(to: CGPoint(x: x1, y: gy)) }, with: .color(SS.n500), lineWidth: 0.8)
                    let label = Text("\(i * 10)").font(.system(size: 7 * k)).foregroundStyle(SS.n400)
                    ctx.draw(label, at: CGPoint(x: x0 - 7 * k, y: gy), anchor: .center)
                    if i > 0 { ctx.draw(label, at: CGPoint(x: gx, y: y0 + 8 * k), anchor: .center) }
                }
                ctx.stroke(Path { $0.move(to: CGPoint(x: x0, y: y1)); $0.addLine(to: CGPoint(x: x0, y: y0)); $0.addLine(to: CGPoint(x: x1, y: y0)) }, with: .color(SS.n400), lineWidth: 0.8)
                // dead zone / edge bands
                if deadFrac > 0 { ctx.fill(Path(CGRect(x: x0, y: y1, width: (x1 - x0) * deadFrac, height: y0 - y1)), with: .color(Color(red: 126/255, green: 133/255, blue: 142/255).opacity(0.3))) }
                if edgeFrac > 0 { ctx.fill(Path(CGRect(x: endPt.x, y: y1, width: (x1 - x0) * edgeFrac, height: y0 - y1)), with: .color(Color(red: 40/255, green: 90/255, blue: 250/255).opacity(0.2))) }
                // reference diagonal
                ctx.stroke(Path { $0.move(to: CGPoint(x: x0, y: y0)); $0.addLine(to: CGPoint(x: x1, y: y1)) }, with: .color(SS.n500), lineWidth: 1)
                // the curve
                let a = plot(p1), b = plot(p2)
                ctx.stroke(Path { $0.move(to: startPt); $0.addLine(to: a); $0.addLine(to: b); $0.addLine(to: endPt) }, with: .color(editable ? SS.brand500 : SS.n300), lineWidth: 1.5)
                // live dot
                if let live {
                    let q = output(for: CGFloat(min(1, max(0, live))))
                    ctx.fill(Path(ellipseIn: CGRect(x: q.x - 5, y: q.y - 5, width: 10, height: 10)), with: .color(SS.brand500.opacity(0.35)))
                    ctx.fill(Path(ellipseIn: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)), with: .color(.white))
                }
            }
            handle(1, plot(p1)) { p1 = $0 }
            handle(2, plot(p2)) { p2 = $0 }
            if let d = dragging {
                let q = d == 1 ? plot(p1) : plot(p2)
                let vx = Int(((q.x - x0) / (x1 - x0) * 100).rounded()), vy = Int(((y0 - q.y) / (y0 - y1) * 100).rounded())
                Text("x: \(vx)\ny: \(vy)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.white)
                    .padding(4).background(Color(hex: 0x232323), in: RoundedRectangle(cornerRadius: 4))
                    .offset(x: q.x > size * 0.72 ? q.x - 52 : q.x + 12, y: q.y > size * 0.72 ? q.y - 44 : q.y + 12)
            }
        }
        .frame(width: size, height: size)
    }

    private func handle(_ id: Int, _ at: CGPoint, set: @escaping ((UInt8, UInt8)) -> Void) -> some View {
        ZStack {
            Circle().fill(Color(hex: 0x3E95FF)).frame(width: 9, height: 9)
            Circle().strokeBorder(.white, lineWidth: 1.2).frame(width: 9, height: 9)
        }
        .frame(width: 24, height: 24).contentShape(Circle())
        .position(at)
        .opacity(editable ? 1 : 0.55)
        .gesture(editable ? DragGesture(minimumDistance: 1)
            .onChanged { v in
                dragging = id
                var q = v.location
                // keep the order start ≤ P1 ≤ P2 ≤ end on both axes, like SS4 clamps
                if id == 1 { q.x = min(q.x, plot(p2).x); q.y = max(q.y, plot(p2).y) } else { q.x = max(q.x, plot(p1).x); q.y = min(q.y, plot(p1).y) }
                set(unplot(q)); onEdit()
            }
            .onEnded { _ in dragging = nil } : nil)
    }
}

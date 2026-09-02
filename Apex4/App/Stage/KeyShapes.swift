// Key silhouettes for the hero chips: triggers, bumpers and back paddles as Space Station 4 draws them
// (path data from its key icons, © Flydigi — see Resources/Flydigi/NOTICE.md), plus a tiny SVG path parser.

import SwiftUI
import FlydigiKit

/// Parses the subset of SVG path syntax used by the icons (M L H V C S Q Z, absolute and relative).
struct SVGPath: Shape {
    let d: String
    let box: CGSize                 // native viewBox size
    var mirrored = false            // flip horizontally (right-hand variants)

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cmds = SVGPath.tokenize(d)
        var cur = CGPoint.zero, start = CGPoint.zero, lastCtrl: CGPoint? = nil
        var i = 0
        func num() -> CGFloat { defer { i += 1 }; return i < cmds.count ? (CGFloat(Double(cmds[i]) ?? 0)) : 0 }
        var op: Character = "M"
        while i < cmds.count {
            let t = cmds[i]
            if let c = t.first, c.isLetter { op = c; i += 1; if op == "Z" || op == "z" { p.closeSubpath(); cur = start; continue } }
            let rel = op.isLowercase
            switch op.uppercased() {
            case "M": let x = num(), y = num(); cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y); start = cur; p.move(to: cur); op = rel ? "l" : "L"
            case "L": let x = num(), y = num(); cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y); p.addLine(to: cur)
            case "H": let x = num(); cur.x = rel ? cur.x + x : x; p.addLine(to: cur)
            case "V": let y = num(); cur.y = rel ? cur.y + y : y; p.addLine(to: cur)
            case "C":
                var c1 = CGPoint(x: num(), y: num()), c2 = CGPoint(x: num(), y: num()), e = CGPoint(x: num(), y: num())
                if rel { c1.x += cur.x; c1.y += cur.y; c2.x += cur.x; c2.y += cur.y; e.x += cur.x; e.y += cur.y }
                p.addCurve(to: e, control1: c1, control2: c2); lastCtrl = c2; cur = e
            case "S":
                var c2 = CGPoint(x: num(), y: num()), e = CGPoint(x: num(), y: num())
                if rel { c2.x += cur.x; c2.y += cur.y; e.x += cur.x; e.y += cur.y }
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                p.addCurve(to: e, control1: c1, control2: c2); lastCtrl = c2; cur = e
            case "Q":
                var c = CGPoint(x: num(), y: num()), e = CGPoint(x: num(), y: num())
                if rel { c.x += cur.x; c.y += cur.y; e.x += cur.x; e.y += cur.y }
                p.addQuadCurve(to: e, control: c); lastCtrl = c; cur = e
            default: i += 1
            }
            if op.uppercased() != "C" && op.uppercased() != "S" && op.uppercased() != "Q" { lastCtrl = nil }
        }
        // Scale the native box into `rect` (uniform, centred).
        let s = min(rect.width / box.width, rect.height / box.height)
        var t = CGAffineTransform.identity
        t = t.translatedBy(x: rect.midX - box.width * s / 2, y: rect.midY - box.height * s / 2)
        t = t.scaledBy(x: s, y: s)
        if mirrored { t = t.translatedBy(x: box.width, y: 0).scaledBy(x: -1, y: 1) }
        return p.applying(t)
    }

    private static func tokenize(_ d: String) -> [String] {
        var out: [String] = []; var cur = ""
        func flush() { if !cur.isEmpty { out.append(cur); cur = "" } }
        for ch in d {
            if ch.isLetter { flush(); out.append(String(ch)) }
            else if ch == "," || ch == " " { flush() }
            else if ch == "-" { if !cur.isEmpty, !cur.hasSuffix("e") { flush() }; cur.append(ch) }
            else if ch == "." { if cur.contains(".") && !cur.contains("e") { flush() }; cur.append(ch) }
            else { cur.append(ch) }
        }
        flush()
        return out
    }
}

enum KeySilhouette {
    // Space Station 4 key icons for the Apex 4 (k2). Native sizes are the SVG viewBoxes.
    static let lt = SVGPath(d: "M41.7938 40.221C29.9728 42.6567 0.933177 49.208 0.933177 49.208C0.933177 49.208 -1.47027 4.94522 16.6617 1.7115C34.7938 -1.52222 40.1071 22.2891 41.7938 40.221Z", box: CGSize(width: 43, height: 51))
    static let rt = SVGPath(d: "M1.41454 40.221C13.2356 42.6567 42.2752 49.208 42.2752 49.208C42.2752 49.208 44.6786 4.94522 26.5466 1.7115C8.41461 -1.52222 3.10129 22.2891 1.41454 40.221Z", box: CGSize(width: 44, height: 51))
    static let lb = SVGPath(d: "M76.2081 29.1047V3.74751H46.3177C44.6828 3.74751 42.9385 2.44513 42.2707 1.79395C31.038 4.06008 3.73192 10.7926 1.10339 11.7303C7.01652 24.028 18.3094 29.1047 33.0548 29.1047H76.2081Z", box: CGSize(width: 77, height: 30))
    static let rb = SVGPath(d: "M1.00041 29.1047V3.74751H30.8908C32.5256 3.74751 34.27 2.44513 34.9378 1.79395C46.1705 4.06008 73.4766 10.7926 76.1051 11.7303C70.192 24.028 58.8991 29.1047 44.1537 29.1047H1.00041Z", box: CGSize(width: 78, height: 30))
    static let m1 = SVGPath(d: "M37.6667 5.10693C37.9579 3.43095 36.4827 1.98141 34.8121 2.3019L14.0016 6.29419C9.70556 7.11834 6.48781 10.7084 6.13705 15.0687L4.38586 36.8382C4.24915 38.5377 5.85798 39.8467 7.49411 39.3673L27.2 33.5936C30.7586 32.551 33.415 29.5762 34.0498 25.9228L37.6667 5.10693Z", box: CGSize(width: 42, height: 41))
    static let m2 = SVGPath(d: "M4.70468 5.10693C4.41347 3.43095 5.88861 1.98141 7.55923 2.3019L28.3697 6.29419C32.6658 7.11834 35.8835 10.7084 36.2343 15.0687L37.9855 36.8382C38.1222 38.5377 36.5134 39.8467 34.8772 39.3673L15.1713 33.5936C11.6128 32.551 8.95635 29.5762 8.32155 25.9228L4.70468 5.10693Z", box: CGSize(width: 42, height: 41))
    static let m3 = SVGPath(d: "M0.963501 8.44858C0.963501 4.46305 4.36037 1.3233 8.33359 1.63634L29.8185 3.32909C32.9412 3.57512 35.4967 5.91273 36.0194 9.00114L37.8867 20.0355C38.8277 25.5958 34.5426 30.6669 28.9033 30.6669H7.79686C4.0229 30.6669 0.963501 27.6075 0.963501 23.8335V8.44858Z", box: CGSize(width: 39, height: 32))
    static let m4 = SVGPath(d: m3.d, box: m3.box, mirrored: true)

    static func shape(for key: ControllerKey) -> SVGPath? {
        switch key {
        case .lt: lt; case .rt: rt; case .lb: lb; case .rb: rb
        case .m1: m1; case .m2: m2; case .m3: m3; case .m4: m4
        default: nil
        }
    }
}

/// Stick well as SS4 draws it: dark disc, ring and a fine radial hatch.
struct StickWell: View {
    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2
            ZStack {
                Circle().fill(SS.chipFill)
                Circle().strokeBorder(SS.n400, lineWidth: 1.5)
                Path { p in
                    for i in 0..<48 {
                        let a = Double(i) / 48 * .pi * 2
                        let inner = r * 0.62, outer = r * 0.86
                        p.move(to: CGPoint(x: r + cos(a) * inner, y: r + sin(a) * inner))
                        p.addLine(to: CGPoint(x: r + cos(a) * outer, y: r + sin(a) * outer))
                    }
                }
                .stroke(SS.n400.opacity(0.7), lineWidth: 0.5)
                Circle().strokeBorder(SS.n500, lineWidth: 1).frame(width: r * 1.2, height: r * 1.2)
            }
        }
    }
}

// Schematic render of the Apex 4 (our own artwork) with normalised hotspot positions for mapping.
// Positions are fractions of the render's bounds; the view scales with its container.

import SwiftUI
import FlydigiKit

struct Hotspot: Identifiable, Hashable {
    let key: ControllerKey
    let x: CGFloat, y: CGFloat          // 0…1 in render space
    var id: UInt8 { key.rawValue }
    var label: String { Apex4Render.shortLabel(key) }
}

enum Apex4Render {
    /// Front + top face hotspots. Back paddles (M1–M4) are drawn as a labelled strip below the body.
    static let hotspots: [Hotspot] = [
        .init(key: .lb, x: 0.24, y: 0.10), .init(key: .rb, x: 0.76, y: 0.10),
        .init(key: .lt, x: 0.17, y: 0.03), .init(key: .rt, x: 0.83, y: 0.03),
        .init(key: .thumbL, x: 0.24, y: 0.40),                  // left stick (click)
        .init(key: .up, x: 0.42, y: 0.62), .init(key: .left, x: 0.36, y: 0.70), .init(key: .right, x: 0.48, y: 0.70), .init(key: .down, x: 0.42, y: 0.78),
        .init(key: .y, x: 0.76, y: 0.30), .init(key: .x, x: 0.69, y: 0.40), .init(key: .b, x: 0.83, y: 0.40), .init(key: .a, x: 0.76, y: 0.50),
        .init(key: .thumbR, x: 0.62, y: 0.68),                  // right stick (click)
        .init(key: .select, x: 0.40, y: 0.36), .init(key: .start, x: 0.60, y: 0.36), .init(key: .home, x: 0.50, y: 0.28),
        .init(key: .c, x: 0.46, y: 0.90), .init(key: .z, x: 0.54, y: 0.90),
        .init(key: .m1, x: 0.30, y: 0.98), .init(key: .m2, x: 0.40, y: 0.98), .init(key: .m3, x: 0.60, y: 0.98), .init(key: .m4, x: 0.70, y: 0.98),
    ]

    static func shortLabel(_ k: ControllerKey) -> String {
        switch k {
        case .up: "▲"; case .down: "▼"; case .left: "◀"; case .right: "▶"
        case .thumbL: "LS"; case .thumbR: "RS"; case .select: "◧"; case .start: "≡"; case .home: "⌂"
        default: "\(k)".uppercased().replacingOccurrences(of: "LB", with: "LB")
        }
    }
}

/// The body drawing (shapes only). Sized to the container; aspect ~ 1.35.
struct Apex4BodyShape: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                // grips
                Capsule().fill(.white.opacity(0.06)).frame(width: w * 0.22, height: h * 0.62).rotationEffect(.degrees(12)).offset(x: -w * 0.30, y: h * 0.16)
                Capsule().fill(.white.opacity(0.06)).frame(width: w * 0.22, height: h * 0.62).rotationEffect(.degrees(-12)).offset(x: w * 0.30, y: h * 0.16)
                // body
                RoundedRectangle(cornerRadius: w * 0.16).fill(.white.opacity(0.08)).frame(width: w * 0.78, height: h * 0.58).offset(y: -h * 0.02)
                    .overlay(RoundedRectangle(cornerRadius: w * 0.16).strokeBorder(.white.opacity(0.10), lineWidth: 1).frame(width: w * 0.78, height: h * 0.58).offset(y: -h * 0.02))
                // screen
                RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.7)).frame(width: w * 0.16, height: h * 0.10).offset(y: -h * 0.24)
                // sticks
                Circle().fill(.white.opacity(0.10)).frame(width: w * 0.16).offset(x: -w * 0.26, y: -h * 0.10)
                Circle().fill(.white.opacity(0.10)).frame(width: w * 0.16).offset(x: w * 0.12, y: h * 0.18)
                // bumpers
                Capsule().fill(.white.opacity(0.10)).frame(width: w * 0.20, height: h * 0.05).offset(x: -w * 0.26, y: -h * 0.40)
                Capsule().fill(.white.opacity(0.10)).frame(width: w * 0.20, height: h * 0.05).offset(x: w * 0.26, y: -h * 0.40)
            }
            .frame(width: w, height: h)
        }
    }
}

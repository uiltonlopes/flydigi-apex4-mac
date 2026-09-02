// The controller on the stage. The outline and product picture come from Space Station 4's assets
// (see Resources/Flydigi/NOTICE.md); the hotspot geometry is Space Station's `device_config_k2`
// (508 × 421 canvas), so buttons land exactly on the drawing. Falls back to a schematic when the files
// are missing.

import SwiftUI
import AppKit
import FlydigiKit

struct Hotspot: Identifiable, Hashable {
    enum Shape: Hashable { case circle, roundRect, rect }
    let key: ControllerKey
    let rect: CGRect                    // in canvas coordinates (Apex4Render.canvas)
    var shape: Shape = .rect
    var rotation: Double = 0            // degrees
    var clickable = true
    var id: UInt8 { key.rawValue }
    var label: String { Apex4Render.shortLabel(key) }
    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    init(_ key: ControllerKey, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ shape: Shape = .rect, rotation: Double = 0, clickable: Bool = true) {
        self.key = key; rect = CGRect(x: x, y: y, width: w, height: h); self.shape = shape; self.rotation = rotation; self.clickable = clickable
    }
}

enum Apex4Render {
    static let canvas = CGSize(width: 508, height: 421)

    /// Mapping targets, in drawing order. Same positions/sizes as Space Station 4 (`device_config_k2`).
    static let hotspots: [Hotspot] = [
        .init(.lt, 6, 3, 40, 48), .init(.rt, 460, 3, 40, 48),
        .init(.lb, 9, 51, 75, 28), .init(.rb, 423, 51, 75, 28),
        .init(.select, 166, 108, 40, 18, .roundRect, rotation: 49), .init(.start, 301, 108, 40, 18, .roundRect, rotation: -51),
        .init(.thumbL, 116.5, 152.5, 32, 32, .circle), .init(.thumbR, 302, 216, 32, 32, .circle),
        .init(.y, 364, 130, 32, 32, .circle), .init(.x, 335, 159, 32, 32, .circle), .init(.b, 393, 159, 32, 32, .circle), .init(.a, 364, 188, 32, 32, .circle),
        .init(.up, 186, 194, 24, 24, .circle), .init(.right, 212, 222, 24, 24, .circle), .init(.down, 186, 250, 24, 24, .circle), .init(.left, 158, 222, 24, 24, .circle),
        .init(.menu, 225, 275, 28, 12, .roundRect, clickable: false), .init(.home, 260, 275, 28, 12, .roundRect, clickable: false),
        .init(.m2, 149, 344, 41, 41), .init(.m4, 206, 344, 41, 41), .init(.m3, 263, 344, 41, 41), .init(.m1, 324, 345, 41, 41),
    ]

    /// Stick wells (decorative rings under the stick-click chips).
    static let stickWells: [CGRect] = [CGRect(x: 100, y: 136, width: 65, height: 65), CGRect(x: 285, y: 200, width: 65, height: 65)]

    /// Keys the user can point at (physical buttons the firmware lets you remap).
    static var mappableKeys: [ControllerKey] { hotspots.filter(\.clickable).map(\.key) }

    static func shortLabel(_ k: ControllerKey) -> String {
        switch k {
        case .up: "▲"; case .down: "▼"; case .left: "◀"; case .right: "▶"
        case .thumbL: "LS"; case .thumbR: "RS"; case .select: "⧉"; case .start: "≡"; case .home: "⌂"; case .menu: "Fn"
        default: "\(k)".uppercased()
        }
    }

    // MARK: Artwork

    static let wireframe: NSImage? = load("apex4-wireframe", "svg")
    static let hero: NSImage? = load("apex4-hero", "png")
    /// Space Station's device-card artwork for the special editions (EVA-01, Assassin's Creed, Black Myth
    /// Wukong, Genshin, Honkai Star Rail); the standard Apex 4 has none.
    static func cardBackground(deviceId: UInt8?) -> NSImage? { deviceId.flatMap { load("card-k2-\($0)", "png") } }
    /// Space Station's "add device" silhouette shown when nothing is connected.
    static let addDevice: NSImage? = load("add-device", "png")
    /// Product picture for a specific Apex 4 variant (Space Station's `k2/<id>/main.png`), falling back to the base model.
    static func productImage(deviceId: UInt8?) -> NSImage? {
        if let id = deviceId, let img = load("k2-\(id)", "png") { return img }
        return hero
    }

    private static func load(_ name: String, _ ext: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// The outline drawing, scaled to fit while keeping the 508 × 421 canvas aspect.
struct Apex4Wireframe: View {
    var body: some View {
        if let img = Apex4Render.wireframe {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(Apex4Render.canvas, contentMode: .fit)
        } else {
            Apex4BodyShape().aspectRatio(Apex4Render.canvas, contentMode: .fit)
        }
    }
}

/// Product picture with a soft accent glow behind it.
struct Apex4Hero: View {
    var body: some View {
        if let img = Apex4Render.hero {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .shadow(color: Stage.glow.opacity(0.45), radius: 40, y: 12)
                .shadow(color: .black.opacity(0.6), radius: 18, y: 14)
        } else {
            Apex4BodyShape().aspectRatio(Apex4Render.canvas, contentMode: .fit)
        }
    }
}

/// Fallback body drawing (shapes only) when the artwork is absent.
struct Apex4BodyShape: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Capsule().fill(.white.opacity(0.06)).frame(width: w * 0.22, height: h * 0.62).rotationEffect(.degrees(12)).offset(x: -w * 0.30, y: h * 0.16)
                Capsule().fill(.white.opacity(0.06)).frame(width: w * 0.22, height: h * 0.62).rotationEffect(.degrees(-12)).offset(x: w * 0.30, y: h * 0.16)
                RoundedRectangle(cornerRadius: w * 0.16).fill(.white.opacity(0.08)).frame(width: w * 0.78, height: h * 0.58).offset(y: -h * 0.02)
                RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.7)).frame(width: w * 0.16, height: h * 0.10).offset(y: -h * 0.24)
                Circle().fill(.white.opacity(0.10)).frame(width: w * 0.16).offset(x: -w * 0.26, y: -h * 0.10)
                Circle().fill(.white.opacity(0.10)).frame(width: w * 0.16).offset(x: w * 0.12, y: h * 0.18)
            }
            .frame(width: w, height: h)
        }
    }
}

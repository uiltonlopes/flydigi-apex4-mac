// The only file that mentions `#available(macOS 26)` for visual APIs. See docs/design.md §6.

import SwiftUI

extension View {
    /// Floating control over content: Liquid Glass on 26, ordinary material on 15.
    @ViewBuilder
    func floatingChip<S: InsettableShape>(tint: Color? = nil, in shape: S = Capsule()) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.background(.regularMaterial, in: shape).overlay(shape.strokeBorder(.separator))
        }
    }

    /// Hero content that should visually continue under sidebar and inspector.
    @ViewBuilder
    func extendsUnderChrome() -> some View {
        if #available(macOS 26, *) { self.backgroundExtensionEffect() } else { self }
    }

    /// Dense content that scrolls under the toolbar.
    @ViewBuilder
    func hardScrollEdge() -> some View {
        if #available(macOS 26, *) { self.scrollEdgeEffectStyle(.hard, for: .top) } else { self }
    }

    /// The one prominent action per window.
    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(macOS 26, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }

    /// Edge-hugging card corners: concentric with the window on 26, 12 pt otherwise.
    @ViewBuilder
    func cardShape() -> some View {
        if #available(macOS 26, *) { self.clipShape(.rect(corners: .concentric, isUniform: true)) } else { self.clipShape(.rect(cornerRadius: 12)) }
    }
}

/// Stage colours (docs/design.md §3): always dark, opaque; the only place with the brand's neutrals.
enum Stage {
    static func top(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.11, green: 0.114, blue: 0.122) : Color(red: 0.149, green: 0.153, blue: 0.165) }
    static func bottom(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.055, green: 0.059, blue: 0.067) : Color(red: 0.094, green: 0.094, blue: 0.094) }
    static let glow = Color(red: 0.157, green: 0.353, blue: 0.98)   // #285AFA
}

/// A property card in the content layer (semantic background, no glass).
struct PropertyCard<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(title).font(.headline) } icon: { if let systemImage { Image(systemName: systemImage).symbolRenderingMode(.hierarchical) } }
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}

/// The hero stage: dark gradient, accent glow and the controller render. Content, not chrome.
struct StageView<Overlay: View>: View {
    @Environment(\.colorScheme) private var scheme
    var height: CGFloat = 300
    @ViewBuilder var overlay: Overlay

    var body: some View {
        ZStack {
            LinearGradient(colors: [Stage.top(scheme), Stage.bottom(scheme)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Stage.glow.opacity(0.28), .clear], center: .center, startRadius: 10, endRadius: height * 0.9)
            overlay
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .extendsUnderChrome()
    }
}

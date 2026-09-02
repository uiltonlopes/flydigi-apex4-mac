// Visual language borrowed from Space Station 4 (palette, radii, control shapes) rendered with native
// SwiftUI controls. Tokens come from SS4's CSS variables (docs/design-ss4-reference.md).

import SwiftUI

enum SS {
    static let n900 = Color(hex: 0x181818)      // darkest: hero, page background
    static let n800 = Color(hex: 0x1c1d1f)      // second dark: content area, inputs
    static let n700 = Color(hex: 0x212225)      // third dark: sidebar, cards
    static let n600 = Color(hex: 0x26272a)      // grey option: segmented container
    static let n500 = Color(hex: 0x2e3035)      // button normal / borders / selected segment
    static let n400 = Color(hex: 0x7e858e)      // grey icons & text
    static let n300 = Color(hex: 0x9ca3ac)      // lighter grey text
    static let brand = Color(hex: 0x285afa)     // brand 600
    static let brand500 = Color(hex: 0x3e6bfa)  // brand 500 (highlight)
    static let green = Color(hex: 0x5bf880)
    static let red = Color(hex: 0xf04040)
    static let yellow = Color(hex: 0xffba60)
    static let chipFill = Color(hex: 0x1e1f22)

    static let sidebarWidth: CGFloat = 248
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Text

struct SectionTitle: View {
    let title: String; let icon: String
    init(_ title: String, icon: String) { self.title = title; self.icon = icon }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.white)
            Text(LocalizedStringKey(title)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(height: 36)
    }
}

/// Label above a control, SS4 style (grey 13 pt).
struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) { self.label = label; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(label)).font(.system(size: 13)).foregroundStyle(SS.n300)
            content
        }
    }
}

struct Notice: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(LocalizedStringKey(text)).font(.system(size: 12)).foregroundStyle(SS.brand500).frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }
}

struct PageHeader: View {
    let title: String
    let back: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(SS.n300).frame(width: 24, height: 24) }
                .buttonStyle(.plain)
            Text(LocalizedStringKey(title)).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 14).frame(height: 52)
    }
}

// MARK: - Containers

struct DarkCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SS.n700, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct VDivider: View {
    var body: some View {
        Rectangle().fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.2), .white.opacity(0)], startPoint: .top, endPoint: .bottom)).frame(width: 1)
    }
}

struct HDivider: View {
    var body: some View {
        Rectangle().fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.2), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
    }
}

// MARK: - Controls

/// Dark select: a Menu that looks like SS4's antd select.
struct DarkSelect<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var width: CGFloat? = nil
    var disabled = false

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { o in
                Button { selection = o.0 } label: {
                    if o.0 == selection { Label(LocalizedStringKey(o.1), systemImage: "checkmark") } else { Text(LocalizedStringKey(o.1)) }
                }
            }
        } label: {
            HStack {
                Text(LocalizedStringKey(options.first { $0.0 == selection }?.1 ?? "—")).font(.system(size: 13)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(SS.n300)
            }
            .padding(.horizontal, 12).frame(height: 36).frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(SS.n800, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SS.n500))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .disabled(disabled).opacity(disabled ? 0.5 : 1)
    }
}

/// Segmented control in a dark pill (SS4's Click / Turbo / Macro / Special).
struct PillSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var compact = false          // tighter padding + smaller type for 4+ options in a narrow column
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { o in
                let on = o.0 == selection
                Button { withAnimation(.easeOut(duration: 0.15)) { selection = o.0 } } label: {
                    Text(LocalizedStringKey(o.1)).font(.system(size: compact ? 12 : 13, weight: on ? .semibold : .regular))
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(on ? .white : SS.n300)
                        .padding(.horizontal, compact ? 9 : 16).frame(height: 28)
                        .background(on ? SS.n500 : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(SS.n600, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// − slider + with the value underneath (SS4's brightness / sensitivity control).
struct StepSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { "\(Int($0.rounded()))" }
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                stepButton("minus") { value = max(range.lowerBound, value - step) }
                Slider(value: $value, in: range, step: step).tint(SS.brand).controlSize(.small)
                stepButton("plus") { value = min(range.upperBound, value + step) }
            }
            Text(format(value)).font(.system(size: 12).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
        .background(SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    private func stepButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 11, weight: .semibold)).foregroundStyle(SS.n300).frame(width: 20, height: 20) }
            .buttonStyle(.plain)
    }
}

/// Vertical list of radio rows (SS4's "Activate method").
struct RadioList<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        VStack(spacing: 6) {
            ForEach(options, id: \.0) { o in
                let on = o.0 == selection
                Button { selection = o.0 } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().strokeBorder(on ? SS.brand500 : SS.n400, lineWidth: 1.5).frame(width: 14, height: 14)
                            if on { Circle().fill(SS.brand500).frame(width: 7, height: 7) }
                        }
                        Text(LocalizedStringKey(o.1)).font(.system(size: 13, weight: on ? .medium : .regular)).foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(on ? SS.n500 : SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(LocalizedStringKey(title)).font(.system(size: 13)).foregroundStyle(SS.n300)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(SS.brand).controlSize(.small)
        }
        .frame(height: 28)
    }
}

/// Filled brand button (SS4 primary).
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(LocalizedStringKey(title)).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 32)
            .background(enabled ? SS.brand500 : SS.n500, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

/// Bordered dark button (SS4 secondary).
struct GhostButton: View {
    let title: String
    var icon: String? = nil
    var enabled = true
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(LocalizedStringKey(title)).font(.system(size: 13)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(destructive ? SS.red : .white).padding(.horizontal, 14).frame(height: 32)
            .background(SS.n700, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SS.n500))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.45)
    }
}

/// Icon-only dark pill button used in the hero (refresh, revert).
struct IconPill: View {
    let icon: String
    var help: String = ""
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(SS.n700.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SS.n500))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.45).help(help)
    }
}

/// Square rail button (SS4's Adaptive Trigger / Screen) — `wide` makes the Settings variant.
struct RailButton: View {
    let title: String; let icon: String
    var active = false
    var wide = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if wide {
                    HStack(spacing: 8) { Image(systemName: icon).font(.system(size: 13)); Text(LocalizedStringKey(title)).font(.system(size: 13)) }
                } else {
                    VStack(spacing: 8) { Image(systemName: icon).font(.system(size: 18)); Text(LocalizedStringKey(title)).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.8) }
                }
            }
            .foregroundStyle(active ? .white : SS.n300)
            .frame(maxWidth: .infinity).frame(height: wide ? 36 : 60)
            .background(SS.n600, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(active ? SS.brand500 : SS.n500))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Round key badge used for Input / Output.
struct KeyBadge: View {
    let label: String
    var size: CGFloat = 28
    var highlighted = false
    var body: some View {
        Text(label).font(.system(size: size * 0.4, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(SS.chipFill, in: Circle())
            .overlay(Circle().strokeBorder(highlighted ? SS.brand500 : SS.n400, lineWidth: highlighted ? 1.5 : 1))
    }
}

// MARK: - Tab bar

struct TabBarView<T: Hashable>: View {
    @Binding var selection: T
    let tabs: [(T, String, String)]     // id, title, symbol
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { t in
                let on = t.0 == selection
                Button { withAnimation(.easeOut(duration: 0.18)) { selection = t.0 } } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: t.2).font(.system(size: 12))
                            Text(LocalizedStringKey(t.1)).font(.system(size: 13, weight: on ? .semibold : .regular))
                        }
                        .foregroundStyle(on ? .white : SS.n300)
                        .frame(height: 40)
                        Rectangle().fill(on ? SS.brand500 : .clear).frame(height: 2).frame(maxWidth: 120)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 44)
        .background(SS.n800)
        .overlay(alignment: .top) { Rectangle().fill(.black.opacity(0.6)).frame(height: 1) }
    }
}

// MARK: - Remote thumbnails (cached, downscaled — the CDN banners are ~1 MB each)

import ImageIO

@MainActor
final class ThumbCache {
    static let shared = ThumbCache()
    private let cache = NSCache<NSURL, NSImage>()
    private var inflight: [URL: Task<NSImage?, Never>] = [:]

    func image(for url: URL, maxPixel: Int = 480) async -> NSImage? {
        if let img = cache.object(forKey: url as NSURL) { return img }
        if let t = inflight[url] { return await t.value }
        let task = Task<NSImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceCreateThumbnailWithTransform: true]
            guard let src = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        inflight[url] = task
        let img = await task.value
        inflight[url] = nil
        if let img { cache.setObject(img, forKey: url as NSURL) }
        return img
    }
}

/// Drop-in replacement for AsyncImage: cached, downscaled, retries when the view reappears.
struct RemoteThumb: View {
    let url: URL?
    var aspect: CGFloat = 16 / 9
    @State private var image: NSImage?
    @State private var attempt = 0
    var body: some View {
        ZStack {
            SS.n800
            if let image { Image(nsImage: image).resizable().aspectRatio(aspect, contentMode: .fill) }
            else if url != nil { ProgressView().controlSize(.mini).tint(SS.n400) }
        }
        .task(id: "\(url?.absoluteString ?? "")#\(attempt)") {
            guard let url, image == nil else { return }
            image = await ThumbCache.shared.image(for: url)
            if image == nil, attempt < 2 { try? await Task.sleep(for: .seconds(2)); attempt += 1 }
        }
    }
}

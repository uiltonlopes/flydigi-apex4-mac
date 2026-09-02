// Screen editor: pan / zoom the source inside a 2:1 viewport, trim GIF frames, set the frame interval,
// see the exact 160 × 80 result — then send. Replaces SS4's static crop dialog with a direct-manipulation one.

import SwiftUI
import FlydigiKit
import FlydigiTransport

@MainActor @Observable
final class ScreenEditorState {
    var url: URL?
    var images: [CGImage] = []
    var delays: [Double] = []
    var zoom: CGFloat = 1              // 1 = fit (letterbox), fill is computed
    var pan: CGSize = .zero            // viewport points
    var start = 0                      // trim (inclusive)
    var end = 0                        // trim (inclusive)
    var intervalMs = 100
    var frameIndex = 0

    var isEmpty: Bool { images.isEmpty }
    var sourceSize: CGSize { images.first.map { CGSize(width: $0.width, height: $0.height) } ?? .zero }
    var selectedCount: Int { images.isEmpty ? 0 : end - start + 1 }
    /// Frames actually sent: evenly thinned to the firmware limit.
    var outputCount: Int { min(selectedCount, Screen.maxFrames) }

    func load(_ url: URL) {
        guard let d = try? ImageLoader.decode(url: url) else { return }
        self.url = url; images = d.images; delays = d.delays
        start = 0; end = max(0, images.count - 1); frameIndex = 0
        let avg = d.delays.reduce(0, +) / Double(max(1, d.delays.count))
        intervalMs = images.count > 1 ? max(20, Int((avg * 1000).rounded())) : 100
        zoom = fillZoom(); pan = .zero          // SS4 default is fill
    }

    /// Zoom that makes the image cover the viewport (relative to fit).
    func fillZoom() -> CGFloat {
        let s = sourceSize; guard s.width > 0, s.height > 0 else { return 1 }
        let fit = min(2 / s.width, 1 / s.height), fill = max(2 / s.width, 1 / s.height)
        return fill / fit
    }

    /// Crop rectangle in source pixels for a viewport of the given size.
    func crop(viewport v: CGSize) -> ScreenCrop? {
        let s = sourceSize; guard s.width > 0, s.height > 0, v.width > 0 else { return nil }
        let fit = min(v.width / s.width, v.height / s.height)
        let k = fit * zoom
        let originX = (v.width - s.width * k) / 2 + pan.width
        let originY = (v.height - s.height * k) / 2 + pan.height
        return ScreenCrop(x: -originX / k, y: -originY / k, width: v.width / k, height: v.height / k)
    }

    func selectedImages() -> [CGImage] {
        guard !images.isEmpty else { return [] }
        return ImageLoader.pick(Array(images[start...end]), max: Screen.maxFrames)
    }

    func encode(viewport v: CGSize) -> [[UInt8]] { ImageLoader.frames(images: selectedImages(), crop: crop(viewport: v)) }
}

struct ScreenEditorView: View {
    @Bindable var state: ScreenEditorState
    static let viewportSize = CGSize(width: 480, height: 240)
    private let viewport = ScreenEditorView.viewportSize
    @State private var dragStart: CGSize = .zero
    @State private var magnifyStart: CGFloat = 1
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                canvas
                HStack(spacing: 8) {
                    GhostButton(title: "Fill") { withAnimation(.easeOut(duration: 0.2)) { state.zoom = state.fillZoom(); state.pan = .zero } }
                    GhostButton(title: "Fit") { withAnimation(.easeOut(duration: 0.2)) { state.zoom = 1; state.pan = .zero } }
                    Text("Drag to move · scroll or pinch to zoom").font(.system(size: 12)).foregroundStyle(SS.n400)
                    Spacer()
                    Text("Zoom").font(.system(size: 12)).foregroundStyle(SS.n300)
                    Slider(value: Binding(get: { Double(state.zoom) }, set: { state.zoom = CGFloat($0) }), in: 0.25...6).tint(SS.brand).controlSize(.small).frame(width: 140)
                }
                if state.images.count > 1 { trim }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("On the controller").font(.system(size: 13)).foregroundStyle(SS.n300)
                preview
                Text("160 × 80 · \(state.outputCount) frame\(state.outputCount == 1 ? "" : "s")\(state.selectedCount > Screen.maxFrames ? " (thinned from \(state.selectedCount))" : "")")
                    .font(.system(size: 12)).foregroundStyle(SS.n400)
                if state.images.count > 1 {
                    Field("Frame interval") {
                        StepSlider(value: Binding(get: { Double(state.intervalMs) }, set: { state.intervalMs = Int($0) }), range: 20...1000, step: 10, format: { "\(Int($0)) ms" })
                    }
                    .frame(width: 240)
                }
            }
        }
        .onReceive(timer) { _ in
            guard state.images.count > 1 else { return }
            // Animate through the trimmed range at the chosen interval (timer is 80 ms; skip ticks accordingly).
            tick += 80
            if tick >= state.intervalMs {
                tick = 0
                let n = state.end - state.start + 1
                state.frameIndex = n <= 0 ? state.start : state.start + ((state.frameIndex - state.start + 1) % n)
            }
        }
    }
    @State private var tick = 0

    private var currentImage: CGImage? {
        guard !state.images.isEmpty else { return nil }
        return state.images[min(max(state.frameIndex, 0), state.images.count - 1)]
    }

    private var canvas: some View {
        ZStack {
            Color.black
            if let img = currentImage {
                let s = state.sourceSize
                let fit = min(viewport.width / s.width, viewport.height / s.height)
                let k = fit * state.zoom
                Image(nsImage: NSImage(cgImage: img, size: s)).resizable().interpolation(.high)
                    .frame(width: s.width * k, height: s.height * k)
                    .offset(state.pan)
            }
            // 160×80 pixel grid hint at the edges
            Rectangle().strokeBorder(SS.brand500.opacity(0.6), lineWidth: 1)
        }
        .frame(width: viewport.width, height: viewport.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1).onChanged { v in
            state.pan = CGSize(width: dragStart.width + v.translation.width, height: dragStart.height + v.translation.height)
        }.onEnded { _ in dragStart = state.pan })
        .gesture(MagnifyGesture().onChanged { v in state.zoom = max(0.25, min(6, magnifyStart * v.magnification)) }.onEnded { _ in magnifyStart = state.zoom })
        .onAppear { dragStart = state.pan; magnifyStart = state.zoom }
        .onChange(of: state.zoom) { _, z in if !isMagnifying { magnifyStart = z } }
        .onScrollWheel { delta in
            state.zoom = max(0.25, min(6, state.zoom * (1 + delta / 200)))
            magnifyStart = state.zoom
        }
    }
    @State private var isMagnifying = false

    private var preview: some View {
        ZStack {
            Color.black
            if let img = currentImage, let p = ImageLoader.preview(img, crop: state.crop(viewport: viewport)) {
                Image(nsImage: NSImage(cgImage: p, size: NSSize(width: 160, height: 80))).interpolation(.none).resizable()
            }
        }
        .frame(width: 240, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(SS.n500))
    }

    private var trim: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trim").font(.system(size: 13)).foregroundStyle(SS.n300)
                Spacer()
                Text("frames \(state.start + 1)–\(state.end + 1) of \(state.images.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(SS.n400)
            }
            // Filmstrip of thumbnails; click sets start (left half) / end (right half) — plus explicit steppers.
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(state.images.indices, id: \.self) { i in
                        Image(nsImage: NSImage(cgImage: state.images[i], size: state.sourceSize)).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 28).clipped()
                            .overlay(Rectangle().strokeBorder(i == state.frameIndex ? SS.brand500 : .clear, lineWidth: 1.5))
                            .opacity(i < state.start || i > state.end ? 0.3 : 1)
                            .onTapGesture { state.frameIndex = i }
                    }
                }
            }
            .frame(height: 32)
            HStack(spacing: 16) {
                Stepper("Start \(state.start + 1)", value: Binding(get: { state.start }, set: { state.start = min($0, state.end) }), in: 0...max(0, state.images.count - 1)).font(.system(size: 12)).foregroundStyle(SS.n300)
                Stepper("End \(state.end + 1)", value: Binding(get: { state.end }, set: { state.end = max($0, state.start) }), in: 0...max(0, state.images.count - 1)).font(.system(size: 12)).foregroundStyle(SS.n300)
                GhostButton(title: "Set start here") { state.start = min(state.frameIndex, state.end) }
                GhostButton(title: "Set end here") { state.end = max(state.frameIndex, state.start) }
            }
        }
        .frame(width: viewport.width)
    }
}

// MARK: - Scroll wheel zoom (AppKit bridge)

private struct ScrollWheelModifier: ViewModifier {
    let onScroll: (CGFloat) -> Void
    func body(content: Content) -> some View { content.background(ScrollWheelCatcher(onScroll: onScroll)) }
}
private struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    func makeNSView(context: Context) -> CatcherView { let v = CatcherView(); v.onScroll = onScroll; return v }
    func updateNSView(_ v: CatcherView, context: Context) { v.onScroll = onScroll }
    final class CatcherView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) { onScroll?(event.scrollingDeltaY) }
        override var acceptsFirstResponder: Bool { true }
    }
}
extension View {
    func onScrollWheel(_ handler: @escaping (CGFloat) -> Void) -> some View { modifier(ScrollWheelModifier(onScroll: handler)) }
}

# Liquid Glass design guide for the Apex 4 companion app (macOS, SwiftUI)

Status: research document, 2026-09-01. Target: native macOS SwiftUI app, deployment macOS 15+,
"first-class" on macOS 26 Tahoe, forward-compatible with macOS 27 (WWDC26, in beta at time of writing).

Every SwiftUI signature below was checked against the macOS 26 SDK that ships with Xcode 26.6
(`MacOSX26.sdk`, SwiftUI/SwiftUICore `.swiftinterface`). macOS 27 APIs are marked as such and come
from the WWDC26 session transcript, not from a local SDK. Sources are tagged **[Apple]** (primary) or
**[3rd-party]** and listed in §10.

---

## 1. Philosophy: one glass layer floating above content

### 1.1 What Liquid Glass is, in Apple's words

**[Apple]** HIG › Materials: "Liquid Glass forms a distinct functional layer for controls and
navigation elements — like tab bars and sidebars — that floats above the content layer, establishing
a clear visual hierarchy between functional elements and content."

**[Apple]** WWDC25 "Meet Liquid Glass": the defining property is *lensing* — "whereas previous
materials scattered light, this new set of materials dynamically bends, shapes, and concentrates
light in real time." The material is adaptive: small elements (toolbar buttons) flip between light
and dark depending on what is behind them; large elements (sidebars, menus) adapt but never flip,
because "their surface area is too big and transitions like these would be distracting." Shadows
grow when glass sits over text and shrink over flat light backgrounds.

### 1.2 The two layers — and which one you are drawing

| Layer | What lives there | Material |
|---|---|---|
| **Functional / navigation layer** | window toolbar, sidebar, inspector chrome, popovers, menus, sheets, alerts, floating controls | Liquid Glass (system-provided) |
| **Content layer** | lists, tables, forms, long text, images, the controller diagram, LED and screen previews | opaque or ordinary materials; *never* glass |

**[Apple]** HIG › Materials: "Don't use Liquid Glass in the content layer. […] including it in the
content layer can result in unnecessary complexity and a confusing visual hierarchy." And: "Use
Liquid Glass effects sparingly. Standard components from system frameworks pick up the appearance
and behavior of this material automatically. If you apply Liquid Glass effects to a custom control,
do so sparingly. […] Limit these effects to the most important functional elements in your app."

The single exception the HIG lists: controls in the content layer with a *transient* interactive
element (sliders, toggles) take on glass while being manipulated — the system does this for you.

### 1.3 Regular vs. clear

**[Apple]** "Meet Liquid Glass": *regular* is "the most versatile; use this most often"; legibility is
guaranteed over any content. *Clear* is permanently transparent, has no adaptive behaviour, needs a
dimming layer (HIG: "consider adding a dark dimming layer of 35% opacity" over bright content) and is
only appropriate over media-rich backgrounds with bold, bright foreground. "They should never be
mixed." For a settings-style utility such as ours: **regular only**.

### 1.4 Tinting

**[Apple]** "Meet Liquid Glass": "Tinting should only be used to bring emphasis to primary elements
and actions in the UI." HIG › Color: "Apply color sparingly to the Liquid Glass material, and to
symbols or text on the material." For primary actions "apply color to the background rather than to
symbols or text" (that is what `.glassProminent` / the prominent toolbar style does), and "refrain
from adding color to the background of multiple controls."

### 1.5 Accessibility and how the system degrades

**[Apple]** "Meet Liquid Glass": *Reduce Transparency* "makes Liquid Glass frostier and obscures more
of the content behind it"; *Increase Contrast* "makes elements predominantly black or white and
highlights them with a contrasting border"; *Reduce Motion* "decreases the intensity of some effects
and disables any elastic properties for the material." Since macOS 26.1 users also have System
Settings › Appearance › Liquid Glass: **Clear** (default) or **Tinted** ("increases opacity and adds
more contrast"); macOS 27 replaces the toggle with a transparency slider **[3rd-party, WWDC26
coverage]**. The setting is unavailable when either accessibility switch is on.

Consequences for us: never encode meaning in translucency; every state must read on opaque black
or white glass with a border. Test the four combinations (dark/light × Increase Contrast on/off) plus
Reduce Transparency — HIG › Dark Mode explicitly asks for this.

---

## 2. Recommended macOS 26 app structure

### 2.1 Sidebar (`NavigationSplitView`) vs. `TabView(.sidebarAdaptable)`

**[Apple]** HIG › Tab bars: "To present a sidebar without the option to convert it to a tab bar, use a
navigation split view instead of a tab view." `sidebarAdaptable` (macOS 15+) exists so that
iPad-style tab apps can become sidebars; on macOS it renders a sidebar-like list but **[3rd-party,
TrozWare]** does not adapt to window size and does not support `ToolbarSpacer` grouping. For a
Mac-only app with seven sections and an inspector, use `NavigationSplitView` — it is also what the
Landmarks sample (Apple's reference app for Liquid Glass) uses, and HIG › Adopting Liquid Glass says
split views "are optimized to create a consistent and familiar experience for sidebar and inspector
layouts across platforms" and "allow fluid resizing of columns."

On macOS 26 the sidebar is a floating pane of glass; **[Apple]** WWDC25 "Build an AppKit app with the
new design": "Sidebars appear as a pane of glass that floats above the window's content, whereas
inspectors use an edge-to-edge glass that sits alongside the content." macOS 27 changes the sidebar
to extend edge-to-edge and gives sidebar icons their colour back **[3rd-party, WWDC26 coverage]** —
automatic, no code.

```swift
import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case status, profiles, sticks, macros, lighting, screen
    var id: Self { self }
    var title: String {
        switch self {
        case .status: "Status"; case .profiles: "Profiles & Mapping"; case .sticks: "Sticks & Triggers"
        case .macros: "Macros"; case .lighting: "Lighting"; case .screen: "Screen"
        }
    }
    var symbol: String {
        switch self {
        case .status: "gamecontroller"; case .profiles: "square.grid.2x2"; case .sticks: "dot.circle.and.hand.point.up.left.fill"
        case .macros: "list.bullet.rectangle"; case .lighting: "light.max"; case .screen: "photo.on.rectangle"
        }
    }
}

struct MainWindow: View {
    @Environment(ControllerModel.self) private var model
    @State private var section: Section? = .status
    @State private var showInspector = false

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { s in
                Label(s.title, systemImage: s.symbol)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { ControllerStatusFooter() }   // plain, NOT glass (§6)
        } detail: {
            DetailHost(section: section ?? .status)
                .inspector(isPresented: $showInspector) {                // macOS 14+
                    MappingInspector().inspectorColumnWidth(min: 260, ideal: 300, max: 360)
                }
                .toolbar { MainToolbar(showInspector: $showInspector) }
        }
    }
}
```

### 2.2 Toolbar

On macOS 26 toolbar items sit on glass; the system groups adjacent items on a shared background.
**[Apple]** WWDC25 "Get to know the new design system": "if you've customized your bars, now's the
time to clean them up. […] Instead of relying on decoration, hierarchy should be expressed through
layout and grouping." HIG › Toolbars: aim for "a maximum of three" groups; "don't mix text and icons
across items that share a background"; "Only specify one primary action, and put it on the trailing
side"; "Don't add an overflow menu manually"; "Make every toolbar item available as a command in the
menu bar."

APIs (macOS 26, verified):

```swift
public struct ToolbarSpacer: ToolbarContent, CustomizableToolbarContent {
    public init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic)
}
public struct DefaultToolbarItem: ToolbarContent {           // .sidebarToggle, .title, .search
    public init(kind: ToolbarDefaultItemKind, placement: ToolbarItemPlacement = .automatic)
}
extension ToolbarContent { func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent }
extension View { func toolbar(removing defaultItemKind: ToolbarDefaultItemKind?) -> some View }
extension View { func searchToolbarBehavior(_ behavior: SearchToolbarBehavior) -> some View } // .minimize
```

```swift
struct MainToolbar: ToolbarContent {
    @Environment(ControllerModel.self) private var model
    @Binding var showInspector: Bool

    var body: some ToolbarContent {
        // Group 1 — which configuration slot we are editing (Picker gets its own glass automatically)
        ToolbarItem(placement: .principal) {
            Picker("Profile", selection: Bindable(model).activeSlot) {
                ForEach(1...4, id: \.self) { Text("Slot \($0)").tag($0) }
            }
            .pickerStyle(.segmented)
        }

        // Group 2 — sync actions, share one glass background
        ToolbarItemGroup(placement: .automatic) {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
            Button("Revert", systemImage: "arrow.uturn.backward") { model.revertDraft() }
                .disabled(!model.hasUnsavedChanges)
        }
        if #available(macOS 26, *) { ToolbarSpacer(.fixed) }

        // Group 3 — the ONE tinted, prominent action (HIG: single primary action, trailing)
        ToolbarItem(placement: .primaryAction) {
            Button("Apply to Controller") { Task { await model.applyDraft() } }
                .prominentGlassButton()                 // §5.2: .glassProminent on 26, .borderedProminent on 15
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.hasUnsavedChanges || model.busy)
        }

        ToolbarItem {
            Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
        }
    }
}
```

WWDC25 "What's new in SwiftUI" shows the same idea with `.buttonStyle(.borderedProminent).tint(.pink)`
on a toolbar item — on 26 a prominent bordered button already renders as tinted glass, so
`.borderedProminent` alone is an acceptable 15-through-26 answer if you prefer one code path.

**macOS 27 additions (from WWDC26 "What's new in SwiftUI", not in the local SDK):**
`ToolbarContent.visibilityPriority(.high | .low | .automatic)` decides what overflows first;
`ToolbarOverflowMenu { … }` (or `.toolbarOverflowMenu { }`) pins secondary commands permanently
in the overflow; `ToolbarItemPlacement.topBarPinnedTrailing` keeps an item at the trailing edge
until only search needs the space; `.toolbarMinimizeBehavior(.onScrollDown, for: .navigationBar)`.
Plan for them behind `#available(macOS 27, *)` once Xcode 27 ships; do not hand-roll an overflow menu.

### 2.3 Titles, search

`.navigationTitle` / `.navigationSubtitle` show inline with the toolbar on macOS (HIG: "window titles
can display inline with controls, and toolbar items don't include a bezel"). Search: `.searchable`
on the `NavigationSplitView` puts the field top-trailing on Mac; `.searchToolbarBehavior(.minimize)`
collapses it to a button when space is tight (macOS 26). We only need search on the Macros and
Profiles lists — attach `.searchable` to those detail views, not globally.

### 2.4 Scroll edge effects

**[Apple]** "Get to know the new design system": "scroll edge effects are not decorative. They don't
block or darken like overlays. They simply clarify where UI and content meet, and shouldn't be used
where there aren't any floating UI elements." Two styles: *soft* (default, progressive blur/fade) and
*hard* ("a more opaque backing to provide greater separation" — recommended on macOS for pinned
headers, text-heavy or control-dense content). One per view; keep heights consistent across split
panes.

```swift
public struct ScrollEdgeEffectStyle: Hashable, Sendable { static var automatic, hard, soft }
extension View {
    @available(macOS 26, *) func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View
    @available(macOS 26, *) func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> some View
    @available(macOS 26, *) func safeAreaBar(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View
}
```

Use `.scrollEdgeEffectStyle(.hard, for: .top)` on the dense Mapping table and Macros list; leave the
default on image-led pages (Screen, Lighting). Remove any custom "darken the top" overlays — they
fight the system effect (WWDC25 "Build a SwiftUI app with the new design").

### 2.5 Background extension under sidebar and inspector

**[Apple]** HIG › Sidebars: "Extend visually rich content beneath the sidebar. […] A background
extension effect mirrors adjacent content to give the impression of stretching it under the sidebar."
"Get to know the new design system" adds the constraint: "make sure any text and controls are layered
above to avoid unwanted visual distortion."

```swift
extension View {
    @available(macOS 26, *) public func backgroundExtensionEffect() -> some View
    @available(macOS 26, *) public func backgroundExtensionEffect(isEnabled: Bool) -> some View
}
```

Our use: the controller render on Status and Mapping pages, and the dark gradient "stage" behind it.
Apply it to the image/gradient only, never to the hotspot buttons on top of it (§7.4). Horizontal
scroll views that touch both edges automatically scroll under sidebar/inspector on macOS 26
(Landmarks sample) — relevant for a horizontal strip of GIF thumbnails on the Screen page.

### 2.6 Settings scene

macOS convention: preferences live in the `Settings` scene (⌘,), not in a sidebar section. Move the
helper install/remove and "About" out of the main window. WWDC25 "What's new in SwiftUI" shows a
`TabView` inside Settings with `.windowResizeAnchor(.top)` (macOS 26) so the window grows downward
when the selected tab changes height:

```swift
Settings {
    SettingsRoot()
        .frame(width: 520)
}

struct SettingsRoot: View {
    enum Tab { case general, helper, about }
    @State private var tab: Tab = .general
    var body: some View {
        TabView(selection: $tab.animation()) {
            Tab("General", systemImage: "gear", value: .general) { GeneralSettings() }
            Tab("Helper", systemImage: "lock.shield", value: .helper) { HelperSettings() }
            Tab("About", systemImage: "info.circle", value: .about) { AboutView() }
        }
        .modifier(ResizeAnchorTop())      // .windowResizeAnchor(.top) on macOS 26, no-op on 15
    }
}
```

Each tab is a `Form { … }.formStyle(.grouped)` (HIG › Adopting Liquid Glass: "Use SwiftUI forms with
the grouped form style to automatically update your form layouts").

### 2.7 Menu bar extra

`MenuBarExtra` (macOS 13+) gets Liquid Glass automatically when built with Xcode 26; the macOS 26
menu bar itself is transparent. Two styles: `.menu` (pull-down, what we have today) and `.window`
(arbitrary SwiftUI). For quick controls — LED brightness slider, slot switch, connection state — use
`.window`; keep it small and never duplicate the whole app (HIG › Menu bar extras). The label must be
a template/monochrome symbol so the system can tint it in the menu bar.

```swift
MenuBarExtra {
    QuickPanel().environment(model).frame(width: 300)
} label: {
    Image(systemName: model.connection == .none ? "gamecontroller" : "gamecontroller.fill")
}
.menuBarExtraStyle(.window)
```

Inside a `.window` extra the background is already system material/glass. Do **not** add
`.glassEffect()` to the panel or its groups (glass on glass). Use `Form(.grouped)` rows or plain
`VStack`s with `.padding()`.

---

## 3. Components

### 3.1 Buttons

```swift
@available(macOS 26, *) extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle
    static func glass(_ glass: Glass) -> Self            // e.g. .glass(.regular.tint(.orange))
}
@available(macOS 26, *) extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle {
    static var glassProminent: GlassProminentButtonStyle
}
```

| Style | When |
|---|---|
| `.borderedProminent` | the one primary action in a form/page; picks up accent + glass look on 26, correct on 15 |
| `.bordered` / default | everything else inside content (forms, cards) |
| `.borderless` | inline/tertiary actions, table row buttons |
| `.glass` | a control that *floats over content* (hotspot on the controller render, overlay on the screen preview) — macOS 26 only |
| `.glassProminent` | the primary action when it floats over content (rare for us) |

**[Apple]** HIG › Adopting Liquid Glass: "Instead of creating buttons with custom Liquid Glass effects,
you can adopt the look and feel of the material with minimal code by using one of the following button
style APIs." Shapes on macOS: mini/small/medium stay rounded-rectangle "which enables greater
horizontal density, while the large and extra-large sizes round out into a capsule shape" (WWDC25
AppKit session). Controls are slightly taller on 26 — don't hard-code heights. `.controlSize(.extraLarge)`
exists since macOS 14 but only becomes the "emphasize your most important action" capsule on 26.

### 3.2 Toggles, sliders, pickers, colour pickers

All system controls adopt the new look automatically. New on macOS 26 (verified):

```swift
Slider(value: $deadZone, in: 0...30, step: 1, neutralValue: 0) { Text("Dead zone") }          // ticks from step
Slider(value: $curve, in: -100...100, neutralValue: 0) { Text("Curve") }                     // fill anchors at 0
Slider(value: $brightness, in: 0...100) { Text("Brightness") } ticks: {                     // custom ticks
    SliderTick(25); SliderTick(50); SliderTick(75)
}
Stepper(value: $rate, format: .number)   // editable value field on 26 (3rd-party observation)
```

`neutralValue` is exactly right for stick curves and trigger dead zones where "0 = factory". Segmented
`Picker` for slot / mode selection; `Menu`/pop-up for long lists (mapping targets). `ColorPicker` for
LED colours is already correct; consider `supportsOpacity: false`. Keep `.controlSize(.small)` in the
inspector for density (WWDC25 macOS note).

### 3.3 Forms, lists, tables

Content layer → no glass. `Form { }.formStyle(.grouped)` for every settings-like page (already in the
app). Section headers now render in title-style capitalisation regardless of input; write them that
way. `Table` for the mapping matrix and macro steps (macOS 26 lists are up to 6× faster to load).

### 3.4 Cards / "insets" in the content layer

Use ordinary materials and semantic backgrounds, with **concentric** corners (§4.4):

```swift
struct PropertyCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 12))   // opaque-ish, adapts to appearance
    }
}
```

If the card sits on a coloured hero (the controller stage), `.regularMaterial` is acceptable in the
content layer — that is a *material*, not Liquid Glass, and still adapts to Reduce Transparency.

### 3.5 Sheets, popovers, alerts, confirmation dialogs

All are glass automatically. HIG › Adopting Liquid Glass: "Audit the backgrounds of sheets and
popovers. […] remove those custom background views." Don't call `.presentationBackground(...)` with
a material — the default is already correct; use it only to supply a *content* colour when you
intentionally want an opaque sheet. `confirmationDialog` should be anchored to its source control
("Specify the source of an action sheet"). Use it for destructive things: "Erase slot 3?", "Remove
helper?".

### 3.6 Badges, progress, status

`Button(...).badge(count)` works on toolbar items (macOS 26). `ProgressView(value:)` for GIF upload;
`.controlSize(.small)` spinner in the toolbar while `busy`. Connection state: an SF Symbol with
variable colour / draw effects (§4.3), not a custom glass pill.

### 3.7 Custom `.glassEffect` — the rule of thumb

Use it only when you are drawing something that behaves like a *floating control over content* that
has no system equivalent: the mapping hotspots on the controller render, an "X frames · 160×80"
caption floating on the screen preview. Never for cards, rows, page backgrounds or the sidebar footer.

```swift
extension View {
    @available(macOS 26, *) func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View
    @available(macOS 26, *) func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View
    @available(macOS 26, *) func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View
    @available(macOS 26, *) func glassEffectTransition(_ transition: GlassEffectTransition) -> some View  // .matchedGeometry (default), .materialize, .identity
}
public struct Glass: Equatable, Sendable {                // macOS 26
    static var regular: Glass; static var clear: Glass; static var identity: Glass
    func tint(_ color: Color?) -> Glass
    func interactive(_ isEnabled: Bool = true) -> Glass
}
public struct GlassEffectContainer<Content: View>: View { // macOS 26
    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content)
}
```

Notes: there is **no** `glassEffect(_:in:isEnabled:)` in the SDK (that URL is a 404); disable with
`.glassEffect(enabled ? .regular : .identity)`. `.interactive()` compiles on macOS 26 but the
press/bounce/shimmer feedback is documented for iOS in WWDC25; WWDC26 says macOS 27 makes custom
glass "interactive" for pointer input — so add `.interactive()` to hotspots now, it simply gets better
on 27. Always group multiple effects in one `GlassEffectContainer` ("glass cannot sample other glass",
and it is where morphing happens); apply `.glassEffect` **after** the modifiers that shape the view.

---

## 4. Typography, colour, icons, shape, motion

### 4.1 Typography

SF Pro via system text styles only. macOS has **no Dynamic Type** (HIG › Typography), but text styles
still track the user's appearance and the 26 metrics. macOS sizes (HIG table): Large Title 26,
Title 1 22, Title 2 17, Title 3 15, Headline 13 bold, Body 13, Callout 12, Subheadline 11,
Footnote 10, Caption 10. The 2025 design makes key text "bolder and left-aligned" (alerts,
onboarding). Hierarchy for a page: `.largeTitle` is *not* used inside the window (the toolbar
carries the title); page sections use `.title2` / `.headline`, values `.body`, help text `.footnote`
with `.foregroundStyle(.secondary)` — which is what `Views.swift` already does. Add emphasis with
`.fontWeight(.semibold)`, never a custom font.

### 4.2 Colour

- **Semantic colours everywhere** (`.primary`, `.secondary`, `.background`, `.fill`, `Color(nsColor: .controlBackgroundColor)`): they adapt to light/dark, Increase Contrast and desktop tinting.
- **Accent colour** in the asset catalog (`AccentColor`). HIG › Color: macOS applies it "when the current value in General > Accent color settings is multicolor"; otherwise the user's choice wins — so never assume the accent is your brand colour. It drives the prominent button, selection and sidebar icons.
- **Brand colour goes in the content layer**, not in glass: a Flydigi-ish gradient behind the controller render is fine; tinting toolbar buttons is not. HIG › Color: "If your app already has bright, colorful content in the content layer, prefer using the default monochromatic appearance of toolbars."
- Custom colours: provide light/dark **and** high-contrast variants in the asset catalog (HIG › Adopting Liquid Glass › Controls). Contrast ≥ 4.5:1, aim for 7:1 on small text (HIG › Dark Mode).
- LED colour swatches are *data*, not UI colour — show them in the content layer (a strip preview), never as tint on glass.

### 4.3 Icons and SF Symbols 7

SF Symbols 7 (macOS 26): Draw On/Off animations, variable draw, gradient rendering, better Magic Replace.

```swift
Image(systemName: "gamecontroller.fill")
    .symbolEffect(.drawOn, isActive: model.connection != .none)     // Symbols.DrawOnSymbolEffect, macOS 26
Image(systemName: "battery.100percent")
    .symbolEffect(.variableDraw(fillValue: level))                  // progress-like fill
Image(systemName: "light.max")
    .symbolColorRenderingMode(.gradient)                             // SwiftUICore, macOS 26 — larger sizes only
    .foregroundStyle(.tint)
Image(systemName: isUploading ? "arrow.up.circle.fill" : "checkmark.circle.fill")
    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
```

Use one symbol per sidebar section (see §2.1), consistent across window, menu bar extra and
toolbar. HIG › Toolbars: "Provide an accessibility label for every icon"; when no clear glyph exists
"a text label is always the better choice."

**App icon.** Build it in **Icon Composer** (Xcode › Open Developer Tool) as a `.icon` file with up to
four groups/layers; Xcode renders default/dark/clear/tinted variants and auto-generates flat icons
for macOS 15 (**[Apple]** "Creating your app icon using Icon Composer"). HIG › App icons: "Let the
system handle blurring and other visual effects"; "Prefer clearly defined edges in foreground
layers"; "avoid replicating UI components"; "Don't use replicas of Apple hardware." A stylised Apex 4
silhouette (foreground) over a solid/gradient background is exactly the recommended shape. Note the
Icon Composer doc: on OS versions earlier than 27 the Refraction setting has no visible effect —
design for 26 first, preview both with the 26/27 toggle.

### 4.4 Spacing and concentric corners

**[Apple]** "Get to know the new design system": three shape types — fixed radius, capsule, and
concentric ("radius calculated by subtracting padding from parent's"); "Keep an eye out for corners
that feel too pinched — or flared." Windows with toolbars use a larger radius that wraps
concentrically around the glass toolbar (AppKit session). macOS 27 unifies the corner radius across
all windows (automatic).

```swift
@available(macOS 26, *)
public struct ConcentricRectangle: Shape, Animatable {
    init()
    init(corners: Edge.Corner.Style, isUniform: Bool = false)
    init(topLeadingCorner: Edge.Corner.Style = .concentric, topTrailingCorner: … , bottomLeadingCorner: … , bottomTrailingCorner: …)
}
// Edge.Corner.Style: .fixed(CGFloat) | .concentric | .concentric(minimum: Edge.Corner.Style?)
// Shape helper: .rect(corners: .concentric(minimum: .fixed(12)))
```

Pattern: a card that hugs the window/sheet edge uses `.rect(corners: .concentric(minimum: .fixed(12)))`
— concentric when nested, 12 pt when standalone. Interior padding follows system metrics (HIG:
"Prefer to use standard spacing metrics instead of overriding them"); we use 8/12/16/20.

### 4.5 Motion: morphing between glass elements

Inside one `GlassEffectContainer`, views with `.glassEffectID(_:in:)` in the same `@Namespace` morph
into each other when they appear/disappear under `withAnimation`. Use it for: the selected mapping
hotspot expanding into its label chip; the "Apply" chip morphing into a progress chip.

```swift
@available(macOS 26, *)
struct HotspotOverlay: View {
    @Namespace private var ns
    @Binding var selected: PadButton?
    let buttons: [PadButton]

    var body: some View {
        GlassEffectContainer(spacing: 24) {
            ForEach(buttons) { b in
                Button { withAnimation(.snappy) { selected = b } } label: {
                    Image(systemName: b.symbol).frame(width: 28, height: 28)
                }
                .buttonStyle(.glass(.regular.interactive()))
                .glassEffectID(b.id, in: ns)
                .position(b.anchor)                  // over the controller render
            }
            if let s = selected {
                Text(s.mappedActionName)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .glassEffect(.regular.tint(.accentColor))   // the only tinted glass on the page
                    .glassEffectID("label", in: ns)
                    .position(s.anchor.applying(.init(translationX: 0, y: -36)))
            }
        }
    }
}
```

Respect Reduce Motion (`@Environment(\.accessibilityReduceMotion)`) by using `.glassEffectTransition(.materialize)`
or no animation.

---

## 5. Compatibility: macOS 15 today, macOS 26 first-class, macOS 27 ready

### 5.1 Build settings

- Deployment target macOS 15, SDK = latest (26). Everything system-provided upgrades automatically on 26.
- **Do not** set `UIDesignRequiresCompatibility`. **[Apple]** Info.plist reference: it is a Boolean valid
  on iOS/iPadOS/macOS/tvOS 26 that "displays the app as it looks when built against previous versions
  of the SDKs", meant to be used "temporarily […] while reviewing and refining your app's UI", and
  "The system ignores this key when you build for […] macOS 27 or later." It exists for legacy apps
  with heavy custom chrome; ours is new and has none.

### 5.2 Conditional modifiers

`if #available` cannot be used inline in a modifier chain, so wrap it in `@ViewBuilder` extensions.
Keep them few and semantic (name the *intent*, not the API):

```swift
import SwiftUI

extension View {
    /// Floating chip over content: Liquid Glass on 26, ordinary material on 15.
    @ViewBuilder
    func floatingChip<S: Shape>(tint: Color? = nil, in shape: S = Capsule()) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.separator))
        }
    }

    /// Hero image / gradient that should visually continue under sidebar & inspector.
    @ViewBuilder
    func extendsUnderChrome() -> some View {
        if #available(macOS 26, *) { self.backgroundExtensionEffect() } else { self }
    }

    /// Dense content that scrolls under the toolbar.
    @ViewBuilder
    func hardScrollEdge() -> some View {
        if #available(macOS 26, *) { self.scrollEdgeEffectStyle(.hard, for: .top) } else { self }
    }

    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(macOS 26, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }
}

struct ResizeAnchorTop: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) { content.windowResizeAnchor(.top) } else { content }
    }
}
```

Whole views that only make sense on 26 (`HotspotOverlay` with `GlassEffectContainer`) are declared
`@available(macOS 26, *)` and instantiated in an `if #available` branch with a plain fallback
(bordered buttons over the render). `ToolbarSpacer` inside a `ToolbarContent` builder also needs
`if #available` (it is `ToolbarContent`, so the builder accepts the conditional).

### 5.3 What the fallback must *not* do

Do not fake glass on macOS 15 with manual blur + gradient + white stroke (a common third-party
recipe). It looks wrong next to real macOS 15 chrome and becomes a maintenance trap. On 15 the
correct fallback is the pre-26 idiom: system materials (`.regularMaterial`, `.bar`) and standard
button styles.

---

## 6. Anti-patterns Apple calls out explicitly

1. **Glass on glass.** "Always avoid glass on glass. […] When placing elements on top of Liquid Glass, avoid applying the material to both layers. Instead, use fills, transparency, and vibrancy for the top elements." (Meet Liquid Glass). → No `.glassEffect` inside the sidebar, inspector, toolbar, popovers or the menu bar extra window.
2. **Glass in the content layer.** Lists, tables, forms, cards, text. (HIG › Materials).
3. **Tinting everything.** "When every element is tinted, nothing stands out." One prominent action per surface.
4. **Custom backgrounds behind bars/controls.** "Any custom backgrounds and appearances you use in these elements might overlay or interfere with Liquid Glass." Remove `NSVisualEffectView`/`.background(.bar)` from sidebars and toolbars.
5. **Fake glass.** Custom blur/gradient stacks imitating the material (see §5.3); "make sure to apply the material directly to the control, not its inner views."
6. **Non-concentric / pinched corners** and hard-coded control heights (controls grew on 26).
7. **Mixing regular and clear**; using clear without a dimming layer.
8. **Text + symbol on one shared toolbar background** ("could be perceived as single button"); more than ~3 toolbar groups; manual overflow menus; hiding a toolbar item's *view* instead of the item (`ToolbarContent.hidden(_:)`).
9. **Content intersecting glass at rest**: "In steady states […] avoid intersections between content and Liquid Glass. Instead, reposition or scale the content."
10. **Critical actions at the bottom of a sidebar** (HIG › Sidebars, macOS: windows are often moved so the bottom is off-screen) — informative status is fine, the *only* Apply button is not.
11. **App-specific appearance setting** (HIG › Dark Mode) — see §8.
12. **Scroll edge effects where nothing floats**; decorative dividers in addition to them.

---

## 7. Applying it to the Apex 4 app

### 7.1 Screen map

```
Window "Apex 4"  (NavigationSplitView, min 900×600)
├─ Sidebar (glass, system)                 ├─ Detail (content layer)                       ├─ Inspector (glass, system, toggle)
│  Status                                  │  Status: hero render + PropertyCards           │  Mapping: selected button →
│  Profiles & Mapping                      │  Profiles & Mapping: render + hotspots, Table  │    target picker, turbo, macro,
│  Sticks & Triggers                       │  Sticks & Triggers: live stick viz + sliders   │    per-slot overrides (Form .grouped,
│  Macros                                  │  Macros: List/Table + step editor              │    controlSize .small)
│  Lighting                                │  Lighting: LED strip preview + Form            │  Lighting: per-group colours
│  Screen                                  │  Screen: 160×80 preview, drop zone, library    │  Screen: fit/fill/crop, frame period
│  ─ footer: ControllerStatusFooter ─      │                                                │
Toolbar: [sidebar toggle] [Slot 1|2|3|4 segmented] … [Refresh][Revert] · [Apply to Controller ▸prominent] [Inspector]
Settings scene (⌘,): General · Helper · About
MenuBarExtra (.window): connection, slot switch, LED brightness, "Open Apex 4…", Quit
```

Rationale: Settings leaves the sidebar (macOS convention; the helper install is a one-time system
task); the slot picker is global context so it lives in the toolbar; Apply is the single prominent,
trailing action and is also a menu bar command (⌘S) because toolbars are customisable/hideable.

### 7.2 Sidebar footer (status, not glass)

```swift
struct ControllerStatusFooter: View {
    @Environment(ControllerModel.self) private var model
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.connection == .none ? "gamecontroller" : "gamecontroller.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.connection == .none ? .secondary : Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.connection == .none ? "Not connected" : "Apex 4")
                    .font(.callout.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.busy { ProgressView().controlSize(.mini) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        // No background: the sidebar already IS the glass. A Divider is enough.
        .overlay(alignment: .top) { Divider() }
    }
    private var subtitle: String {
        switch model.connection {
        case .none: "Plug in or power on"
        case .dinput: model.info?.wired == false ? "2.4 GHz · DInput" : "USB · DInput"
        case .xinput: model.info?.wired == false ? "2.4 GHz · XInput" : "USB · XInput"
        }
    }
}
```

### 7.3 Detail page skeleton

```swift
struct DetailHost: View {
    let section: Section
    var body: some View {
        ScrollView {
            switch section {
            case .status:   StatusPage()
            case .profiles: MappingPage()
            case .sticks:   SticksPage()
            case .macros:   MacrosPage()
            case .lighting: LightingPage()
            case .screen:   ScreenPage()
            }
        }
        .hardScrollEdge()                                   // §5.2 (no-op on 15)
        .navigationTitle(section.title)
        .navigationSubtitle(subtitle)                       // e.g. "Slot 2 · unsaved changes"
    }
}
```

### 7.4 Hero "stage" (the one place with brand colour) + hotspots

```swift
struct ControllerStage<Overlay: View>: View {
    @ViewBuilder var overlay: Overlay
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color("StageTop"), Color("StageBottom")],   // asset colours with dark/light/high-contrast variants
                           startPoint: .top, endPoint: .bottom)
            Image("apex4-render").resizable().scaledToFit().padding(32)
        }
        .extendsUnderChrome()                               // backgroundExtensionEffect on 26 (§2.5)
        .overlay { overlay }                                // controls stay ABOVE the extension effect
        .frame(minHeight: 320)
        .clipShape(.rect(corners: .concentric(minimum: .fixed(16))))   // macOS 26 API — guard for 15 if used
    }
}
```

The gradient is *content* and may be as dark and "gaming" as we like; the hotspots on top are glass
(§4.5) and adapt to it automatically.

### 7.5 Property card in the inspector / lighting page

```swift
struct DeadZoneCard: View {
    @Binding var left: Double
    @Binding var right: Double
    var body: some View {
        PropertyCard(title: "Stick Dead Zone") {
            Slider(value: $left,  in: 0...30, step: 1, neutralValue: 0) { Text("Left") }  minimumValueLabel: { Text("0") } maximumValueLabel: { Text("30") }
            Slider(value: $right, in: 0...30, step: 1, neutralValue: 0) { Text("Right") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("30") }
            Text("Inputs below the dead zone are ignored. 0 restores the factory value.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
```

(`neutralValue:` is macOS 26; on 15 fall back to the classic `Slider(value:in:step:label:)` via
`if #available`.)

### 7.6 Migration from the current `Views.swift`

1. Replace the `TabView` shell in `ContentView` with `MainWindow` (§2.1); keep `StatusView`, `LightingView`, `ScreenView` as detail pages.
2. Move `SettingsView` into a `Settings` scene (§2.6); add `SettingsLink()` to the menu bar extra.
3. Move "Refresh" into a `ToolbarItemGroup`; make "Apply and save to controller" the toolbar's prominent action with `⌘S`; keep the in-page button for discoverability but as `.bordered`.
4. Replace the error overlay (`.thinMaterial` pill at the bottom of the window) with a non-glass inline banner in the content layer or a `confirmationDialog`/alert for actionable failures.
5. Drop `.padding()` on the whole `TabView`; let the content layer touch the edges so scroll edge effects and background extension work.
6. Produce `AppIcon.icon` in Icon Composer; remove the asset-catalog icon.

---

## 8. Dark, gaming-flavoured, still a Mac app

Flydigi's Space Station is a fixed dark UI. On macOS the HIG is unambiguous: **[Apple]** HIG › Dark
Mode: people "generally expect all apps and games to respect their preference"; "Avoid offering an
app-specific appearance setting"; and "In rare cases, consider using only a dark appearance in the
interface. For example, it can make sense for an app that supports immersive media viewing." A
controller configuration utility with forms and tables is not that case.

### 8.1 Option A — force `.preferredColorScheme(.dark)` on the window

Pros: predictable screenshots, brand parity with Flydigi, colour pickers/LED swatches always read
against dark. Cons: violates HIG › Dark Mode; the whole chrome (toolbar glass, sidebar, sheets,
menus spawned from the window) goes dark in a light desktop and looks foreign; Liquid Glass loses
half of its adaptivity (it exists to pick up the surroundings); **[3rd-party, nilcoalescing]** on
macOS `.preferredColorScheme(.light)` is not honoured and once set to `.dark` you cannot return to
`nil`/system at runtime; early-26 betas had a bug with `.hard` scroll edge + forced dark (fixed in
beta 3 — evidence the combination is less tested). Not recommended.

### 8.2 Option B (recommended) — system appearance + dark *content* stage

Keep the app appearance-neutral and put the "gaming" feel where the HIG wants brand colour: the
content layer.

- The **hero stage** (§7.4) is always dark: deep gradient (`StageTop`/`StageBottom` asset colours with light/dark/high-contrast variants; in light mode a slightly lighter dark), controller render, LED strip preview and the 160×80 screen preview all sit on it. Glass hotspots and toolbar adapt to it automatically — that *is* the Liquid Glass showcase.
- Everything else (forms, tables, inspector) uses semantic colours so it follows the user.
- **Accent colour**: pick a Flydigi-adjacent hue (their orange/amber) as `AccentColor`; the system applies it only when the user's accent is Multicolor — accept that.
- In dark mode, use `.background.secondary` cards over `.background`; macOS has no elevated/base pair like iOS, so rely on material and separators, not brightness steps.
- Desktop tinting: with the graphite accent, window backgrounds pick up desktop colour; HIG › Dark Mode suggests "some transparency in custom component backgrounds" — our semantic backgrounds already do this; the stage gradient should be opaque by design.
- Offer **no** in-app appearance switch. If users ask, point to System Settings; a "Stage: dark / follow system" toggle for the hero only is acceptable because it is content, not chrome.

### 8.3 Test matrix before shipping

Light/Dark × Increase Contrast × Reduce Transparency × Liquid Glass "Clear/Tinted" (26.1+) × Reduce
Motion; plus inactive-window state (macOS 27 dims toolbar icons/text automatically; `@Environment(\.appearsActive)` if we need to dim custom things).

---

## 9. Checklist

- [ ] `NavigationSplitView` + `.inspector`, no custom sidebar/toolbar backgrounds
- [ ] ≤ 3 toolbar groups, `ToolbarSpacer(.fixed)` between, one prominent trailing action, every item also in the menu bar
- [ ] Settings scene, not a sidebar item
- [ ] `.formStyle(.grouped)` everywhere; Title-Style Section Headers
- [ ] `.glassEffect` only on floating controls over content, inside one `GlassEffectContainer`, ≤ 1 tint per surface
- [ ] `backgroundExtensionEffect` on the stage only; `.hard` scroll edge on dense pages
- [ ] Concentric corners for edge-hugging cards; no hard-coded control heights
- [ ] All 26 APIs behind `#available`, fallbacks use pre-26 idioms, no fake glass, no `UIDesignRequiresCompatibility`
- [ ] Icon Composer `.icon`; SF Symbols only; accessibility labels on every icon button
- [ ] Follow system appearance; brand lives in the stage gradient + accent colour
- [ ] Accessibility matrix (§8.3) passed

---

## 10. Sources

**Apple — primary**

- **[Apple]** HIG › Materials (Liquid Glass section) — https://developer.apple.com/design/human-interface-guidelines/materials
- **[Apple]** Adopting Liquid Glass (Technology Overviews) — https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- **[Apple]** Applying Liquid Glass to custom views — https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- **[Apple]** Landmarks: Building an app with Liquid Glass (+ sub-articles on background extension, horizontal scrolling under sidebar/inspector, refining toolbars) — https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass
- **[Apple]** HIG › Color (Liquid Glass color, macOS accent) — https://developer.apple.com/design/human-interface-guidelines/color
- **[Apple]** HIG › Toolbars — https://developer.apple.com/design/human-interface-guidelines/toolbars
- **[Apple]** HIG › Sidebars — https://developer.apple.com/design/human-interface-guidelines/sidebars
- **[Apple]** HIG › Tab bars — https://developer.apple.com/design/human-interface-guidelines/tab-bars
- **[Apple]** HIG › Dark Mode — https://developer.apple.com/design/human-interface-guidelines/dark-mode
- **[Apple]** HIG › Typography (macOS text styles; no Dynamic Type on macOS) — https://developer.apple.com/design/human-interface-guidelines/typography
- **[Apple]** HIG › App icons — https://developer.apple.com/design/human-interface-guidelines/app-icons
- **[Apple]** Creating your app icon using Icon Composer — https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
- **[Apple]** Info.plist › `UIDesignRequiresCompatibility` — https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility
- **[Apple]** WWDC25 219 "Meet Liquid Glass" — https://developer.apple.com/videos/play/wwdc2025/219/
- **[Apple]** WWDC25 356 "Get to know the new design system" — https://developer.apple.com/videos/play/wwdc2025/356/
- **[Apple]** WWDC25 323 "Build a SwiftUI app with the new design" — https://developer.apple.com/videos/play/wwdc2025/323/
- **[Apple]** WWDC25 310 "Build an AppKit app with the new design" (macOS window/sidebar/inspector specifics) — https://developer.apple.com/videos/play/wwdc2025/310/
- **[Apple]** WWDC25 256 "What's new in SwiftUI" — https://developer.apple.com/videos/play/wwdc2025/256/
- **[Apple]** WWDC25 337 "What's new in SF Symbols 7" — https://developer.apple.com/videos/play/wwdc2025/337/
- **[Apple]** WWDC26 269 "What's new in SwiftUI" (macOS 27 toolbar APIs, interactive glass on macOS, `appearsActive`) — https://developer.apple.com/videos/play/wwdc2026/269/
- **[Apple]** Apple Newsroom, "Apple introduces a delightful and elegant new software design" (2025-06-09) — https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/
- **[Apple]** Developer Forums thread 799607 (DTS on the compatibility key timeline) — https://developer.apple.com/forums/thread/799607
- **[Apple]** Developer Forums thread 790861 (`.hard` scroll edge + forced dark, fixed in 26 beta 3) — https://developer.apple.com/forums/thread/790861
- **[Apple]** macOS 26 SDK module interfaces, Xcode 26.6 (17F113): `SwiftUI.swiftinterface`, `SwiftUICore.swiftinterface`, `Symbols.swiftinterface` — local, used to verify every signature and `@available` above.

**Third-party**

- **[3rd-party]** Swift with Majid — "Glassifying custom SwiftUI views" (2025-07-16), "…Groups" (2025-07-23), "Glassifying toolbars" (2025-07-01), "Taking control of toolbar items" (2026-06-23) — https://swiftwithmajid.com
- **[3rd-party]** Nil Coalescing — "Adaptive SwiftUI toolbars in iOS 27" — https://nilcoalescing.com/blog/AdaptiveSwiftUIToolbarsInIOS27/ ; "Reading and setting color scheme in SwiftUI" (macOS `.preferredColorScheme` caveats) — https://nilcoalescing.com/blog/ReadingAndSettingColorSchemeInSwiftUI/
- **[3rd-party]** TrozWare — "SwiftUI for Mac 2025" (macOS 26 `sidebarAdaptable`, steppers, glass buttons) — https://troz.net/post/2025/swiftui-mac-2025/
- **[3rd-party]** Donny Wals — "Opting your app out of the Liquid Glass redesign with Xcode 26" — https://www.donnywals.com/opting-your-app-out-of-the-liquid-glass-redesign-with-xcode-26/
- **[3rd-party]** MacRumors — "Apple Releases macOS Tahoe 26.1 With New Liquid Glass Setting" — https://www.macrumors.com/2025/11/03/apple-releases-macos-tahoe-26-1/
- **[3rd-party]** Neowin / Cult of Mac / Stuff — WWDC26 coverage of macOS 27 Liquid Glass changes (transparency slider, unified window corner radius, edge-to-edge sidebars, coloured sidebar icons) — https://www.neowin.net/news/apple-finally-brings-the-slider-for-liquid-glass-and-many-other-changes/ , https://www.cultofmac.com/news/liquid-glass-changes-ios-27-macos-27 , https://www.stuff.tv/news/ios-27-macos-golden-gate-liquid-glass-changes/
- **[3rd-party]** Create with Swift — "Morphing glass effect elements into one another with glassEffectID" — https://www.createwithswift.com/morphing-glass-effect-elements-into-one-another-with-glasseffectid/

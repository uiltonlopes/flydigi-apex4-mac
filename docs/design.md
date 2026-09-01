# Apex 4 for macOS — design system

The one page every UI change is checked against. Backed by two research documents:
[`design-liquid-glass.md`](design-liquid-glass.md) (Apple's Liquid Glass / macOS 26 rules and APIs, all
verified against the SDK) and [`design-ss4-reference.md`](design-ss4-reference.md) (what Space Station 4
looks like and how it names things). Decided 2026-09-01.

## 1. Principles

1. **A Mac app first.** Native chrome — sidebar, toolbar, inspector, Settings scene, menu bar extra —
   built from system controls. Users should feel "this is how a Mac app works", not "this is a port".
2. **The gaming feel lives in the content, not in the chrome.** Brand colour, the dark stage with the
   controller render, LED and screen previews are *content*; Liquid Glass floats over it. This is exactly
   where the HIG puts colour and identity — and it is what makes Liquid Glass look good.
3. **Same map, same words as Space Station.** A Windows user must recognise the sections (Profiles,
   Buttons, Sticks, Triggers, Motion, Macros, Lighting, Screen) and the labels (Center dead zone, Grip
   vibration, Onboard configs → Profiles…). Physical button names exactly as printed on the pad.
4. **Follow the user.** System appearance (light/dark), accent colour, Dynamic Type, Reduce Transparency,
   Increase Contrast, Reduce Motion — nothing in the UI may *depend* on translucency or colour alone.
5. **One primary action per screen**: "Apply to Controller" (⌘S). Everything else is secondary. Changes
   are staged locally and the toolbar subtitle says "unsaved changes".
6. **macOS 15 works, macOS 26 shines.** Every 26-only API sits behind a semantic helper with a native
   pre-26 fallback (`.regularMaterial`, `.borderedProminent`); never fake glass.

## 2. Shell and information architecture

```
Window "Apex 4" — NavigationSplitView (min 900×600), state restored per user
Sidebar (system glass)          Detail (content)                                  Inspector (system glass, ⌥⌘I)
  Status                          hero stage + property cards                       —
  Profiles & Buttons              stage + button hotspots · mapping table           selected button: target, turbo, macro
  Sticks & Triggers               live stick/trigger viz · dead zones · curves      ForceAdapt mode + per-game preset
  Motion                          gyro → stick, curve, dead-zone compensation       —
  Macros                          list · step editor (timeline)                      step details
  Lighting                        LED strip preview on stage · Form                  per-group colours
  Screen                          160×80 preview · drop zone · online library        fit/fill/crop · frame period
  ── footer: ControllerStatusFooter (connection, link, battery, busy) ──
Toolbar: [Slot ①②③④ segmented, principal] ⋯ [Refresh][Revert] · ToolbarSpacer(.fixed) · [Apply to Controller ▸ prominent] [Inspector]
Settings (⌘,): General (appearance of the stage, language) · Helper (install/remove, status) · About
MenuBarExtra (.window): connection + battery, slot switch, LED brightness, "Open Apex 4…", Quit
```

- Settings is **not** a sidebar item (macOS convention; helper install is a one-time system task).
- The slot picker is global context → toolbar. Reading a slot moves the pad's "current" cursor, so the
  model re-applies the user's chosen slot after enumerating (protocol quirk, see `protocol.md`).
- Every toolbar item is also a menu-bar command (toolbars are customisable/hideable).
- ≤ 3 toolbar groups. No custom toolbar or sidebar backgrounds, ever.

## 3. Colour

| Role | Token / value | Notes |
|---|---|---|
| Chrome, forms, tables, text | **system semantic colours** (`.background`, `.background.secondary`, `.primary/.secondary`, `.separator`) | follow appearance; no hard-coded greys |
| Accent | `AccentColor` asset = Flydigi-adjacent **electric blue** `#285AFA` (light) / `#3E6BFF` (dark) | the system uses it only when the user's accent is Multicolor — accept that |
| Stage gradient (hero) | `StageTop` `#1C1D1F` → `StageBottom` `#0E0F11` (dark); light mode: `#26272A` → `#181818`; high-contrast variants slightly lighter | **always dark, opaque**; the one place with SS4's neutrals |
| Stage accent glow | accent at 25 % behind the controller render | never as text or control colour |
| LED preview | actual LED colours from the config (0–100 % → sRGB) | content, not UI |
| Status | `.green` connected · `.orange` wireless/low battery · `.red` errors | with an icon + text, never colour alone |

Rules: at most **one tinted glass element per surface** (the prominent Apply button); no tinted toolbar
icons; no brand colour on chrome; no fixed dark chrome (`preferredColorScheme(.dark)` is not used).

## 4. Typography, icons, shape, motion

- **SF Pro via system text styles** only (`.largeTitle` for the page hero, `.title2` for section titles,
  `.body`, `.callout` in property cards, `.caption` for hints). No custom fonts. pt-BR and EN strings via
  String Catalog; Chinese profile titles from the pad are displayed as-is (the system font falls back).
- **SF Symbols 7**: `gamecontroller.fill` (connection), `battery.*`, `light.max` (lighting),
  `photo.on.rectangle` (screen), `dial.medium` (sticks), `arrow.trianglehead.2.clockwise` (refresh),
  `checkmark.circle.fill` (apply). Hierarchical rendering; `variableColor`/`drawOn` animations only for
  connection/battery state; every icon-only button has an accessibility label.
- **App icon**: Icon Composer `.icon` (≤ 4 groups: stage gradient, controller silhouette, blue glow,
  highlight) so it gets the system's glass treatment on 26; PNG fallback for 15.
- **Shape**: system corner radii; `.rect(corners: .concentric)` for edge-hugging cards on 26 (12 pt
  fallback). Spacing scale 4/8/12/16/24/32 — the same steps SS4 uses, so densities feel familiar.
- **Motion**: default system animations; `glassEffectID` morphing between button hotspot and the
  selected-button chip; `withAnimation` only on user actions; respect Reduce Motion.

## 5. Components — what to use where

| Need | Use |
|---|---|
| Settings-like pages (Lighting, Motion, Screen options) | `Form` + `.formStyle(.grouped)`, Title-Style Section Headers |
| Button mapping | hero render + `HotspotOverlay` (one `GlassEffectContainer`, chips `floatingChip()`), plus a `Table` of all 32 keys for keyboard users |
| Dead zones, ranges | `Slider(value:in:step:)`; paired min/max as two sliders + numeric `TextField` with `.monospacedDigit()` |
| Sensitivity curves | custom `Canvas` chart with draggable control points; read-only in non-custom curve modes (SS4 hint "curve not adjustable in this mode") |
| Mode/preset choice | segmented `Picker` (≤ 5 options) or `Menu` picker |
| Colours | `ColorPicker(supportsOpacity: false)` + swatch row of the SS4 defaults |
| Live input (sticks, triggers, gyro) | GameController framework → `Canvas` gauges; 60 Hz, no glass |
| Progress (screen upload) | `ProgressView(value:)` with ETA text; the Apply button becomes disabled, not hidden |
| Destructive (restore defaults, remove helper) | `confirmationDialog`, `.destructive` role |
| Errors | inline `Label` with `exclamationmark.triangle.fill` under the affected control; toolbar subtitle for global state; no modal alerts for routine failures |
| Primary action | `prominentGlassButton()` — one per window |

Custom `.glassEffect` is allowed **only** for controls floating over the stage (hotspots, chip). Never
inside sidebar, inspector, toolbar, popovers, sheets or the menu bar extra (glass-on-glass).

## 6. Compatibility helpers (the only place `#available(macOS 26)` appears)

`floatingChip(tint:in:)` · `extendsUnderChrome()` · `hardScrollEdge()` · `prominentGlassButton()` ·
`ResizeAnchorTop` — defined once in `App/DesignSystem.swift`, semantic names, native fallbacks. Views that
only make sense on 26 (`HotspotOverlay`) are `@available(macOS 26, *)` with a bordered-buttons fallback.
Build with the macOS 26 SDK, deployment target 15.0. Do **not** ship `UIDesignRequiresCompatibility`.

## 7. Accessibility matrix (run before every release)

Light · Dark · Increase Contrast · Reduce Transparency · Reduce Motion · Dynamic Type +2 steps ·
keyboard-only (every hotspot reachable via the Table; ⌘S applies) · VoiceOver on the mapping page.
Glass may become opaque or frosted — no state may be conveyed only by translucency, colour or motion.

## 8. Migration plan from the current `Views.swift`

1. Replace `TabView` with `NavigationSplitView` + sidebar sections + `ControllerStatusFooter`; move
   Settings to a `Settings` scene; add the slot picker and Apply/Revert to the toolbar with a staged
   `ProfileDraft` model (dirty tracking, ⌘S).
2. Build the **stage** (`StageView`: gradient + controller render placeholder + `extendsUnderChrome()`).
3. Profiles & Buttons page (hotspots + table + inspector) on top of `GamepadConfig`.
4. Port Lighting and Screen onto the stage (LED strip preview, 160×80 preview, online library).
5. Sticks & Triggers, Motion, Macros.
6. Icon Composer icon, String Catalog (EN, pt-BR), accessibility pass.

## 9. Checklist (copy into every UI PR)

- [ ] `NavigationSplitView` + `.inspector`; no custom sidebar/toolbar backgrounds
- [ ] ≤ 3 toolbar groups, one prominent trailing action, all items also in the menu bar
- [ ] Forms `.grouped`; system text styles; SF Symbols only, labelled
- [ ] Glass only on floating controls over the stage, inside one container, ≤ 1 tint per surface
- [ ] Brand colour only in stage + accent; follows system appearance
- [ ] 26 APIs behind the helpers; fallbacks native; no fake glass
- [ ] Concentric corners for edge cards; spacing on the 4/8/12/16/24/32 scale
- [ ] Vocabulary matches `design-ss4-reference.md` §4; physical button names as printed
- [ ] Accessibility matrix passed; keyboard path for every mouse-only interaction

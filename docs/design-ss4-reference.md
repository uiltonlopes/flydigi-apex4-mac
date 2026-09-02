# Space Station 4 — visual reference (what users already know)

Extracted from Space Station 4.2.2.3's renderer bundle (CSS variables, theme tokens, locale strings). This
is **reference only**: none of Flydigi's assets, CSS or copy is used in this project. The goal is that an
Apex 4 owner coming from Windows finds the same *information architecture and vocabulary*, while the app
itself looks and behaves like a native macOS 26 app (see `design-liquid-glass.md` and `design.md`).

## 1. Look & feel in one paragraph

Dark UI (near-black neutrals), one strong **brand accent** per connected device (Apex 4 "normal" theme:
electric blue `#285AFA`; licensed editions swap it — EVA red `#FF2B3A`, Castorice purple `#8D4CB9`…),
white text with two grey tiers, cards with 8–12 px radii on a flat dark background, a large hero
illustration of the controller with the buttons as click targets for mapping, and Ant Design controls
(sliders, segmented pickers, switches). Typography is the system UI font (Noto Sans SC for CJK).

## 2. Tokens

| Token | Value | Use |
|---|---|---|
| `neutral-900` | `#181818` | darkest background ("bg-darkest", disabled buttons) |
| `neutral-800` | `#1C1D1F` | second-level background (cards) |
| `neutral-700` | `#212225` | third-level background (nested panels) |
| `neutral-600` | `#26272A` | option/grey backgrounds |
| `neutral-500` | `#2E3035` | normal button, borders, disabled text |
| `neutral-400` | `#7E858E` | secondary ("grey normal") text, grey lines |
| `neutral-300` | `#9CA3AC` | lighter grey text |
| `neutral-100/200` | `#FFFFFF` | primary text, hover borders |
| `brand-600` | `#285AFA` (normal) | highlight button hover, dark-blue backgrounds |
| `brand-500` | 90 % brand + 10 % white | **highlight**: selected state, text highlight, highlight lines/borders |
| `brand-100…400` | brand mixed with white 20–80 % | tints |
| `brand-700…900` | brand mixed with black 20–60 % | shades |
| `red` / `yellow` / `green` | `#F04040` / `#FFBA60` / (green) | danger / warning / success |
| spacing | 4 · 8 · 12 · 16 · 24 · 32 · 36 px | xxs…2xl |
| radius | 6 · 8 · 12 · 16 px | xs…l (Ant default controls 2–4 px) |
| font | `-apple-system, BlinkMacSystemFont, …` + Noto Sans SC | system UI font |

Per-device themes: `[data-theme=normal] #285AFA`, `eva #FF2B3A`, `mm #D7000F`, `castorice #8D4CB9`,
`fp4_gs #A73B1E`, `fp4_mrfz #E2E200`, `k5_gs #422ED5`, `f5_dbz #FF4000`, `f5_hk3 #CC5C83`,
`bs2pro_eva #FFB23C`. Device cards use a dark illustration keyed to the edition (the EVA card is a purple
line-art mecha on black).

## 3. Information architecture

Side navigation (routes): **Home / Device Center** (`/home`, `/deviceCenter`: device list, "My Device",
"Add device"), **Screen** (`/screenPage`), **Adaptive Trigger** (`/adaptTrigger`: per-game presets,
Standard vs DS mode, "Games Supported"), **Keyboard** (`/keyboard`, Windows-only driver),
**Controller test** (`/handleTestPage`: "Advanced test"), Cooler / Charger pages (other products),
**Settings** (modal), Member Center / Credit Mall (China).

Device page tabs (`Kt` enum): **Key Mapping** · **Lighting** · **Actuation** (sticks/triggers) ·
**Advanced**. Inside Actuation: Common · Joystick (Left/Right; Center dead zone, Edge, Sensitivity curve,
Circularity algorithm, Active range) · Trigger (Left/Right; Trigger mode, ForceAdapt) · Motion (gyro to
left stick for racing / right stick for shooting; gyro curve; polling-rate warning).

Profiles: **"Onboard configs"** — the controller stores **four**; "Unnamed config"; Apply / Restore
default / Import config; share codes. Macros: **"Onboard Macro"**, "Macro/Key Mapping" per button,
activation "Press to trigger once" / "Hold to loop" / "Press to start/stop the loop", fields Output
Button · Duration · Cycle Interval. Turbo: "Activate method" = "Hold for turbo" / "Press to toggle turbo".
Vibration: "Grip vibration", intensity, min/max, "Grip vibration test" ("50 % ≈ Xbox feel").
Screen: "Screen Settings", "Custom Animation", "Animation" on/off, "Status bar display", Edit.
Firmware: "Device Firmware / Dongle Firmware / Screen Firmware", "Firmware update available".

## 4. Vocabulary map (SS4 → our app, EN / pt-BR)

| SS4 (EN) | Ours (EN) | pt-BR |
|---|---|---|
| Onboard configs | Profiles (4 on-board slots) | Perfis |
| Key Mapping | Buttons | Botões |
| Actuation → Joystick / Trigger / Motion | Sticks · Triggers · Motion | Sticks · Gatilhos · Movimento |
| Adaptive Trigger | ForceAdapt / Adaptive triggers | Gatilhos adaptativos |
| Lighting / Light Settings | Lighting | Iluminação |
| Screen / Custom Animation | Screen | Tela |
| Onboard Macro | Macros | Macros |
| Advanced test | Test | Teste |
| Device Firmware | Firmware | Firmware |

Keep the *names of physical buttons* exactly as printed on the pad (A B X Y, LB RB LT RT, M1–M4, C Z,
Home, Back/Select, Start, Turbo) — that is what users search for.

## 5. What we deliberately do differently

- Native macOS chrome (sidebar, toolbar, inspector, Liquid Glass) instead of an in-window Electron frame;
  system controls instead of Ant Design.
- No fixed-dark chrome: follow the system appearance by default, with the dark, accent-tinted *content*
  (controller illustration, cards) that keeps the gaming feel — details in `design.md`.
- No member centre / mall / telemetry.

## Verified against the running renderer (2026-09-01)

Using `tools/ss4-harness/`, the real SS4 4.2.2.3 UI was rendered at 1440 × 900 with a simulated Apex 4:

- **Shell**: 248 px sidebar (`--neutral-700` #212225) holding the app title, a "My Device" card
  (name, green dot, cable/battery glyphs, chevron) and a bottom rail with two square buttons
  (Adaptive Trigger, Screen) plus a wide Settings button. Main area is `--neutral-800` #1c1d1f.
- **Hero** (`.home-top`, ~50 % of the height, #181818): wireframe centred, blue radial glow from the
  bottom, key chips drawn from `device_config_k2` (dark fill, grey 1 px stroke, blue when selected),
  profile dropdown top-right ("Test ▾").
- **Tabs** under the hero: Common · Button · Joystick · Gyro · Trigger, icon + label, 2 px blue underline.
- **Common**: two columns separated by a vertical hairline — Light (mode select, colour swatches with
  + / −, brightness and cycle-time "− slider +" boxes) and Vibration (switch, intensity slider,
  "Vibration test").
- **Button**: hint card until a chip is clicked; then a Click / Turbo / Macro / Special pill and an
  "Input = [output box]" layout. Turbo adds an "Activate method" radio list and "Shots per second".
  Macro shows a "Click to set macro ›" card with a preview strip. Special shows a disabled select.
- **Joystick / Trigger**: Left / Right pill, then selects and sliders in two columns.
- **Gyro**: blue notice, Mapping to / How to activate / Activate key selects, X/Y sensitivity boxes.
- **Screen** (own route): "‹ Screen" header, "Screen Settings" card (Upload, formats hint, Restore
  default) and an "Official selection" grid from `screen_pic/list`.
- **Settings** (own route): left sub-navigation (Space Station / Controller / Update), right content
  in labelled sections with switches and links.

The macOS app mirrors this structure (`SpaceStation/App/Views.swift`, `Pages.swift`, `Theme.swift`).

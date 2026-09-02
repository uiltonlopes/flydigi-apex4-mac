# Space Station 4 vs Space Station for Mac — gap analysis (Apex 4)

Date: 2026-09-02. Sources: SS4 4.2.2.3 renderer bundle (routes, React components, `locales/en/translation.json`),
decompiled service/SDK (`IpcCommandEnum`, command factories, `FlydigiControllerFactory.GenerateControllerApex4`),
and this app's sources. Scope: what SS4 shows **for the Apex 4 (`k2`, device types 84/86/87/92/93/102/103/104)**.
Things SS4 hides for k2 are listed separately — we do not owe parity on those.

Legend: ✅ we have it · 🟡 partial · ❌ missing · ➖ not applicable on macOS / not for k2.

## 1. Missing or partial, ordered by value ÷ effort

| # | SS4 feature (k2) | Ours | Notes / how SS4 does it | Effort |
|---|---|---|---|---|
| 1 | **GIF frame interval sent to the pad** | ✅ (2026-09-02) | Our start packet hard-codes `period = 02`; SS4 sends the chosen interval in `UploadPic2K2Start[7]`. The slider only drives our preview today. | S |
| 2 | **Restore default configuration** (per slot / all) | ✅ (2026-09-02) | `ResetMappingConfig` → service writes `Configs/…/default/default_mapping_<type>.dat` into the slot. We ship no default blob; we could capture the factory blob once (we already decoded `default_mapping_84.dat`) and bundle the 8 variants. | S |
| 3 | **Controller sleep time** (1/5/15 min, 1 h, 3 h, never) | ✅ (2026-09-02) | `A5 30 05 <min>` implemented in `DeviceSession`, read via `A5 30 04`; **no UI**. Settings › Controller. | S |
| 4 | **Fast swap config** (`SELECT + A/B/X/Y` switches slots on the pad) | ✅ (2026-09-02) | `EnableQuickSwitchConfig`: XInput `A5 A2 <0/1>`, DInput `05 FA A2 <0/1>`. Gated by `quickSwitchConfigUsable` from `ReadHardwareFunction` (`A5 50 07`), which our pad does not answer — expose as a plain toggle with the SS4 illustration. | S |
| 5 | **Turbo function hardware switch** (on-pad turbo: `Turbo + key`) | ✅ (2026-09-02) | `EnableMappingSwitch`: `A5 50 06 <!enable>`. Same gating caveat. | S |
| 6 | **Local (inactive) profile library** — create / duplicate / rename / delete / reorder, apply local → slot, save slot → local | ✅ (2026-09-02) | SS4 keeps `.dat` files per device; UI is the left rail's "Inactive configs". We only have the 4 on-board slots (CLI `config dump/restore`). Plain JSON/`.dat` files in Application Support + a list under the profile menu. | M |
| 7 | **Share profile by code / import by code** | ❌ | `POST /config_share/upload` → code; `GET /config_share/download`. Payload = hex-dash of the **protobuf** `ControllerMappingConfigBean` (`ControllerRepository.GetConfigDetail`), not the device blob → needs the bean ↔ blob conversion (`MappingConfigParser`) in Swift first. Local library + `.fdgprofile` files done 2026-09-02. | M–L |
| 8 | **Macro library** — local macros, duplicate, rename, share/import by code | 🟡 | We edit the macros stored *in the slot* only. SS4 also has a local library (`GetLocalMacroConfigList…`, share as decimal-dash byte string). | M |
| 9 | **Advanced test page** (`/handleTestPage`) — live key/stick/trigger viewer, mapped vs raw output, **polling-rate meter**, **stick circularity test** with average error | ✅ (2026-09-02, in the Joystick tab) | We show live sticks/triggers and highlight keys on the hero. Missing: polling-rate meter (count input reports/s) and circularity test. Both are pure reading of the input stream we already have. | M |
| 10 | **Apply profile to NS (Switch) mode** | ❌ | `ApplySwitchConfig` → `SaveCurrentSwitchMappingConfig` (`A5 50 03` variant with the Switch slot). `IsSupportNs = true` for k2. Needs a protocol test on hardware (what the Switch slot id is). | M (research) |
| 11 | **Keyboard / mouse mapping** — Click → keyboard key, Special (wheel up/down, mouse L/R), Joystick map type Keyboard (WASD, 4/8-way) and Mouse (X/Y sensitivity), Gyro map type Mouse | ❌ | Not done by the firmware: SS4's service injects through a kernel virtual-HID driver (`FeizVKBComm.dll`, `KeyboardMouseInjectRunner`). On macOS this is an app-side engine (CGEvent, Accessibility permission) that runs while the app is open. Roadmap "keyboard/mouse frontier". | L |
| 12 | **Firmware flashing** (main chip; SS4 also lists screen / trigger / switch / dongle chips) | 🟡 | We check, download, verify and probe the OTA interface; the Update button is disabled by decision. Flash path documented in `docs/firmware-update.md`. Waiting for an explicit go. | M–L |
| 13 | **Device nickname** (local rename in the device center) | ✅ (2026-09-02) | Local only in SS4 (`UpdateNickname` is never sent for k2). Trivial UserDefaults field. | S |
| 14 | **App self-update** ("Space Station update") | ❌ | Sparkle or a GitHub-releases check; only meaningful once we publish releases. | M |
| 15 | **Log toggle + open log folder**, "when closing the window: tray vs quit" | 🟡 | We keep running in the menu bar; no preference, no log file. | S |
| 16 | **Screen: restore default animation** | ✅ (2026-09-02) | We show the factory GIF but cannot send it back as-is; SS4 uploads `default_screen_image_<type>.bin`. We have those bins (converted to GIF) — uploading the original LVGL frames is trivial. | S |
| 17 | **Motor min/max per grip motor** (blob has enabled/min/max/scale per motor) | 🟡 | SS4's UI exposes only `scale` (min/max keys are dead), so parity is fine; our single slider = SS4. Optional: per-motor scale. | S |
| 18 | **Second gyro activation key** (`enableKey2`) | ✅ (2026-09-02) | SS4 shows a 2-key picker. Bytes already round-trip. | S |
| 19 | **Per-LED-group colours** (16 groups) | ➖ | SS4 UI writes the same colour list to all groups, like us. Nothing to do. | — |

## 2. Present in SS4 but hidden or disabled for the Apex 4 (no parity owed)

- Joystick global settings (debounce, auto-calibration, rebound, precision bits, centre sensitivity) and the
  circularity algorithm: hidden for `k2` unless device type 102 (Black Myth edition). We hide them too; the
  commands exist in `DeviceSession` if ever wanted.
- Joystick polling rate (f4 only), "vibration light effect" (k5 only), screen animation on/off (k5 only),
  on-pad macro recording help (k5/fp4/f5), SS 5.0 migration (f5, zh-Hans), NSS survey.
- Dead UI in SS4 for everyone: screen status-bar toggle, gyro response curve, trigger vibration test button,
  interface theme, motor min/max.
- Trigger vibration switch / intensity / amplitude: gated on `IsSupportTriggerVibration`, which is **false for
  k2** (the Apex 4 has no trigger motors; its "Vibration" mode follows the grip motors).

## 3. Windows-only in SS4 — replaced or not applicable

| SS4 | Why not | What we do instead |
|---|---|---|
| Adaptive-trigger **game mods** (DLL injected into the game, `AdapterTriggerRunner`) and **DS / PS5 mode** (proprietary `PS5Driver`) | Windows drivers | Per-app game profiles (slot + ForceAdapt presets + lighting) switched by the frontmost app; Flydigi's game list as a seed |
| Third-party takeover (Steam Input / reWASD arbitration) | NewXInput-only command | ➖ |
| Account, member centre, credit mall, NPS survey | Flydigi account features | ➖ |
| Dock CD2 / cooler BS2-BS3 / keyboard pages | other products | ➖ (dock lighting could come later — the Dock 2 Pro is a separate USB device) |
| Space Station Service install / Devcon | Windows service model | SMAppService privileged helper (XInput only; DInput needs nothing) |

## 4. What we have that SS4 does not

Per-app profiles with lighting; GIPHY search; "on the controller" record with factory animations; live dot on the
sensitivity curve; live ForceAdapt preview while dragging with the pad's own presets as defaults; guided stick
and trigger calibration (SS4 exposes only the factory ADC command); receiver-aware battery and reconnection;
menu-bar status; CLI and protocol notes; runs without root in DInput.

## 5. Suggested order

1. Quick wins (S): frame interval on upload · sleep time · fast swap · turbo switch · restore default (bundle the
   8 factory blobs) · restore default animation · device nickname · gyro second key.
2. Profiles & macros library with share codes (M) — biggest day-to-day parity gap.
3. Advanced test page: polling-rate meter + circularity test (M).
4. NS-mode profile (research on hardware).
5. Firmware flash (on your go), then app self-update once releases exist.
6. Keyboard/mouse engine (L) — the one large frontier left.

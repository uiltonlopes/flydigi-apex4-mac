# Third-party artwork (not covered by the MIT licence)

The files in this folder are © Flydigi (Shanghai Flydigi Electronics Technology Co., Ltd.) and were
taken from the public Space Station 4 installer so that this app can show the controller the same way
the official tool does:

| File | Origin in Space Station 4.2.2.3 | Use in this app |
|---|---|---|
| `apex4-hero.png` | `assets/images/product/Controller/k2/84/main.png` | Controller picture on the Home page (the button hotspots are drawn over it) |
| `AppIcon.icns` | `assets/icons/mac/icon.icns` | App icon |
| `products/k2-<id>.png` | `assets/images/product/Controller/k2/<id>/main.png` | Device card / hero picture per Apex 4 variant (84, 86, 87, 92, 93, 102, 103, 104) |
| `screens/factory-k2-<id>.gif` | `Configs/Controller/k2/default/default_screen_image_<id>.bin` (LVGL frames, decoded with the project's own RGB565 reader and re-encoded as GIF) | "On the controller" preview before anything was sent from this Mac |
| `cards/card-k2-<id>.png` | `assets/bg_device_card_k2_<id>-*.png` | Device-card background for the special editions (86 EVA-01, 92 Assassin's Creed, 102 Black Myth Wukong, 103 Genshin, 104 Honkai Star Rail) |
| `add-device.png` | `assets/equipe-add-*.png` | Silhouette on the welcome screen when no controller is connected |
| `apex4-wireframe.svg` | `assets/device_wireframe_k2-*.js` (React SVG, serialised back to plain SVG) | Outline the button hotspots are drawn over |

The hotspot geometry in `SpaceStation/App/Stage/Apex4Render.swift` is transcribed from `device_config_k2-*.js`
(positions and sizes only, no code).

They are used for interoperability with the Apex 4 and stay separate from the MIT-licensed source so a
fork can swap them for original artwork. If Flydigi asks, replace these files and the app keeps working
(the code falls back to a schematic drawing when the files are missing).

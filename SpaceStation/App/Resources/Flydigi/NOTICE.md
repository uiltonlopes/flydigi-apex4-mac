# Third-party artwork (not covered by the MIT licence)

The files in this folder are © Flydigi (Shanghai Flydigi Electronics Technology Co., Ltd.) and were
taken from the public Space Station 4 installer so that this app can show the controller the same way
the official tool does:

| File | Origin in Space Station 4.2.2.3 | Use in this app |
|---|---|---|
| `apex4-hero.png` | `assets/images/product/Controller/k2/84/main.png` | Product picture on the Status page |
| `AppIcon.icns` | `assets/icons/mac/icon.icns` | App icon |
| `products/k2-<id>.png` | `assets/images/product/Controller/k2/<id>/main.png` | Device card / hero picture per Apex 4 variant (84, 86, 87, 92, 93, 102, 103, 104) |
| `apex4-wireframe.svg` | `assets/device_wireframe_k2-*.js` (React SVG, serialised back to plain SVG) | Outline the button hotspots are drawn over |

The hotspot geometry in `SpaceStation/App/Stage/Apex4Render.swift` is transcribed from `device_config_k2-*.js`
(positions and sizes only, no code).

They are used for interoperability with the Apex 4 and stay separate from the MIT-licensed source so a
fork can swap them for original artwork. If Flydigi asks, replace these files and the app keeps working
(the code falls back to a schematic drawing when the files are missing).

# Flydigi Apex 4 — USB protocol (reverse-engineered)

Everything here was verified against a real Apex 4 (`deviceId 84`, firmware 6.8.3.0) on macOS 26,
using the scripts in [`research/python`](../research/python). Where a fact comes only from reading
Flydigi's Windows software and was **not** exercised on hardware, it is marked *(unverified)*.

The Apex 4 is Flydigi's internal model **`k2`** (Apex 3 = `k1`). Device IDs in the k2 family:
`84` (Apex 4), `86` (EVA), `87` (STN), `92` (Assassin's Creed), `93`, `102`, `103`, `104`.
It has **4 LED groups** and a **160×80** LCD driven by an ESP32 running LVGL v8.

## 1. USB modes

The controller has a hardware/software mode switch. Two modes expose a vendor channel over USB:

| Mode | VID:PID | What macOS sees | Vendor channel | Root needed on macOS |
|---|---|---|---|---|
| **XInput** | `045e:028e` (Xbox 360 pad emulation) | Apple's `com.apple.gamecontroller.driver.XboxGamepad` dext claims interface 0 | same interface 0: interrupt **OUT ep5**, **IN ep1** (64 B) | **yes** — the device must be *captured* from Apple's dext (IOUSBHost device capture / libusb `detach_kernel_driver`) |
| **DInput** | `04b4:2412` | 4 HID interfaces; generic HID drivers, nothing exclusive | HID **interface 2** (usage page `0xFFA0`): OUTPUT report id **5** (63 B), INPUT report id **4** (31 B) | **no** — plain `IOHIDManager`/hidapi |

Interface 3 in DInput (usage page `0xFFEF`, report id 5, 63 B in/out/feature) is unused by Flydigi's software.

Software mode switch:
- DInput → XInput: write `05 ED` (report 5, cmd 237) *(unverified on hardware)*
- XInput → DInput: `A5 17 … crc` (cmd 23) *(unverified on hardware)*

Both cause a USB re-enumeration.

## 2. Framing

### XInput channel (raw interrupt transfers on interface 0)
- Command packets are **15 bytes**: `A5 <cmd> <args…> <crc>` where `crc` = byte-sum of bytes `[0..13]` (mod 256). Zero-padded.
- Replies arrive inside the 64-byte gamepad input report; the vendor payload starts at **offset 14**:
  - `r[14]==0xA5` → command reply, `r[15]` = cmd, `r[16..]` = payload.
  - `r[14]==0x5A && r[15]==0xA5` → **screen** reply, `r[16]` = cmd (`D0..D3`), `r[18]` = ret, `r[19..20]` = size/offset (BE).

### DInput channel (HID interface 2)
- Output = report id `5`: `05 <cmd> <args…>` — short writes (12–14 B) are accepted; the report is nominally 63 B.
- Input = report id `4`: `04 xx xx <payload…>` — payload starts at **offset 3**. For bulk reads the parcel index is at `r[3]`, data at `r[5..14]`, and the command id at `r[15]`.

## 3. Commands

| Function | XInput | DInput | Reply |
|---|---|---|---|
| Device info | `A5 10` | `05 EC` (236) | XInput: `r[15]=0x10`, deviceId `r[16]`, MAC `r[17..20]`, fw `r[21..22]` (nibbles → `H2.H1.L2.L1`), battery `r[23]`, cpu `r[24]`, conn `r[25]`, motion `r[26]`. DInput: `r[15]=236`, deviceId `r[3]`, MAC `r[5..8]`, fw `r[9..10]`, battery `r[11]`, cpu `r[12]`, conn `r[13]` (1 = wired), motion `r[14]` |
| Dongle info | `A5 11` | `05 11` | fw bytes; all-zero = wired |
| Read config (790 B) | `A5 21 <cfgId>` (33) → replies cmd `34`, idx `r[16]`, 10 B at `r[17..26]`, 79 parcels | `05 EB <cfgId>` (235) → `r[15]=235`, idx `r[3]`, 10 B at `r[5..14]` | |
| Read LED config (500 B) | `A5 26 <cfgId>` (38) → replies cmd `39`, 50 parcels | `05 E5 <cfgId>` (229) → `r[15]=229` | |
| Write config | start `A5 25 <N> A0 <cfgId>` (37) → ack cmd 35/37; data `A5 24 <10 B> A0 <idx> 00 crc` (36) → ack cmd 36 | start `05 EA <N> A0 <cfgId>` (234); data `05 22 <10 B> A0 <idx>` (34); acks `r[15]∈{234,231,51}` with idx at `r[3]` | |
| Write LED config | start `A5 2A <cfgId> <N>` (42) → ack 42; data `A5 29 <10 B> A0 <idx> 00 crc` (41) → ack 41 with idx at `r[16]` | start `05 E7 <cfgId> <N>` (231); data `05 33 <10 B> A0 <idx>` (51); ack `r[15]=231`, idx `r[3]` | see §5 |
| Read config random id | `A5 50 02 <cfgId>` → `r[15]=0x50,r[16]=2`, id `r[17..18]` BE, cfg `r[19]` | `05 50 02 <cfgId> crc` → payload `[80,2,hi,lo,cfg]` at `r[3..]` | |
| **Save to flash** | `A5 50 03 <hi> <lo>` (id = random+1) → `r[17]==1` on success | `05 50 03 <hi> <lo> crc` → `r[5]==1` | **required** for a written config/LED to survive power-cycle |
| Screen info / sleep time | — | `05 F2 03` / `05 F2 02 <sleep>` (242) | `r[3]=242,r[4]=3/4` *(unverified)* |
| Switch active config | `A5 50 05 <cfgId>` *(unverified)* | | |
| Motor test | `A5 12 <L> <R>` *(unverified)* | | |

`N` = number of 10-byte parcels (config: 79, LED: 50). Config id 0 was used throughout; the
controller has several config slots.

### Firmware quirk — LED writes in XInput
In XInput mode a standalone LED write is **acknowledged but ignored**. Flydigi's software always
writes the full config first (`37/36`), waits ~500 ms, then writes the LED config (`42/41`).
Replaying that sequence makes the LED write take effect. In DInput mode a standalone LED write
takes effect immediately.

## 4. Config blob (790 B) — partially decoded

Mapping, joystick, trigger, gyro and vibration settings. Layout decoded by Flydigi's
`GamepadConfigUtilsV2` — to be documented as we implement each feature. Round-tripping the blob
unchanged is safe (verified: 80/80 acks, re-read identical).

## 5. LED blob (500 B)

```
offset  size  field
0       2     version (observed 00 02)
2       1     type
3       1     loop_start
4       1     loop_end
5       1     speed        0–100
6       1     brightness   0–100
7       1     rgb_num      number of LED groups in use (Apex 4: 4)
8       1     mode         0 off · 1 streamlined · 2 breathing · 3 gradient · 4 feedback · 5 steady
9       11    reserved (FF)
20      480   16 groups × 10 units × (R,G,B); each channel is 0–100 (%), not 0–255
```
Factory default observed: mode 3 (gradient), speed 50, brightness 50, 4 groups each with units
`(0,0,100) (100,0,0) (0,100,0)` → blue→red→green cycle.

## 6. Screen (LCD) — image format and upload

### Image binary (one per frame)
LVGL v8 `lv_img_dsc_t`-style file, produced on Windows by `lvImage2bin_x64.dll`:
```
4-byte header, little-endian uint32:  cf | (w << 10) | (h << 21)
   cf = 4  (LV_IMG_CF_TRUE_COLOR),  w = 160,  h = 80   → 04 80 02 0A
pixels: 160*80 × RGB565, **big-endian** (byte-swapped: `rol 8`), row-major
```
Per-channel quantisation used by Flydigi: `R5 = min(31, floor(R/8 + 0.5))`, `G6 = min(63, floor(G/4 + 0.5))`,
`B5 = min(31, floor(B/8 + 0.5))`. Frame size = 4 + 25600 = **25 604 B**. GIF: max **35 frames** for k2,
frames are resized to 160×80; frame delay is taken from the GIF (`duration/10` = centiseconds).

### Upload sequence (XInput only — see §1)
For each frame `num = 1..N` (`gifType=1`, size = frame length):
```
start   A5 D0 09 01 <gifType> <N> <num> 02 <sizeHi> <sizeLo> <crc = sum(bytes 1..9)> 00 00 00 00
        → reply 5A A5 D0 … ret@18
data    A5 D1 <offHi> <offLo> <26 data bytes, FF-padded> <crc = sum(bytes 1..29)>   (31 B)
        → reply 5A A5 D1 … ret@18 (0 = ok, 1 = resend), next offset @19..20
end     A5 D2 07 01 <num> <sentHi> <sentLo> 00 <crc = sum(bytes 1..7)> 00…      (15 B)
        → reply 5A A5 D2 … ret@18
```
After the last frame: `A5 D3 07 01 <N> 00 00 00 <crc> …` (EndAll). Throughput ≈ 4.5 s per frame
(985 × 26-byte packets, each acknowledged).

The DInput start command (`05 A5 D0 09 01 <gifType> <N> <num> <freq*10/50> <hi> <lo> <crc(2..10)>`)
**is** acknowledged (`5A A5 D0 03 00`) and puts the controller in upload mode ("1/N" on the LCD), but
the firmware then NAKs every HID OUT transfer on interfaces 2 and 3 — there is no working DInput data
path. Recovery: unplug and power-cycle the controller.

## 7. Newer Flydigi devices (for reference)
Flydigi's official WebHID tool (`hid2.flydigi.com`, a "device ID correction" utility) talks to
devices with Flydigi's own vendor id **`0x37D7`** using report id 5 and a different framing:
`5A A5 <cmd> <len+2> <payload…> <crc>`. The Apex 4 (fw 6.8.x) does not enumerate with that VID, but the
`5A A5` family is the same one the Apex 4 uses for screen replies — expect newer firmware/products to
converge on it.

## 8. Legacy / other
- Apex 3 (`k1`, deviceId 24) uses a different screen protocol (`05 F0/F1`, 20-byte packets, w/h in
  the start command). Not targeted by this project.
- Bluetooth: Flydigi's BLE configuration service does not cover the Apex 4.
- **2.4 GHz dongle (charging base): works.** The dongle enumerates as `045e:028e` "Flydigi VADER3"
  (4 interfaces, Xbox-360-receiver style); interface 0 has the same OUT ep5 / IN ep1 and speaks the
  same XInput protocol — LED read/write and screen upload verified through it. `DeviceInfo.connection`
  reports wireless. Root is needed exactly as in wired XInput.

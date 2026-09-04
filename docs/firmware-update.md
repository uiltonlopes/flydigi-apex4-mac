# Firmware update — how Space Station 4.2 flashes the Apex 4 (research 2026-09-02, flashed on hardware 2026-09-04)

Derived read-only from Space Station 4.2.2.3: the .NET service (`SpaceStationService`), the Electron main
process, the renderer bundle and the separate flasher tool `firmware\FirmwareConsole.exe` (`FirmwareLibrary.dll`).
**§6c records the first real flash (6.8.3.0 → 6.8.3.7) done with this project's flasher.** Legend: **[proven]** read from code;
**[inferred]** deduced from code + Telink OTA SDK conventions.

## 1. Who does what

| Layer | Role |
|---|---|
| Renderer | version check (`POST /Update/firmware`), dialog, sends IPC `SwitchUsb`, waits 5 s, asks main to run the flasher, shows progress |
| Electron main | forwards `SwitchUsb`; spawns `FirmwareConsole.exe`; parses its stdout (`Progress: N%`, `/success/i`, `/failed/i`) into `callback_firmware_upgrade` (100 = done, −1 = failed); **no timeout** |
| Service (C#) | only sends **switch-to-upgrade-mode** (`A5 17`) and later `SwitchToXInputMode` (`05 ED`) |
| FirmwareConsole | downloads the `.bin`, opens HID `04b4:2412` **usage page `0xFFEF`**, streams a Telink-style OTA in 64-byte reports |

`IpcCommandEnum_UploadProgressChanged` is *not* firmware progress (it is the screen/serial upload). Main-chip
progress comes only from the flasher's stdout **[proven]**.

## 2. Sequence (main chip, Telink)

1. `POST /Update/firmware` → `chip_list.main_chip = {version "6.8.3.7", url …/K2_Telink87_Gamepad_6837_0714.bin, info, min_app_version "4.1.2.0", is_push}`. Chip keys map to `ChipModule` main 0 / rf 1 / si 2 / screen 4 / trigger 5 / dongle 6.
2. UI requires the pad **wired** (except dongle flashing) **[proven, UI-only]**.
3. `SwitchUsb{uid, chipModule 0, chipType Telink}` → service sends the classic 15-byte `A5 17 00 … [crc]` — **the same command as "switch to DInput"** **[proven]**; no reply awaited.
4. Pad re-enumerates as `04b4:2412` (our DInput mode). The OTA server is an extra HID interface (usage page `0xFFEF`, report id 5, 64-byte reports) that coexists with the config interface (`0xFFA0`) — application firmware exposing a Telink OTA service, not a separate bootloader enumeration **[coexistence proven; "not a bootloader" inferred]**.
5. 5 s later: `FirmwareConsole.exe --device_id k2 --chip_module 0 --chip_type Telink --url <bin> --vendor_id 04b4 --product_id 2412`. It downloads to a temp file, opens the `0xFFEF` interface (one-shot, no wait), loads the image, streams the OTA (one report in flight, ack-paced), sleeps 100 ms after END, prints `Progress: 100%` and `Upgrade Completed Successfully!`. Electron matches "success" and **kills the tool**, so the device's OTA result report is normally never read **[proven]**.
6. Renderer shows "controller restarting" (10 s), and on any reconnect with VID `04b4` sends `SwitchToXInputMode` (65528) after 5 s → service writes `05 ED` on the `0xFFA0` interface → pad returns to `045e:028e` **[proven]**.

## 3. Bytes

**Switch to upgrade mode (XInput, 15 B):** `A5 17 00 00 … 00 [crc = sum(0..13)]` for main chip and dongle; screen `A5 30 0B …`; trigger board `A5 30 0C …`. If the pad is already in DInput the service emits `05 F5 00 …` (effect unknown).

**OTA output report (host → pad, `0xFFEF`, 64 B including report id):**

| Offset | Value |
|---|---|
| 0 | `05` report id |
| 1 | `02` |
| 2 | payload length: `02` start · `14`/`28`/`3C` data (1–3 packets) · `06` end |
| 3 | `00` |
| 4… | payload; zero-padded to 64 |

- **START**: payload `01 FF` (opcode `0xFF01` LE) → `05 02 02 00 01 FF 00…`
- **DATA**: 1–3 packets of 20 bytes: `index (LE u16, 0-based, +1 per 16-byte block)` + `16 image bytes` + `CRC-16/MODBUS over the 18 bytes (init 0xFFFF, poly 0xA001 reflected, LE)`. Exactly `ceil(size/16)` packets, last one `0xFF`-padded, up to 48 image bytes per report. Progress = `index*16*100/size`.
- **END**: payload `02 FF n_lo n_hi m_lo m_hi` with `n` = last index sent and `m = (0x10000 − n) & 0xFFFF` (two's complement — Telink reference servers check `n ^ m == 0xFFFF`; send exactly what SS4 sends) **[bytes proven, semantics uncertain]**.

**Input reports (pad → host):**

| Pattern | Meaning |
|---|---|
| `05 02 03 00 06 FF <code>` | OTA result: 0 success; else error (Telink codes ≈ 1 packet loss, 2 data CRC, 3 flash write, 4 incomplete, 5 flow, 6 fw check, 7 version, 8 PDU len, 9 fw mark, 10 fw size) **[codes inferred]** |
| `05 01 08 00 <ver u32> <crc u32>` | version reply to `0xFF00` (never used by SS4) |
| any report with `[0] == 05` | treated as the ack for the previous write |

No timeouts or retries anywhere in SS4's OTA path.

## 4. Firmware file

Host checks are minimal **[proven]**: `u32 LE @0x02` printed as version; `u32 LE @0x18` = number of bytes transmitted (`size`); `u32 LE @size−4` = CRC32, only checked ≠ 0 and ≠ 0xFFFFFFFF. No signature, no model check. **Verified on the real 6.8.3.7 image (161 380 B): the stored value is the IEEE CRC-32 register without the final inversion (a5ca3c6d = ~5a35c392); our validator recomputes it.** Telink convention **[inferred]**: boot mark `KNLT` at 0x08, size at 0x18, CRC32 appended by `tl_check_fw`, verified by the device after END; image written to the inactive bank and the boot flag switched only after CRC passes. Version bytes `0x68 0x37` ⇔ `6.8.3.7` ⇔ `6837` in the file name. Max image 2 MiB.

## 5. Other chips (k2)

| Chip | Enter mode | Flasher | Transport |
|---|---|---|---|
| Dongle (Telink) | `A5 17` via the dongle | same OTA | HID usage page `0xFFEE` on `04b4:2412` **[re-enumeration of the dongle not observed]** |
| Trigger board (WCH) | `A5 30 0C` | CH375 ISP | WCH bootloader USB `4348:55E0`, vendor driver |
| Screen MCU ("Freq"/FRK — SS4 does **not** call it ESP32) | `A5 30 0B` | serial OTA | USB-serial `FFAA:5555` @ 921600, 4 KiB erase / 55-byte writes, resource images split at fixed offsets |
| Switch chip (Krly) | — | none | not flashable; SS4 tells the user to hold START 8 s on failure |

## 6. Recovery

SS4 has no rollback, no stuck-device probe for controllers, one attempt, and "retry" just repeats START.
Safety rests on the Telink OTA design (inactive bank + CRC + boot flag). `05 ED` on the `0xFFA0` interface
is the only way back to XInput; the hardware combo also toggles modes.

## 6b. Observed on hardware (2026-09-02, read-only)

- In DInput the OTA interface is present: usage page `0xFFEF`, 64-byte input and output reports.
- Sending the `0xFF00` version query (`05 02 02 00 00 FF …`) made the pad answer
  `05 02 03 00 06 FF 09 00 02 00 00 00 02 00 00 00`, i.e. an **OTA result report with code 9**
  (Telink: "firmware mark" / unexpected command) — the application firmware does not implement the version
  query and reports the stray packet as an error. Nothing else changed; the pad kept working. The dry run no
  longer sends it. So the only packets the OTA server accepts are START / DATA / END, exactly as SS4 sends.

## 6c. First flash on hardware (2026-09-04, `apex4 firmware flash --yes --verbose`)

- Pad wired, switched to DInput with `A5 17`, battery level 4/5. Image `K2_Telink87_Gamepad_6837_0714.bin`
  (161 380 B, 10 087 packets, 3 per report).
- **Every report is acknowledged by an echo of the report itself**: START was answered with
  `05 02 02 00 01 ff 00…`, DATA 0 with `05 02 3c 00 00 00 0e 80 …` (our own bytes back). So "any report id 5"
  really is the ack, as SS4 assumes.
- END (`02 FF 66 27 9A D8`) was answered with the **result report `05 02 03 00 06 ff 00 …` = code 0** within
  the 10 s window. Whole transfer: 11 s.
- The pad rebooted on its own and was back on USB **about 1 s later, still in DInput** (`04b4:2412`), reporting
  firmware **6.8.3.7**. `05 ED` returned it to XInput. Profile slots (names, mappings, sticks, triggers), LED
  configuration and the screen animation all survived the update.
- Right after any re-enumeration the XInput channel can fail once with "not found" for a second or two while
  Apple's driver attaches; a retry succeeds.

## 7. Status in this project (2026-09-04)

Everything for the main chip is reachable **without root** once the pad is in DInput: `IOHIDManager` on
`04b4:2412` usage page `0xFFEF`, 64-byte output reports, one input report per write, then `05 ED` on the
config interface.

- **Dry run** (done, verified on hardware): download, validate the file (size field, CRC32 recomputed over
  `0..size−4`, `KNLT` mark), enumerate the `0xFFEF` interface. Nothing written.
- **Flasher** (implemented and **run once on hardware, see §6c**): `OTAPacket` (FlydigiKit) builds START / DATA /
  END exactly as §3; `OTALink.flash` (FlydigiTransport) streams them one report in flight, waits for the ack
  of each (any report id 5, like SS4), aborts on a result report with a non-zero code or on a 3 s silence,
  and after END waits up to 10 s for `FF06 00`. CLI: `apex4 firmware flash [<url|path>] --yes`, which also
  refuses XInput, the wireless receiver, battery < 40 % and any image that does not validate.
- **App**: `ControllerModel.flashFirmware` runs the same sequence (download + validate, `A5 17` through the
  helper when in XInput, `OTALink.flash` with progress, poll the DInput config interface until the pad is back,
  `05 ED`, refresh). Gates: cable, battery ≥ 40 %, helper when in XInput. **Exercised on 2026-09-04** by re-flashing 6.8.3.7 from the app
  with the pad in XInput: helper switch → OTA (progress bar) → back on USB in DInput → `05 ED` → XInput, all automatic.
- Never flash over the receiver; never flash a file whose header does not validate.

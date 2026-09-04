// apex4 — command-line tool for the Flydigi Apex 4 on macOS.

import ArgumentParser
import Foundation
import FlydigiKit
import FlydigiTransport
import FlydigiHelperProtocol
import XPC

@main
struct Apex4: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Configure a Flydigi Apex 4 from macOS (LEDs, screen, profiles).",
        subcommands: [Firmware.self, Info.self, LED.self, ScreenCmd.self, Config.self, Mode.self, Helper.self, API.self, Dev.self],
        defaultSubcommand: Info.self)
}

struct ChannelOption: ParsableArguments {
    @Option(name: .long, help: "Force a channel: dinput (no root) or xinput (root).")
    var channel: String?

    func open() throws -> DeviceSession {
        let pref: Channel? = channel.map { $0.lowercased() == "xinput" ? .xinput : .dinput }
        return try DeviceSession.open(preferring: pref)
    }
}

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show device information.")
    @OptionGroup var ch: ChannelOption
    func run() throws {
        let s = try ch.open(); defer { s.close() }
        let i = try s.deviceInfo()
        print("""
        channel      \(s.channel)
        model        \(i.modelName)\(i.descriptor.map { " · \($0.support.rawValue)" } ?? " · unknown id")
        device id    \(i.deviceId)
        firmware     \(i.firmware)
        mac          \(i.mac.map { String(format: "%02x", $0) }.joined(separator: ":"))
        connection   \(i.isWired ? "wired" : "wireless (\(i.connection))")
        battery raw  \(i.batteryRaw)
        """)
    }
}

struct LED: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read or change lighting.",
                                                    subcommands: [Show.self, Brightness.self, Steady.self, Cycle.self, ModeCmd.self],
                                                    defaultSubcommand: Show.self)

    struct Show: ParsableCommand {
        @OptionGroup var ch: ChannelOption
        func run() throws {
            let s = try ch.open(); defer { s.close() }
            let led = try s.readLED()
            print("mode \(led.mode)  speed \(led.speed)  brightness \(led.brightness)  groups \(led.activeGroups)")
            for g in 0..<Int(led.activeGroups) {
                print("  group \(g): " + led.colours(ofGroup: g).map { "(\($0.r),\($0.g),\($0.b))%" }.joined(separator: " "))
            }
        }
    }
    struct Brightness: ParsableCommand {
        @OptionGroup var ch: ChannelOption
        @Argument(help: "0–100") var value: UInt8
        @Flag(name: .long, help: "Do not persist to flash.") var noSave = false
        func run() throws {
            let s = try ch.open(); defer { s.close() }
            var led = try s.readLED(); led.brightness = min(value, 100)
            try s.applyLED(led, persist: !noSave); print("brightness → \(led.brightness)\(noSave ? "" : " (saved)")")
        }
    }
    struct Steady: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Solid colour, e.g. `led steady ff0000`.")
        @OptionGroup var ch: ChannelOption
        @Argument(help: "RRGGBB hex") var colour: String
        @Flag(name: .long) var noSave = false
        func run() throws {
            let u = try parseColour(colour)
            let s = try ch.open(); defer { s.close() }
            var led = try s.readLED(); led.setSteady(u)
            try s.applyLED(led, persist: !noSave); print("steady #\(colour)\(noSave ? "" : " (saved)")")
        }
    }
    struct Cycle: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Colour cycle, e.g. `led cycle ff0000 00ff00 0000ff --mode gradient`.")
        @OptionGroup var ch: ChannelOption
        @Argument(help: "up to 10 RRGGBB colours") var colours: [String]
        @Option(help: "gradient | breathing | streamlined") var mode: String = "gradient"
        @Option(help: "0–100") var speed: UInt8?
        @Flag(name: .long) var noSave = false
        func run() throws {
            let units = try colours.map(parseColour)
            guard let m = ["gradient": LEDConfig.Mode.gradient, "breathing": .breathing, "streamlined": .streamlined][mode] else {
                throw ValidationError("mode must be gradient, breathing or streamlined")
            }
            let s = try ch.open(); defer { s.close() }
            var led = try s.readLED(); led.setCycle(units, mode: m); if let speed { led.speed = min(speed, 100) }
            try s.applyLED(led, persist: !noSave); print("\(mode) with \(units.count) colours\(noSave ? "" : " (saved)")")
        }
    }
    struct ModeCmd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "mode", abstract: "off | streamlined | breathing | gradient | feedback | steady")
        @OptionGroup var ch: ChannelOption
        @Argument var mode: String
        @Flag(name: .long) var noSave = false
        func run() throws {
            guard let m = LEDConfig.Mode.allCases.first(where: { "\($0)" == mode.lowercased() }) else { throw ValidationError("unknown mode") }
            let s = try ch.open(); defer { s.close() }
            var led = try s.readLED(); led.mode = m
            try s.applyLED(led, persist: !noSave); print("mode → \(m)")
        }
    }
}

func parseColour(_ hex: String) throws -> LEDConfig.Unit {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard h.count == 6, let v = UInt32(h, radix: 16) else { throw ValidationError("colour must be RRGGBB") }
    return LEDConfig.Unit(rgb8: UInt8(v >> 16), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
}

struct ScreenCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "screen", abstract: "Upload an image or GIF to the LCD (requires XInput + root).")
    @Argument(help: "GIF, PNG or JPEG. Resized to 160×80; GIFs up to 35 frames.") var file: String
    @Option(help: "Limit the number of frames.") var frames: Int?
    @Flag(help: "Only convert and report; do not talk to the controller.") var dryRun = false
    @Flag(help: "Log screen acks to stderr.") var debug = false
    func run() throws {
        if debug { DeviceSession.debug = true }
        var lvgl = try ImageLoader.frames(url: URL(fileURLWithPath: file))
        if let frames { lvgl = Array(lvgl.prefix(frames)) }
        print("\(lvgl.count) frame(s) × \(lvgl.first?.count ?? 0) B")
        if dryRun { return }
        let s = try DeviceSession.open(preferring: .xinput); defer { s.close() }
        let t0 = Date()
        var lastFrame = 0
        try s.uploadScreen(frames: lvgl) { p in
            if p.frame != lastFrame { lastFrame = p.frame; print("frame \(p.frame)/\(p.frames) …") }
        }
        print(String(format: "done in %.1fs", Date().timeIntervalSince(t0)))
    }
}

struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Dump or restore the raw configuration blobs.",
                                                    subcommands: [Show.self, Dump.self, Restore.self, ShareCode.self, ImportCode.self], defaultSubcommand: Show.self)
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Decode the active configuration (keys, sticks, triggers, motion, vibration, macros).")
        @OptionGroup var ch: ChannelOption
        @Option(help: "Decode a saved config.bin instead of reading the controller") var file: String?
        func run() throws {
            let bytes: [UInt8]
            if let file { bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: file))) }
            else { let s = try ch.open(); defer { s.close() }; bytes = try s.readBlob(.config) }
            guard let cfg = GamepadConfig(bytes: bytes) else { throw ValidationError("not a 790-byte config blob") }
            print(cfg.summary)
            print("round-trip identical: \(cfg.bytes == bytes)")
        }
    }
    struct ShareCode: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "share-code", abstract: "Space Station share string for the active config (or a config.bin); --upload gets a code from Flydigi.")
        @OptionGroup var ch: ChannelOption
        @Option(help: "Use a saved config.bin instead of reading the controller") var file: String?
        @Option(help: "Name to publish with (default: the profile title)") var name: String?
        @Flag(name: .long, help: "Upload to Flydigi and print the share code") var upload = false
        func run() throws {
            let raw: [UInt8]
            if let file { raw = [UInt8](try Data(contentsOf: URL(fileURLWithPath: file))) } else { let s = try ch.open(); defer { s.close() }; raw = try s.readBlob(.config) }
            let bean = SS4Profile(blob: raw)
            let s = bean.shareString
            print("\(bean.title.isEmpty ? "(untitled)" : bean.title) · \(bean.protobuf().count) protobuf bytes")
            if upload {
                let code = try FlydigiAPI.shareUpload(name: name ?? bean.title, shareString: s)
                print("share code: \(code)")
            } else { print(s) }
        }
    }
    struct ImportCode: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "import-code", abstract: "Download a Space Station share code and write it as a 790-byte config.bin (nothing is sent to the controller).")
        @Argument(help: "share code, or a raw 0A-1B-… string") var code: String
        @Option(help: "output file (default: <title>.fdgprofile)") var out: String?
        func run() throws {
            let bean: SS4Profile; var title = ""
            if let b = SS4Profile(shareString: code) { bean = b } else {
                let r = try FlydigiAPI.shareDownload(code: code); title = r.name
                guard let b = SS4Profile(shareString: r.shareString) else { throw ValidationError("the reply is not a profile bean") }
                bean = b
            }
            let blob = bean.blob()
            guard let cfg = GamepadConfig(bytes: blob) else { throw ValidationError("converted blob does not parse") }
            let name = out ?? ((bean.title.isEmpty ? (title.isEmpty ? "profile" : title) : bean.title) + ".fdgprofile")
            try Data(blob).write(to: URL(fileURLWithPath: name))
            print("\(cfg.title) · keys remapped: \(cfg.keys.filter { $0.value != .identity }.count) · macros: \(cfg.macros.count) → \(name)")
        }
    }
    struct Dump: ParsableCommand {
        @OptionGroup var ch: ChannelOption
        @Argument(help: "output directory") var dir: String
        func run() throws {
            let s = try ch.open(); defer { s.close() }
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try Data(try s.readBlob(.config)).write(to: URL(fileURLWithPath: dir).appendingPathComponent("config.bin"))
            try Data(try s.readBlob(.led)).write(to: URL(fileURLWithPath: dir).appendingPathComponent("led.bin"))
            print("wrote \(dir)/config.bin (790 B) and led.bin (500 B)")
        }
    }
    struct Restore: ParsableCommand {
        @OptionGroup var ch: ChannelOption
        @Argument(help: "directory with config.bin / led.bin") var dir: String
        func run() throws {
            let cfg = [UInt8](try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("config.bin")))
            let led = [UInt8](try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("led.bin")))
            guard cfg.count == 790, led.count == 500 else { throw ValidationError("unexpected blob sizes") }
            let s = try ch.open(); defer { s.close() }
            let a = try s.writeBlob(cfg, kind: .config); Thread.sleep(forTimeInterval: 0.5)
            let b = try s.writeBlob(led, kind: .led)
            try s.saveToFlash()
            print("config acks \(a.acks)/\(a.packets), led acks \(b.acks)/\(b.packets), saved")
        }
    }
}

struct Mode: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Switch between XInput and DInput by software (controller re-enumerates).")
    @OptionGroup var ch: ChannelOption
    func run() throws {
        let s = try ch.open(); defer { s.close() }
        try s.switchMode(); print("switch requested from \(s.channel)")
    }
}

/// Talks to the privileged helper daemon installed by the Apex4 app (SMAppService) over XPC.
struct Helper: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Query the Apex4 privileged helper daemon over XPC.",
                                                    subcommands: [Ping.self, HInfo.self, HLed.self, HSwitch.self], defaultSubcommand: Ping.self)
    @available(macOS 14.0, *)
    static func send(_ req: HelperRequest) throws -> HelperReply {
        let session = try XPCSession(machService: HelperConstants.machService, targetQueue: nil, options: [], cancellationHandler: nil)
        defer { session.cancel(reason: "done") }
        let reply = try session.sendSync(req).decode(as: HelperReply.self)
        if case let .error(e) = reply { throw ValidationError("helper: \(e)") }
        return reply
    }
    struct Ping: ParsableCommand {
        func run() throws {
            guard #available(macOS 14.0, *) else { throw ValidationError("macOS 14+") }
            if case let .pong(v, uid) = try Helper.send(.ping) { print("helper alive · protocol v\(v) · uid \(uid)\(uid == 0 ? " (root)" : "")") }
        }
    }
    struct HInfo: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "info")
        func run() throws {
            guard #available(macOS 14.0, *) else { throw ValidationError("macOS 14+") }
            if case let .deviceInfo(i) = try Helper.send(.deviceInfo) { print("device \(i.deviceId) fw \(i.firmware) mac \(i.mac) \(i.wired ? "wired" : "wireless") battery \(i.batteryRaw)") }
        }
    }
    struct HSwitch: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "switch", abstract: "Ask the pad (via the helper, XInput) to switch to DInput.")
        func run() throws {
            guard #available(macOS 14.0, *) else { throw ValidationError("macOS 14+") }
            _ = try Helper.send(.switchMode); print("switch requested — the controller re-enumerates in ~2 s")
        }
    }
    struct HLed: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "led")
        func run() throws {
            guard #available(macOS 14.0, *) else { throw ValidationError("macOS 14+") }
            if case let .blob(b) = try Helper.send(.readLED(slot: 0)), let led = LEDConfig(bytes: b) { print("mode \(led.mode) speed \(led.speed) brightness \(led.brightness)") }
        }
    }
}

/// Flydigi's public web API (what Space Station 4 uses): GIF library, per-game presets, firmware check.
struct API: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "api", abstract: "Query Flydigi's public web API (GIF library, game presets, firmware).",
                                                    subcommands: [Gifs.self, Games.self, Firmware.self])
    struct Gifs: ParsableCommand {
        @Flag(help: "Download every picture into ./flydigi-gifs") var download = false
        func run() throws {
            let pics = try FlydigiAPI.screenPictures()
            print("\(pics.count) pictures for k2 (\(pics.filter(\.isGIF).count) GIF)")
            for p in pics { print("  #\(p.id) \(p.type) freq=\(p.freq) cate=\(p.cate) \(p.isRecomment == 1 ? "★" : " ") \(p.title)  \(p.imagePath.lastPathComponent)") }
            if download {
                let dir = URL(fileURLWithPath: "flydigi-gifs"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for p in pics { try FlydigiAPI.download(p.imagePath).write(to: dir.appendingPathComponent("\(p.id)-\(p.imagePath.lastPathComponent)")) }
                print("saved to \(dir.path)")
            }
        }
    }
    struct Games: ParsableCommand {
        @Argument(help: "Filter by name (optional)") var filter: String?
        func run() throws {
            var games = try FlydigiAPI.gamePresets()
            if let f = filter?.lowercased() { games = games.filter { $0.enGameName.lowercased().contains(f) || $0.gameName.lowercased().contains(f) } }
            print("\(games.count) game presets")
            for g in games { print("  #\(g.id) \(g.enGameName) [\(g.platforms.joined(separator: ","))] procs=\(g.processGameNames.joined(separator: ",")) vib=\(g.isVibration) type=\(g.vibType) params=\(g.vibParams) filter=\(g.vibFilter) pwm=\(g.pwmScal) minFw=\(g.minFirmwareVersion)\(g.isPS5 == 1 ? " PS5" : "")") }
        }
    }
    struct Firmware: ParsableCommand {
        @Option(help: "Current main-chip firmware, e.g. 6.8.3.0 (default: ask the controller)") var current: String?
        func run() throws {
            var cur = current
            if cur == nil, let s = try? DeviceSession.open() { cur = try? s.deviceInfo().firmware; s.close() }
            guard let cur else { throw ValidationError("pass --current x.y.z.w or connect the controller") }
            let chips = try FlydigiAPI.firmwareUpdates(mainChip: cur)
            if chips.isEmpty { print("firmware \(cur): up to date (no chips offered)"); return }
            for (chip, c) in chips { print("\(chip): \(c.version) available (you have \(cur))\n  \(c.url)\n  min app \(c.min_app_version) · \(c.info.replacingOccurrences(of: "\n", with: " "))") }
        }
    }
}


// MARK: - Firmware (read-only)

struct Firmware: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Firmware: check Flydigi for updates, download and verify the image, probe the OTA interface, flash (only with --yes).",
                                                    subcommands: [Check.self, Verify.self, OTAVersion.self, Flash.self], defaultSubcommand: Check.self)
    struct Check: ParsableCommand {
        @Option(help: "Installed main-chip version, e.g. 6.8.3.0 (default: read from the pad).") var installed: String?
        @OptionGroup var ch: ChannelOption
        func run() throws {
            let fw: String
            if let installed { fw = installed } else { let s = try ch.open(); defer { s.close() }; fw = try s.deviceInfo().firmware }
            let chips = try FlydigiAPI.firmwareUpdates(mainChip: fw)
            print("installed \(fw)")
            for (k, v) in chips.sorted(by: { $0.key < $1.key }) { print("\(k): \(v.version)\(FirmwareVersion.isNewer(v.version, than: fw) && k == "main_chip" ? "  ← newer" : "")  \(v.url.lastPathComponent)") }
        }
    }
    struct Verify: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download (or open) a firmware image and validate header, size and CRC32.")
        @Argument(help: "URL or local path of the .bin") var source: String
        func run() throws {
            let data: Data
            if let u = URL(string: source), u.scheme?.hasPrefix("http") == true { data = try FlydigiAPI.download(u) } else { data = try Data(contentsOf: URL(fileURLWithPath: source)) }
            let img = try FirmwareImage(data: data)
            print(String(format: "file %d bytes · payload %d · version field 0x%08x · boot mark %@", data.count, img.payloadSize, img.versionField, img.hasBootMark ? "KNLT" : "none"))
            print(String(format: "crc32 stored %08x computed %08x %@", img.storedCRC, img.computedCRC, img.crcMatches ? "OK" : "MISMATCH"))
            try img.validate(); print("valid · \(img.packetCount) OTA packets")
        }
    }
    struct Flash: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: """
        Flash the main-chip firmware over the OTA interface, the way Space Station's FirmwareConsole does.
        Requirements: pad in DInput mode over the USB cable (run `apex4 mode` from XInput first), battery ≥ 40 %,
        a valid image. Nothing is written without --yes. Afterwards the pad reboots; run `apex4 mode --channel dinput`
        to go back to XInput.
        """)
        @Argument(help: "URL or local path of the .bin (default: the newest main-chip image Flydigi offers for this pad).") var source: String?
        @Flag(name: .long, help: "Really write the firmware.") var yes = false
        @Flag(name: .long, help: "Print the first acknowledgements and every unusual report.") var verbose = false
        @Option(name: .long, help: "Minimum battery percentage.") var minBattery: Int = 40
        @Option(name: .long, help: "OTA packets per report (1–3, Space Station uses 3).") var packetsPerReport: Int = 3

        func run() throws {
            // 1. The pad, over the cable, in DInput.
            let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
            guard s.channel == .dinput else { throw ValidationError("the pad is in XInput; run `sudo apex4 mode` first, wait for it to re-enumerate, then retry") }
            let info = try s.deviceInfo()
            guard info.isWired else { throw ValidationError("the pad is on the wireless receiver; connect the USB cable") }
            guard OTALink.isPresent() else { throw ValidationError("OTA interface (usage page FFEF) not present") }
            // The device-info byte is a 0–5 level (low nibble), bit 4 = charging; the app shows it as level × 20 %.
            let battery = min(5, Int(info.batteryRaw & 0xF)) * 20
            print("pad \(info.modelName) · device id \(info.deviceId) · firmware \(info.firmware) · battery \(battery) %\(info.batteryRaw >> 4 == 1 ? " (charging)" : "") · wired")
            guard battery >= minBattery else { throw ValidationError("battery \(battery) % is below \(minBattery) %; charge first") }

            // 2. The image.
            let url: URL
            if let source {
                url = (URL(string: source).flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil }) ?? URL(fileURLWithPath: source)
            } else {
                let chips = try FlydigiAPI.firmwareUpdates(deviceId: Int(info.deviceId), mainChip: info.firmware)
                guard let main = chips["main_chip"] else { print("Flydigi offers no newer main-chip firmware for \(info.firmware)"); return }
                print("Flydigi offers \(main.version): \(main.url.lastPathComponent)")
                url = main.url
            }
            let data = url.isFileURL ? try Data(contentsOf: url) : try FlydigiAPI.download(url)
            let img = try FirmwareImage(data: data)
            try img.validate()
            print(String(format: "image %d bytes · payload %d · crc32 %08x OK · %d packets · version field 0x%08x", data.count, img.payloadSize, img.storedCRC, img.packetCount, img.versionField))

            guard yes else { print("dry run only — add --yes to flash"); return }

            // 3. Stream it. Keep the config session closed while the OTA runs (one HID client per interface is enough).
            s.close()
            let ota = try OTALink(); defer { ota.close() }
            let started = Date()
            var lastShown = -1
            let outcome = try ota.flash(img, packetsPerReport: packetsPerReport, trace: verbose ? { print("  \($0)") } : nil) { sent, total in
                let pct = sent * 100 / total
                if pct / 5 != lastShown / 5 || sent == total { print("Progress: \(pct)%  (\(sent)/\(total) packets)"); lastShown = pct }
            }
            let secs = Int(Date().timeIntervalSince(started))
            switch outcome {
            case .confirmed: print("Upgrade completed: the controller confirmed the image (\(secs) s). It is rebooting now.")
            case .sentNoResult: print("Image sent and acknowledged (\(secs) s); no result report before the timeout — the pad normally reboots straight away. Check `apex4 info` in a few seconds.")
            }
        }
    }
    struct OTAVersion: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "ota-version", abstract: "Read the version through the OTA interface (DInput, read-only).")
        func run() throws {
            guard OTALink.isPresent() else { print("OTA interface not present (pad must be in DInput over the cable)"); return }
            let ota = try OTALink(); defer { ota.close() }
            print("report sizes: \(ota.reportSizes)")
            let v = try ota.queryVersion()
            print("raw: " + v.raw.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))
            if let ver = v.version { print(String(format: "version 0x%08x crc 0x%08x", ver, v.crc ?? 0)) }
        }
    }
}

// apex4 — command-line tool for the Flydigi Apex 4 on macOS.

import ArgumentParser
import Foundation
import FlydigiKit
import FlydigiTransport

@main
struct Apex4: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Configure a Flydigi Apex 4 from macOS (LEDs, screen, profiles).",
        subcommands: [Info.self, LED.self, ScreenCmd.self, Config.self, Mode.self],
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
        device id    \(i.deviceId) \(i.isApex4Family ? "(Apex 4 family)" : "")
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
    func run() throws {
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
                                                    subcommands: [Dump.self, Restore.self])
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

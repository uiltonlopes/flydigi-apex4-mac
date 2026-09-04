// Developer experiments — not part of the supported CLI surface.

import ArgumentParser
import Foundation
import FlydigiKit
import FlydigiTransport

struct Dev: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Developer experiments (protocol re-tests).", shouldDisplay: false,
                                                    subcommands: [XInputRaw.self, HIDDiff.self, HIDSniff.self, SlotWriteTest.self, Slots.self, Probe.self, HWStatus.self, GyroWatch.self])

    /// XInput (captured) version of hid-diff: optionally sends Space Station's "enable raw data"
    /// (`A5 50`) first, then prints changing bytes for N seconds. Needs root (USB capture).
    struct XInputRaw: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "xinput-raw")
        @Option(name: .long) var seconds: Double = 12
        @Flag(name: .long, help: "Do not send A5 50 before listening") var noEnable = false
        func run() throws {
            let s = try DeviceSession.open(preferring: .xinput); defer { s.close() }
            if !noEnable { try s.link.write(XInput.command(0x50)); print("sent A5 50 (enable raw data)") }
            var last: [UInt8: [UInt8]] = [:]          // keyed by r[15] tag / length so different report kinds don't mix
            var tags: [String: Int] = [:]
            let t0 = Date()
            print("watching for \(Int(seconds)) s — press one button at a time…")
            while Date().timeIntervalSince(t0) < seconds {
                guard let r: [UInt8] = try? s.link.waitForReport(timeout: 0.5, { (r: [UInt8]) -> [UInt8]? in r }) else { continue }
                let tag = r.count > 15 ? r[15] : UInt8(r.count)
                tags["\(r.count)B/\(String(format: "%02x", tag))", default: 0] += 1
                guard let prev = last[tag], prev.count == r.count else {
                    last[tag] = r; print(String(format: "%6.2fs  first %dB tag %02x: ", Date().timeIntervalSince(t0), r.count, tag) + r.map { String(format: "%02x", $0) }.joined(separator: " ")); continue
                }
                var changes: [String] = []
                for i in 0..<r.count where r[i] != prev[i] {
                    if abs(Int(r[i]) - Int(prev[i])) < 6 && ((r[i] ^ prev[i]) & 0xF0) == 0 && prev[i] != 0 { continue }
                    let diff = r[i] ^ prev[i]
                    let bits = (0..<8).filter { diff & (1 << $0) != 0 }.map { "b\($0)" }.joined(separator: ",")
                    changes.append(String(format: "[%d] %02x→%02x (%@)", i, prev[i], r[i], bits))
                }
                if !changes.isEmpty { print(String(format: "%6.2fs  tag %02x  ", Date().timeIntervalSince(t0), tag) + changes.joined(separator: "  ")) }
                last[tag] = r
            }
            print("report kinds: \(tags.sorted { $0.key < $1.key })")
        }
    }

    /// Watches DInput input reports for N seconds and prints every byte/bit that changes versus the idle
    /// report, with timestamps — press buttons one at a time to map them.
    struct HIDDiff: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "hid-diff")
        @Option(name: .long) var seconds: Double = 10
        func run() throws {
            let link = try HIDLink(); defer { link.close() }
            var baseline: [UInt8]? = nil
            var last: [UInt8]? = nil
            let t0 = Date()
            print("watching for \(Int(seconds)) s — press one button at a time…")
            while Date().timeIntervalSince(t0) < seconds {
                guard let r: [UInt8] = try? link.waitForReport(timeout: 0.5, { (r: [UInt8]) -> [UInt8]? in r }) else { continue }
                if baseline == nil { baseline = r; last = r; print("baseline (\(r.count) B): \(hex(r))"); continue }
                guard let prev = last, r.count == prev.count else { last = r; continue }
                var changes: [String] = []
                for i in 0..<r.count where r[i] != prev[i] {
                    // Ignore analogue jitter on bytes that only move a little.
                    if abs(Int(r[i]) - Int(prev[i])) < 6 && ((r[i] ^ prev[i]) & 0xF0) == 0 && baseline![i] != 0 { continue }
                    let diff = r[i] ^ prev[i]
                    let bits = (0..<8).filter { diff & (1 << $0) != 0 }.map { "b\($0)" }.joined(separator: ",")
                    changes.append(String(format: "[%d] %02x→%02x (%@)", i, prev[i], r[i], bits))
                }
                if !changes.isEmpty { print(String(format: "%6.2fs  ", Date().timeIntervalSince(t0)) + changes.joined(separator: "  ")) }
                last = r
            }
        }
        private func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }
    }

    /// Counts raw input reports on the DInput vendor interface for 2 s (transport smoke test).
    struct HIDSniff: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "hid-sniff")
        func run() throws {
            let link = try HIDLink(); defer { link.close() }
            do { try link.write(DInput.command(DInput.Cmd.deviceInfo)); print("write ok: \(DInput.command(DInput.Cmd.deviceInfo).map { String(format: "%02x", $0) }.joined(separator: " "))") }
            catch { print("write failed: \(error)") }
            var n = 0; var tags: [UInt8: Int] = [:]; var interesting: [[UInt8]] = []
            let t0 = Date()
            while Date().timeIntervalSince(t0) < 2 {
                if let r: [UInt8] = try? link.waitForReport(timeout: 0.5, { (r: [UInt8]) -> [UInt8]? in r }) {
                    n += 1
                    if r.count > 15 { tags[r[15], default: 0] += 1 }
                    if r.count > 2 && r[1] == 0xff && interesting.count < 4 { interesting.append(r) }
                }
            }
            print("reports in 2 s: \(n); r[15] histogram: \(tags.sorted { $0.key < $1.key })")
            for r in interesting { print("  ", r.map { String(format: "%02x", $0) }.joined(separator: " ")) }
        }
    }









    /// Write path for profiles: remaps A→B in a non-active slot, saves, reads back, activates it briefly,
    /// then restores the original bytes and the original active slot.
    struct SlotWriteTest: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "slot-write-test")
        @Option(help: "Slot to use for the test (default 3)") var slot: UInt8 = 3
        func run() throws {
            let s = try DeviceSession.open(preferring: .xinput); defer { s.close() }
            let active = try s.currentConfigId(); print("active slot \(active); testing on slot \(slot)")
            s.configId = slot
            let original = try s.readBlob(.config)
            guard var cfg = GamepadConfig(bytes: original) else { throw ValidationError("bad blob") }
            print("before: A → \(cfg.keys[.a]!) · title \"\(cfg.title)\"")
            cfg.keys[.a] = .key(.b); cfg.title = "apex4 test"
            let acks = try s.writeBlob(cfg.bytes, kind: .config); print("write acks \(acks.acks)/\(acks.packets)")
            try s.saveToFlash(); print("saved to flash")
            Thread.sleep(forTimeInterval: 0.5)
            let back = try require(GamepadConfig(bytes: try s.readBlob(.config)))
            print("after:  A → \(back.keys[.a]!) · title \"\(back.title)\" · other fields intact: \(back.keys[.c] == cfg.keys[.c] && back.leftStick == cfg.leftStick)")
            try s.applyConfig(slot: slot); print("activated slot \(slot) → current \(try s.currentConfigId()) (press A on the pad: it should act as B for a few seconds)")
            Thread.sleep(forTimeInterval: 6)
            try s.applyConfig(slot: active); print("restored active slot → \(try s.currentConfigId())")
            let r = try s.writeBlob(original, kind: .config); try s.saveToFlash()
            let now = try s.readBlob(.config)
            let diffs = zip(original, now).enumerated().filter { $0.element.0 != $0.element.1 }.map { "\($0.offset):\(String(format: "%02x→%02x", $0.element.0, $0.element.1))" }
            print("restored original bytes: acks \(r.acks)/\(r.packets), identical \(diffs.isEmpty)\(diffs.isEmpty ? "" : " — differing offsets: \(diffs.joined(separator: " "))")")
        }
        private func require<T>(_ v: T?) throws -> T { guard let v else { throw ValidationError("nil") }; return v }
    }

    /// Reads and decodes every on-board config slot (0…3) without changing anything.
    struct Slots: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "slots")
        @Option var count: Int = 4          // 8 = also the Switch-mode mirror slots 4…7
        func run() throws {
            let s = try DeviceSession.open(preferring: .xinput); defer { s.close() }
            let active = try? s.currentConfigId()
            for slot in 0..<count {
                s.configId = UInt8(slot)
                guard let cfg = GamepadConfig(bytes: try s.readBlob(.config)) else { print("slot \(slot): bad blob"); continue }
                let remapped = cfg.keys.filter { if case .identity = $0.value { return false } else { return true } }.count
                print("slot \(slot)\(active == UInt8(slot) ? " (active)" : ""): \"\(cfg.title)\" · dataVersion \(cfg.dataVersion) · \(remapped) remapped keys · sticks dz \(cfg.leftStick.deadZone)/\(cfg.rightStick.deadZone) · triggers \(cfg.leftTrigger.kind)/\(cfg.rightTrigger.kind) · motion \(cfg.motion.mapType) · macros \(cfg.macros.count)")
            }
            if let active { try s.applyConfig(slot: active) }   // reading a slot moves the pad's "current" slot; put it back
        }
    }

    /// Exercises the extra XInput commands confirmed in SS4 (read-only unless --motor / --slot given).
    struct Probe: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "xinput-probe")
        @Flag(help: "Buzz both motors briefly") var motor = false
        @Option(help: "Activate a config slot 0…3") var slot: UInt8?
        func run() throws {
            let s = try DeviceSession.open(preferring: .xinput); defer { s.close() }
            print("current config slot: \((try? s.currentConfigId()).map(String.init) ?? "no reply")")
            print("module versions (A5 30 01): \((try? s.moduleVersions().description) ?? "no reply")")
            print("status bar on: \((try? s.screenStatusBar()).map(String.init) ?? "no reply")")
            print("screen sleep: \((try? s.screenSleepTime()).map(String.init) ?? "no reply")")
            if motor { try s.motorTest(left: 200, right: 200); print("motor test sent"); Thread.sleep(forTimeInterval: 0.6); try s.motorTest(left: 0, right: 0) }
            if let slot { try s.applyConfig(slot: slot); print("applied slot \(slot); now: \((try? s.currentConfigId()).map(String.init) ?? "?")") }
        }
    }




}

extension Dev {

}

extension Dev {

}

extension Dev {

}


extension Dev {

}


extension Dev {
    /// Raw reply to the hardware-function status query (`A5 50 07` / `05 F2 03`) plus our parse.
    struct HWStatus: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "hw-status")
        @OptionGroup var ch: ChannelOption
        func run() throws {
            let s = try ch.open(); defer { s.close() }
            s.link.discardPending()
            switch s.channel {
            case .xinput: try s.link.write(XInput.command(XInput.Cmd.subFunc, 0x07))
            case .dinput: try s.link.write(DInput.command(DInput.Cmd.screenInfo, 0x03))
            }
            let t0 = Date(); var n = 0
            while Date().timeIntervalSince(t0) < 1.5, n < 6 {
                guard let r: [UInt8] = try? s.link.waitForReport(timeout: 0.5, { (r: [UInt8]) -> [UInt8]? in (s.channel == .xinput ? !(r.count > 1 && r[0] == 0 && r[1] == 0x14) : (r.count > 1 && r[1] != 0xFE)) ? r : nil }) else { break }
                n += 1
                print("reply: " + r.map { String(format: "%02x", $0) }.joined(separator: " "))
                if let j = s.channel == .xinput ? JoystickSettings.fromXInput(r) : JoystickSettings.fromDInput(r) { print("parsed: \(j)") }
            }
            if n == 0 { print("no reply") }
        }
    }










}



/// Prints the motion rates decoded from the DInput status report (bytes 4–6) plus the raw bytes that move,
/// to confirm which bytes carry the gyro and their sign. Rotate the pad slowly around each axis.
struct GyroWatch: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "gyro-watch")
    @Option(name: .long) var seconds: Double = 15
    @Flag(name: .long, help: "Temporarily set the slot's motion map type to Mouse (3) — the pad may only stream motion when the profile asks for it.") var enable = false
    func run() throws {
        var original: [UInt8]?
        let session = try DeviceSession.open(preferring: .dinput)
        if enable {
            session.configId = 0
            let bytes = try session.readBlob(.config)
            guard var cfg = GamepadConfig(bytes: bytes) else { throw ValidationError("config did not parse") }
            original = bytes
            cfg.motion.mapType = .mouse; cfg.motion.enableKey1 = 255; cfg.motion.enableKey2 = 255
            _ = try session.writeBlob(cfg.bytes, kind: .config); try session.saveToFlash()
            print("slot 0: motion map type → Mouse (always on) for the test")
        }
        session.close()
        defer {
            if let original, let r = try? DeviceSession.open(preferring: .dinput) {
                r.configId = 0
                if (try? r.writeBlob(original, kind: .config)) != nil, (try? r.saveToFlash()) != nil { print("slot 0 restored") } else { print("RESTORE FAILED") }
                r.close()
            }
        }
        Thread.sleep(forTimeInterval: 0.5)
        let link = try HIDLink(); defer { link.close() }
        let t0 = Date(); var n = 0; var first: [UInt8]?; var lastPrint = Date.distantPast; var rate = 0; var rateT = Date()
        let known: Set<Int> = [0, 1, 7, 8, 9, 10, 17, 19, 21, 22, 23, 24]
        print("rotate the controller: yaw (turn left/right), then pitch (tilt forward/back) — \(Int(seconds)) s")
        while Date().timeIntervalSince(t0) < seconds {
            guard let r: [UInt8] = try? link.waitForReport(timeout: 0.5, { (r: [UInt8]) -> [UInt8]? in r.count >= 32 && r[0] == 4 && r[1] == 0xFE ? r : nil }) else { continue }
            n += 1; rate += 1
            if first == nil { first = r; print("first: " + r.map { String(format: "%02x", $0) }.joined(separator: " ")) }
            if Date().timeIntervalSince(rateT) >= 1 { print("  \(rate) reports/s"); rate = 0; rateT = Date() }
            guard Date().timeIntervalSince(lastPrint) >= 0.15, let st = ControllerState(dinputReport: r), let f = first else { continue }
            lastPrint = Date()
            let changed = (0..<32).filter { !known.contains($0) && r[$0] != f[$0] }.map { String(format: "%d:%02x", $0, r[$0]) }.joined(separator: " ")
            if !changed.isEmpty { print(String(format: "%5.1fs  gyroX %5d  gyroY %5d   changed vs first: ", Date().timeIntervalSince(t0), st.gyroX, st.gyroY) + changed) }
        }
        print("reports: \(n)")
    }
}






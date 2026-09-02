// Developer experiments — not part of the supported CLI surface.

import ArgumentParser
import Foundation
import FlydigiKit
import FlydigiTransport

struct Dev: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Developer experiments (protocol re-tests).", shouldDisplay: false,
                                                    subcommands: [DInputRetest.self, HIDSniff.self, HIDDiff.self, XInputRaw.self, DualOpen.self, DInputSlots.self, DInputCursor.self, DInputApply.self, HWStatus.self, RandomId.self, Probe.self, Slots.self, SlotWriteTest.self, ReadAffectsActive.self, ScreenSettings.self, MacroTest.self, ForceTest.self])

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

    /// ForceAdapt: Race (stiff, stroke 50) on both triggers for 8 s, then Sniper for 8 s, then Normal.
    struct ForceTest: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "force-test")
        func run() throws {
            let s = try DeviceSession.open(preferring: .xinput); defer { s.close() }
            try s.setForceTrigger(.race(stroke: 50, resistance: 8, matchStroke: true), side: .both); print("Race (resistance 8) on both triggers — 8 s")
            Thread.sleep(forTimeInterval: 8)
            try s.setForceTrigger(.sniper(stroke: 60, pressure: 5, strength: 8, frequency: 5, matchStroke: true), side: .both); print("Sniper — 8 s")
            Thread.sleep(forTimeInterval: 8)
            try s.setForceTrigger(.normal, side: .both); print("back to Normal")
        }
    }

    /// Toggles the status bar and sleep time, verifying each read-back, then restores the originals.
    struct ScreenSettings: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "screen-settings-test")
        func run() throws {
            let s = try DeviceSession.open(preferring: .xinput); defer { s.close() }
            let bar = try s.screenStatusBar(), sleep = try s.screenSleepTime()
            print("status bar on=\(bar), sleep=\(sleep)")
            try s.setScreenStatusBar(!bar); Thread.sleep(forTimeInterval: 0.5); print("set status bar on=\(!bar) → read \(try s.screenStatusBar())")
            try s.setScreenSleepTime(sleep == 15 ? 30 : 15); Thread.sleep(forTimeInterval: 0.5); print("set sleep \(sleep == 15 ? 30 : 15) → read \(try s.screenSleepTime())")
            Thread.sleep(forTimeInterval: 4)
            try s.setScreenStatusBar(bar); try s.setScreenSleepTime(sleep); Thread.sleep(forTimeInterval: 0.5)
            print("restored → status bar on=\(try s.screenStatusBar()), sleep=\(try s.screenSleepTime())")
        }
    }

    /// Writes a macro (M1 → A press/release, B press/release) into a slot, activates it for 15 s, then restores.
    struct MacroTest: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "macro-test")
        @Option var slot: UInt8 = 3
        func run() throws {
            let s = try DeviceSession.open(preferring: .xinput); defer { s.close() }
            let active = try s.currentConfigId()
            s.configId = slot
            let original = try s.readBlob(.config)
            guard var cfg = GamepadConfig(bytes: original) else { throw ValidationError("bad blob") }
            cfg.keys[.m1] = .macro
            cfg.macros = [GamepadConfig.Macro(key: ControllerKey.m1.rawValue, count: 1, enable: .once, actions: [
                .init(durationMs: 0, key: ControllerKey.a.rawValue, event: .press),
                .init(durationMs: 100, key: ControllerKey.a.rawValue, event: .release),
                .init(durationMs: 100, key: ControllerKey.b.rawValue, event: .press),
                .init(durationMs: 100, key: ControllerKey.b.rawValue, event: .release),
            ])]
            let acks = try s.writeBlob(cfg.bytes, kind: .config); try s.saveToFlash()
            let back = GamepadConfig(bytes: try s.readBlob(.config))
            print("write acks \(acks.acks)/\(acks.packets); read back: M1=\(back?.keys[.m1].map { "\($0)" } ?? "?") macros=\(back?.macros.count ?? -1) actions=\(back?.macros.first?.actions.count ?? -1)")
            if let m = back?.macros.first { print("  macro: key \(m.key) count \(m.count) enable \(m.enable) actions \(m.actions.map { "\($0.durationMs)ms \(ControllerKey(rawValue: $0.key)!) \($0.event)" })") }
            try s.applyConfig(slot: slot); print("slot \(slot) active for 15 s — press M1 on the pad: it should fire A then B")
            Thread.sleep(forTimeInterval: 15)
            try s.applyConfig(slot: active); _ = try s.writeBlob(original, kind: .config); try s.saveToFlash()
            print("restored slot \(slot) and active slot \(try s.currentConfigId())")
        }
    }

    /// Does reading slot N's config change what `A5 20` reports as the current slot?
    struct ReadAffectsActive: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "read-affects-active")
        func run() throws {
            let s = try DeviceSession.open(preferring: .xinput); defer { s.close() }
            print("current before: \(try s.currentConfigId())")
            s.configId = 2; _ = try s.readBlob(.config); Thread.sleep(forTimeInterval: 0.3)
            print("current after reading slot 2: \(try s.currentConfigId())")
            try s.applyConfig(slot: 0); print("re-applied 0 → \(try s.currentConfigId())")
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
        func run() throws {
            let s = try DeviceSession.open(preferring: .xinput); defer { s.close() }
            let active = try? s.currentConfigId()
            for slot in 0..<4 {
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

    /// DInput read-random-id framing experiment: 5-byte (3.4 code) vs 12-byte zero-padded vs no crc.
    struct RandomId: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "dinput-randomid")
        func run() throws {
            let link = try HIDLink(); defer { link.close() }
            func raw(_ secs: Double) -> [String] {
                var out: [String] = []; let t0 = Date()
                while Date().timeIntervalSince(t0) < secs && out.count < 3 {
                    if let r: [UInt8] = try? link.waitForReport(timeout: 0.3, { (r: [UInt8]) -> [UInt8]? in (r.count > 2 && r[1] == 0xff) ? r : nil }) {
                        out.append(r.prefix(18).map { String(format: "%02x", $0) }.joined(separator: " "))
                    }
                }
                return out
            }
            _ = raw(0.5)   // drain stale
            let variants: [(String, [UInt8])] = [
                ("5 B  05 50 02 00 crc", Checksum.apply([5, 0x50, 2, 0, 0])),
                ("12 B 05 50 02 00 crc 00…", Checksum.apply([5, 0x50, 2, 0, 0]) + [UInt8](repeating: 0, count: 7)),
                ("12 B 05 50 02 00 00…  (no crc)", [5, 0x50, 2, 0] + [UInt8](repeating: 0, count: 8)),
                ("12 B 05 50 04 00… (all ids, SS4)", [5, 0x50, 4] + [UInt8](repeating: 0, count: 9)),
                ("12 B 05 EB A0 (current cfg id, SS4)", [5, 0xEB, 0xA0] + [UInt8](repeating: 0, count: 9)),
            ]
            for (label, pkt) in variants {
                try link.write(pkt)
                print("\(label) → \(raw(1.2))")
            }
        }
    }

    /// Re-tests the three DInput details flagged by the Space Station 4 analysis (protocol.md §3):
    /// config-write start EF vs EA, LED-write start E6 vs E7, save-to-flash byte order.
    struct DInputRetest: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "dinput-retest")
        func run() throws {
            let link = try HIDLink(); defer { link.close() }
            let s = DeviceSession(link: link)
            let info = try s.deviceInfo(); print("device \(info.deviceId) fw \(info.firmware)")
            let cfg = try s.readBlob(.config), led = try s.readBlob(.led)
            print("config \(cfg.count) B, led \(led.count) B (read back unchanged at the end)")

            func raw(_ secs: Double, _ max: Int = 3) -> [String] {
                var out: [String] = []; let t0 = Date()
                while Date().timeIntervalSince(t0) < secs && out.count < max {
                    if let r: [UInt8] = try? link.waitForReport(timeout: 0.3, { (r: [UInt8]) -> [UInt8]? in (r.count > 2 && r[1] == 0xff) ? r : nil }) {
                        out.append(r.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))
                    }
                }
                return out
            }
            func writeBlob(_ blob: [UInt8], header: [UInt8], dataCmd: UInt8, label: String) throws {
                let n = UInt8((blob.count + 9) / 10)
                var acks = 0; var ackTags = Set<UInt8>()
                try link.write(header)
                print("  \(label)\n    header reply: \(raw(1.0, 2))")
                for i in 0..<Int(n) {
                    var p = [UInt8](repeating: 0, count: 14); p[0] = 5; p[1] = dataCmd
                    let chunk = blob[(i*10)..<min((i+1)*10, blob.count)]; p.replaceSubrange(2..<(2+chunk.count), with: chunk); p[12] = 0xA0; p[13] = UInt8(i)
                    try link.write(p)
                    let replies = raw(i < 2 ? 1.0 : 0.15, 1)
                    if i < 2 { print("    parcel \(i) reply: \(replies)") }
                    if !replies.isEmpty { acks += 1 }
                }
                print("    data acks \(acks)/\(Int(n))")
                _ = ackTags
            }
            // LED write: our E7 header vs SS4's E6 header (same 500 B blob → no visible change)
            print("LED write starts:")
            try writeBlob(led, header: [5, 0xE7, 0, 50, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], dataCmd: 0x33, label: "E7 <cfg> <N>        (ours)")
            Thread.sleep(forTimeInterval: 0.5)
            try writeBlob(led, header: [5, 0xE6, 0, 0, 50, 0, 0, 0, 0, 0, 0, 0, 0, 0], dataCmd: 0x33, label: "E6 <cfg> <start> <N> (SS4)")
            Thread.sleep(forTimeInterval: 0.5)
            // Config write: our EA vs SS4's EF (same 790 B blob)
            print("Config write starts:")
            try writeBlob(cfg, header: [5, 0xEA, 79, 0xA0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], dataCmd: 0x22, label: "EA <N> A0 <cfg>          (ours)")
            Thread.sleep(forTimeInterval: 0.5)
            try writeBlob(cfg, header: [5, 0xEF, 0, 79, 0xA0, 0, 0, 0, 0, 0, 0, 0, 0, 0], dataCmd: 0x22, label: "EF <start> <N> A0 <cfg>  (SS4)")
            Thread.sleep(forTimeInterval: 0.5)
            // Save-to-flash byte order: read id, save BE(id+1), read; save LE(id+1), read.
            print("Save-to-flash byte order:")
            func readId() throws -> UInt16 {
                try link.write(DInput.readRandomId(configId: 0))
                print("  readRandomId raw replies: \(raw(1.5, 3))")
                try link.write(DInput.readRandomId(configId: 0))
                return try link.waitForReport(timeout: 2) { (r: [UInt8]) -> UInt16? in DInputReply.randomId(r)?.id }
            }
            let id0 = try readId(); print("  random id (as BE hi,lo) = \(id0) raw=\(String(format: "%02x %02x", id0 >> 8, id0 & 0xff))")
            let target = UInt16(0x0102)
            try link.write(Checksum.apply([5, 0x50, 3, 0x01, 0x02, 0]))            // bytes 01 02
            let okA: Bool = (try? link.waitForReport(timeout: 3) { (r: [UInt8]) -> Bool? in DInputReply.saveToFlashOK(r) }) ?? false
            let idA = try readId(); print("  wrote bytes 01 02 → save ok=\(okA), read back raw=\(String(format: "%02x %02x", idA >> 8, idA & 0xff))  (BE would read 01 02; LE would read 01 02 too if symmetric)")
            print("  → the firmware echoes bytes; byte order is a convention on our side only. Restoring original id \(id0).")
            try link.write(DInput.saveToFlash(randomId: id0))
            _ = try? link.waitForReport(timeout: 3) { (r: [UInt8]) -> Bool? in DInputReply.saveToFlashOK(r) }
            _ = target
            let cfg2 = try s.readBlob(.config), led2 = try s.readBlob(.led)
            print("config unchanged: \(cfg2 == cfg), led unchanged: \(led2 == led)")
        }
    }
}

extension Dev {
    /// Opens the DInput vendor interface twice in one process (like the app: raw-input monitor + a
    /// command session) and checks whether the second link still gets replies while the first streams.
    struct DualOpen: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "dual-open")
        func run() throws {
            let monitor = try HIDLink(); defer { monitor.close() }
            let stop = DispatchSemaphore(value: 0)
            let counter = NSLock(); var seen = 0
            let t = Thread {
                while stop.wait(timeout: .now()) != .success {
                    if let _: [UInt8] = try? monitor.waitForReport(timeout: 0.2, { (r: [UInt8]) -> [UInt8]? in r }) { counter.lock(); seen += 1; counter.unlock() }
                }
            }
            t.start()
            Thread.sleep(forTimeInterval: 0.5)
            let session = try DeviceSession(link: try HIDLink()); defer { session.close() }
            do { let i = try session.deviceInfo(); print("second link: deviceInfo OK → fw \(i.firmware)") } catch { print("second link: deviceInfo FAILED → \(error)") }
            do { let b = try session.readBlob(.led); print("second link: LED blob OK (\(b.count) B)") } catch { print("second link: LED blob FAILED → \(error)") }
            do { session.configId = 0; let c = try session.readBlob(.config); print("second link: config slot 0 OK title \"\(GamepadConfig(bytes: c)?.title ?? "?")\"") } catch { print("second link: config FAILED → \(error)") }
            stop.signal()
            counter.lock(); print("monitor link saw \(seen) reports meanwhile"); counter.unlock()
        }
    }
}

extension Dev {
    /// DInput: what does `05 EB <id>` return for ids 0…4, and what does the random-id reply say is the config id?
    struct DInputSlots: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "dinput-slots")
        func run() throws {
            let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
            for id in 0...4 {
                s.configId = UInt8(id)
                let title = (try? s.readBlob(.config)).flatMap { GamepadConfig(bytes: $0) }.map { "\"\($0.title)\" dataVersion \($0.dataVersion)" } ?? "no reply"
                try? s.link.write(DInput.readRandomId(configId: UInt8(id)))
                let rid: (id: UInt16, configId: UInt8)? = try? s.link.waitForReport(timeout: 1) { DInputReply.randomId($0) }
                print("read id \(id): \(title) · randomId reply: \(rid.map { "id \($0.id) configId \($0.configId)" } ?? "none")")
            }
        }
    }
}

extension Dev {
    /// DInput cursor test: read ids in a sequence and see whether id 0 follows the last id read.
    struct DInputCursor: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "dinput-cursor")
        func run() throws {
            let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
            for id in [0, 1, 0, 2, 0, 3, 0] {
                s.configId = UInt8(id)
                let t = (try? s.readBlob(.config)).flatMap { GamepadConfig(bytes: $0) }.map { "\"\($0.title)\" v\($0.dataVersion)" } ?? "no reply"
                print("read \(id) → \(t)")
            }
        }
    }
}


extension Dev {
    /// DInput: does `05 50 05 <slot>` activate a slot, and does id 0 then read that slot?
    struct DInputApply: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "dinput-apply")
        @Argument var slot: UInt8
        func run() throws {
            let s = try DeviceSession.open(preferring: .dinput); defer { s.close() }
            try s.applyConfig(slot: slot)
            s.configId = 0
            let t = (try? s.readBlob(.config)).flatMap { GamepadConfig(bytes: $0) }.map { "\"\($0.title)\" v\($0.dataVersion)" } ?? "no reply"
            print("apply \(slot) → read 0 → \(t)")
        }
    }
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

// Developer experiments — not part of the supported CLI surface.

import ArgumentParser
import Foundation
import FlydigiKit
import FlydigiTransport

struct Dev: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Developer experiments (protocol re-tests).", shouldDisplay: false,
                                                    subcommands: [DInputRetest.self, HIDSniff.self, RandomId.self])

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

import Testing
import Foundation
@testable import FlydigiKit

// Byte strings below were captured from a real Apex 4 session (see docs/protocol.md).

func hex(_ s: String) -> [UInt8] {
    var out: [UInt8] = []; var i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); out.append(UInt8(s[i..<j], radix: 16)!); i = j }
    return out
}

func fixture(_ name: String) throws -> [UInt8] {
    let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    return [UInt8](try Data(contentsOf: url))
}

@Suite struct XInputFraming {
    @Test func deviceInfoCommand() {
        #expect(XInput.command(XInput.Cmd.deviceInfo) == hex("a510000000000000000000000000b5"))
        #expect(XInput.command(XInput.Cmd.dongleInfo) == hex("a511000000000000000000000000b6"))
    }

    @Test func screenStartPacketMatchesCapture() {
        // 3-frame dry run: frame 1 of 3, 25604 bytes
        let plan = ScreenUploadPlan(frames: Array(repeating: [UInt8](repeating: 0, count: 25604), count: 3))
        guard case let .start(frame, packet) = plan.steps()[0] else { Issue.record("no start"); return }
        #expect(frame == 1)
        #expect(packet == hex("a5d009010103010264044900000000"))
    }

    @Test func screenDataPacketLayout() {
        let frame = [UInt8](0..<60).map { UInt8($0) }
        let steps = ScreenUploadPlan(frames: [frame]).steps()
        guard case let .data(_, offset, p) = steps[1] else { Issue.record("no data step"); return }
        #expect(offset == 0 && p.count == 31 && p[0] == 0xA5 && p[1] == 0xD1)
        #expect(Array(p[4..<30]) == Array(frame[0..<26]))
        #expect(p[30] == p[1..<30].reduce(0) { $0 &+ $1 })
        // last chunk is FF padded
        guard case let .data(_, off3, p3) = steps[3] else { Issue.record("no 3rd data"); return }
        #expect(off3 == 52 && Array(p3[12..<30]) == [UInt8](repeating: 0xFF, count: 18))
        #expect(steps.count == 1 + 3 + 1 + 1)   // start, 3 data, end, endAll
    }

    @Test func blobWriteParcels() {
        let blob = [UInt8](repeating: 0xAB, count: 500)
        let pk = XInput.writeParcels(blob, kind: .led, configId: 0)
        #expect(pk.count == 51)
        #expect(Array(pk[0][0..<4]) == [0xA5, 0x2A, 0x00, 50])
        #expect(pk[1][1] == 0x29 && pk[1][12] == 0xA0 && pk[1][13] == 0 && pk[50][13] == 49)
    }

    @Test func saveToFlash() {
        #expect(XInput.saveToFlash(randomId: 26) == hex("a55003001a00000000000000000012"))
    }
}

@Suite struct DInputFraming {
    @Test func commands() {
        #expect(DInput.command(DInput.Cmd.deviceInfo) == hex("05ec00000000000000000000"))
        #expect(DInput.readRandomId(configId: 0) == [5, 0x50, 2, 0, 0x57, 0, 0, 0, 0, 0, 0, 0])
    }
    @Test func ledWriteParcels() {
        let pk = DInput.writeParcels([UInt8](repeating: 1, count: 500), kind: .led, configId: 0)
        #expect(pk.count == 51 && pk[0].prefix(4) == [5, 231, 0, 50])
        #expect(pk[1].prefix(2) == [5, 51] && pk[1][12] == 0xA0 && pk[1][13] == 0)
    }
}

@Suite struct Parsing {
    @Test func dinputDeviceInfo() {
        let r = hex("04fff05400f25a9054306804020102ec017f007f007f7f000000000054000000")
        let info = DInputReply.deviceInfo(r)
        #expect(info?.deviceId == 84 && info?.firmware == "6.8.3.0" && info?.isWired == true && info?.isApex4Family == true)
    }
    @Test func xinputDeviceInfo() {
        let r = hex("0014000000000000000000000000a51054f25a90543068040201020000000000")
        let info = XInputReply.deviceInfo(r)
        #expect(info?.deviceId == 84 && info?.firmware == "6.8.3.0" && info?.mac == [0xf2, 0x5a, 0x90, 0x54])
    }
    @Test func screenAck() {
        var r = [UInt8](repeating: 0, count: 64)
        r.replaceSubrange(14..<24, with: hex("5aa5d1050063d60f0000"))
        let a = XInputReply.screenAck(r)
        #expect(a == ScreenAck(cmd: 0xD1, ret: 0, value: 25558))
    }
    @Test func dinputScreenAck() {
        let r = hex("04fff05aa5d00300d30000000000000000000000000000000000000000000000")
        #expect(DInputReply.screenAck(r)?.cmd == 0xD0)
    }
}

@Suite struct Blobs {
    @Test func ledFactoryConfig() throws {
        let cfg = try #require(LEDConfig(bytes: try fixture("led_factory_500.bin")))
        #expect(cfg.mode == .gradient && cfg.speed == 50 && cfg.brightness == 50 && cfg.activeGroups == 4)
        #expect(cfg.colours(ofGroup: 0) == [.init(r: 0, g: 0, b: 100), .init(r: 100, g: 0, b: 0), .init(r: 0, g: 100, b: 0)])
        #expect(cfg.bytes == (try fixture("led_factory_500.bin")))   // round-trip
    }
    @Test func ledEdit() throws {
        var cfg = try #require(LEDConfig(bytes: try fixture("led_factory_500.bin")))
        cfg.setSteady(.init(rgb8: 255, 0, 0))
        #expect(cfg.mode == .steady && cfg.groups[0][0] == .init(r: 100, g: 0, b: 0) && cfg.groups[3][1].isOff)
        #expect(cfg.bytes.count == 500)
    }
    @Test func assembler() {
        var a = BlobAssembler(expectedLength: 25)
        a.add(index: 2, data: [UInt8](repeating: 3, count: 10))
        a.add(index: 0, data: [UInt8](repeating: 1, count: 10))
        #expect(!a.isComplete)
        a.add(index: 1, data: [UInt8](repeating: 2, count: 10))
        #expect(a.assemble()?.count == 25 && a.assemble()?[24] == 3)
    }
}

@Suite struct LVGL {
    @Test func headerAndSize() {
        let f = Screen.encodeFrame(rgb: [UInt8](repeating: 0, count: 160 * 80 * 3))
        #expect(f.count == Screen.frameLength && Array(f[0..<4]) == [0x04, 0x80, 0x02, 0x0A])
        #expect(Screen.header(of: f)! == (4, 160, 80))
    }
    @Test func pixelQuantisationIsBigEndian565() {
        let f = Screen.encodeFrame(rgb: [40, 88, 248], width: 1, height: 1)
        // R 40→5, G 88→22, B 248→31  → 0x2ADF
        #expect(f[4] == 0x2A && f[5] == 0xDF)
    }
    @Test func matchesFlydigiConverterOnFactoryFrame() throws {
        // frame 1 of Flydigi's default GIF, decoded to RGB with ImageIO, must match the bin our
        // Python prototype uploaded successfully (identical algorithm to lvImage2bin_x64.dll).
        let png = try fixture("screen_frame1_160x80.png")
        let rgb = try #require(TestImage.rgb8(png: png))
        #expect(Screen.encodeFrame(rgb: rgb) == (try fixture("screen_frame1_lvgl.bin")))
    }
}


@Suite struct ConfigBlob {
    @Test func decodesFactoryConfig() throws {
        let cfg = try #require(GamepadConfig(bytes: try fixture("config_factory_790.bin")))
        #expect(cfg.protoVersion == 0x0300 && cfg.title == "常规游戏配置")
        #expect(cfg.keys[.c] == .key(.thumbL) && cfg.keys[.z] == .key(.thumbR) && cfg.keys[.a] == .identity)
        #expect(cfg.leftStick.end == 127 && cfg.leftTrigger.kind == .normal && cfg.motion.mapType == .off)
        #expect(cfg.vibration.enabled && cfg.vibration.left.scale == 60)
        #expect(cfg.macros.isEmpty)
    }
    @Test func roundTripsUnchanged() throws {
        let raw = try fixture("config_factory_790.bin")
        #expect(GamepadConfig(bytes: raw)?.bytes == raw)
    }
    @Test func encodesEdits() throws {
        var cfg = try #require(GamepadConfig(bytes: try fixture("config_factory_790.bin")))
        cfg.keys[.a] = .key(.b); cfg.title = "Test"; cfg.leftStick.deadZone = 10
        let again = try #require(GamepadConfig(bytes: cfg.bytes))
        #expect(again.keys[.a] == .key(.b) && again.title == "Test" && again.leftStick.deadZone == 10)
        #expect(again.keys[.c] == .key(.thumbL))   // untouched fields survive
    }
}

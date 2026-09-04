import Testing
import Foundation
@testable import FlydigiKit

struct SS4ProfileTests {
    private func fixture(_ name: String) throws -> [UInt8] {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return [UInt8](try Data(contentsOf: url))
    }

    @Test func factoryBlobSurvivesBeanRoundTrip() throws {
        let raw = try fixture("config_factory_790.bin")
        let bean = SS4Profile(blob: raw)
        #expect(bean.protoVersion == 0x0300 && bean.keys.count == 32)
        #expect(bean.title == GamepadConfig(bytes: raw)?.title)
        let back = bean.blob()
        // Space Station's conversion is lossy on purpose (0xFF fills, integer stick maths) — what matters is that
        // the fields the app edits come back identical.
        let a = try #require(GamepadConfig(bytes: raw))
        let b = try #require(GamepadConfig(bytes: back))
        #expect(a.keys == b.keys)
        #expect(a.motion == b.motion)
        #expect(a.vibration == b.vibration)
        #expect(a.leftTrigger == b.leftTrigger)
        #expect(a.rightTrigger == b.rightTrigger)
        #expect(a.macros == b.macros)
        #expect(a.title == b.title)
        // Space Station's stick maths for proto 3.0 is lossy (percent conversions with integer division) — the curve
        // type, dead zone and edge survive; the intermediate points move by a few units, as they do in Space Station.
        #expect(a.leftStick.curve == b.leftStick.curve)
        #expect(a.leftStick.deadZone == b.leftStick.deadZone)
        #expect(a.leftStick.end == b.leftStick.end)
    }

    @Test func protobufRoundTrip() throws {
        var bean = SS4Profile(blob: try fixture("config_factory_790.bin"))
        bean.led = SS4Profile.Led(led: try #require(LEDConfig(bytes: try fixture("led_factory_500.bin"))))
        let pb = bean.protobuf()
        let again = SS4Profile(protobuf: pb)
        #expect(again == bean)
        #expect(again.led?.groups.count == 16)
    }

    @Test func shareStringIsHexDash() throws {
        let bean = SS4Profile(blob: try fixture("config_factory_790.bin"))
        let s = bean.shareString
        #expect(s.hasPrefix("10-80-06-"))          // field 2 (protoVersion 0x0300 = 768 → varint 80 06)
        #expect(SS4Profile(shareString: s) == bean)
        #expect(SS4Profile(shareString: "\"" + s + "\"") == bean)   // JSON-quoted, as the API returns it
        #expect(SS4Profile(shareString: "zz-01") == nil)
    }

    @Test func negativeIntEncodesLikeProtobuf() {
        var w = Protobuf.Writer(); w.int(3, -1)
        #expect(w.bytes == [0x18, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
        let fs = Protobuf.fields(w.bytes)
        #expect(Protobuf.intValue(fs, 3) == -1)
    }
}

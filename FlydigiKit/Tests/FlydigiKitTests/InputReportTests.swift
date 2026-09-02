import Testing
import Foundation
@testable import FlydigiKit

struct InputReportTests {
    /// Idle report captured from an Apex 4 in DInput mode (dev hid-diff, 2026-09-01).
    static let idle: [UInt8] = [0x04, 0xfe, 0x66, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x7f, 0, 0x7f, 0, 0x7f, 0x7f, 0, 0, 0, 0, 0, 0x54, 0, 0, 0]

    @Test func idleReportHasNothingPressed() {
        let s = ControllerState(dinputReport: Self.idle)!
        #expect(s.pressed.isEmpty)
        #expect(abs(s.leftX) < 0.01 && abs(s.leftY) < 0.01 && abs(s.rightX) < 0.01 && abs(s.rightY) < 0.01)
        #expect(s.leftTrigger == 0 && s.rightTrigger == 0)
    }

    @Test func paddlesAndSystemKeys() {
        var r = Self.idle
        r[7] = 0x04 | 0x20          // M1 + M4 (bits seen in the capture)
        r[8] = 0x01 | 0x08          // Fn (menu) + Home
        let s = ControllerState(dinputReport: r)!
        #expect(s.pressed == [.m1, .m4, .menu, .home])
    }

    @Test func faceButtonsAndAxes() {
        var r = Self.idle
        r[9] = 0x10 | 0x01          // A + Up
        r[10] = 0x04 | 0x40         // LB + left stick click
        r[17] = 0xff; r[19] = 0x00  // left stick full right, full up
        r[23] = 0x80                // LT half
        let s = ControllerState(dinputReport: r)!
        #expect(s.pressed == [.a, .up, .lb, .thumbL])
        #expect(s.leftX > 0.99 && s.leftY > 0.99)
        #expect(abs(s.leftTrigger - 0.5) < 0.01)
    }

    /// Idle XInput interrupt report captured with `apex4 dev xinput-raw` (2026-09-02); M1 at byte 19 bit 2.
    @Test func xinputReportCarriesPaddles() {
        var r: [UInt8] = [0x00, 0x14, 0, 0, 0, 0, 0, 0, 0, 0, 0x70, 0xf9, 0xa0, 0, 0, 0, 0, 0, 0, 0, 0, 0x80, 0x80, 0x7c, 0x80, 0, 0, 0, 0, 0xff, 0xff, 0]
        #expect(ControllerState(xinputReport: r)!.pressed.isEmpty)
        r[19] = 0x04; r[17] = 0x10; r[25] = 0xff
        let s = ControllerState(xinputReport: r)!
        #expect(s.pressed == [.m1, .a])
        #expect(s.leftTrigger == 1)
        #expect(abs(s.leftX) < 0.01)
    }

    @Test func rejectsOtherReports() {
        var r = Self.idle; r[1] = 0xff
        #expect(ControllerState(dinputReport: r) == nil)
        #expect(ControllerState(dinputReport: [0x04, 0xfe]) == nil)
    }
}

struct FirmwareImageTests {
    /// Synthetic Telink-style image: size field at 0x18, KNLT at 0x08, CRC32 appended.
    static func image(size: Int) -> Data {
        var d = Data(repeating: 0xAB, count: size)
        d.replaceSubrange(8..<12, with: "KNLT".utf8)
        let n = UInt32(size)
        d[0x18] = UInt8(n & 0xFF); d[0x19] = UInt8(n >> 8 & 0xFF); d[0x1A] = UInt8(n >> 16 & 0xFF); d[0x1B] = UInt8(n >> 24)
        let crc = FirmwareImage.crc32(d.subdata(in: 0..<(size - 4)))
        d[size - 4] = UInt8(crc & 0xFF); d[size - 3] = UInt8(crc >> 8 & 0xFF); d[size - 2] = UInt8(crc >> 16 & 0xFF); d[size - 1] = UInt8(crc >> 24)
        return d
    }

    @Test func validImagePasses() throws {
        let img = try FirmwareImage(data: Self.image(size: 1000))
        try img.validate()
        #expect(img.packetCount == 63)
        #expect(img.block(62).suffix(8).allSatisfy { $0 == 0xFF })   // 1000 = 62*16 + 8 → padded
    }

    @Test func corruptedImageFails() throws {
        var d = Self.image(size: 512); d[100] ^= 0xFF
        let img = try FirmwareImage(data: d)
        #expect(throws: FirmwareImage.Problem.self) { try img.validate() }
    }

    @Test func knownCRCs() {
        #expect(FirmwareImage.crc32(Data("123456789".utf8)) == 0xCBF4_3926)          // CRC-32/IEEE check value
        #expect(FirmwareImage.crc16Modbus(Array("123456789".utf8)) == 0x4B37)         // CRC-16/MODBUS check value
    }

    @Test func versions() {
        #expect(FirmwareVersion.string(hi: 0x68, lo: 0x37) == "6.8.3.7")
        #expect(FirmwareVersion.isNewer("6.8.3.7", than: "6.8.3.0"))
        #expect(!FirmwareVersion.isNewer("6.8.3.0", than: "6.8.3.7"))
        #expect(!FirmwareVersion.isNewer("6.8.3.0", than: "6.8.3.0"))
    }
}

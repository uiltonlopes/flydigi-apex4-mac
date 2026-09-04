import Testing
import Foundation
@testable import FlydigiKit

struct OTATests {
    @Test func crc16ModbusCheckValue() {
        #expect(FirmwareImage.crc16Modbus(Array("123456789".utf8)) == 0x4B37)
    }
    @Test func startAndEndReportsMatchSpaceStation() {
        let start = OTAPacket.report(payload: OTAPacket.startPayload)
        #expect(start.count == 64)
        #expect(Array(start.prefix(6)) == [0x05, 0x02, 0x02, 0x00, 0x01, 0xFF])
        // END after packet 0x2765 (10086 packets): n = 0x2765, m = 0x10000 − n = 0xD89B
        let end = OTAPacket.report(payload: OTAPacket.endPayload(lastIndex: 0x2765))
        #expect(Array(end.prefix(10)) == [0x05, 0x02, 0x06, 0x00, 0x02, 0xFF, 0x65, 0x27, 0x9B, 0xD8])
    }
    @Test func dataPacketLayoutAndCRC() {
        let block = [UInt8](repeating: 0xAB, count: 16)
        let p = OTAPacket.packet(index: 0x0102, block: block)
        #expect(p.count == 20)
        #expect(p[0] == 0x02 && p[1] == 0x01)
        let crc = FirmwareImage.crc16Modbus(Array(p[0..<18]))
        #expect(p[18] == UInt8(crc & 0xFF) && p[19] == UInt8(crc >> 8))
        // three packets per report → length byte 0x3C, padded to 64
        let r = OTAPacket.report(payload: p + p + p)
        #expect(r[2] == 0x3C && r.count == 64)
    }
    @Test func resultReportParsing() {
        #expect(OTAPacket.resultCode([0x05, 0x02, 0x03, 0x00, 0x06, 0xFF, 0x09, 0x00]) == 9)
        #expect(OTAPacket.resultCode([0x05, 0x02, 0x03, 0x00, 0x06, 0xFF, 0x00]) == 0)
        #expect(OTAPacket.resultCode([0x05, 0x01, 0x08, 0x00, 0x01, 0x02]) == nil)
    }
}

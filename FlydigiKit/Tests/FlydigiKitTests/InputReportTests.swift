import Testing
import Foundation
@testable import FlydigiKit

struct InputReportTests {
    /// Idle report captured from an Apex 4 in DInput mode (dev hid-diff, 2026-09-01).
    static let idle: [UInt8] = [0x04, 0xfe, 0x66, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x7f, 0, 0x7f, 0, 0x7f, 0x7f, 0, 0, 0, 0, 0, 0x54, 0, 0, 0]

    @Test func idleReportHasNothingPressed() {
        let s = DInputState(report: Self.idle)!
        #expect(s.pressed.isEmpty)
        #expect(abs(s.leftX) < 0.01 && abs(s.leftY) < 0.01 && abs(s.rightX) < 0.01 && abs(s.rightY) < 0.01)
        #expect(s.leftTrigger == 0 && s.rightTrigger == 0)
    }

    @Test func paddlesAndSystemKeys() {
        var r = Self.idle
        r[7] = 0x04 | 0x20          // M1 + M4 (bits seen in the capture)
        r[8] = 0x01 | 0x08          // Fn (menu) + Home
        let s = DInputState(report: r)!
        #expect(s.pressed == [.m1, .m4, .menu, .home])
    }

    @Test func faceButtonsAndAxes() {
        var r = Self.idle
        r[9] = 0x10 | 0x01          // A + Up
        r[10] = 0x04 | 0x40         // LB + left stick click
        r[17] = 0xff; r[19] = 0x00  // left stick full right, full up
        r[23] = 0x80                // LT half
        let s = DInputState(report: r)!
        #expect(s.pressed == [.a, .up, .lb, .thumbL])
        #expect(s.leftX > 0.99 && s.leftY > 0.99)
        #expect(abs(s.leftTrigger - 0.5) < 0.01)
    }

    @Test func rejectsOtherReports() {
        var r = Self.idle; r[1] = 0xff
        #expect(DInputState(report: r) == nil)
        #expect(DInputState(report: [0x04, 0xfe]) == nil)
    }
}

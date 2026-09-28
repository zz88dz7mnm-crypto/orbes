import XCTest
@testable import OrbexCore

final class ClockTests: XCTestCase {
    func testHandAngles() {
        let a = ClockMath.angles(hour: 3, minute: 0, second: 0)
        XCTAssertEqual(a.hour, 90, accuracy: 0.001)
        XCTAssertEqual(a.minute, 0, accuracy: 0.001)
        let b = ClockMath.angles(hour: 15, minute: 30, second: 30, nanosecond: 500_000_000)
        XCTAssertEqual(b.second, 183, accuracy: 0.001)
        XCTAssertEqual(b.minute, (30 + 30.5 / 60) * 6, accuracy: 0.001)
        XCTAssertEqual(b.hour, (3 + (30 + 30.5 / 60) / 60) * 30, accuracy: 0.001)
        let c = ClockMath.angles(hour: 0, minute: 0, second: 10, nanosecond: 900_000_000, smooth: false)
        XCTAssertEqual(c.second, 60, accuracy: 0.001)
    }

    func testNumerals() {
        XCTAssertEqual(ClockMath.roman(4), "IV")
        XCTAssertEqual(ClockMath.roman(9), "IX")
        XCTAssertEqual(ClockMath.roman(12), "XII")
        XCTAssertEqual(ClockMath.numerals(roman: false).first, "12")
        XCTAssertEqual(ClockMath.numerals(roman: true)[3], "III")
    }

    func testDateWindow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
        XCTAssertEqual(ClockMath.dateWindowText(d, calendar: cal), "LUN 28")
        XCTAssertEqual(ClockMath.dayText(d, calendar: cal), "28")
    }

    func testOrbitPoint() {
        let p = ClockMath.orbitPoint(angle: 90, radius: 10)
        XCTAssertEqual(p.x, 10, accuracy: 0.0001)
        XCTAssertEqual(p.y, 0, accuracy: 0.0001)
        let q = ClockMath.orbitPoint(angle: 0, radius: 10)
        XCTAssertEqual(q.y, -10, accuracy: 0.0001)
    }

    func testSnap() {
        let v = ClockRect(x: 0, y: 0, w: 1000, h: 800)
        let near = ClockMath.snap(frame: ClockRect(x: 12, y: 300, w: 100, h: 100), to: v, threshold: 20)
        XCTAssertEqual(near.x, 0)
        XCTAssertEqual(near.y, 300)
        let right = ClockMath.snap(frame: ClockRect(x: 885, y: 690, w: 100, h: 100), to: v, threshold: 20)
        XCTAssertEqual(right.x, 900)
        XCTAssertEqual(right.y, 700)
        let out = ClockMath.snap(frame: ClockRect(x: -50, y: 900, w: 100, h: 100), to: v, threshold: 5)
        XCTAssertEqual(out, ClockRect(x: 0, y: 700, w: 100, h: 100))
    }

    func testSettingsRoundTripAndDefaults() {
        var s = ClockSettings()
        s.face = .orbit; s.size = .large; s.originX = 40; s.originY = 60; s.tickSound = true
        XCTAssertEqual(ClockSettings.decode(s.encoded()), s)
        let partial = ClockSettings.decode(#"{"face":"retroWall"}"#.data(using: .utf8))
        XCTAssertEqual(partial.face, .retroWall)
        XCTAssertEqual(partial.size, .normal)
        XCTAssertTrue(partial.snapToEdges)
        XCTAssertEqual(ClockSettings.decode(nil), ClockSettings())
        XCTAssertEqual(partial.windowSize.height, 190 * 1.42, accuracy: 0.001)
        XCTAssertEqual(ClockFace.retroWall.label, "Retro de pared")
        XCTAssertEqual(ClockSize.mini.points, 110)
    }
}

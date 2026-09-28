import XCTest
@testable import OrbexCore

final class LifeSchedulerTests: XCTestCase {

    func testBlinksWithinRange() {
        var s = LifeScheduler(level: .normal, now: 0, seed: 42)
        var blinkTimes: [Double] = []
        var t = 0.0
        while t < 300 {
            for e in s.update(now: t) {
                if case .blink = e { blinkTimes.append(t) }
            }
            t += 0.05
        }
        XCTAssertGreaterThan(blinkTimes.count, 40)
        for (a, b) in zip(blinkTimes, blinkTimes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 2.5 - 0.06)
            XCTAssertLessThanOrEqual(b - a, 6 + 0.06)
        }
    }

    func testGesturesHappenRegularly() {
        var s = LifeScheduler(level: .normal, now: 0, seed: 7)
        var gestures = 0
        var t = 0.0
        while t < 600 {
            for e in s.update(now: t) {
                switch e {
                case .microgesture, .surprise: gestures += 1
                default: break
                }
            }
            t += 0.1
        }
        // 600 s / (8–20 s) ≈ 30–75 gestos.
        XCTAssertGreaterThan(gestures, 25)
        XCTAssertLessThan(gestures, 80)
    }

    func testNeverTwoSecondsWithoutMotion() {
        // La respiración siempre cambia: en cualquier ventana de 2 s la escala varía.
        var t = 0.0
        while t < 20 {
            let a = LifeScheduler.breathScale(at: t)
            let b = LifeScheduler.breathScale(at: t + 1)
            let c = LifeScheduler.breathScale(at: t + 2)
            XCTAssertGreaterThan(max(abs(a - b), abs(b - c), abs(a - c)), 0.001)
            t += 0.37
        }
    }

    func testBreathRange() {
        for i in 0..<100 {
            let v = LifeScheduler.breathScale(at: Double(i) * 0.13)
            XCTAssertGreaterThanOrEqual(v, 1.0 - 1e-9)
            XCTAssertLessThanOrEqual(v, 1.02 + 1e-9)
        }
    }

    func testBlinkOpenness() {
        XCTAssertEqual(LifeScheduler.blinkOpenness(elapsed: -1), 1)
        XCTAssertLessThan(LifeScheduler.blinkOpenness(elapsed: 0.08), 0.2)
        XCTAssertEqual(LifeScheduler.blinkOpenness(elapsed: 0.5), 1)
        XCTAssertLessThan(LifeScheduler.blinkOpenness(elapsed: 0.32, double: true), 0.2)
    }

    func testSeededIsDeterministic() {
        var a = LifeScheduler(level: .hyper, now: 0, seed: 99)
        var b = LifeScheduler(level: .hyper, now: 0, seed: 99)
        for i in 0..<500 {
            XCTAssertEqual(a.update(now: Double(i) * 0.2), b.update(now: Double(i) * 0.2))
        }
    }
}

final class ExpressionTests: XCTestCase {
    func testEveryExpressionHasShape() {
        for e in Expression.allCases {
            let s = EyeShape.forExpression(e)
            XCTAssertGreaterThan(s.width, 0)
            XCTAssertGreaterThan(s.height, 0)
        }
    }

    func testLerpEndpoints() {
        let a = EyeShape.forExpression(.neutral)
        let b = EyeShape.forExpression(.surprised)
        XCTAssertEqual(EyeShape.lerp(a, b, 0), a)
        XCTAssertEqual(EyeShape.lerp(a, b, 1), b)
    }

    func testLookAtIsBounded() {
        let far = LookAt.offset(target: (x: 10_000, y: 0))
        XCTAssertLessThanOrEqual(abs(far.x), 0.07 + 1e-9)
        let zero = LookAt.offset(target: (x: 0, y: 0))
        XCTAssertEqual(zero.x, 0)
        let left = LookAt.offset(target: (x: -200, y: 0))
        XCTAssertLessThan(left.x, 0)
    }

    func testTapTracker() {
        var t = TapTracker()
        XCTAssertEqual(t.tap(at: 0), .squish)
        XCTAssertEqual(t.tap(at: 0.3), .squish)
        XCTAssertEqual(t.tap(at: 0.6), .dizzy)
        XCTAssertEqual(t.tap(at: 5), .squish)
    }

    func testSleepPolicy() {
        let p = SleepPolicy(enabled: true, startHour: 23, endHour: 7, idleMinutes: 20)
        XCTAssertTrue(p.isNight(hour: 23))
        XCTAssertTrue(p.isNight(hour: 3))
        XCTAssertFalse(p.isNight(hour: 7))
        XCTAssertFalse(p.isNight(hour: 15))
        XCTAssertTrue(p.shouldSleep(hour: 15, idleSeconds: 21 * 60))
        XCTAssertFalse(SleepPolicy(enabled: false).shouldSleep(hour: 2, idleSeconds: 99999))
    }

    func testDirector() {
        XCTAssertEqual(CharacterDirector.mood(for: .sleeping).pose, .crouch)
        XCTAssertEqual(CharacterDirector.mood(for: .needsYou).pose, .wave)
        XCTAssertEqual(CharacterDirector.mood(for: .open, isPlayingMusic: true).pose, .dance)
    }

    func testGreeting() {
        XCTAssertEqual(Greeting.text(hour: 9), "¡Buen día!")
        XCTAssertEqual(Greeting.text(hour: 21, name: "Juan"), "¡Buenas noches, Juan!")
    }
}

final class SettingsTests: XCTestCase {
    func testRoundTrip() throws {
        var s = OrbexSettings()
        s.tint = .violet
        s.screen = .display(3)
        s.glassTint = 0.8
        let data = try s.exportJSON()
        XCTAssertEqual(try OrbexSettings.importJSON(data), s)
    }

    func testTolerantDecoding() throws {
        let json = #"{"tint":"orange","unknownKey":5,"volume":"loud"}"#.data(using: .utf8)!
        let s = try OrbexSettings.importJSON(json)
        XCTAssertEqual(s.tint, .orange)
        XCTAssertEqual(s.volume, OrbexSettings().volume)
    }

    func testQuietHours() {
        var s = OrbexSettings()
        s.quietHoursEnabled = true
        s.quietStartHour = 22
        s.quietEndHour = 8
        XCTAssertEqual(s.effectiveVolume(hour: 23), 0)
        XCTAssertGreaterThan(s.effectiveVolume(hour: 12), 0)
        s.soundEnabled = false
        XCTAssertEqual(s.effectiveVolume(hour: 12), 0)
    }
}

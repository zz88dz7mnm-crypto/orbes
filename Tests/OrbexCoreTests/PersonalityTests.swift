import XCTest
@testable import OrbexCore

final class PersonalityTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        return c
    }()

    private func date(_ d: Int, _ h: Int, _ m: Int = 0, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m, second: s))!
    }

    private func headers(_ events: [PersonalityEvent]) -> [String] {
        events.compactMap { if case .header(let s) = $0 { return s } else { return nil } }
    }

    // MARK: - Frases

    func testFirstName() {
        XCTAssertEqual(PersonalityPhrases.firstName(from: "Juan Pedro Ameijeiras"), "Juan")
        XCTAssertEqual(PersonalityPhrases.firstName(from: "  Ana  "), "Ana")
        XCTAssertEqual(PersonalityPhrases.firstName(from: ""), "")
    }

    func testDayPartAndGreeting() {
        XCTAssertEqual(DayPart(hour: 3), .madrugada)
        XCTAssertEqual(DayPart(hour: 9), .manana)
        XCTAssertEqual(DayPart(hour: 15), .tarde)
        XCTAssertEqual(DayPart(hour: 22), .noche)
        XCTAssertEqual(PersonalityPhrases.greeting(name: "Juan", part: .manana), "Buen día, Juan")
        XCTAssertEqual(PersonalityPhrases.greeting(name: "Juan", part: .tarde), "Buenas tardes, Juan")
        XCTAssertEqual(PersonalityPhrases.greeting(name: "", part: .noche), "Buenas noches")
    }

    func testStreakText() {
        XCTAssertNil(PersonalityPhrases.streak(days: 1))
        XCTAssertEqual(PersonalityPhrases.streak(days: 3), "3.º día seguido usando ORBEX")
    }

    func testRotatorNeverRepeatsBackToBack() {
        var r = PhraseRotator(memory: 2)
        let pool = ["a", "b", "c"]
        var last: String?
        for i in 0..<50 {
            let p = r.next(from: pool, random: { n in (i * 7) % n })!
            XCTAssertNotEqual(p, last)
            last = p
        }
    }

    func testRotatorWithSinglePhrase() {
        var r = PhraseRotator(memory: 3)
        XCTAssertEqual(r.next(from: ["solo"]), "solo")
        XCTAssertEqual(r.next(from: ["solo"]), "solo")
        XCTAssertNil(r.next(from: []))
    }

    // MARK: - Rachas

    func testStreakCountsConsecutiveDays() {
        var rec = PersonalityRecord()
        XCTAssertTrue(rec.registerUse(now: date(1, 10), calendar: cal))
        XCTAssertEqual(rec.streakDays, 1)
        XCTAssertFalse(rec.registerUse(now: date(1, 22), calendar: cal))
        XCTAssertTrue(rec.registerUse(now: date(2, 0, 5), calendar: cal))
        XCTAssertEqual(rec.streakDays, 2)
        XCTAssertTrue(rec.registerUse(now: date(3, 8), calendar: cal))
        XCTAssertEqual(rec.streakDays, 3)
        // Se salteó un día: vuelve a 1.
        XCTAssertTrue(rec.registerUse(now: date(5, 8), calendar: cal))
        XCTAssertEqual(rec.streakDays, 1)
    }

    func testRecordRoundTripsJSON() throws {
        var rec = PersonalityRecord()
        rec.registerUse(now: date(1, 10), calendar: cal)
        let data = try JSONEncoder().encode(rec)
        XCTAssertEqual(try JSONDecoder().decode(PersonalityRecord.self, from: data), rec)
    }

    // MARK: - Cerebro

    func testStartGreetsThenShowsStreak() {
        var rec = PersonalityRecord()
        rec.registerUse(now: date(1, 10), calendar: cal)
        rec.registerUse(now: date(2, 10), calendar: cal)
        var brain = PersonalityBrain(record: rec, name: "Juan")
        XCTAssertEqual(headers(brain.start(now: date(3, 9), calendar: cal)), ["Buen día, Juan"])
        XCTAssertEqual(brain.record.streakDays, 3)
        // Mientras dura el saludo no cambia nada.
        XCTAssertTrue(headers(brain.tick(now: date(3, 9, 0, 5), idleSeconds: 1, keyIdleSeconds: 100, calendar: cal)).isEmpty)
        // Después, la racha.
        XCTAssertEqual(headers(brain.tick(now: date(3, 9, 0, 11), idleSeconds: 1, keyIdleSeconds: 100, calendar: cal)),
                       ["3.º día seguido usando ORBEX"])
    }

    func testMissedYouAfterLongAbsence() {
        var brain = PersonalityBrain(name: "Juan")
        _ = brain.start(now: date(1, 10), calendar: cal)
        _ = brain.tick(now: date(1, 10, 40), idleSeconds: 30 * 60, keyIdleSeconds: 30 * 60, calendar: cal)
        XCTAssertTrue(brain.isAway)
        let ev = brain.tick(now: date(1, 10, 41), idleSeconds: 1, keyIdleSeconds: 100, calendar: cal)
        XCTAssertFalse(brain.isAway)
        XCTAssertTrue(ev.contains(.emote(.love)))
        XCTAssertEqual(headers(ev), ["¡Te extrañé, Juan!"])
    }

    func testShortIdleDoesNotMissYou() {
        var brain = PersonalityBrain(name: "Juan")
        _ = brain.start(now: date(1, 10), calendar: cal)
        _ = brain.tick(now: date(1, 10, 5), idleSeconds: 5 * 60, keyIdleSeconds: 5 * 60, calendar: cal)
        let ev = brain.tick(now: date(1, 10, 6), idleSeconds: 1, keyIdleSeconds: 100, calendar: cal)
        XCTAssertFalse(ev.contains(.emote(.love)))
    }

    func testTypingLooksDownAndBlinks() {
        var brain = PersonalityBrain()
        _ = brain.start(now: date(1, 10), calendar: cal)
        let a = brain.tick(now: date(1, 10, 0, 2), idleSeconds: 0.2, keyIdleSeconds: 0.2, calendar: cal)
        XCTAssertTrue(brain.isTyping)
        XCTAssertTrue(a.contains(.glance(.keyboard, duration: 0)))
        XCTAssertTrue(a.contains(.blink))
        let b = brain.tick(now: date(1, 10, 0, 10), idleSeconds: 0.2, keyIdleSeconds: 0.2, calendar: cal)
        XCTAssertTrue(b.contains(.blink))   // parpadeo periódico mientras tipea
        let c = brain.tick(now: date(1, 10, 0, 16), idleSeconds: 5, keyIdleSeconds: 5, calendar: cal)
        XCTAssertFalse(brain.isTyping)
        XCTAssertTrue(c.contains(.glance(.ahead, duration: 0)))
        XCTAssertTrue(c.contains(.eyeScale(1)))
    }

    func testNewDayWhileRunningGreetsAgain() {
        var brain = PersonalityBrain(name: "Juan")
        _ = brain.start(now: date(1, 23, 50), calendar: cal)
        _ = brain.tick(now: date(2, 0, 1), idleSeconds: 1, keyIdleSeconds: 100, calendar: cal)
        XCTAssertEqual(brain.record.streakDays, 2)
        XCTAssertEqual(brain.headerLine, "Buenas noches, Juan")
    }

    func testAppGlanceRespectsCooldown() {
        var brain = PersonalityBrain()
        let dir = GazeVector(dx: -0.4, dy: 0.2)
        XCTAssertEqual(brain.appActivated(now: date(1, 10), toward: dir).first, .glance(dir, duration: 0.9))
        XCTAssertTrue(brain.appActivated(now: date(1, 10, 0, 1), toward: dir).isEmpty)
        XCTAssertFalse(brain.appActivated(now: date(1, 10, 0, 3), toward: nil).isEmpty)
    }

    func testGazeVectorClamps() {
        let g = GazeVector.toward(originX: 500, originY: 0, targetX: 2500, targetY: 0, reach: 500)
        XCTAssertEqual(g.dx, 1, accuracy: 0.0001)
        XCTAssertEqual(g.dy, 0, accuracy: 0.0001)
        let h = GazeVector.toward(originX: 500, originY: 0, targetX: 250, targetY: 250, reach: 1000)
        XCTAssertEqual(h.dx, -0.25, accuracy: 0.0001)
        XCTAssertEqual(h.dy, 0.25, accuracy: 0.0001)
    }
}

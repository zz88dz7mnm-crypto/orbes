import XCTest
@testable import OrbexCore

final class UtilitiesTimerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)

    func testCountdownPauseResumeFinish() {
        var e = TimerEngine()
        let t = e.add(duration: 300, label: "Pizza", now: t0)
        XCTAssertEqual(e.timer(t.id)?.remaining(at: t0.addingTimeInterval(100)), 200)
        XCTAssertEqual(e.timer(t.id)?.progress(at: t0.addingTimeInterval(150)) ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertTrue(e.anyRunning)

        e.pause(t.id, now: t0.addingTimeInterval(100))
        XCTAssertFalse(e.anyRunning)
        XCTAssertEqual(e.timer(t.id)?.remaining(at: t0.addingTimeInterval(1000)), 200)
        e.resume(t.id, now: t0.addingTimeInterval(1000))

        XCTAssertEqual(e.tick(now: t0.addingTimeInterval(1199)), [])
        XCTAssertEqual(e.tick(now: t0.addingTimeInterval(1200)),
                       [.finished(id: t.id, label: "Pizza", at: t0.addingTimeInterval(1200))])
        XCTAssertTrue(e.anyRinging)
        XCTAssertEqual(e.statusLine(at: t0.addingTimeInterval(1201)), "⏰ ¡Terminó Pizza!")
        // Se saca solo después de un minuto.
        XCTAssertEqual(e.tick(now: t0.addingTimeInterval(1261)), [])
        XCTAssertTrue(e.timers.isEmpty)
    }

    func testAddTimeAndRestart() {
        var e = TimerEngine()
        let t = e.add(duration: 60, now: t0)
        e.addTime(t.id, seconds: 60, now: t0)
        XCTAssertEqual(e.timer(t.id)?.remaining(at: t0), 120)
        XCTAssertEqual(e.timer(t.id)?.duration, 120)
        _ = e.tick(now: t0.addingTimeInterval(120))
        XCTAssertTrue(e.timer(t.id)?.isFinished ?? false)
        e.restart(t.id, now: t0.addingTimeInterval(130))
        XCTAssertEqual(e.timer(t.id)?.remaining(at: t0.addingTimeInterval(130)), 120)
        e.remove(t.id)
        XCTAssertNil(e.timer(t.id))
    }

    func testSurvivesRestartThroughCodable() throws {
        var e = TimerEngine()
        let t = e.add(duration: 300, label: nil, now: t0)
        e.stopwatch.start(at: t0)
        let data = try JSONEncoder().encode(e)
        var back = try JSONDecoder().decode(TimerEngine.self, from: data)
        XCTAssertEqual(back, e)
        XCTAssertEqual(back.stopwatch.elapsed(at: t0.addingTimeInterval(42)), 42)
        // Terminó hace mucho mientras la app estaba cerrada: avisa y se saca.
        let events = back.tick(now: t0.addingTimeInterval(3600))
        XCTAssertEqual(events, [.finished(id: t.id, label: "Timer", at: t0.addingTimeInterval(300))])
        XCTAssertTrue(back.timers.isEmpty)
    }

    func testStatusLine() {
        var e = TimerEngine()
        XCTAssertEqual(e.statusLine(at: t0), "")
        e.add(duration: 750, label: "Pizza", now: t0)
        e.add(duration: 900, label: "Té", now: t0)
        XCTAssertEqual(e.statusLine(at: t0), "⏱ Pizza 12:30")
        var s = TimerEngine()
        s.stopwatch.start(at: t0)
        XCTAssertEqual(s.statusLine(at: t0.addingTimeInterval(192)), "⏱ 3:12")
        var p = TimerEngine()
        p.startPomodoro(now: t0)
        XCTAssertEqual(p.statusLine(at: t0.addingTimeInterval(50)), "🍅 Foco 1/4 24:10")
    }

    func testPomodoroCycle() {
        var p = Pomodoro()
        XCTAssertEqual(p.phase, .focus)
        var phases: [Pomodoro.Phase] = []
        while p.advance() { phases.append(p.phase) }
        XCTAssertEqual(phases, [.shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak])
        XCTAssertEqual(p.completedFocus, 4)
        XCTAssertEqual(p.duration(of: .longBreak), 900)
    }

    func testPomodoroInEngineCatchesUp() {
        var e = TimerEngine()
        let t = e.startPomodoro(now: t0)
        XCTAssertEqual(e.tick(now: t0.addingTimeInterval(1500)),
                       [.pomodoroPhase(id: t.id, phase: .shortBreak, at: t0.addingTimeInterval(1500))])
        XCTAssertEqual(e.timer(t.id)?.remaining(at: t0.addingTimeInterval(1500)), 300)

        var f = TimerEngine()
        let u = f.startPomodoro(now: t0)
        // 4 focos (100 min) + 3 descansos (15) + descanso largo (15) = 7800 s.
        let events = f.tick(now: t0.addingTimeInterval(7800))
        XCTAssertEqual(events.count, 8)
        XCTAssertEqual(events.last, .finished(id: u.id, label: "Pomodoro", at: t0.addingTimeInterval(7800)))
        XCTAssertTrue(f.anyRinging)
    }

    func testStopwatchLaps() {
        var s = Stopwatch()
        XCTAssertFalse(s.hasStarted)
        s.start(at: t0)
        XCTAssertEqual(s.lap(at: t0.addingTimeInterval(10)), 10)
        XCTAssertEqual(s.lap(at: t0.addingTimeInterval(25)), 15)
        s.pause(at: t0.addingTimeInterval(30))
        XCTAssertNil(s.lap(at: t0.addingTimeInterval(40)))
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(100)), 30)
        XCTAssertEqual(s.laps.map(\.number), [2, 1])
        XCTAssertEqual(s.laps.first?.duration, 15)
        s.start(at: t0.addingTimeInterval(100))
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(105)), 35)
        XCTAssertEqual(s.currentLap(at: t0.addingTimeInterval(105)), 10)
        s.reset()
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(200)), 0)
        XCTAssertFalse(s.hasStarted)
    }

    func testFormats() {
        XCTAssertEqual(TimerFormat.countdown(300), "5:00")
        XCTAssertEqual(TimerFormat.countdown(4.2), "0:05")
        XCTAssertEqual(TimerFormat.clock(3725), "1:02:05")
        XCTAssertEqual(TimerFormat.stopwatch(62.34), "1:02,3")
        XCTAssertEqual(TimerFormat.words(4800), "1 h 20 min")
        XCTAssertEqual(TimerFormat.words(45), "45 s")
    }
}

final class UtilitiesNoteTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: -3 * 3600)!
        return c
    }()

    func testTitle() {
        XCTAssertEqual(NoteFormat.title(for: "  comprar   pan \n y leche"), "Comprar pan")
        XCTAssertEqual(NoteFormat.title(for: ""), "Nota")
        XCTAssertEqual(NoteFormat.title(for: String(repeating: "a", count: 60), maxLength: 10), "Aaaaaaaaaa…")
    }

    func testFileNameAndMarkdown() {
        let created = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 14, minute: 30))!
        let note = Note(text: "comprar pan / leche?", created: created)
        XCTAssertEqual(NoteFormat.fileName(for: note, calendar: cal), "2026-09-28 14.30 Comprar pan leche.md")
        let md = NoteFormat.markdown(for: note, calendar: cal)
        XCTAssertTrue(md.hasPrefix("# Comprar pan / leche?\n\ncomprar pan / leche?\n"))
        XCTAssertTrue(md.contains("_Anotado por ORBEX · 28/09/2026 14:30_"))
    }

    func testUniqueName() {
        XCTAssertEqual(NoteFormat.uniqueName("a.md", existing: []), "a.md")
        XCTAssertEqual(NoteFormat.uniqueName("a.md", existing: ["a.md", "a 2.md"]), "a 3.md")
    }

    func testAppleNotesEscaping() {
        XCTAssertEqual(NoteFormat.htmlEscaped("<b>&</b>"), "&lt;b&gt;&amp;&lt;/b&gt;")
        XCTAssertEqual(NoteFormat.appleScriptEscaped("di \"hola\" \\"), "di \\\"hola\\\" \\\\")
        let script = NoteFormat.appleNotesScript(for: Note(text: "Llamar a \"Tito\""))
        XCTAssertTrue(script.contains("tell application \"Notes\""))
        XCTAssertTrue(script.contains("&quot;Tito&quot;"))
    }

    func testNoteCodable() throws {
        let n = Note(text: "hola", savedTo: "/tmp/x.md")
        let back = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(back, n)
        XCTAssertEqual(back.title, "Hola")
    }
}

final class UtilitiesAutonomyTests: XCTestCase {
    let home = "/Users/yo"
    let list = ActionAllowlist.default

    func level(_ c: OrbexCommand, _ l: ActionAllowlist? = nil) -> AutonomyLevel {
        AutonomyPolicy.level(for: c, allowlist: l ?? list, homeDirectory: home)
    }

    func testInternalCommandsAreFree() {
        XCTAssertEqual(level(.timer(seconds: 60, label: nil)), .free)
        XCTAssertEqual(level(.note(text: "x")), .free)
        XCTAssertEqual(level(.stopwatch), .free)
        XCTAssertEqual(level(.pomodoro), .free)
        XCTAssertEqual(level(.showClock), .free)
        XCTAssertEqual(level(.remember(fact: "x")), .free)
        XCTAssertEqual(level(.remind(at: Date(), text: "x")), .free)
        XCTAssertEqual(level(.scheduledAction(at: Date(), actionName: "x")), .free)
    }

    func testApps() {
        XCTAssertEqual(level(.openApp(name: "Spotify")), .notify)
        XCTAssertEqual(level(.openApp(name: "la terminal")), .notify)
        XCTAssertEqual(level(.openApp(name: "Blender")), .confirm)
        XCTAssertEqual(level(.openApp(name: "mi setup de trabajo")), .notify)
        XCTAssertEqual(level(.openApp(name: "Keychain Access")), .never)
        XCTAssertEqual(level(.openApp(name: "youtube.com")), .notify)

        var custom = ActionAllowlist(actions: [], extraApps: ["Blender"], allowCommonApps: false)
        XCTAssertEqual(level(.openApp(name: "Blender"), custom), .notify)
        XCTAssertEqual(level(.openApp(name: "Spotify"), custom), .confirm)
        custom.actions = [AllowedAction(name: "Música", items: [ActionItem(kind: .app, value: "Spotify")])]
        XCTAssertTrue(custom.isAllowedApp("spotify"))
        XCTAssertEqual(custom.action(named: "musica")?.name, "Música")
    }

    func testFolders() {
        XCTAssertEqual(level(.openFolder(path: "~/Proyectos/x")), .notify)
        XCTAssertEqual(level(.openFolder(path: "/Users/yo/Documents")), .notify)
        XCTAssertEqual(level(.openFolder(path: "proyecto")), .notify)
        XCTAssertEqual(level(.openFolder(path: "/etc")), .confirm)
        XCTAssertEqual(level(.openFolder(path: "~/../../etc")), .confirm)
        let l = ActionAllowlist(actions: [AllowedAction(name: "logs", items: [ActionItem(kind: .folder, value: "/var/log")])])
        XCTAssertEqual(level(.openFolder(path: "/var/log/"), l), .notify)
    }

    func testPaths() {
        XCTAssertEqual(AutonomyPolicy.standardized("~/a/./b/../c/", home: home), "/Users/yo/a/c")
        XCTAssertTrue(AutonomyPolicy.isInside("~", home: home))
        XCTAssertFalse(AutonomyPolicy.isInside("/Users/yoyo", home: home))
        XCTAssertTrue(AutonomyPolicy.looksLikeWebAddress("www.lanacion.com.ar"))
        XCTAssertFalse(AutonomyPolicy.looksLikeWebAddress("Spotify.app"))
        XCTAssertEqual(AutonomyPolicy.webURLString("youtube.com"), "https://youtube.com")
    }

    func testAllowlistCodable() throws {
        let back = try JSONDecoder().decode(ActionAllowlist.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(back, list)
        XCTAssertEqual(AutonomyLevel.confirm.title, "Siempre confirmar")
        XCTAssertTrue(AutonomyLevel.notify < .confirm)
    }
}

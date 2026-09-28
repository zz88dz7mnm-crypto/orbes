import XCTest
@testable import OrbexCore

final class UtilitiesCommandTests: XCTestCase {
    // Lunes 28/09/2026 10:00 (UTC−3).
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: -3 * 3600)!
        return c
    }()
    lazy var now: Date = at(28, 10, 0)

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func parse(_ s: String) -> OrbexCommand? {
        CommandParser.parse(s, now: now, calendar: cal)
    }

    // MARK: - Abrir

    func testOpenApp() {
        XCTAssertEqual(parse("abrime Spotify"), .openApp(name: "Spotify"))
        XCTAssertEqual(parse("Abrí figma"), .openApp(name: "Figma"))
        XCTAssertEqual(parse("che, abrime Spotify porfa"), .openApp(name: "Spotify"))
        XCTAssertEqual(parse("abrí la calculadora"), .openApp(name: "Calculator"))
        XCTAssertEqual(parse("abrir Blender"), .openApp(name: "Blender"))
        XCTAssertEqual(parse("abrí youtube.com"), .openApp(name: "youtube.com"))
    }

    func testOpenSeveralApps() {
        XCTAssertEqual(parse("abrí Figma y la terminal"), .openApp(name: "Figma"))
        XCTAssertEqual(CommandParser.parseAll("abrí Figma y la terminal", now: now, calendar: cal),
                       [.openApp(name: "Figma"), .openApp(name: "Terminal")])
        XCTAssertEqual(CommandParser.parseAll("abrime Slack, Mail e iTerm", now: now, calendar: cal),
                       [.openApp(name: "Slack"), .openApp(name: "Mail"), .openApp(name: "iTerm")])
    }

    func testOpenFolder() {
        XCTAssertEqual(parse("abrir la carpeta ~/Proyectos/x"), .openFolder(path: "~/Proyectos/x"))
        XCTAssertEqual(parse("abrí la carpeta de descargas"), .openFolder(path: "~/Downloads"))
        XCTAssertEqual(parse("abrí descargas"), .openFolder(path: "~/Downloads"))
        XCTAssertEqual(parse("abrime /Users/yo/Documentos"), .openFolder(path: "/Users/yo/Documentos"))
        XCTAssertEqual(parse("abrí la carpeta del proyecto"), .openFolder(path: "proyecto"))
    }

    // MARK: - Notas

    func testNotes() {
        XCTAssertEqual(parse("anotá que mañana llamo al contador"), .note(text: "mañana llamo al contador"))
        XCTAssertEqual(parse("nota: comprar pan"), .note(text: "comprar pan"))
        XCTAssertEqual(parse("Nota:comprar pan"), .note(text: "comprar pan"))
        XCTAssertEqual(parse("anotá: comprar leche."), .note(text: "comprar leche"))
        XCTAssertEqual(parse("tomá nota de que el lunes cierra el banco"), .note(text: "el lunes cierra el banco"))
        XCTAssertNil(parse("anotá"))
    }

    // MARK: - Timers

    func testTimers() {
        XCTAssertEqual(parse("timer de 5 minutos"), .timer(seconds: 300, label: nil))
        XCTAssertEqual(parse("poné un temporizador de 1 hora y 20 para la pizza"), .timer(seconds: 4800, label: "Pizza"))
        XCTAssertEqual(parse("timer de dos horas y media"), .timer(seconds: 9000, label: nil))
        XCTAssertEqual(parse("temporizador de media hora para el té"), .timer(seconds: 1800, label: "Té"))
        XCTAssertEqual(parse("timer de 25"), .timer(seconds: 1500, label: nil))
        XCTAssertEqual(parse("poné un timer"), .timer(seconds: 0, label: nil))
        XCTAssertEqual(parse("timer 1h20"), .timer(seconds: 4800, label: nil))
        XCTAssertEqual(parse("media hora"), .timer(seconds: 1800, label: nil))
        XCTAssertEqual(parse("un cuarto de hora"), .timer(seconds: 900, label: nil))
        XCTAssertEqual(parse("cinco minutos"), .timer(seconds: 300, label: nil))
        XCTAssertEqual(parse("avisame en 5 minutos"), .timer(seconds: 300, label: nil))
    }

    func testStopwatchPomodoroClock() {
        XCTAssertEqual(parse("cronómetro"), .stopwatch)
        XCTAssertEqual(parse("arrancá el CRONOMETRO"), .stopwatch)
        XCTAssertEqual(parse("abrí el cronómetro"), .stopwatch)
        XCTAssertEqual(parse("pomodoro"), .pomodoro)
        XCTAssertEqual(parse("modo foco"), .pomodoro)
        XCTAssertEqual(parse("modo reloj"), .showClock)
        XCTAssertEqual(parse("mostrame el reloj"), .showClock)
    }

    func testStopsAndQuestionsAreNotCommands() {
        XCTAssertNil(parse("cancelá el timer"))
        XCTAssertNil(parse("pará el timer"))
        XCTAssertNil(parse("cuánto falta del timer"))
        XCTAssertNil(parse("hola"))
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("recordame comprar pan"))
    }

    // MARK: - Recordatorios y acciones programadas

    func testRemindAbsolute() {
        XCTAssertEqual(parse("a las 21 recordame llamar a mamá"), .remind(at: at(28, 21), text: "llamar a mamá"))
        XCTAssertEqual(parse("recordame llamar a mamá a las 21"), .remind(at: at(28, 21), text: "llamar a mamá"))
        XCTAssertEqual(parse("mañana a las 9:30 recordame pagar la luz"), .remind(at: at(29, 9, 30), text: "pagar la luz"))
        XCTAssertEqual(parse("mañana a las 9 de la noche recordame sacar la basura"),
                       .remind(at: at(29, 21), text: "sacar la basura"))
        XCTAssertEqual(parse("recordame el viernes a las 18 ir al gimnasio"),
                       .remind(at: at(2, 18, month: 10), text: "ir al gimnasio"))
        XCTAssertEqual(parse("recordame a las 5 y media de la tarde que llame a Juan"),
                       .remind(at: at(28, 17, 30), text: "llame a Juan"))
    }

    func testRemindPastHourMovesToTomorrow() {
        // Son las 10: "a las 9" es mañana a las 9.
        XCTAssertEqual(parse("a las 9 recordame regar"), .remind(at: at(29, 9), text: "regar"))
        XCTAssertEqual(parse("alarma a las 7"), .remind(at: at(29, 7), text: "Alarma"))
    }

    func testRemindRelative() {
        XCTAssertEqual(parse("en 10 minutos recordame sacar la pizza"),
                       .remind(at: now.addingTimeInterval(600), text: "sacar la pizza"))
        XCTAssertEqual(parse("recordame en 10 minutos que saque la ropa"),
                       .remind(at: now.addingTimeInterval(600), text: "saque la ropa"))
        XCTAssertEqual(parse("en 1 hora y media recordame estirar"),
                       .remind(at: now.addingTimeInterval(5400), text: "estirar"))
        XCTAssertEqual(parse("avisame en 20 minutos que saque la pizza"),
                       .remind(at: now.addingTimeInterval(1200), text: "saque la pizza"))
    }

    func testScheduledAction() {
        XCTAssertEqual(parse("a las 9 abrime mi setup de trabajo"),
                       .scheduledAction(at: at(29, 9), actionName: "setup de trabajo"))
        XCTAssertEqual(parse("abrí Spotify mañana a las 8"),
                       .scheduledAction(at: at(29, 8), actionName: "Spotify"))
    }

    func testRemember() {
        XCTAssertEqual(parse("acordate que mi perro se llama Toto"), .remember(fact: "mi perro se llama Toto"))
        XCTAssertEqual(parse("Acordate de que prefiero el té sin azúcar"), .remember(fact: "prefiero el té sin azúcar"))
        XCTAssertEqual(parse("no te olvides que soy de Boca"), .remember(fact: "soy de Boca"))
    }

    // MARK: - Piezas

    func testDurations() {
        func d(_ s: String) -> Double? { DurationParser.parse(CommandText.tokenize(s), at: 0)?.seconds }
        XCTAssertEqual(d("5 minutos"), 300)
        XCTAssertEqual(d("1 hora y 20"), 4800)
        XCTAssertEqual(d("1 hora 20 minutos"), 4800)
        XCTAssertEqual(d("hora y media"), 5400)
        XCTAssertEqual(d("un minuto y medio"), 90)
        XCTAssertEqual(d("tres cuartos de hora"), 2700)
        XCTAssertEqual(d("90s"), 90)
        XCTAssertEqual(d("5min"), 300)
        XCTAssertEqual(d("1h20"), 4800)
        XCTAssertEqual(d("treinta y cinco segundos"), 35)
        XCTAssertNil(d("5"))
        XCTAssertNil(d("hora"))
    }

    func testClockTokens() {
        XCTAssertEqual(TimeExpressionParser.clockToken("9:30")?.hour, 9)
        XCTAssertEqual(TimeExpressionParser.clockToken("9:30")?.minute, 30)
        XCTAssertEqual(TimeExpressionParser.clockToken("21hs")?.hour, 21)
        XCTAssertEqual(TimeExpressionParser.clockToken("9h30")?.minute, 30)
        XCTAssertNil(TimeExpressionParser.clockToken("9:3"))
        XCTAssertNil(TimeExpressionParser.clockToken("25:00"))
    }

    func testFoldAndNumbers() {
        XCTAssertEqual(CommandText.fold("CRONÓMETRO Mañana"), "cronometro manana")
        let t = CommandText.tokenize("cuarenta y dos")
        XCTAssertEqual(SpanishNumber.read(t, at: 0)?.value, 42)
        XCTAssertEqual(SpanishNumber.digits("1,5"), 1.5)
        XCTAssertNil(SpanishNumber.digits("1,"))
    }

    func testAppMatching() {
        XCTAssertEqual(AppAliases.canonical("la terminal"), "Terminal")
        XCTAssertEqual(AppAliases.canonical("Blender"), "Blender")
        XCTAssertEqual(AppAliases.bestMatch("figma", in: ["Figma", "Final Cut Pro"]), "Figma")
        XCTAssertEqual(AppAliases.bestMatch("chrome", in: ["Chrome Remote Desktop", "Google Chrome"]), "Google Chrome")
        XCTAssertEqual(AppAliases.bestMatch("visual", in: ["Visual Studio Code", "Xcode"]), "Visual Studio Code")
        XCTAssertEqual(AppAliases.bestMatch("calculadora", in: ["Calculator", "Calendar"]), "Calculator")
        XCTAssertEqual(AppAliases.bestMatch("studio", in: ["Visual Studio Code", "Android Studio"]), "Android Studio")
        XCTAssertNil(AppAliases.bestMatch("zzz", in: ["Figma"]))
    }
}

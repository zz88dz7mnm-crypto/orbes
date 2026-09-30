import XCTest
@testable import OrbexCore

final class VoiceTests: XCTestCase {
    // Lunes 28/09/2026 10:00 (UTC−3).
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: -3 * 3600)!
        return c
    }()
    lazy var now: Date = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!

    let matcher = WakeWordMatcher()

    func route(_ s: String) -> VoiceIntentRouter.Route {
        VoiceIntentRouter.route(s, now: now, calendar: cal)
    }

    func parse(_ s: String) -> OrbexCommand? {
        CommandParser.parse(s, now: now, calendar: cal)
    }

    // MARK: - Palabra de activación: variantes

    func testNameVariantsActivate() {
        let cases: [(String, String)] = [
            ("Orbex abrí Spotify", "Orbex"),
            ("Orbes, abrí Spotify", "Orbes"),
            ("orbis abrí Spotify", "orbis"),
            ("Orbi abrí Spotify", "Orbi"),
            ("Orby abrí Spotify", "Orby"),
            ("Orvex abrí Spotify", "Orvex"),
            ("Orves abrí Spotify", "Orves"),
            ("Orbeks abrí Spotify", "Orbeks"),
            ("ORBEX abrí Spotify", "ORBEX"),
            ("Órbex abrí Spotify", "Órbex"),
            ("Or bex abrí Spotify", "Or bex"),
            ("Or Bex, abrí Spotify", "Or Bex"),
            ("Orbe X abrí Spotify", "Orbe X"),
            ("Horbi abrí Spotify", "Horbi"),
            ("Orbexs abrí Spotify", "Orbexs"),   // 1 error
            ("Orvix abrí Spotify", "Orvix"),     // 1 error
            ("Or vez abrí Spotify", "Or vez"),   // partido y con 1 error
        ]
        for (text, wake) in cases {
            let m = matcher.match(text)
            XCTAssertEqual(m?.wakeWord, wake, text)
            XCTAssertEqual(m?.command, "abrí Spotify", text)
        }
    }

    func testGreetingsBeforeName() {
        XCTAssertEqual(matcher.match("hola orbi abrí safari"), WakeMatch(wakeWord: "orbi", command: "abrí safari"))
        XCTAssertEqual(matcher.match("Hola Orbex, poné un timer"), WakeMatch(wakeWord: "Orbex", command: "poné un timer"))
        XCTAssertEqual(matcher.match("Oye Orbi, recordame algo")?.command, "recordame algo")
        XCTAssertEqual(matcher.match("Che, Orbex: abrí Mail")?.command, "abrí Mail")
        XCTAssertEqual(matcher.match("Eh, Orbex, abrí Mail")?.command, "abrí Mail")
        XCTAssertEqual(matcher.match("Hey Orbes abrí Mail")?.command, "abrí Mail")
        XCTAssertEqual(matcher.match("Oye, che, Orbi, abrí Mail")?.command, "abrí Mail")
        XCTAssertEqual(matcher.match("Buenos días Orbex, abrí Mail")?.command, "abrí Mail")
    }

    func testCommandExtraction() {
        XCTAssertEqual(matcher.match("Orbex, abrí Spotify.")?.command, "abrí Spotify")
        XCTAssertEqual(matcher.match("Orbex")?.command, "")
        XCTAssertEqual(matcher.match("Orbex.")?.command, "")
        XCTAssertEqual(matcher.match("¿Orbex?")?.wakeWord, "Orbex")
        XCTAssertEqual(matcher.match("Orbex, ¿qué hora es?")?.command, "¿qué hora es?")
        XCTAssertEqual(matcher.match("Orbex, Orbex, abrí Spotify")?.command, "abrí Spotify")
        XCTAssertEqual(matcher.match("  orbex   poné un timer de 5 minutos  ")?.command, "poné un timer de 5 minutos")
    }

    func testNameMustStartTheSentence() {
        XCTAssertNil(matcher.match("abrí spotify orbex"))
        XCTAssertNil(matcher.match("le dije a orbex que abra spotify"))
        XCTAssertNil(matcher.match("hola che cómo andás"))
        // Al principio de otra oración sí.
        XCTAssertEqual(matcher.match("Qué calor. Orbex, poné un timer")?.command, "poné un timer")
        XCTAssertEqual(matcher.match("qué calor\nOrbi abrí Safari")?.command, "abrí Safari")
        // Vale el pedido más nuevo.
        XCTAssertEqual(matcher.match("Orbex abrí Spotify. Orbi poné un timer")?.command, "poné un timer")
    }

    func testFalsePositives() {
        for text in [
            "órbita", "Orbita baja", "La órbita de la luna", "sorbete de limón", "horno a 180", "orden del día",
            "orbit", "Orbital", "obra de teatro", "hora de irse", "horas", "ok", "orb", "", "   ", "...",
            "otro día", "ores", "o bien", "hombre", "sorbe", "urbe", "Forbes",
        ] {
            XCTAssertNil(matcher.match(text), text)
        }
    }

    func testMaxDistanceAndCustomNames() {
        XCTAssertNil(WakeWordMatcher(maxDistance: 0).match("Orbexs abrí Spotify"))
        XCTAssertNotNil(WakeWordMatcher(maxDistance: 0).match("Orbex abrí Spotify"))
        let jarvis = WakeWordMatcher(names: ["Jarvis"])
        XCTAssertEqual(jarvis.match("Jarvis, abrí Spotify")?.command, "abrí Spotify")
        XCTAssertNil(jarvis.match("Orbex, abrí Spotify"))
        XCTAssertTrue(WakeWordMatcher.defaultNames.contains("orbex"))
        XCTAssertTrue(WakeWordMatcher.defaultNames.contains("orbi"))
    }

    // MARK: - Limpieza

    func testCleanerFillersAndCourtesy() {
        XCTAssertEqual(VoiceCommandCleaner.clean("por favor abrí Spotify"), "abrí Spotify")
        XCTAssertEqual(VoiceCommandCleaner.clean("che, abrí Spotify, por favor."), "abrí Spotify")
        XCTAssertEqual(VoiceCommandCleaner.clean("eh, bueno, dale, abrí Safari gracias"), "abrí Safari")
        XCTAssertEqual(VoiceCommandCleaner.clean("abrí, por favor, Spotify"), "abrí, Spotify")
        XCTAssertEqual(VoiceCommandCleaner.clean("poné eh un timer mmm de 5 minutos"), "poné un timer de 5 minutos")
        XCTAssertEqual(VoiceCommandCleaner.clean("este, abrí Mail"), "abrí Mail")
        XCTAssertEqual(VoiceCommandCleaner.clean("este año quiero viajar"), "este año quiero viajar")
        XCTAssertEqual(VoiceCommandCleaner.clean("por favor"), "")
        XCTAssertEqual(VoiceCommandCleaner.clean("  "), "")
    }

    func testCleanerPoliteRequests() {
        XCTAssertEqual(VoiceCommandCleaner.clean("¿podrías abrir Spotify?"), "abrir Spotify")
        XCTAssertEqual(VoiceCommandCleaner.clean("¿Me podrías abrir Spotify, por favor?"), "abrime Spotify")
        XCTAssertEqual(VoiceCommandCleaner.clean("¿Me ponés un timer de cinco minutos?"), "poneme un timer de 5 minutos")
        XCTAssertEqual(VoiceCommandCleaner.clean("¿me recordás comprar pan a las nueve?"), "recordame comprar pan a las 9")
        XCTAssertEqual(VoiceCommandCleaner.clean("quiero que me recuerdes llamar a mamá a las seis"),
                       "recordame llamar a mamá a las 6")
        XCTAssertEqual(VoiceCommandCleaner.clean("¿me hacés acordar de sacar la ropa en veinte minutos?"),
                       "haceme acordar de sacar la ropa en 20 minutos")
        XCTAssertEqual(VoiceCommandCleaner.clean("¿podés recordar que soy vegetariano?"), "recordá que soy vegetariano")
        XCTAssertEqual(VoiceCommandCleaner.clean("¿me decís qué hora es?"), "decime qué hora es")
        // Una pregunta de verdad conserva los signos.
        XCTAssertEqual(VoiceCommandCleaner.clean("¿qué hora es?"), "¿qué hora es?")
        XCTAssertEqual(VoiceCommandCleaner.clean("¿qué hora es, por favor?"), "¿qué hora es?")
        // "me" que no es de pedido se queda.
        XCTAssertEqual(VoiceCommandCleaner.clean("me gusta el jazz"), "me gusta el jazz")
    }

    func testCleanerNumbers() {
        XCTAssertEqual(VoiceCommandCleaner.clean("poné un timer de cinco minutos"), "poné un timer de 5 minutos")
        XCTAssertEqual(VoiceCommandCleaner.clean("timer de treinta y cinco segundos"), "timer de 35 segundos")
        XCTAssertEqual(VoiceCommandCleaner.clean("recordame a las nueve y media"), "recordame a las 9 y media")
        XCTAssertEqual(VoiceCommandCleaner.clean("a las diez y veinte"), "a las 10 y 20")
        XCTAssertEqual(VoiceCommandCleaner.clean("ciento veinte segundos"), "120 segundos")
        XCTAssertEqual(VoiceCommandCleaner.clean("doscientos treinta y un pasos"), "231 pasos")
        XCTAssertEqual(VoiceCommandCleaner.clean("veinticinco minutos"), "25 minutos")
        XCTAssertEqual(VoiceCommandCleaner.clean("dieciséis horas"), "16 horas")
        XCTAssertEqual(VoiceCommandCleaner.clean("cien metros"), "100 metros")
        XCTAssertEqual(VoiceCommandCleaner.clean("una nota: comprar dos kilos"), "una nota: comprar 2 kilos")
        XCTAssertEqual(VoiceCommandCleaner.clean("a la una y cuarto"), "a la una y cuarto")
        XCTAssertEqual(VoiceCommandCleaner.clean("timer de cinco, para la pizza"), "timer de 5, para la pizza")
    }

    func testCleanerIsIdempotent() {
        for s in ["¿Me ponés un timer de cinco minutos?", "che, abrí Spotify, por favor.", "¿qué hora es?",
                  "quiero que me recuerdes llamar a mamá a las seis", "recordame a las nueve y media"] {
            let once = VoiceCommandCleaner.clean(s)
            XCTAssertEqual(VoiceCommandCleaner.clean(once), once, s)
        }
    }

    // MARK: - Fin de frase

    func testEndpointerSilence() {
        var e = UtteranceEndpointer()
        e.start(at: 0)
        e.heard("abrí", at: 0.5)
        e.heard("abrí spotify", at: 1.0)
        e.heard("abrí spotify", at: 1.8)      // igual: no es habla
        e.heard("Abrí Spotify.", at: 2.0)     // solo signos/mayúsculas: no es habla
        XCTAssertFalse(e.isFinished(at: 2.15))
        XCTAssertTrue(e.isFinished(at: 2.25))
        XCTAssertEqual(e.reason, .silence)
        XCTAssertEqual(e.transcript, "abrí spotify")
        // Lo que llega después del fin se ignora.
        e.heard("abrí spotify y safari", at: 3.0)
        XCTAssertTrue(e.isFinished(at: 3.0))
        XCTAssertEqual(e.reason, .silence)
    }

    func testEndpointerMaxDuration() {
        var e = UtteranceEndpointer(silenceAfterSpeech: 1.2, maxListen: 12, noSpeechTimeout: 5)
        e.start(at: 100)
        var said = ""
        var t = 100.5
        while t < 113 {
            said += " palabra\(Int(t * 10))"
            e.heard(said, at: t)
            t += 0.5
        }
        XCTAssertFalse(e.isFinished(at: 111.9))
        XCTAssertTrue(e.isFinished(at: 112))
        XCTAssertEqual(e.reason, .maxDuration)
    }

    func testEndpointerNoSpeech() {
        var e = UtteranceEndpointer()
        XCTAssertFalse(e.isFinished(at: 50))
        XCTAssertNil(e.reason)
        e.start(at: 10)
        e.heard("", at: 11)
        e.heard("   ", at: 12)
        XCTAssertFalse(e.hasSpeech)
        XCTAssertFalse(e.isFinished(at: 14.9))
        XCTAssertTrue(e.isFinished(at: 15))
        XCTAssertEqual(e.reason, .noSpeech)
        // Volver a empezar limpia todo.
        e.start(at: 20)
        XCTAssertFalse(e.isFinished(at: 21))
        e.heard("poné un timer", at: 21)
        XCTAssertTrue(e.hasSpeech)
        XCTAssertFalse(e.isFinished(at: 22))
        XCTAssertTrue(e.isFinished(at: 22.25))
        XCTAssertEqual(e.reason, .silence)
    }

    func testEndpointerWaitsAfterBareName() {
        // "Orbex" … (pausa) … "abrí Spotify": decir solo el nombre no corta a los 1,2 s.
        var e = UtteranceEndpointer()
        e.start(at: 0)
        e.heard(matcher.match("Orbex")?.command ?? "", at: 0.1)
        XCTAssertFalse(e.isFinished(at: 2))
        e.heard(matcher.match("Orbex abrí Spotify")?.command ?? "", at: 3)
        XCTAssertFalse(e.isFinished(at: 4))
        XCTAssertTrue(e.isFinished(at: 4.25))
        XCTAssertEqual(e.reason, .silence)
    }

    // MARK: - Ruteo

    func testRouteLocal() {
        XCTAssertEqual(route("abrí Spotify"), .local(.openApp(name: "Spotify")))
        XCTAssertEqual(route("poné un timer de cinco minutos"), .local(.timer(seconds: 300, label: nil)))
        XCTAssertEqual(route("¿Me podrías abrir Safari, por favor?"), .local(.openApp(name: "Safari")))
        XCTAssertEqual(route("¿Me ponés un timer de diez minutos para la pizza?"),
                       .local(.timer(seconds: 600, label: "Pizza")))
        let remind = parse("recordame comprar pan a las 9")
        XCTAssertNotNil(remind)
        XCTAssertEqual(route("¿me recordás comprar pan a las nueve?"), remind.map { .local($0) })
        XCTAssertEqual(route("che, anotá que tengo que llamar a Juan"), .local(.note(text: "tengo que llamar a Juan")))
        XCTAssertEqual(route("mostrame el reloj"), .local(.showClock))
    }

    func testRouteClaude() {
        XCTAssertEqual(route("¿qué tiempo va a hacer mañana?"), .claude("¿qué tiempo va a hacer mañana?"))
        XCTAssertEqual(route("che, explicame qué es un closure"), .claude("explicame qué es un closure"))
        XCTAssertEqual(route("¿me decís cuántos días faltan para navidad?"),
                       .claude("decime cuántos días faltan para navidad"))
        // "pará el timer" es un pedido, no una cancelación de la escucha.
        XCTAssertEqual(route("cancelá el timer"), .claude("cancelá el timer"))
    }

    func testRouteStopAndEmpty() {
        for s in ["cancelá", "Cancelar.", "nada", "pará", "pará, pará", "no, nada, gracias", "olvidalo", "dejá",
                  "basta", "ya está", "no importa", "me equivoqué", "nada, Orbex", "gracias"] {
            XCTAssertEqual(route(s), .stop, s)
        }
        for s in ["", "   ", "eh", "mmm", "por favor", "¿?"] {
            XCTAssertEqual(route(s), .empty, s)
        }
    }

    func testFullFlow() {
        let m = matcher.match("Hola Orbi, ¿me ponés un timer de cinco minutos?")
        XCTAssertEqual(m?.wakeWord, "Orbi")
        XCTAssertEqual(route(m?.command ?? ""), .local(.timer(seconds: 300, label: nil)))
        XCTAssertEqual(route(matcher.match("orbes recordame a las nueve sacar la basura")?.command ?? ""),
                       parse("recordame a las 9 sacar la basura").map { .local($0) })
        XCTAssertEqual(route(matcher.match("Orbex, nada")?.command ?? ""), .stop)
        XCTAssertEqual(route(matcher.match("Orbex")?.command ?? ""), .empty)
    }
}

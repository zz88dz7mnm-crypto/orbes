import Foundation

/// Ajustes de la voz (Configuración › Voz). No son sensibles: van en `UserDefaults` con claves `orbex.voice.*`.
/// La vista los edita con `@AppStorage` usando estas mismas claves y después avisa a
/// `VoiceController.shared.settingsDidChange()`.
enum VoiceSettings {
    enum Keys {
        /// Interruptor general de la voz (atajo, clic largo y "siempre atento").
        static let enabled = "orbex.voice.enabled"
        /// Escuchar todo el tiempo esperando el nombre ("Orbex, …"). Apagado por defecto (batería).
        static let alwaysListening = "orbex.voice.alwaysListening"
        /// "auto" o un identificador de idioma ("es-AR", "es-ES", "es-MX", "es-US").
        static let locale = "orbex.voice.locale"
        /// Nombres extra para despertarlo, separados por coma ("Jarvis, Robotito").
        static let extraNames = "orbex.voice.extraNames"
        /// Sonidito cuando empieza a escuchar.
        static let chime = "orbex.voice.chime"
        /// Pausar "siempre atento" con el Modo de bajo consumo de macOS o el modo ahorro de ORBEX.
        static let pauseOnLowPower = "orbex.voice.pauseOnLowPower"
        /// Atajo ⌃⌥Espacio para hablarle sin decir el nombre.
        static let pushToTalk = "orbex.voice.pushToTalk"
        /// Mantener apretado en la isla para hablarle.
        static let longPress = "orbex.voice.longPress"
        /// Permitir el reconocimiento en los servidores de Apple si no hay modelo en la Mac (el audio sale).
        static let allowCloud = "orbex.voice.allowCloud"
    }

    struct Language: Identifiable {
        /// "auto" o identificador de idioma.
        let id: String
        let name: String
    }

    /// Idiomas que se pueden elegir.
    static let languages: [Language] = [
        Language(id: "auto", name: "Automático (el de tu Mac, si es español)"),
        Language(id: "es-AR", name: "Español (Argentina)"),
        Language(id: "es-ES", name: "Español (España)"),
        Language(id: "es-MX", name: "Español (México)"),
        Language(id: "es-US", name: "Español (EE. UU.)"),
    ]

    /// Variantes del nombre que ya reconoce (solo para mostrar; las entiende `WakeWordMatcher`).
    static let builtInNames = ["Orbex", "Orbi", "Orbes", "Orbis", "Orby", "Orvex"]

    private static var defaults: UserDefaults { .standard }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    static var enabled: Bool { bool(Keys.enabled, false) }
    static var alwaysListening: Bool { bool(Keys.alwaysListening, false) }
    static var chime: Bool { bool(Keys.chime, true) }
    static var pauseOnLowPower: Bool { bool(Keys.pauseOnLowPower, true) }
    static var pushToTalk: Bool { bool(Keys.pushToTalk, true) }
    static var longPress: Bool { bool(Keys.longPress, false) }
    static var allowCloud: Bool { bool(Keys.allowCloud, false) }

    static var localeID: String {
        let v = defaults.string(forKey: Keys.locale) ?? "auto"
        return v.isEmpty ? "auto" : v
    }

    /// Nombres extra, limpios y sin repetidos.
    static var extraNames: [String] {
        let raw = defaults.string(forKey: Keys.extraNames) ?? ""
        var seen = Set<String>()
        var out: [String] = []
        for part in raw.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" }) {
            let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2, name.count <= 30 else { continue }
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if seen.insert(key).inserted { out.append(name) }
        }
        return Array(out.prefix(8))
    }
}

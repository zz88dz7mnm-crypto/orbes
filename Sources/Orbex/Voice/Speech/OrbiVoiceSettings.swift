import Foundation

/// Motor que usa Orbi para hablar.
enum OrbiVoiceBackend: String, CaseIterable, Identifiable, Sendable {
    /// Kokoro, local (helper de Python en Application Support). Voz natural, sin internet.
    case kokoro
    /// Cartesia (nube, opcional; clave en el Keychain).
    case cartesia
    /// Voz de macOS (`AVSpeechSynthesizer`), siempre disponible.
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kokoro: return "Kokoro (local)"
        case .cartesia: return "Cartesia (nube)"
        case .system: return "Voz de macOS"
        }
    }
}

/// Preferencias de la voz de salida (en `UserDefaults`; la clave de Cartesia va al Keychain).
enum OrbiVoiceSettings {
    enum Keys {
        static let enabled = "orbex.voiceOut.enabled"
        /// "auto" o el `rawValue` de un `OrbiVoiceBackend`.
        static let backend = "orbex.voiceOut.backend"
        static let speed = "orbex.voiceOut.speed"
        static let kokoroVoice = "orbex.voiceOut.kokoroVoice"
        static let cartesiaVoice = "orbex.voiceOut.cartesiaVoice"
        static let systemVoice = "orbex.voiceOut.systemVoice"
    }

    /// Cuenta del Keychain (está en `KeychainStore.allKeys`).
    static let cartesiaKeyAccount = "cartesia-api-key"

    static let defaultKokoroVoice = "ef_dora"
    /// Voz por defecto de OpenJarvis ("British Butler"); con `language: "es"` habla en español.
    static let defaultCartesiaVoice = "a0e99841-438c-4a64-b679-ae501e7d6091"

    /// Voces de Kokoro en español.
    struct KokoroVoice: Identifiable, Hashable {
        let id: String
        let name: String
    }

    static let kokoroVoices: [KokoroVoice] = [
        KokoroVoice(id: "ef_dora", name: "Dora · mujer"),
        KokoroVoice(id: "em_alex", name: "Alex · hombre"),
        KokoroVoice(id: "em_santa", name: "Santa · hombre, grave"),
    ]

    private static var d: UserDefaults { .standard }

    static var enabled: Bool {
        get { d.object(forKey: Keys.enabled) as? Bool ?? true }
        set { d.set(newValue, forKey: Keys.enabled) }
    }

    /// `nil` = automático.
    static var preferredBackend: OrbiVoiceBackend? {
        OrbiVoiceBackend(rawValue: d.string(forKey: Keys.backend) ?? "auto")
    }

    /// 0.7…1.4, 1 = normal.
    static var speed: Double {
        let v = d.object(forKey: Keys.speed) as? Double ?? 1.0
        return min(max(v, 0.7), 1.4)
    }

    static var kokoroVoice: String {
        let v = d.string(forKey: Keys.kokoroVoice) ?? ""
        return v.isEmpty ? defaultKokoroVoice : v
    }

    static var cartesiaVoice: String {
        let v = (d.string(forKey: Keys.cartesiaVoice) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? defaultCartesiaVoice : v
    }

    /// Identificador de `AVSpeechSynthesisVoice`; vacío = la mejor en español.
    static var systemVoice: String { d.string(forKey: Keys.systemVoice) ?? "" }
}

/// Dónde vive la voz local (lo arma `scripts/instalar-voz.sh`).
enum OrbiVoicePaths {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ORBEX/voz", isDirectory: true)
    }

    static var python: URL { folder.appendingPathComponent("venv/bin/python") }
    static var marker: URL { folder.appendingPathComponent(".instalado") }
    static var log: URL { folder.appendingPathComponent("helper.log") }

    /// Helper instalado; si no, el que viene dentro de la app (si el empaquetado lo incluye).
    static var helper: URL? {
        let installed = folder.appendingPathComponent("orbex-tts.py")
        if FileManager.default.fileExists(atPath: installed.path) { return installed }
        return Bundle.main.url(forResource: "orbex-tts", withExtension: "py")
    }

    /// Carpeta temporal para los WAV que genera el helper.
    static var tempAudio: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("orbex-voz", isDirectory: true)
    }

    /// Kokoro está listo: venv + helper + prueba pasada.
    static var kokoroInstalled: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: python.path)
            && helper != nil
            && fm.fileExists(atPath: marker.path)
    }

    /// Instalador que viene con la app, si está; si no, el del repo.
    static var installCommand: String {
        if let url = Bundle.main.url(forResource: "instalar-voz", withExtension: "sh") {
            return "bash \"\(url.path)\""
        }
        return "cd <carpeta de ORBEX> && ./scripts/instalar-voz.sh"
    }
}

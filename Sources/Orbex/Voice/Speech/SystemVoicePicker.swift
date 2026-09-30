import AVFoundation

/// Elige la mejor voz de macOS en español: premium > mejorada > básica; entre iguales, es-AR, es-MX,
/// es-US, es-ES y femenina. Nunca las voces "novedad" ni la voz personal.
enum SystemVoicePicker {
    struct Option: Identifiable, Hashable {
        let id: String      // identifier
        let label: String
        let quality: AVSpeechSynthesisVoiceQuality
    }

    private static let regionRank = ["es-AR": 0, "es-MX": 1, "es-US": 2, "es-419": 3, "es-ES": 4]

    static func spanishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { v in
            guard v.language.lowercased().hasPrefix("es") else { return false }
            if v.voiceTraits.contains(.isNoveltyVoice) || v.voiceTraits.contains(.isPersonalVoice) { return false }
            return true
        }
        .sorted { score($0) > score($1) }
    }

    /// La voz a usar: la elegida en Configuración si existe; si no, la mejor.
    static func voice(preferred identifier: String) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty, let v = AVSpeechSynthesisVoice(identifier: identifier) { return v }
        return spanishVoices().first ?? AVSpeechSynthesisVoice(language: "es-ES")
    }

    /// `true` si solo hay voces básicas en español (conviene descargar una mejorada).
    static var onlyBasicAvailable: Bool {
        !spanishVoices().contains { $0.quality != .default }
    }

    static func options() -> [Option] {
        spanishVoices().map { v in
            Option(id: v.identifier, label: "\(v.name) · \(regionName(v.language)) · \(qualityName(v.quality))",
                   quality: v.quality)
        }
    }

    static func qualityName(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .premium: return "premium"
        case .enhanced: return "mejorada"
        default: return "básica"
        }
    }

    private static func regionName(_ lang: String) -> String {
        switch lang {
        case "es-AR": return "Argentina"
        case "es-MX": return "México"
        case "es-ES": return "España"
        case "es-US": return "EE. UU."
        case "es-CO": return "Colombia"
        case "es-CL": return "Chile"
        default: return lang
        }
    }

    private static func score(_ v: AVSpeechSynthesisVoice) -> Int {
        let quality: Int
        switch v.quality {
        case .premium: quality = 3
        case .enhanced: quality = 2
        default: quality = 1
        }
        let region = 5 - (regionRank[v.language] ?? 5)
        let female = v.gender == .female ? 1 : 0
        return quality * 100 + region * 10 + female
    }
}

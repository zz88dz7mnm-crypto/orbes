import Foundation

/// Temas disponibles (informe §7). El detalle visual vive en la app.
public enum ThemeID: String, CaseIterable, Codable, Sendable {
    case liquidGlass, macClean, y2k

    public var label: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .macClean: return "macOS limpio"
        case .y2k: return "Y2K metálico"
        }
    }
}

/// En qué pantalla vive la isla.
public enum ScreenChoice: Codable, Equatable, Hashable, Sendable {
    /// Pantalla con notch si hay; si no, la principal.
    case automatic
    case main
    /// Por identificador de pantalla (`NSScreenNumber`).
    case display(UInt32)
}

/// Todos los ajustes de la app (sin claves: esas van al Keychain).
/// Se guardan como JSON en `UserDefaults`. Cada campo tiene valor por defecto para que
/// agregar ajustes nuevos no rompa los guardados.
public struct OrbexSettings: Codable, Equatable, Sendable {
    // Personaje
    public var lifeLevel: LifeLevel = .normal
    public var tint: OrbexTint = .clear
    public var sleep = SleepPolicy()
    public var userName: String = ""
    public var greetOnLaunch: Bool = true
    public var characterScale: Double = 1

    // Isla
    public var screen: ScreenChoice = .automatic
    public var notchAdjustWidth: Double = 0   // ±10 pt
    public var notchAdjustHeight: Double = 0  // ±6 pt
    public var wingScale: Double = 1
    public var hoverPeeks: Bool = true
    public var openAutoCloseSeconds: Double = 15
    public var hiddenPulse: Bool = true

    // Tema
    public var theme: ThemeID = .liquidGlass
    public var useGlass: Bool = true
    /// 0 = vidrio claro, 1 = vidrio teñido (control propio de transparencia, informe §3.1).
    public var glassTint: Double = 0.35

    // Sonido
    public var soundEnabled: Bool = true
    public var volume: Double = 0.6
    public var quietHoursEnabled: Bool = false
    public var quietStartHour: Int = 22
    public var quietEndHour: Int = 8
    public var duckWithMusic: Bool = true
    public var mutedSounds: [String] = []

    // General
    public var launchAtLogin: Bool = false
    public var desktopShortcut: Bool = false
    public var firstRunDone: Bool = false

    // Accesibilidad y rendimiento
    public var reduceMotion: Bool = false
    public var maxFPS: Int = 60
    public var lowPowerMode: Bool = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case lifeLevel, tint, sleep, userName, greetOnLaunch, characterScale
        case screen, notchAdjustWidth, notchAdjustHeight, wingScale, hoverPeeks, openAutoCloseSeconds, hiddenPulse
        case theme, useGlass, glassTint
        case soundEnabled, volume, quietHoursEnabled, quietStartHour, quietEndHour, duckWithMusic, mutedSounds
        case launchAtLogin, desktopShortcut, firstRunDone
        case reduceMotion, maxFPS, lowPowerMode
    }

    /// Decodificación tolerante: cualquier campo que falte o no se entienda toma su valor por defecto.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = OrbexSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        lifeLevel = v(.lifeLevel, d.lifeLevel)
        tint = v(.tint, d.tint)
        sleep = v(.sleep, d.sleep)
        userName = v(.userName, d.userName)
        greetOnLaunch = v(.greetOnLaunch, d.greetOnLaunch)
        characterScale = v(.characterScale, d.characterScale)
        screen = v(.screen, d.screen)
        notchAdjustWidth = v(.notchAdjustWidth, d.notchAdjustWidth)
        notchAdjustHeight = v(.notchAdjustHeight, d.notchAdjustHeight)
        wingScale = v(.wingScale, d.wingScale)
        hoverPeeks = v(.hoverPeeks, d.hoverPeeks)
        openAutoCloseSeconds = v(.openAutoCloseSeconds, d.openAutoCloseSeconds)
        hiddenPulse = v(.hiddenPulse, d.hiddenPulse)
        theme = v(.theme, d.theme)
        useGlass = v(.useGlass, d.useGlass)
        glassTint = v(.glassTint, d.glassTint)
        soundEnabled = v(.soundEnabled, d.soundEnabled)
        volume = v(.volume, d.volume)
        quietHoursEnabled = v(.quietHoursEnabled, d.quietHoursEnabled)
        quietStartHour = v(.quietStartHour, d.quietStartHour)
        quietEndHour = v(.quietEndHour, d.quietEndHour)
        duckWithMusic = v(.duckWithMusic, d.duckWithMusic)
        mutedSounds = v(.mutedSounds, d.mutedSounds)
        launchAtLogin = v(.launchAtLogin, d.launchAtLogin)
        desktopShortcut = v(.desktopShortcut, d.desktopShortcut)
        firstRunDone = v(.firstRunDone, d.firstRunDone)
        reduceMotion = v(.reduceMotion, d.reduceMotion)
        maxFPS = v(.maxFPS, d.maxFPS)
        lowPowerMode = v(.lowPowerMode, d.lowPowerMode)
    }

    /// Volumen efectivo según horario silencioso.
    public func effectiveVolume(hour: Int) -> Double {
        guard soundEnabled else { return 0 }
        if quietHoursEnabled {
            let quiet = SleepPolicy(enabled: true, startHour: quietStartHour, endHour: quietEndHour, idleMinutes: 0)
            if quiet.isNight(hour: hour) { return 0 }
        }
        // Un poco más bajo de noche.
        let nightFactor = (hour >= 22 || hour < 7) ? 0.6 : 1
        return volume.clamped(0, 1) * nightFactor
    }

    /// Exportar ajustes (nunca incluye claves: no están acá).
    public func exportJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }

    public static func importJSON(_ data: Data) throws -> OrbexSettings {
        try JSONDecoder().decode(OrbexSettings.self, from: data)
    }
}

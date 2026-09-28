import Foundation

public enum ClockFace: String, CaseIterable, Codable, Sendable, Identifiable {
    case classic, retroWall, orbit
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .classic: return "Clásica"
        case .retroWall: return "Retro de pared"
        case .orbit: return "ORBIT"
        }
    }
}

public enum ClockSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case mini, normal, large
    public var id: String { rawValue }
    public var points: Double {
        switch self {
        case .mini: return 110
        case .normal: return 190
        case .large: return 280
        }
    }
    public var label: String {
        switch self {
        case .mini: return "Mini"
        case .normal: return "Normal"
        case .large: return "Grande"
        }
    }
}

/// Ajustes del reloj flotante (se guardan como JSON en `orbex.clock.settings`).
public struct ClockSettings: Codable, Equatable, Sendable {
    public static let storageKey = "orbex.clock.settings"

    public var face: ClockFace = .classic
    public var size: ClockSize = .normal
    public var opacity: Double = 1
    public var clickThrough: Bool = false
    public var snapToEdges: Bool = true
    public var showSeconds: Bool = true
    public var tickSound: Bool = false
    /// Última posición (esquina inferior izquierda, coordenadas de pantalla). `nil` = por defecto.
    public var originX: Double?
    public var originY: Double?

    public init() {}

    public var isCompact: Bool { size == .mini }
    public var effectiveShowSeconds: Bool { showSeconds && !isCompact }
    public var clampedOpacity: Double { min(1, max(0.25, opacity)) }

    /// Tamaño de la ventana: el reloj de pared suma el péndulo debajo (salvo en mini).
    public var windowSize: (width: Double, height: Double) {
        let p = size.points
        return (p, face == .retroWall && !isCompact ? p * 1.42 : p)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        face = (try? c.decodeIfPresent(ClockFace.self, forKey: .face)) ?? .classic
        size = (try? c.decodeIfPresent(ClockSize.self, forKey: .size)) ?? .normal
        opacity = (try? c.decodeIfPresent(Double.self, forKey: .opacity)) ?? 1
        clickThrough = (try? c.decodeIfPresent(Bool.self, forKey: .clickThrough)) ?? false
        snapToEdges = (try? c.decodeIfPresent(Bool.self, forKey: .snapToEdges)) ?? true
        showSeconds = (try? c.decodeIfPresent(Bool.self, forKey: .showSeconds)) ?? true
        tickSound = (try? c.decodeIfPresent(Bool.self, forKey: .tickSound)) ?? false
        originX = try? c.decodeIfPresent(Double.self, forKey: .originX)
        originY = try? c.decodeIfPresent(Double.self, forKey: .originY)
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decode(_ data: Data?) -> ClockSettings {
        guard let data, let s = try? JSONDecoder().decode(ClockSettings.self, from: data) else { return ClockSettings() }
        return s
    }
}

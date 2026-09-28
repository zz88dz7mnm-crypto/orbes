import Foundation

/// Generador pseudoaleatorio con semilla (SplitMix64) para que la vida de ORBEX sea
/// reproducible en las pruebas.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Nivel de vida elegido en Configuración.
public enum LifeLevel: String, Codable, CaseIterable, Sendable {
    case calm, normal, hyper

    /// Multiplicador de los intervalos (más chico = más activo).
    public var intervalFactor: Double {
        switch self {
        case .calm: return 1.6
        case .normal: return 1
        case .hyper: return 0.55
        }
    }

    public var label: String {
        switch self {
        case .calm: return "Tranquilo"
        case .normal: return "Normal"
        case .hyper: return "Hiperactivo"
        }
    }
}

/// Microgestos (capa L1 del sistema de vida, informe §4.6).
public enum Microgesture: String, CaseIterable, Codable, Sendable {
    case stretch      // se estira
    case lookAround   // mira alrededor
    case yawn         // bosteza
    case scratch      // se rasca
    case followDot    // sigue un puntito imaginario
    case wiggle       // se sacude
    case hop          // saltito
    case waveSmall    // saludito

    /// Duración de la animación en segundos.
    public var duration: Double {
        switch self {
        case .stretch: return 1.6
        case .lookAround: return 2.2
        case .yawn: return 1.8
        case .scratch: return 1.4
        case .followDot: return 2.6
        case .wiggle: return 0.8
        case .hop: return 0.7
        case .waveSmall: return 1.3
        }
    }
}

/// Sorpresas raras (capa L5, ~1 de cada 100).
public enum Surprise: String, CaseIterable, Codable, Sendable {
    case spin        // gira sobre sí mismo
    case sparkle     // destellos
    case peekaboo    // se esconde y reaparece
    case heartEyes   // ojos de corazón

    public var duration: Double {
        switch self {
        case .spin: return 1.4
        case .sparkle: return 1.8
        case .peekaboo: return 2.0
        case .heartEyes: return 1.6
        }
    }
}

public enum LifeEvent: Equatable, Sendable {
    case blink(double: Bool)
    case microgesture(Microgesture)
    case surprise(Surprise)
}

/// Decide cuándo parpadea ORBEX y cuándo hace microgestos o sorpresas.
/// No tiene timers: la app llama a `update(now:)` en cada cuadro o cada ~0,1 s.
public struct LifeScheduler: Sendable {
    public var level: LifeLevel
    /// Probabilidad de que un microgesto sea una sorpresa rara.
    public var surpriseChance: Double = 0.01

    public private(set) var nextBlinkAt: Double
    public private(set) var nextGestureAt: Double
    private var rng: SeededGenerator

    /// Rangos base (informe §4.6): parpadeo cada 2,5–6 s, microgestos cada 8–20 s.
    public static let blinkRange: ClosedRange<Double> = 2.5...6
    public static let gestureRange: ClosedRange<Double> = 8...20

    public init(level: LifeLevel = .normal, now: Double = 0, seed: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)) {
        self.level = level
        self.rng = SeededGenerator(seed: seed)
        self.nextBlinkAt = now + 1.5
        self.nextGestureAt = now + 6
    }

    public mutating func update(now: Double, allowGestures: Bool = true) -> [LifeEvent] {
        var events: [LifeEvent] = []
        if now >= nextBlinkAt {
            // De vez en cuando, doble parpadeo.
            let double = Double.random(in: 0..<1, using: &rng) < 0.15
            events.append(.blink(double: double))
            nextBlinkAt = now + Double.random(in: Self.blinkRange, using: &rng) * level.intervalFactor.squareRootish
        }
        if now >= nextGestureAt {
            if allowGestures {
                if Double.random(in: 0..<1, using: &rng) < surpriseChance {
                    events.append(.surprise(Surprise.allCases.randomElement(using: &rng)!))
                } else {
                    events.append(.microgesture(Microgesture.allCases.randomElement(using: &rng)!))
                }
            }
            nextGestureAt = now + Double.random(in: Self.gestureRange, using: &rng) * level.intervalFactor
        }
        return events
    }

    // MARK: - Capa L0 (siempre): funciones continuas del tiempo

    /// Respiración: escala 1,00 → 1,02 con un ciclo de ~4 s.
    public static func breathScale(at t: Double, amplitude: Double = 0.02) -> Double {
        1 + amplitude * (0.5 - 0.5 * cos(t * 2 * .pi / 4.0))
    }

    /// Flotación leve: desplazamiento vertical en fracción del diámetro.
    public static func floatOffset(at t: Double) -> Double {
        sin(t * 2 * .pi / 5.3) * 0.015
    }

    /// Apertura del ojo durante un parpadeo (1 = abierto, ~0,08 = cerrado).
    /// `elapsed` es el tiempo desde que empezó el parpadeo.
    public static func blinkOpenness(elapsed: Double, double: Bool = false) -> Double {
        let single = 0.16
        func one(_ e: Double) -> Double {
            guard e >= 0, e < single else { return 1 }
            let p = e / single                   // 0 → 1
            let closed = 1 - abs(p * 2 - 1)      // 0 → 1 → 0
            return 1 - 0.92 * closed
        }
        if double {
            return min(one(elapsed), one(elapsed - 0.24))
        }
        return one(elapsed)
    }
}

extension Double {
    /// Suaviza el factor para que el parpadeo no cambie tanto entre niveles.
    fileprivate var squareRootish: Double { (self + 1) / 2 }
}

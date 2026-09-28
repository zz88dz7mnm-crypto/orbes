import Foundation

/// Expresiones de ORBEX con solo dos óvalos (informe §4.5).
public enum FaceExpression: String, CaseIterable, Codable, Sendable {
    case neutral
    case happy        // arquitos hacia arriba
    case annoyed      // achatados por arriba
    case surprised    // más altos
    case sleepy       // rayitas
    case dizzy        // los ojos giran
    case thinking     // miran hacia arriba
    case focused      // más chicos y juntos
    case love         // corazones
    case worried      // inclinados hacia adentro
    case celebrate    // estrellitas cortas
}

/// Cómo se dibuja un ojo. Todas las medidas en fracción del diámetro del cuerpo `D`.
public struct EyeShape: Equatable, Sendable {
    /// Ancho y alto del óvalo.
    public var width: Double
    public var height: Double
    /// Desplazamiento del centro de cada ojo respecto de su posición base (x hacia afuera).
    public var spread: Double
    public var offsetY: Double
    /// Fracción superior recortada (0 = nada; 0,4 = achatado arriba, molesto).
    public var topCut: Double
    /// Inclinación en radianes (positivo = ceja "preocupada").
    public var tilt: Double
    /// Forma especial en lugar del óvalo.
    public var glyph: Glyph

    public enum Glyph: String, Equatable, Sendable {
        case oval, arcUp, line, spiral, heart, star
    }

    public init(width: Double = 0.075, height: Double = 0.2, spread: Double = 0, offsetY: Double = 0,
                topCut: Double = 0, tilt: Double = 0, glyph: Glyph = .oval) {
        self.width = width
        self.height = height
        self.spread = spread
        self.offsetY = offsetY
        self.topCut = topCut
        self.tilt = tilt
        self.glyph = glyph
    }

    /// Posición base de los ojos (hoja del personaje): centros a ±0,14 D, un poco arriba del centro.
    public static let baseSeparation = 0.14
    public static let baseY = -0.06

    public static func forExpression(_ e: FaceExpression) -> EyeShape {
        switch e {
        case .neutral:   return EyeShape()
        case .happy:     return EyeShape(width: 0.1, height: 0.08, offsetY: -0.01, glyph: .arcUp)
        case .annoyed:   return EyeShape(width: 0.085, height: 0.16, offsetY: 0.015, topCut: 0.42)
        case .surprised: return EyeShape(width: 0.09, height: 0.25, offsetY: -0.02)
        case .sleepy:    return EyeShape(width: 0.1, height: 0.02, offsetY: 0.02, glyph: .line)
        case .dizzy:     return EyeShape(width: 0.11, height: 0.11, glyph: .spiral)
        case .thinking:  return EyeShape(width: 0.07, height: 0.18, spread: -0.01, offsetY: -0.05)
        case .focused:   return EyeShape(width: 0.06, height: 0.15, spread: -0.025)
        case .love:      return EyeShape(width: 0.12, height: 0.11, glyph: .heart)
        case .worried:   return EyeShape(width: 0.075, height: 0.17, offsetY: 0.01, topCut: 0.18, tilt: 0.28)
        case .celebrate: return EyeShape(width: 0.12, height: 0.12, glyph: .star)
        }
    }

    /// Interpola entre dos formas (para transiciones suaves). El glifo cambia a la mitad.
    public static func lerp(_ a: EyeShape, _ b: EyeShape, _ t: Double) -> EyeShape {
        let k = t.clamped(0, 1)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * k }
        return EyeShape(width: mix(a.width, b.width), height: mix(a.height, b.height),
                        spread: mix(a.spread, b.spread), offsetY: mix(a.offsetY, b.offsetY),
                        topCut: mix(a.topCut, b.topCut), tilt: mix(a.tilt, b.tilt),
                        glyph: k < 0.5 ? a.glyph : b.glyph)
    }
}

/// Hacia dónde miran los ojos (capa L2: siguen el cursor, con límite dentro de la esfera).
public enum LookAt {
    /// Devuelve el desplazamiento de los ojos en fracción de `D` (máx. `maxOffset`).
    /// - Parameters:
    ///   - target: posición del cursor relativa al centro del cuerpo (en puntos, y hacia abajo).
    ///   - reach: distancia (en puntos) a la que la mirada llega al máximo.
    public static func offset(target: (x: Double, y: Double), reach: Double = 400,
                              maxOffset: Double = 0.07) -> (x: Double, y: Double) {
        let dist = (target.x * target.x + target.y * target.y).squareRoot()
        guard dist > 0.001 else { return (0, 0) }
        let strength = min(1, dist / reach)
        // Curva suave: cerca del cuerpo se mueve poco.
        let eased = 1 - (1 - strength) * (1 - strength)
        let nx = target.x / dist, ny = target.y / dist
        return (nx * maxOffset * eased, ny * maxOffset * 0.7 * eased)
    }
}

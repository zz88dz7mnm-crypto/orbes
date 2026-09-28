import Foundation

/// Medida del notch tomada en vivo de `NSScreen` (en puntos).
public struct NotchMetrics: Equatable, Sendable {
    public var width: Double
    public var height: Double
    /// `false` si la pantalla no tiene notch y ORBEX lo simula.
    public var isHardware: Bool

    public init(width: Double, height: Double, isHardware: Bool) {
        self.width = width
        self.height = height
        self.isHardware = isHardware
    }

    /// Ajuste fino del usuario (ancho ±10 pt, alto ±6 pt). Informe §5.2.
    public func adjusted(dw: Double, dh: Double) -> NotchMetrics {
        NotchMetrics(width: max(80, width + dw.clamped(-10, 10)),
                     height: max(18, height + dh.clamped(-6, 6)),
                     isHardware: isHardware)
    }

    /// Notch simulado para pantallas sin notch: ~12,2 % del ancho (informe §3.2), alto de barra de menú.
    public static func simulated(screenWidth: Double, menuBarHeight: Double) -> NotchMetrics {
        NotchMetrics(width: (screenWidth * 0.122).clamped(150, 240),
                     height: max(24, menuBarHeight),
                     isHardware: false)
    }

    /// Calcula la medida con los valores de `NSScreen`:
    /// alto = `safeAreaInsets.top`; ancho = `frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`.
    /// Si no hay notch (`top == 0` o sin áreas auxiliares) devuelve `nil`.
    public static func measure(screenWidth: Double, safeAreaTop: Double,
                               auxLeftWidth: Double?, auxRightWidth: Double?) -> NotchMetrics? {
        guard safeAreaTop > 0, let l = auxLeftWidth, let r = auxRightWidth else { return nil }
        let w = screenWidth - l - r
        guard w > 40, w < screenWidth * 0.5 else { return nil }
        return NotchMetrics(width: w, height: safeAreaTop, isHardware: true)
    }
}

/// Tamaño de la isla para un estado.
public struct IslandSize: Equatable, Sendable {
    public var width: Double
    public var height: Double
    /// Radio de las esquinas inferiores.
    public var bottomRadius: Double
    /// Radio de las "hombreras" superiores (curva cóncava que funde con la barra de menú).
    public var shoulderRadius: Double

    public init(width: Double, height: Double, bottomRadius: Double, shoulderRadius: Double) {
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.shoulderRadius = shoulderRadius
    }
}

/// Opciones del usuario que afectan la geometría.
public struct IslandGeometryOptions: Equatable, Sendable {
    /// Escala de las alitas laterales (0,5 – 1,5).
    public var wingScale: Double
    /// Ancho máximo del asistente como fracción de la pantalla.
    public var assistantMaxScreenFraction: Double

    public init(wingScale: Double = 1, assistantMaxScreenFraction: Double = 0.4) {
        self.wingScale = wingScale
        self.assistantMaxScreenFraction = assistantMaxScreenFraction
    }
}

/// Reglas de tamaño de la isla (informe §5.1). Todo relativo a la medida en vivo del notch.
public enum IslandGeometry {

    /// Ancho de cada alita lateral por estado (antes de la escala del usuario).
    public static func wing(for state: IslandState) -> Double {
        switch state {
        case .hidden, .clock: return 0
        case .peek, .sleeping: return 14
        case .active, .needsYou: return 30
        case .open: return 40
        case .assistant: return 0 // el asistente usa su propio ancho
        }
    }

    /// Alto extra por debajo del notch.
    public static func extraHeight(for state: IslandState) -> Double {
        switch state {
        case .hidden, .clock: return 0
        case .peek: return 10
        case .sleeping: return 8
        case .active: return 14
        case .needsYou: return 22
        case .open: return 268
        case .assistant: return 0 // calculado aparte
        }
    }

    public static func size(for state: IslandState,
                            notch: NotchMetrics,
                            screenWidth: Double,
                            screenHeight: Double,
                            options: IslandGeometryOptions = IslandGeometryOptions()) -> IslandSize {
        let nw = notch.width
        let nh = notch.height
        switch state {
        case .hidden, .clock:
            return IslandSize(width: nw, height: nh, bottomRadius: notchBottomRadius(nh), shoulderRadius: 6)

        case .assistant:
            let wanted = (nw * 2.6).clamped(420, 520)
            let width = min(wanted, screenWidth * options.assistantMaxScreenFraction)
            let height = (screenHeight * 0.55).clamped(320, 640)
            return IslandSize(width: max(width, nw + 80), height: height, bottomRadius: 26, shoulderRadius: 10)

        default:
            let w = nw + 2 * wing(for: state) * options.wingScale.clamped(0.5, 1.5)
            let h = nh + extraHeight(for: state)
            let bottom: Double
            switch state {
            case .open: bottom = 24
            case .needsYou, .active: bottom = 14
            default: bottom = 11
            }
            return IslandSize(width: w, height: h, bottomRadius: bottom, shoulderRadius: state == .open ? 10 : 7)
        }
    }

    /// El notch real tiene esquinas inferiores de ~8 pt con 32 pt de alto.
    public static func notchBottomRadius(_ notchHeight: Double) -> Double {
        (notchHeight * 0.25).clamped(6, 10)
    }

    /// Tamaño máximo que puede alcanzar la isla (para dimensionar la ventana una sola vez).
    public static func maxSize(notch: NotchMetrics, screenWidth: Double, screenHeight: Double,
                               options: IslandGeometryOptions = IslandGeometryOptions()) -> (width: Double, height: Double) {
        var w = 0.0, h = 0.0
        for s in IslandState.allCases {
            let size = self.size(for: s, notch: notch, screenWidth: screenWidth, screenHeight: screenHeight, options: options)
            w = max(w, size.width + 2 * size.shoulderRadius)
            h = max(h, size.height)
        }
        return (w + 40, h + 30) // margen para sombras y rebote del resorte
    }
}

extension Double {
    public func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}

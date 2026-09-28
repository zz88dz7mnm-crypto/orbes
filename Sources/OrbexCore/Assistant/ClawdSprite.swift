import Foundation

/// Estado de ánimo de Clawd, la mascota pixelada que acompaña al asistente.
public enum ClawdMood: String, Codable, Sendable, CaseIterable {
    /// Esperando: respira, parpadea y a veces camina un poquito.
    case idle
    /// Claude está pensando: tres puntitos saltan arriba de la cabeza.
    case thinking
    /// Llega texto: mueve los bracitos como si tipeara.
    case typing
    /// Terminó bien: salta con los brazos arriba.
    case happy
    /// Hubo un error: se achica, baja los brazos y le cae una lágrima.
    case sad
}

/// Un píxel del dibujo de Clawd (coordenadas de grilla, y hacia abajo).
public struct ClawdPixel: Equatable, Hashable, Sendable {
    public enum Kind: Int, Sendable, CaseIterable {
        case body, shade, highlight, eye, dot, tear, sparkle
    }

    public var x: Int
    public var y: Int
    public var kind: Kind

    public init(_ x: Int, _ y: Int, _ kind: Kind) {
        self.x = x
        self.y = y
        self.kind = kind
    }
}

/// Clawd dibujado por código: grilla de píxeles cuadrados animada según el ánimo y el tiempo.
///
/// El cuerpo mide 16 × 10 píxeles (bloque naranja con ojos altos, bracitos a media altura y cuatro
/// patitas). La grilla total deja lugar para caminar a los costados y para saltos y puntitos arriba.
/// Todo es función pura de (ánimo, tiempo): la vista solo pinta.
public enum ClawdSprite {
    /// Columnas de la grilla (16 del cuerpo + 3 a cada lado para caminar).
    public static let columns = 22
    /// Filas de la grilla (10 del cuerpo + 6 arriba para saltos y puntitos).
    public static let rows = 16
    /// Cuánto puede caminar hacia cada lado.
    public static let walkRange = 3

    static let bodyTop = 6
    static let bodyLeft = 3

    /// Píxeles para un instante.
    /// - Parameters:
    ///   - time: segundos (monótonos) para las animaciones de fondo.
    ///   - moodElapsed: segundos desde que empezó el ánimo actual (saltos, lágrimas).
    public static func frame(mood: ClawdMood, time t: Double, moodElapsed: Double, reduceMotion: Bool = false) -> [ClawdPixel] {
        var px: [ClawdPixel] = []
        px.reserveCapacity(140)

        // Caminata (solo en reposo) y dirección de la mirada.
        let walk = (mood == .idle && !reduceMotion) ? walkState(at: t) : (offset: 0, moving: false, direction: 0, step: 0)
        let ox = bodyLeft + walk.offset

        // Desplazamiento vertical del cuerpo: respiración, salto o tristeza.
        var dy = 0          // negativo = arriba
        var squash = 0      // 1 = patitas más cortas (agachado)
        switch mood {
        case .idle, .typing:
            if !reduceMotion && !walk.moving { squash = breathDown(at: t) ? 1 : 0 }
        case .thinking:
            if !reduceMotion { squash = breathDown(at: t * 0.7) ? 1 : 0 }
        case .happy:
            if !reduceMotion && moodElapsed < 1.8 {
                let p = (moodElapsed.truncatingRemainder(dividingBy: 0.6)) / 0.6
                let h = sin(Double.pi * p)
                dy = -Int((h * 3.4).rounded())
                if p < 0.12 || p > 0.9 { squash = 1 }
            }
        case .sad:
            squash = 1
        }
        let top = bodyTop + dy + squash

        // Brazos: altura relativa a la fila 4 del cuerpo.
        var leftArmRow = 4, rightArmRow = 4
        switch mood {
        case .happy:
            leftArmRow = 2; rightArmRow = 2
            if !reduceMotion && Int(t * 8) % 2 == 0 { leftArmRow = 1; rightArmRow = 1 }
        case .sad:
            leftArmRow = 6; rightArmRow = 6
        case .typing:
            if !reduceMotion {
                let k = Int(t * 9) % 4
                leftArmRow = k == 0 ? 3 : 4
                rightArmRow = k == 2 ? 3 : 4
            }
        case .idle:
            if walk.moving {
                leftArmRow = walk.step % 2 == 0 ? 4 : 5
                rightArmRow = walk.step % 2 == 0 ? 5 : 4
            }
        case .thinking:
            break
        }

        // Tronco (filas 0–7 del cuerpo, columnas 2–13).
        for row in 0..<8 {
            for col in 2...13 {
                let kind: ClawdPixel.Kind
                if row == 0 && col > 2 && col < 13 { kind = .highlight }
                else if row == 7 { kind = .shade }
                else { kind = .body }
                px.append(ClawdPixel(ox + col, top + row, kind))
            }
        }
        // Bracitos (dos píxeles de ancho, dos de alto, a cada lado).
        for r in 0..<2 {
            px.append(ClawdPixel(ox + 0, top + leftArmRow + r, r == 1 ? .shade : .body))
            px.append(ClawdPixel(ox + 1, top + leftArmRow + r, r == 1 ? .shade : .body))
            px.append(ClawdPixel(ox + 14, top + rightArmRow + r, r == 1 ? .shade : .body))
            px.append(ClawdPixel(ox + 15, top + rightArmRow + r, r == 1 ? .shade : .body))
        }

        // Patitas: cuatro, de 1 píxel de ancho y 2 de alto (1 si está agachado o levantada al caminar).
        let legs = [3, 5, 10, 12]
        let legTop = top + 8
        let floor = bodyTop + 10 // primera fila debajo de los pies en reposo
        for (i, lx) in legs.enumerated() {
            var height = max(1, floor - legTop)
            if dy < 0 { height = 2 } // en el aire: patitas completas
            if walk.moving && (i % 2 == walk.step % 2) { height = 1 }
            for r in 0..<min(2, height) {
                px.append(ClawdPixel(ox + lx, legTop + r, .shade))
            }
        }

        // Ojos: dos píxeles altos (columnas 4 y 11, filas 2–3), con parpadeo y mirada.
        let lookX = walk.moving ? walk.direction : 0
        var eyeRows: [Int] = [2, 3]
        switch mood {
        case .thinking: eyeRows = [1, 2]           // mira para arriba
        case .happy: eyeRows = [2]                  // ojitos entrecerrados de alegría
        case .sad: eyeRows = [3]                    // caídos
        case .idle, .typing:
            if !reduceMotion && isBlinking(at: t) { eyeRows = [3] }
        }
        for ex in [4, 11] {
            for r in eyeRows {
                px.append(ClawdPixel(ox + ex + lookX, top + r, .eye))
            }
        }

        // Extras.
        switch mood {
        case .thinking:
            // Tres puntitos que saltan en secuencia arriba de la cabeza.
            let base = top - 3
            for (i, col) in [5, 8, 11].enumerated() {
                let phase = reduceMotion ? 0 : Int((t * 6).rounded(.down) + Double(3 - i)) % 4
                let up = phase == 0 ? 1 : 0
                px.append(ClawdPixel(ox + col, base - up, .dot))
            }
        case .sad:
            // Lágrima que cae del ojo izquierdo.
            let cycle = reduceMotion ? 0 : Int((moodElapsed * 5).rounded(.down)) % 5
            px.append(ClawdPixel(ox + 4, top + 4 + cycle, .tear))
        case .happy:
            if moodElapsed < 2.4 {
                let on = reduceMotion || Int(t * 6) % 2 == 0
                let sy = top - 1
                px.append(ClawdPixel(ox - 2, sy + (on ? 0 : 1), .sparkle))
                px.append(ClawdPixel(ox + 17, sy + (on ? 1 : 0), .sparkle))
                if on { px.append(ClawdPixel(ox + 8, top - 3, .sparkle)) }
            }
        case .idle, .typing:
            break
        }

        // Todo dentro de la grilla.
        return px.filter { $0.x >= 0 && $0.x < columns && $0.y >= 0 && $0.y < rows }
    }

    // MARK: - Relojes internos (funciones puras del tiempo)

    /// Respiración: medio ciclo "abajo" cada ~1,4 s.
    static func breathDown(at t: Double) -> Bool {
        let p = t.truncatingRemainder(dividingBy: 1.4)
        return p > 0.85
    }

    /// Parpadeo breve en un momento pseudoaleatorio de cada tramo de 3,7 s.
    static func isBlinking(at t: Double) -> Bool {
        guard t >= 0 else { return false }
        let seg = Int(t / 3.7)
        let start = Double(seg) * 3.7 + 0.4 + unit(seg &* 7 &+ 3) * 2.8
        return t >= start && t < start + 0.14
    }

    /// Caminata: cada tramo de 7 s elige un destino entre −3 y +3 y camina 1 píxel cada 0,25 s.
    static func walkState(at t: Double) -> (offset: Int, moving: Bool, direction: Int, step: Int) {
        guard t >= 0 else { return (0, false, 0, 0) }
        let segLen = 7.0
        let seg = Int(t / segLen)
        let from = walkTarget(seg - 1)
        let to = walkTarget(seg)
        let local = t - Double(seg) * segLen
        let steps = Int(local / 0.25)
        let distance = abs(to - from)
        if steps >= distance || distance == 0 { return (to, false, 0, 0) }
        let dir = to > from ? 1 : -1
        return (from + dir * steps, true, dir, steps)
    }

    static func walkTarget(_ seg: Int) -> Int {
        if seg < 0 { return 0 }
        let r = unit(seg &* 31 &+ 11)
        // La mitad de las veces se queda quieto donde estaba.
        if r < 0.5 { return seg == 0 ? 0 : walkTarget(seg - 1) }
        return Int((unit(seg &* 13 &+ 5) * Double(2 * walkRange + 1)).rounded(.down)) - walkRange
    }

    /// Número pseudoaleatorio estable en [0, 1).
    static func unit(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x = x ^ (x >> 31)
        return Double(x % 10_000) / 10_000
    }
}

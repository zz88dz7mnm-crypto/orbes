import AppKit
import SwiftUI
import OrbexCore

/// Todo lo necesario para dibujar a ORBEX en un instante. Medidas en fracción del diámetro `D`.
struct CharacterFrame {
    var scaleX: Double = 1
    var scaleY: Double = 1
    /// Desplazamiento vertical del cuerpo (negativo = arriba).
    var offsetY: Double = 0
    var rotation: Double = 0

    var eye = EyeShape()
    /// 1 = abierto, ~0 = cerrado.
    var eyeOpenness: Double = 1
    var look: (x: Double, y: Double) = (0, 0)
    /// Giro de los ojos (mareado).
    var eyeSpin: Double = 0

    /// Cuánto levanta cada brazo (0 = colgando, ~2,8 = arriba del todo). Positivo = hacia afuera.
    var leftArmRaise: Double = 0.08
    var rightArmRaise: Double = 0.08
    /// Elevación de cada pie (fracción de D).
    var leftFootLift: Double = 0
    var rightFootLift: Double = 0
    /// 0 = de pie, 1 = agachado del todo.
    var crouch: Double = 0

    var tint: OrbexTint = .clear
    var extras: [Extra] = []

    enum Extra {
        case zzz(phase: Double)
        case hearts(phase: Double)
        case sparkles(phase: Double)
        case notes(phase: Double)
        case exclamation(phase: Double)
        case dot(x: Double, y: Double)
        case sweat(phase: Double)
    }
}

/// El "cerebro" de ORBEX: combina las capas de vida del informe §4.6
/// (L0 respiración/parpadeo, L1 microgestos, L2 atención, L3 contexto, L5 sorpresas)
/// y responde a clics. Las vistas le piden un `CharacterFrame` en cada cuadro.
/// Se usa solo desde el hilo principal (no se marca `@MainActor` para poder llamarlo desde `Canvas`).
final class CharacterBrain: ObservableObject {
    static let shared = CharacterBrain()

    // Estado de fondo (L3)
    @Published var mood = CharacterDirector.Mood(pose: .idle, expression: .neutral)
    @Published var tint: OrbexTint = .clear
    var lifeLevel: LifeLevel = .normal {
        didSet { scheduler.level = lifeLevel }
    }
    var reduceMotion = false

    /// Última posición del mouse en coordenadas de pantalla (AppKit). La actualiza el controlador de la isla.
    var mouseOnScreen: CGPoint = .zero
    /// Momento del último movimiento del mouse (para saber si hay que mirar al cursor).
    var lastMouseMove: Double = 0

    /// Se llama cuando el personaje reacciona (para sonidos).
    var onReaction: ((TapTracker.Reaction) -> Void)?

    private var scheduler = LifeScheduler(level: .normal, now: CACurrentMediaTime())
    private var lastUpdate: Double = 0

    // Eventos en curso
    private var blinkStart: Double = -10
    private var blinkDouble = false
    private var gesture: (kind: Microgesture, start: Double)?
    private var surprise: (kind: Surprise, start: Double)?
    private var squishStart: Double = -10
    private var dizzyUntil: Double = -10
    private var annoyedUntil: Double = -10
    private var overrideExpression: (FaceExpression, until: Double)?
    private var celebrateUntil: Double = -10
    private var worriedUntil: Double = -10
    private var greetUntil: Double = -10
    private var taps = TapTracker()

    private init() {}

    // MARK: - Entradas

    func tap() {
        let now = CACurrentMediaTime()
        let r = taps.tap(at: now)
        switch r {
        case .squish:
            squishStart = now
            annoyedUntil = now + 1.2
        case .dizzy:
            squishStart = now
            dizzyUntil = now + 3.2
        }
        onReaction?(r)
    }

    var isDizzy: Bool { CACurrentMediaTime() < dizzyUntil }

    func celebrate(for seconds: Double = 2.4) {
        celebrateUntil = CACurrentMediaTime() + seconds
    }

    func worry(for seconds: Double = 2.5) {
        worriedUntil = CACurrentMediaTime() + seconds
    }

    func greet(for seconds: Double = 2.2) {
        greetUntil = CACurrentMediaTime() + seconds
    }

    func show(_ expression: FaceExpression, for seconds: Double) {
        overrideExpression = (expression, CACurrentMediaTime() + seconds)
    }

    func blinkNow() {
        blinkStart = CACurrentMediaTime()
        blinkDouble = false
    }

    // MARK: - Cuadro

    /// Calcula el cuadro para el instante `t` (segundos de `CACurrentMediaTime`).
    /// `lookTarget` es el cursor relativo al centro del cuerpo (puntos, y hacia abajo).
    func frame(at t: Double, lookTarget: (x: Double, y: Double)?) -> CharacterFrame {
        advance(to: t)

        var f = CharacterFrame()
        f.tint = tint
        let calm = reduceMotion

        // L0: respiración y flotación (siempre, aunque sea mínima).
        let breath = LifeScheduler.breathScale(at: t, amplitude: calm ? 0.008 : 0.02)
        f.scaleX = 1 + (breath - 1) * 0.6
        f.scaleY = breath
        f.offsetY = calm ? 0 : LifeScheduler.floatOffset(at: t)

        // Expresión de fondo.
        var expression = mood.expression
        var pose = mood.pose

        // L2: mirada al cursor (si se movió hace poco), si no, mirada perezosa.
        if let target = lookTarget, t - lastMouseMove < 6 {
            f.look = LookAt.offset(target: target)
        } else {
            f.look = (sin(t * 0.37) * 0.025, cos(t * 0.23) * 0.012)
        }

        // L3: eventos de contexto con prioridad.
        if t < celebrateUntil { pose = .celebrate; expression = .celebrate }
        if t < worriedUntil { pose = .worried; expression = .worried }
        if t < greetUntil { pose = .wave; expression = .happy }
        if let o = overrideExpression, t < o.until { expression = o.0 }
        if t < annoyedUntil { expression = .annoyed }
        if t < dizzyUntil { expression = .dizzy }

        applyPose(pose, t: t, to: &f)

        // L1: microgesto en curso.
        if let g = gesture, !calm {
            let p = (t - g.start) / g.kind.duration
            if p >= 0 && p <= 1 { applyGesture(g.kind, p: p, t: t, to: &f, expression: &expression) }
        }
        // L5: sorpresa rara.
        if let s = surprise, !calm {
            let p = (t - s.start) / s.kind.duration
            if p >= 0 && p <= 1 { applySurprise(s.kind, p: p, to: &f, expression: &expression) }
        }

        // Reacción al toque: se achata con rebote.
        let sq = t - squishStart
        if sq >= 0 && sq < 0.6 {
            let k = exp(-sq * 7) * cos(sq * 26)
            f.scaleY -= 0.16 * k
            f.scaleX += 0.12 * k
        }
        if t < dizzyUntil {
            f.eyeSpin = t * 7
            f.rotation += sin(t * 5) * (calm ? 0.02 : 0.09)
        }

        f.eye = EyeShape.forExpression(expression)

        // Parpadeo (no cuando duerme o tiene ojos especiales).
        if f.eye.glyph == .oval {
            f.eyeOpenness = LifeScheduler.blinkOpenness(elapsed: t - blinkStart, double: blinkDouble)
        }

        // Extras según pose/expresión.
        if pose == .crouch && expression == .sleepy { f.extras.append(.zzz(phase: t)) }
        if expression == .love { f.extras.append(.hearts(phase: t)) }
        if pose == .dance { f.extras.append(.notes(phase: t)) }
        if pose == .celebrate { f.extras.append(.sparkles(phase: t)) }
        if pose == .wave && mood.pose == .wave { f.extras.append(.exclamation(phase: t)) }
        if pose == .worried { f.extras.append(.sweat(phase: t)) }
        return f
    }

    // MARK: - Internos

    private func advance(to t: Double) {
        guard t > lastUpdate else { return }
        lastUpdate = t
        let sleeping = mood.pose == .crouch
        for e in scheduler.update(now: t, allowGestures: !sleeping && !reduceMotion) {
            switch e {
            case .blink(let double):
                if !sleeping { blinkStart = t; blinkDouble = double }
            case .microgesture(let g):
                if gesture == nil || t - gesture!.start > gesture!.kind.duration { gesture = (g, t) }
            case .surprise(let s):
                surprise = (s, t)
            }
        }
    }

    private func applyPose(_ pose: Pose, t: Double, to f: inout CharacterFrame) {
        let calm = reduceMotion
        switch pose {
        case .idle:
            f.leftArmRaise = 0.08 + sin(t * 1.3) * 0.04
            f.rightArmRaise = 0.08 + sin(t * 1.3 + 1) * 0.04
        case .wave:
            f.rightArmRaise = 2.3 + (calm ? 0 : sin(t * 10) * 0.35)
            f.leftArmRaise = 0.12
        case .walk:
            let s = calm ? 0 : sin(t * 8)
            f.leftFootLift = max(0, s) * 0.05
            f.rightFootLift = max(0, -s) * 0.05
            f.offsetY -= abs(s) * 0.015
            f.leftArmRaise = 0.15 + s * 0.22
            f.rightArmRaise = 0.15 - s * 0.22
        case .crouch:
            f.crouch = 1
            f.leftArmRaise = 0.45
            f.rightArmRaise = 0.45
            // Respiración de dormido más lenta y profunda.
            f.scaleY = LifeScheduler.breathScale(at: t * 0.6, amplitude: 0.03)
        case .dance:
            let beat = t * 2 * .pi * 1.9
            f.rotation = calm ? 0 : sin(beat / 2) * 0.12
            f.offsetY -= calm ? 0 : abs(sin(beat)) * 0.04
            f.leftArmRaise = 1.4 + sin(beat) * 0.9
            f.rightArmRaise = 1.4 - sin(beat) * 0.9
            f.leftFootLift = max(0, sin(beat)) * 0.04
            f.rightFootLift = max(0, -sin(beat)) * 0.04
        case .celebrate:
            let jump = calm ? 0 : abs(sin(t * 6.5))
            f.offsetY -= jump * 0.13
            f.scaleY += (1 - jump) * 0.03
            f.leftArmRaise = 2.5 + sin(t * 13) * 0.2
            f.rightArmRaise = 2.5 - sin(t * 13) * 0.2
        case .worried:
            f.rotation = calm ? 0 : sin(t * 22) * 0.015
            f.leftArmRaise = 0.55
            f.rightArmRaise = 0.55
        case .focused:
            f.leftArmRaise = 0.02
            f.rightArmRaise = 0.02
            f.scaleY *= 0.99
        }
    }

    private func applyGesture(_ g: Microgesture, p: Double, t: Double, to f: inout CharacterFrame, expression: inout FaceExpression) {
        let env = sin(.pi * p)
        switch g {
        case .stretch:
            f.scaleY += 0.07 * env
            f.scaleX -= 0.035 * env
            f.leftArmRaise += 2.6 * env
            f.rightArmRaise += 2.6 * env
            if env > 0.6 { expression = .happy }
        case .lookAround:
            f.look = (sin(p * 2 * .pi) * 0.075, -0.01)
        case .yawn:
            f.scaleY += 0.045 * env
            f.eyeOpenness = 1 - 0.7 * env
            if env > 0.5 { expression = .sleepy }
        case .scratch:
            f.rightArmRaise += (1.9 + sin(t * 32) * 0.18) * env
            if env > 0.4 { expression = .thinking }
        case .followDot:
            let a = p * 4 * .pi
            let dx = cos(a) * 0.5, dy = sin(a) * 0.3 - 0.35
            f.look = (dx * 0.14, dy * 0.14)
            f.extras.append(.dot(x: dx, y: dy))
        case .wiggle:
            f.rotation += sin(p * 6 * .pi) * 0.12 * env
        case .hop:
            f.offsetY -= 0.11 * env
            f.scaleY += 0.05 * (p < 0.2 ? -1 : 1) * env
        case .waveSmall:
            f.rightArmRaise += (2.0 + sin(t * 11) * 0.3) * env
            if env > 0.3 { expression = .happy }
        }
    }

    private func applySurprise(_ s: Surprise, p: Double, to f: inout CharacterFrame, expression: inout FaceExpression) {
        switch s {
        case .spin:
            let e = p * p * (3 - 2 * p)
            f.rotation += e * 2 * .pi
            expression = .happy
        case .sparkle:
            f.extras.append(.sparkles(phase: p * 3))
            expression = .celebrate
        case .peekaboo:
            if p < 0.55 {
                f.leftArmRaise = 2.9
                f.rightArmRaise = 2.9
                f.eyeOpenness = 0.08
            } else {
                expression = .surprised
            }
        case .heartEyes:
            expression = .love
        }
    }
}

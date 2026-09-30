import SwiftUI
import QuartzCore
import OrbexCore

/// Qué está haciendo Orbi en el modo inteligente (decide la cara y el halo).
enum SmartFacePhase: Equatable {
    case idle, listening, thinking, speaking

    var label: String {
        switch self {
        case .idle: return "Te escucho cuando quieras"
        case .listening: return "Escuchándote…"
        case .thinking: return "Pensando…"
        case .speaking: return "Hablando"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "circle.dotted"
        case .listening: return "waveform"
        case .thinking: return "sparkles"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    /// Color del halo: magenta al escuchar (#E040FB, el mismo de la isla), violeta al pensar, celeste al hablar.
    var glow: (r: Double, g: Double, b: Double) {
        switch self {
        case .idle: return (0.62, 0.74, 0.95)
        case .listening: return (0.878, 0.251, 0.984)
        case .thinking: return (0.69, 0.49, 0.91)
        case .speaking: return (0.45, 0.85, 1.0)
        }
    }
}

/// La cara grande de Orbi: el cuerpo lo pinta `OrbexPainter` con el cuadro de `CharacterBrain`
/// (respira, parpadea, microgestos) y encima se ajusta según la fase:
/// - reposo: respira; halo tenue.
/// - escuchando: halo magenta, mano en la oreja y ondas al ritmo de tu voz (`orbex.voice.level`).
/// - pensando: mira arriba y un remolino de puntitos.
/// - hablando: brillo y anillos al ritmo de la voz de Orbi (`orbex.voice.outLevel`).
/// Solo corre mientras el panel está abierto; con "reducir movimiento" baja cuadros y amplitudes.
struct SmartFaceView: View {
    let phase: SmartFacePhase
    let levels: SmartLevels
    let paused: Bool

    @Environment(\.orbexTheme) private var theme
    @State private var clock = FaceClock()

    var body: some View {
        let reduce = theme.reduceMotion
        let fps = reduce ? 20 : min(60, AppModel.shared.characterFPS)
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: paused)) { timeline in
            Canvas { ctx, size in
                _ = timeline.date
                let t = CACurrentMediaTime()
                let dt = clock.tick(t)
                levels.step(dt: dt)
                clock.blend(toward: phase, dt: dt)
                draw(&ctx, size: size, t: t, reduce: reduce)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Orbi, \(phase.label.lowercased())")
    }

    // MARK: - Dibujo

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double, reduce: Bool) {
        let layout = OrbexPainter.Layout(size: size, showLimbs: true, scale: 0.82)
        let D = layout.D
        let center = CGPoint(x: layout.center.x, y: layout.center.y)
        let glow = phase.glow
        let glowColor = Color(red: glow.r, green: glow.g, blue: glow.b)
        let amp: CGFloat = reduce ? 0.35 : 1
        let inLevel = levels.input, outLevel = levels.output
        let breath = 0.5 + 0.5 * sin(t * 2 * .pi / 4.2)

        // Halo detrás del cuerpo (respira; crece con la voz).
        let energy: CGFloat = {
            switch phase {
            case .idle: return 0.12 + 0.06 * CGFloat(breath)
            case .listening: return 0.3 + 0.5 * inLevel
            case .thinking: return 0.25 + 0.08 * CGFloat(breath)
            case .speaking: return 0.3 + 0.6 * outLevel
            }
        }()
        let haloR = D * (0.75 + 0.18 * energy * amp)
        let halo = Path(ellipseIn: CGRect(x: center.x - haloR, y: center.y - haloR, width: haloR * 2, height: haloR * 2))
        ctx.fill(halo, with: .radialGradient(
            Gradient(colors: [glowColor.opacity(Double(0.18 + 0.4 * energy) * clock.mix), glowColor.opacity(0)]),
            center: center, startRadius: D * 0.3, endRadius: haloR))

        switch phase {
        case .listening:
            drawWaves(&ctx, center: center, D: D, t: t, level: inLevel, color: glowColor, amp: amp, reduce: reduce)
        case .speaking:
            drawRings(&ctx, center: center, D: D, t: t, level: outLevel, color: glowColor, amp: amp, reduce: reduce)
        case .thinking, .idle:
            break
        }

        // Cuerpo: el cuadro vivo del cerebro, con los ajustes de la fase.
        var f = CharacterBrain.shared.frame(at: t, lookTarget: nil)
        f.material = theme.glassAllowed || theme.id != .liquidGlass ? OrbexMaterial(theme: theme.id) : .solid
        switch phase {
        case .idle:
            break
        case .listening:
            // Mano en la oreja y ojos un poco más grandes, atentos.
            f.rightArmRaise = 2.3
            f.eye.height *= 1.08 + 0.12 * Double(inLevel)
            f.look = (0.02, -0.01)
        case .thinking:
            // Mira arriba y a un costado, con un vaivén lento.
            f.look = (0.05 * sin(t * 1.3) * Double(amp), -0.06)
            f.eye.height *= 0.9
            f.leftArmRaise = 1.1
        case .speaking:
            // Late con la voz: se estira un poquito y los ojos "sonríen" en los picos.
            let s = Double(outLevel * amp)
            f.scaleY *= 1 + 0.05 * s
            f.scaleX *= 1 - 0.025 * s
            f.eyeOpenness = min(f.eyeOpenness, 1 - 0.35 * s)
            f.leftArmRaise = 0.35 + 0.5 * s
            f.rightArmRaise = 0.35 + 0.35 * s
        }
        OrbexPainter.draw(f, in: &ctx, layout: layout, t: t)

        // Brillo encima al hablar (vidrio que se enciende).
        if phase == .speaking {
            let r = D * 0.5
            let bodyCenter = CGPoint(x: center.x, y: center.y + CGFloat(f.offsetY) * D)
            var lit = ctx
            lit.blendMode = .plusLighter
            lit.fill(Path(ellipseIn: CGRect(x: bodyCenter.x - r, y: bodyCenter.y - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [glowColor.opacity(Double(0.28 * outLevel)), .clear]),
                                           center: bodyCenter, startRadius: 0, endRadius: r))
        }
        if phase == .thinking {
            drawSwirl(&ctx, center: CGPoint(x: center.x, y: center.y - D * 0.05), D: D, t: t,
                      color: glowColor, reduce: reduce)
        }
    }

    /// Ondas que salen hacia los costados, como un ecualizador redondo que sigue tu voz.
    private func drawWaves(_ ctx: inout GraphicsContext, center: CGPoint, D: CGFloat, t: Double,
                           level: CGFloat, color: Color, amp: CGFloat, reduce: Bool) {
        let count = reduce ? 2 : 4
        for side in [-1.0, 1.0] {
            for i in 0..<count {
                let k = CGFloat(i) / CGFloat(max(1, count - 1))
                let wobble = reduce ? 0 : CGFloat(sin(t * 7 + Double(i) * 1.3)) * 0.04
                let r = D * (0.62 + 0.13 * CGFloat(i) + (0.06 + wobble) * level * amp)
                let spread = Angle.degrees(Double(22 + 20 * level * amp))
                let mid = side < 0 ? Angle.degrees(180) : .degrees(0)
                var p = Path()
                p.addArc(center: center, radius: r, startAngle: mid - spread, endAngle: mid + spread, clockwise: false)
                let alpha = Double((0.25 + 0.65 * level) * (1 - 0.6 * k))
                ctx.stroke(p, with: .color(color.opacity(alpha)),
                           style: StrokeStyle(lineWidth: D * (0.03 - 0.012 * k), lineCap: .round))
            }
        }
    }

    /// Anillos que se expanden desde el cuerpo al ritmo de la voz de Orbi.
    private func drawRings(_ ctx: inout GraphicsContext, center: CGPoint, D: CGFloat, t: Double,
                           level: CGFloat, color: Color, amp: CGFloat, reduce: Bool) {
        let count = reduce ? 1 : 3
        for i in 0..<count {
            let p0 = reduce ? 0.4 : (t * 0.9 + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
            let r = D * (0.55 + 0.45 * CGFloat(p0)) * (1 + 0.08 * level * amp)
            let alpha = (1 - p0) * Double(0.18 + 0.6 * level)
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(color.opacity(alpha)),
                       lineWidth: D * 0.012 * (1 + level))
        }
    }

    /// Remolino de puntitos arriba de la cabeza mientras piensa.
    private func drawSwirl(_ ctx: inout GraphicsContext, center: CGPoint, D: CGFloat, t: Double,
                           color: Color, reduce: Bool) {
        let dots = 7
        let speed = reduce ? 0.4 : 1.6
        for i in 0..<dots {
            let a = t * speed + Double(i) * (2 * .pi / Double(dots))
            let rx = D * 0.62, ry = D * 0.2
            let p = CGPoint(x: center.x + rx * CGFloat(cos(a)), y: center.y - D * 0.62 + ry * CGFloat(sin(a)))
            let depth = (sin(a) + 1) / 2          // adelante = más grande y claro
            let s = D * (0.018 + 0.022 * CGFloat(depth))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s)),
                     with: .color(color.opacity(0.3 + 0.6 * depth)))
        }
    }
}

/// Reloj propio de la cara: dt entre cuadros y un fundido suave al cambiar de fase.
private final class FaceClock {
    private var last: Double = 0
    private var current: SmartFacePhase = .idle
    /// 0…1: cuánto del halo de la fase actual se ve (vuelve a subir tras cada cambio).
    private(set) var mix: Double = 1

    func tick(_ t: Double) -> Double {
        defer { last = t }
        return last == 0 ? 1.0 / 60 : min(0.1, max(0, t - last))
    }

    func blend(toward phase: SmartFacePhase, dt: Double) {
        if phase != current { current = phase; mix = 0.2 }
        mix = min(1, mix + dt * 3)
    }
}

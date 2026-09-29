// Basado en Coucou (https://github.com/louis-cfm/coucou) © 2026 Louis Raillé — licencia MIT.
// Modificado para ORBEX (solo el código; ningún asset de Coucou). Ver THIRD_PARTY_NOTICES.md.

import SwiftUI
import OrbexCore

// Saludo de ORBEX: vista `greeting` de la isla abierta (lienzo de 640×150 centrado en la isla).
//
// Coreografía (segundos desde que aparece la vista):
//   0,04–0,60  ORBEX se forma como una gota de vidrio colgando del notch, se suelta y cae creciendo.
//   0,60–1,10  Toca el piso aplastándose (squash & stretch de vidrio), rebota, le salen las piernas y
//              sube hasta quedar parado. En cada contacto el piso hace una onda y saltan gotitas.
//   1,18–2,80  Saluda con el brazo-gota; un reflejo le barre el cuerpo y titilan chispitas de vidrio.
//   1,98–3,55  Cuatro mini-ORBEX de colores se asoman por el borde de abajo de la tarjeta y saludan.
//   4,60       Avisa `.greetComplete` (el FSM cierra `greetAutoCollapseDelay` = 0,6 s después). Si el
//              mouse está encima queda respirando y parpadeando. Con `.greetingInterrupt` vuelve en
//              0,34 s a su lugar de la isla compacta (x = 40, y = 16, diámetro 20, como `botPosition`).
// Con "reducir movimiento" no hay caída ni rebotes: aparece en su lugar y saluda suave.

// MARK: - Tiempos

private enum GT {
    static let hang0:     Double = 0.04   // la gota empieza a salir del notch
    static let fall0:     Double = 0.24   // se suelta
    static let land1:     Double = 0.60   // primer contacto con el piso
    static let land2:     Double = 0.84   // segundo contacto (rebote chico)
    static let stand0:    Double = 0.86   // le salen las piernas y sube
    static let stand1:    Double = 1.10   // ya está parado
    static let wave0:     Double = 1.18   // levanta el brazo-gota
    static let wave1:     Double = 2.80   // lo baja
    static let sweep0:    Double = 1.36   // reflejo que barre el cuerpo
    static let sweep1:    Double = 1.96
    static let text0:     Double = 1.30   // entra el texto
    static let minis0:    Double = 1.98   // se asoma el primer mini-ORBEX
    static let minisOut:  Double = 3.30   // se esconden
    static let happy0:    Double = 3.45   // cara contenta al final
    static let happy1:    Double = 3.95
    static let idle0:     Double = 3.00   // desde acá titila una chispita por vez (siempre hay algo vivo)
    static let end:       Double = 4.60   // termina: se avisa `.greetComplete`
    static let autoLeave: Double = 4.90
    static let COLLAPSE:  Double = 0.34   // igual que el cierre de la isla (closeEase de 0,34 s)
}

// MARK: - Geometría (lienzo de 640×150)

private let GCARD = CGRect(x: 10, y: 36, width: 620, height: 104)
private let GCARD_R: CGFloat = 20
private let GCX: CGFloat = 320                        // centro de la isla
private let GD: CGFloat = 54                          // diámetro de la esfera
private let GSTAND_Y: CGFloat = 84                    // centro de la esfera parada
private let GFLOOR_Y: CGFloat = GSTAND_Y + 0.7 * GD   // piso (base de los pies)
// Lugar de ORBEX en la isla compacta (lo mismo que `botPosition(.compact)`).
private let GCOMPACT_X: CGFloat = 40                  // desde el borde izquierdo de la isla compacta
private let GCOMPACT_Y: CGFloat = 16
private let GCOMPACT_D: CGFloat = 20
private let GMINI_D: CGFloat = 22

private let greetTitle = "¡Hola! Soy ORBEX"
private let greetSubtitle = "Vivo acá arriba, en el notch."

// MARK: - Curvas

private enum GE {
    static func out(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    static func easeIn(_ t: Double) -> Double { t * t * t }
    static func inOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    static func back(_ t: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}

private func gClamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }
private func gLerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func gSeg(_ t: Double, _ a: Double, _ b: Double) -> Double { gClamp((t - a) / (b - a), 0, 1) }
private func gLerpF(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// Golpe de squash que se amortigua como vidrio gelatinoso: > 0 aplasta, < 0 estira.
private func gImpulse(_ t: Double, at t0: Double, amp: Double) -> Double {
    let d = t - t0
    guard d >= 0 && d < 0.8 else { return 0 }
    return amp * exp(-d * 8) * cos(d * 26)
}

/// Parpadeo que empieza en `tb` y dura 0,14 s. Devuelve la apertura de los ojos.
private func gBlink(_ t: Double, _ tb: Double) -> Double {
    let k = gSeg(t, tb, tb + 0.14)
    return (k > 0 && k < 1) ? 1 - sin(.pi * k) * 0.93 : 1
}

// MARK: - Estilo y pose

private typealias GRGB = (r: Double, g: Double, b: Double)

private struct GStyle {
    var tint: GRGB
    var material: OrbexMaterial
    var reduce: Bool
    /// x de ORBEX en la isla compacta, en coordenadas del lienzo.
    var compactX: CGFloat
    var notchH: CGFloat
}

private struct GPose {
    var cx: CGFloat = GCX
    var cy: CGFloat = GSTAND_Y          // centro de la esfera
    var D: CGFloat = GD
    var sx: Double = 1
    var sy: Double = 1
    var rot: Double = 0
    var floorY: CGFloat = GFLOOR_Y
    var lift: CGFloat = 0               // altura sobre el piso (achica el brillo de contacto)
    var limbs: Double = 1               // 0…1 brazos y piernas
    var armL: Double = 0.08
    var armR: Double = 0.08
    var expression: FaceExpression = .neutral
    var open: Double = 1
    var lookX: Double = 0
    var lookY: Double = 0
    var sweep: Double = 0               // 0…1 reflejo que barre el cuerpo (0 = nada)
    var glow: Double = 0                // halo de vidrio detrás
    var contact: Double = 1             // brillo de contacto en el piso
    var card: Double = 0
    var text: Double = 0
    var fx: Double = 1                  // chispitas y gotitas (se apagan al cerrar)
    var minis: Double = 1               // mini-ORBEX (se apagan al cerrar)
}

private func gPose(_ t: Double, s: GStyle) -> GPose {
    var p = GPose()
    let calm = s.reduce
    p.card = GE.out(gSeg(t, 0.08, 0.40))
    p.text = GE.out(gSeg(t, GT.text0, GT.text0 + 0.35))
    p.glow = GE.out(gSeg(t, GT.land1 - 0.10, GT.land1 + 0.50))

    // ── Entrada ──
    let yLand = GFLOOR_Y - GD / 2       // centro de la esfera apoyada en el piso, todavía sin piernas
    if calm {
        // Reducir movimiento: crece en su lugar, sin caída ni rebotes.
        let k = GE.out(gSeg(t, GT.hang0, GT.land1))
        p.D = GD * CGFloat(0.4 + 0.6 * k)
        p.limbs = gSeg(t, GT.land1 - 0.15, GT.stand1)
        p.contact = k
    } else if t < GT.fall0 {
        // La gota se forma colgando del borde del notch y se va estirando.
        let k = GE.out(gSeg(t, GT.hang0, GT.fall0))
        p.D = gLerpF(8, 22, CGFloat(k))
        p.cy = gLerpF(s.notchH * 0.3, s.notchH + 4, CGFloat(k))
        p.sy = 1 + 0.24 * k
        p.sx = 1 - 0.14 * k
        p.limbs = 0
        p.lift = max(0, GFLOOR_Y - (p.cy + p.D / 2))
        p.contact = 0.3 * k
    } else if t < GT.land1 {
        // Se suelta y cae acelerando mientras crece; estirada por la velocidad.
        let k = gSeg(t, GT.fall0, GT.land1)
        p.D = gLerpF(22, GD, CGFloat(GE.out(k)))
        p.cy = gLerpF(s.notchH + 4, yLand, CGFloat(k * k))
        p.sy = 1.16 + 0.06 * k
        p.sx = 0.90 - 0.04 * k
        p.limbs = 0
        p.lift = max(0, GFLOOR_Y - (p.cy + p.D / 2))
        p.contact = 0.3 + 0.7 * k
    } else {
        // Rebota una vez; después le salen las piernas y el centro sube hasta quedar parado.
        var lift: CGFloat = 0
        if t < GT.land2 {
            let k = gSeg(t, GT.land1, GT.land2)
            lift = 11 * CGFloat(4 * k * (1 - k))
        }
        let st = CGFloat(GE.back(gSeg(t, GT.stand0, GT.stand1)))
        p.cy = yLand + (GSTAND_Y - yLand) * st - lift
        p.lift = lift
        p.limbs = gSeg(t, GT.stand0 - 0.04, GT.stand0 + 0.14)
        let sq = gImpulse(t, at: GT.land1, amp: 0.24)
            + gImpulse(t, at: GT.land2, amp: 0.10)
            + gImpulse(t, at: GT.stand1 - 0.04, amp: 0.05)
        p.sy = 1 - sq
        p.sx = 1 + 0.75 * sq
    }

    // ── Saludo con el brazo-gota derecho ──
    let up = GE.back(gSeg(t, GT.wave0, GT.wave0 + 0.24))
    let down = GE.inOut(gSeg(t, GT.wave1 - 0.24, GT.wave1))
    let env = up * (1 - down)
    let w = t - GT.wave0
    let amp = calm ? 0.12 : 0.42
    let freq = calm ? 1.1 : 2.3
    p.armR = 0.08 + env * (2.25 + amp * sin(2 * .pi * freq * w))
    p.armL = 0.08 + env * 0.22 + sin(t * 1.3) * 0.04
    if !calm && env > 0 {
        p.rot = 0.045 * sin(2 * .pi * 1.15 * w) * env
        p.cx += CGFloat(1.5 * sin(2 * .pi * 1.15 * w + 0.6) * env)
    }

    // ── Respiración (ya parado) ──
    if t >= GT.stand1 {
        let b = sin(2 * .pi * 0.28 * (t - GT.stand1))
        let a = calm ? 0.008 : 0.018
        p.sy += a * b
        p.sx -= a * 0.6 * b
    }

    // ── Reflejo que barre el cuerpo (y otro cada 5 s si se queda abierto) ──
    if t > GT.sweep0 && t < GT.sweep1 {
        p.sweep = gSeg(t, GT.sweep0, GT.sweep1)
    } else if t > GT.end + 0.8 {
        let ph = (t - GT.end - 0.8).truncatingRemainder(dividingBy: 5.0)
        if ph < 0.6 { p.sweep = ph / 0.6 }
    }

    // ── Ojos ──
    var expr: FaceExpression = .neutral
    var open = 1.0
    if calm {
        if t >= GT.wave0 && t < GT.wave0 + 0.85 { expr = .happy }
        if t >= GT.happy0 && t < GT.happy1 { expr = .happy }
    } else if t < GT.fall0 {
        open = 0.12                                             // la gota "duerme"
    } else if t < GT.land1 {
        expr = .surprised                                       // ¡se cae!
        open = 0.12 + 0.88 * gSeg(t, GT.fall0, GT.fall0 + 0.08)
    } else if t < GT.land1 + 0.10 {
        open = 0.25                                             // el golpe
    } else if t >= GT.land2 && t < GT.wave0 + 0.85 {
        expr = .happy
    } else if t >= GT.happy0 && t < GT.happy1 {
        expr = .happy
    }
    if expr == .neutral && t >= GT.wave0 + 0.85 {
        // Dos parpadeos mientras mira a los minis y después uno cada 3,4 s.
        open = min(gBlink(t, 2.30), gBlink(t, 3.10))
        if t >= GT.happy1 {
            open = gBlink((t - GT.happy1).truncatingRemainder(dividingBy: 3.4), 1.8)
        }
    }
    p.expression = expr
    p.open = open

    // ── Mirada ──
    if t >= GT.land1 && t < GT.land2 {
        p.lookY = 0.04                                          // mira el piso
    } else if t >= GT.minis0 + 0.05 && t < GT.minis0 + 0.55 {
        p.lookX = -0.06; p.lookY = 0.03                         // a los minis de la izquierda
    } else if t >= GT.minis0 + 0.55 && t < GT.minis0 + 1.05 {
        p.lookX = 0.06; p.lookY = 0.03                          // a los de la derecha
    } else if t >= GT.happy1 {
        p.lookX = sin(t * 0.37) * 0.025
        p.lookY = cos(t * 0.23) * 0.012
    }
    return p
}

/// Pose en la isla compacta (sin brazos ni piernas, igual que el ORBEX de `BotPlacement`).
private func gCompactPose(_ s: GStyle) -> GPose {
    var p = GPose()
    p.cx = s.compactX
    p.cy = GCOMPACT_Y
    p.D = GCOMPACT_D
    p.floorY = GCOMPACT_Y + 0.7 * GCOMPACT_D
    p.limbs = 0
    p.contact = 0
    return p
}

/// Pose en el instante `t`; desde `tc` (interrupción) vuelve a la isla compacta.
private func gPoseAt(_ t: Double, tc: Double, s: GStyle) -> GPose {
    if t < tc { return gPose(t, s: s) }
    let a = gPose(tc, s: s)
    let b = gCompactPose(s)
    let e = GE.inOut(gSeg(t, tc, tc + GT.COLLAPSE))
    let ef = CGFloat(e)
    var p = a
    p.cx = gLerpF(a.cx, b.cx, ef)
    p.cy = gLerpF(a.cy, b.cy, ef)
    p.D = gLerpF(a.D, b.D, ef)
    p.floorY = gLerpF(a.floorY, b.floorY, ef)
    p.lift = a.lift * (1 - ef)
    p.sx = gLerp(a.sx, 1, e)
    p.sy = gLerp(a.sy, 1, e)
    p.rot = a.rot * (1 - e)
    p.limbs = a.limbs * (1 - gSeg(t, tc, tc + 0.20))
    p.armL = gLerp(a.armL, 0.08, e)
    p.armR = gLerp(a.armR, 0.08, e)
    p.contact = a.contact * (1 - gSeg(t, tc, tc + 0.15))
    p.glow = a.glow * (1 - e)
    p.card = a.card * (1 - gSeg(t, tc, tc + 0.18))
    p.text = a.text * (1 - gSeg(t, tc, tc + 0.10))
    p.fx = 1 - gSeg(t, tc, tc + 0.20)
    p.minis = 1 - gSeg(t, tc, tc + 0.15)
    p.sweep = 0
    p.expression = .neutral
    p.open = gBlink(t, tc + 0.14)
    p.lookX = a.lookX * (1 - e)
    p.lookY = a.lookY * (1 - e)
    return p
}

// MARK: - Dibujo

private func gColor(_ c: GRGB, _ a: Double) -> Color {
    Color(red: c.r, green: c.g, blue: c.b).opacity(a)
}

/// ORBEX completo con las partes de `OrbexPainter` (piernas, cuerpo, reflejo, ojos, brazos).
/// El squash & stretch va anclado abajo de la esfera, como en `OrbexPainter.draw`.
private func gDrawFigure(_ ctx: inout GraphicsContext, p: GPose, s: GStyle) {
    let D = p.D
    guard D > 0.5 else { return }
    let tint = s.tint
    let feetY = p.floorY - 0.05 * D - p.lift

    if p.contact > 0.01 {
        var g = ctx
        g.opacity = p.contact * p.card
        OrbexPainter.drawContactGlow(&g, x: p.cx, floorY: p.floorY, D: D, lift: p.lift)
    }
    if p.limbs > 0.01 {
        var legs = ctx
        legs.opacity = p.limbs
        for side in [-1.0, 1.0] {
            OrbexPainter.drawLeg(&legs, side: side, bodyCenter: CGPoint(x: p.cx, y: p.cy), footY: feetY,
                                 D: D, tint: tint, crouch: 0, material: s.material)
        }
    }

    var body = ctx
    body.translateBy(x: p.cx, y: p.cy)
    body.rotate(by: .radians(p.rot))
    body.translateBy(x: 0, y: 0.5 * D)
    body.scaleBy(x: CGFloat(p.sx), y: CGFloat(p.sy))
    body.translateBy(x: 0, y: -0.5 * D)
    OrbexPainter.drawBody(&body, D: D, tint: tint, material: s.material)
    if p.sweep > 0 && p.sweep < 1 { gDrawSweep(&body, D: D, k: p.sweep) }

    var face = CharacterFrame()
    face.eye = EyeShape.forExpression(p.expression)
    face.eyeOpenness = p.open
    face.look = (p.lookX, p.lookY)
    OrbexPainter.drawEyes(&body, f: face, D: D)

    if p.limbs > 0.01 {
        var arms = body
        arms.opacity = p.limbs
        OrbexPainter.drawArm(&arms, side: -1, raise: p.armL, D: D, tint: tint, material: s.material)
        OrbexPainter.drawArm(&arms, side: 1, raise: p.armR, D: D, tint: tint, material: s.material)
    }
}

/// Banda de luz que cruza la esfera en diagonal (recortada al cuerpo). `k` va de 0 a 1.
private func gDrawSweep(_ ctx: inout GraphicsContext, D: CGFloat, k: Double) {
    var s = ctx
    s.clip(to: Path(ellipseIn: CGRect(x: -D / 2, y: -D / 2, width: D, height: D)))
    s.rotate(by: .degrees(-24))
    let w = 0.26 * D
    let x = CGFloat(gLerp(-0.9, 0.9, GE.inOut(k))) * D
    let a = 0.5 * sin(.pi * k)
    let band = CGRect(x: x - w / 2, y: -D, width: w, height: 2 * D)
    s.fill(Path(band), with: .linearGradient(
        Gradient(colors: [Color.white.opacity(0), Color.white.opacity(a), Color.white.opacity(0)]),
        startPoint: CGPoint(x: band.minX, y: 0), endPoint: CGPoint(x: band.maxX, y: 0)))
}

/// Halo suave del color de ORBEX detrás de la esfera.
private func gDrawGlow(_ ctx: inout GraphicsContext, p: GPose, s: GStyle) {
    let R = p.D * 1.5
    let c = CGPoint(x: p.cx, y: p.cy)
    ctx.fill(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)),
             with: .radialGradient(Gradient(colors: [gColor(s.tint, 0.16 * p.glow), gColor(s.tint, 0)]),
                                   center: c, startRadius: 0, endRadius: R))
}

// Gotitas de vidrio que saltan en el primer contacto (semilla fija: siempre iguales).
private struct GDrop { let vx, vy, r, life: Double }

private let gDrops: [GDrop] = {
    var seed: UInt32 = 11
    func rnd() -> Double {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Double(seed >> 8) / Double(1 << 24)
    }
    return (0..<10).map { i in
        let side: Double = i % 2 == 0 ? -1 : 1
        return GDrop(vx: side * (40 + rnd() * 90), vy: -(70 + rnd() * 90),
                     r: 1.1 + rnd() * 1.2, life: 0.45 + rnd() * 0.25)
    }
}()

/// Onda en el piso en cada contacto y gotitas que saltan en el primero.
private func gDrawSplash(_ ctx: inout GraphicsContext, t: Double, alpha: Double) {
    let ripples: [(t0: Double, w0: Double, w1: Double)] = [(GT.land1, 0.5, 2.2), (GT.land2, 0.4, 1.4)]
    for r in ripples {
        let k = gSeg(t, r.t0, r.t0 + 0.5)
        guard k > 0 && k < 1 else { continue }
        let w = GD * CGFloat(gLerp(r.w0, r.w1, GE.out(k)))
        let h = w * 0.16
        let rect = CGRect(x: GCX - w / 2, y: GFLOOR_Y - h / 2, width: w, height: h)
        ctx.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.35 * (1 - k) * alpha)), lineWidth: 1.2)
    }
    let d = t - GT.land1
    guard d > 0 && d < 0.75 else { return }
    for drop in gDrops where d < drop.life {
        let x = Double(GCX) + drop.vx * d
        let y = Double(GFLOOR_Y) - 2 + drop.vy * d + 260 * d * d
        let a = (1 - d / drop.life) * alpha
        let r = drop.r
        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                 with: .color(Color.white.opacity(0.75 * a)))
    }
}

// Chispitas alrededor de ORBEX: posición (en diámetros, desde el centro) y cuándo titilan.
// Quedan por debajo del notch (y > 36) para que la cámara no las tape.
private let gTwinkles: [(dx: CGFloat, dy: CGFloat, t0: Double)] = [
    (-0.95, -0.50, 1.24), (1.00, -0.62, 1.40), (-1.28, 0.08, 1.56),
    (1.32, -0.06, 1.72), (-0.55, -0.80, 1.90), (0.62, -0.80, 2.10),
]

private func gDrawTwinkles(_ ctx: inout GraphicsContext, t: Double, p: GPose, s: GStyle) {
    let life = 0.55
    var active: [(index: Int, k: Double)] = []
    for (i, tw) in gTwinkles.enumerated() {
        let k = (t - tw.t0) / life
        if k > 0 && k < 1 { active.append((i, k)) }
    }
    if t >= GT.idle0 {
        // En reposo: una chispita por vez, rotando de lugar.
        let slot = 0.9
        let n = Int((t - GT.idle0) / slot)
        let k = (t - GT.idle0 - Double(n) * slot) / life
        if k > 0 && k < 1 { active.append((n % gTwinkles.count, k)) }
    }
    for item in active {
        let tw = gTwinkles[item.index]
        let pulse = sin(.pi * item.k)
        let size: CGFloat = s.reduce ? GD * 0.16 : GD * 0.22 * CGFloat(pulse)
        guard size > 0.5 else { continue }
        var c = ctx
        c.opacity = p.fx * pulse
        c.translateBy(x: p.cx + tw.dx * p.D, y: p.cy + tw.dy * p.D)
        if !s.reduce { c.rotate(by: .radians(item.k * 0.9)) }
        let h = size * 0.45
        c.fill(Path(ellipseIn: CGRect(x: -h, y: -h, width: 2 * h, height: 2 * h)), with: .color(gColor(s.tint, 0.28)))
        c.fill(OrbexPainter.sparkle(size: size), with: .color(Color.white.opacity(0.95)))
    }
}

// Mini-ORBEX de colores que se asoman por el borde de abajo de la tarjeta.
private struct GMini {
    let x: CGFloat
    let color: GRGB
    let delay: Double
}

private let gMinis: [GMini] = [
    GMini(x: 118, color: (0.95, 0.63, 0.29), delay: 0.00),   // naranja
    GMini(x: 440, color: (0.55, 0.72, 0.42), delay: 0.10),   // verde
    GMini(x: 200, color: (0.47, 0.74, 0.98), delay: 0.20),   // celeste
    GMini(x: 522, color: (0.69, 0.49, 0.91), delay: 0.30),   // violeta
]

/// Se dibujan con el contexto recortado a la tarjeta: al subir parecen salir de atrás del borde.
private func gDrawMinis(_ ctx: inout GraphicsContext, t: Double, s: GStyle) {
    let bottom = GCARD.maxY
    let D = GMINI_D
    for m in gMinis {
        let t0 = GT.minis0 + m.delay
        guard t > t0 else { continue }
        let tOut = GT.minisOut + m.delay * 0.5
        let upK = s.reduce ? GE.out(gSeg(t, t0, t0 + 0.40)) : GE.back(gSeg(t, t0, t0 + 0.30))
        let downK = GE.easeIn(gSeg(t, tOut, tOut + 0.24))
        let vis = upK * (1 - downK)
        guard vis > 0.001 else { continue }
        let hiddenY = bottom + D * 0.62
        let peekY = bottom - D * 0.58
        let cy = hiddenY + (peekY - hiddenY) * CGFloat(vis)
        let inward: Double = m.x < GCX ? 1 : -1       // el brazo del lado de ORBEX es el que saluda
        let w = t - t0 - 0.18
        let wEnv = gSeg(t, t0 + 0.15, t0 + 0.30) * (1 - gSeg(t, tOut - 0.25, tOut))
        let wave = wEnv * (2.1 + (s.reduce ? 0.1 : 0.5) * sin(2 * .pi * 2.8 * w))

        var face = CharacterFrame()
        face.eye = EyeShape.forExpression(wEnv > 0.5 && w < 0.55 ? .happy : .neutral)
        face.eyeOpenness = gBlink(t, t0 + 0.72)
        face.look = (0.05 * inward, -0.01)

        var c = ctx
        if s.reduce { c.opacity = vis }
        c.translateBy(x: m.x, y: cy)
        if !s.reduce { c.rotate(by: .radians(0.08 * inward * sin(2 * .pi * 1.4 * w) * wEnv)) }
        OrbexPainter.drawBody(&c, D: D, tint: m.color, material: s.material)
        OrbexPainter.drawEyes(&c, f: face, D: D)
        OrbexPainter.drawArm(&c, side: -inward, raise: 0.1, D: D, tint: m.color, material: s.material)
        OrbexPainter.drawArm(&c, side: inward, raise: 0.1 + wave, D: D, tint: m.color, material: s.material)
    }
}

private func gDrawText(_ ctx: inout GraphicsContext, alpha: Double) {
    var c = ctx
    c.opacity = alpha
    c.translateBy(x: CGFloat(-8 * (1 - alpha)), y: 0)
    let title = Text(greetTitle)
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundColor(Color(red: 0.96, green: 0.965, blue: 0.97))
    let subtitle = Text(greetSubtitle)
        .font(.system(size: 12))
        .foregroundColor(Color(red: 0.58, green: 0.6, blue: 0.64))
    c.draw(title, at: CGPoint(x: 34, y: 70), anchor: .leading)
    c.draw(subtitle, at: CGPoint(x: 34, y: 91), anchor: .leading)
}

private func gDrawGreeting(_ ctx: inout GraphicsContext, t: Double, tc: Double, s: GStyle) {
    let p = gPoseAt(t, tc: tc, s: s)
    let card = Path(roundedRect: GCARD, cornerRadius: GCARD_R)

    if p.card > 0.001 {
        var c = ctx
        c.opacity = p.card
        c.fill(card, with: .color(Color(red: 0.078, green: 0.082, blue: 0.094)))
        c.stroke(card, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
    }
    if p.glow > 0.01 { gDrawGlow(&ctx, p: p, s: s) }
    if p.minis > 0.01 && p.card > 0.01 && t > GT.minis0 {
        var m = ctx
        m.clip(to: card)
        m.opacity = p.minis
        gDrawMinis(&m, t: t, s: s)
    }
    if p.text > 0.01 { gDrawText(&ctx, alpha: p.text) }
    if p.fx > 0.01 && !s.reduce { gDrawSplash(&ctx, t: t, alpha: p.fx) }
    gDrawFigure(&ctx, p: p, s: s)
    if p.fx > 0.01 { gDrawTwinkles(&ctx, t: t, p: p, s: s) }
}

// MARK: - Vista

struct GreetingCanvasView: View {
    @ObservedObject var state: AppState

    @State private var startDate = Date()
    @State private var tc: Double = .infinity   // solo colapsa cuando el FSM manda `.greetingInterrupt`
    @State private var greetFired = false
    @State private var works: [DispatchWorkItem] = []   // sonidos y aviso de fin (cancelables)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / max(24, AppModel.shared.characterFPS))) { timeline in
            let t = timeline.date.timeIntervalSince(startDate)
            let style = currentStyle()
            let tcNow = tc
            Canvas { context, _ in
                gDrawGreeting(&context, t: t, tc: tcNow, s: style)
            }
            // Avisa `.greetComplete` una sola vez al llegar al final (si nadie lo interrumpió antes).
            .onChange(of: !greetFired && t >= GT.end && tc >= GT.autoLeave) { _, trigger in
                if trigger { fireGreetComplete() }
            }
        }
        .onAppear {
            startDate = Date()
            tc = .infinity
            greetFired = false
            scheduleWorks()
        }
        .onDisappear {
            cancelWorks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingHover)) { _ in
            // Mouse sobre el notch durante el saludo → se queda abierto (sin colapso automático).
            if tc >= GT.autoLeave { tc = .infinity }
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingInterrupt)) { _ in
            // El FSM pasó a compacta → ORBEX vuelve a su lugar desde donde esté.
            let t = Date().timeIntervalSince(startDate)
            if tc.isInfinite || tc > t { tc = t }
            cancelWorks()
        }
    }

    /// Color, material y preferencias del momento (tema, "reducir movimiento", notch en vivo).
    @MainActor private func currentStyle() -> GStyle {
        let model = AppModel.shared
        let theme = model.themeStyle
        let material: OrbexMaterial = (theme.glassAllowed || theme.id != .liquidGlass)
            ? OrbexMaterial(theme: theme.id) : .solid
        let compactW = state.notchWidth + 160          // igual que `islandSize(.compact)`
        return GStyle(tint: CharacterBrain.shared.tint.rgb,
                      material: material,
                      reduce: model.effectiveReduceMotion,
                      compactX: GCX - compactW / 2 + GCOMPACT_X,
                      notchH: state.notchHeight)
    }

    private func fireGreetComplete() {
        guard !greetFired else { return }
        greetFired = true
        cancelWorks()
        NotificationCenter.default.post(name: .greetComplete, object: nil)
    }

    private func scheduleWorks() {
        cancelWorks()
        var list: [DispatchWorkItem] = []
        // Sonidos atados a la coreografía: aterriza, saluda, se asoman los minis.
        let cues: [(delay: Double, name: String)] = [(GT.land1, "pop"), (GT.wave0, "greet"), (GT.minis0, "blip")]
        for cue in cues {
            let name = cue.name
            let item = DispatchWorkItem { MainActor.assumeIsolated { SoundEngine.shared.play(name) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + cue.delay, execute: item)
            list.append(item)
        }
        // Respaldo: el camino normal es el `onChange` de arriba.
        let done = DispatchWorkItem { MainActor.assumeIsolated { fireGreetComplete() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + GT.end + 0.05, execute: done)
        list.append(done)
        works = list
    }

    private func cancelWorks() {
        works.forEach { $0.cancel() }
        works = []
    }
}

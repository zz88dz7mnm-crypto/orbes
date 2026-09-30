import SwiftUI
import OrbexCore

/// Dibuja a ORBEX con `GraphicsContext` (Canvas). Proporciones de `design/character/README.md`.
/// Cada parte está en su función para poder reemplazarla por assets más adelante.
enum OrbexPainter {

    struct Layout {
        /// Diámetro del cuerpo.
        let D: CGFloat
        /// Centro del cuerpo de pie (sin animación).
        let center: CGPoint
        let showLimbs: Bool

        init(size: CGSize, showLimbs: Bool, scale: CGFloat = 1) {
            self.showLimbs = showLimbs
            if showLimbs {
                let d = min(size.width / 1.42, size.height / 1.42) * scale
                D = d
                center = CGPoint(x: size.width / 2, y: size.height - 0.74 * d)
            } else {
                let d = min(size.width, size.height) * 0.9 * scale
                D = d
                center = CGPoint(x: size.width / 2, y: size.height / 2)
            }
        }
    }

    // MARK: - Colores

    private static let eyeColor = Color(red: 0.03, green: 0.035, blue: 0.05)

    private static func rgb(_ c: (r: Double, g: Double, b: Double), _ a: Double) -> Color {
        Color(red: c.r, green: c.g, blue: c.b).opacity(a)
    }

    private static func mix(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double), _ k: Double) -> (r: Double, g: Double, b: Double) {
        (a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k)
    }

    private static let white: (r: Double, g: Double, b: Double) = (1, 1, 1)
    private static let deep: (r: Double, g: Double, b: Double) = (0.12, 0.2, 0.32)

    // MARK: - Dibujo principal

    static func draw(_ f: CharacterFrame, in ctx: inout GraphicsContext, layout: Layout, t: Double) {
        let D = layout.D
        let tint = f.tint.rgb
        let hop = CGFloat(f.offsetY) * D
        let crouchDrop = CGFloat(f.crouch) * 0.14 * D
        let bodyCenter = CGPoint(x: layout.center.x, y: layout.center.y + hop + crouchDrop)
        let floorY = layout.center.y + 0.7 * D

        if layout.showLimbs {
            drawContactGlow(&ctx, x: layout.center.x, floorY: floorY, D: D, lift: -hop)
            for side in [-1.0, 1.0] {
                let lift = CGFloat(side < 0 ? f.leftFootLift : f.rightFootLift) * D
                drawLeg(&ctx, side: side, bodyCenter: bodyCenter, footY: floorY + hop - lift - 0.05 * D,
                        D: D, tint: tint, crouch: f.crouch, material: f.material)
            }
        }

        // Transformación del cuerpo: rotación + squash & stretch anclado abajo.
        var body = ctx
        body.translateBy(x: bodyCenter.x, y: bodyCenter.y)
        body.rotate(by: .radians(f.rotation))
        body.translateBy(x: 0, y: 0.5 * D)
        body.scaleBy(x: CGFloat(f.scaleX), y: CGFloat(f.scaleY))
        body.translateBy(x: 0, y: -0.5 * D)

        drawBody(&body, D: D, tint: tint, material: f.material)
        drawEyes(&body, f: f, D: D)
        if layout.showLimbs {
            drawArm(&body, side: -1, raise: f.leftArmRaise, D: D, tint: tint, material: f.material)
            drawArm(&body, side: 1, raise: f.rightArmRaise, D: D, tint: tint, material: f.material)
        }
        drawExtras(&body, f.extras, D: D, t: t)
    }

    // MARK: - Partes

    /// "Sombra" de contacto: sobre fondo negro se ve como un reflejo tenue en el piso.
    static func drawContactGlow(_ ctx: inout GraphicsContext, x: CGFloat, floorY: CGFloat, D: CGFloat, lift: CGFloat) {
        let shrink = max(0.4, 1 - lift / D * 2)
        let w = 0.9 * D * shrink, h = 0.08 * D * shrink
        var layer = ctx
        layer.addFilter(.blur(radius: 0.03 * D))
        layer.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: floorY - h / 2, width: w, height: h)),
                   with: .color(Color.white.opacity(0.10 * Double(shrink))))
    }

    static func drawBody(_ ctx: inout GraphicsContext, D: CGFloat, tint: (r: Double, g: Double, b: Double),
                         material: OrbexMaterial = .glass) {
        let r = D / 2
        let circle = Path(ellipseIn: CGRect(x: -r, y: -r, width: D, height: D))
        switch material {
        case .glass: break
        case .solid: drawSolidBody(&ctx, circle: circle, D: D, tint: tint); return
        case .chrome: drawChromeBody(&ctx, circle: circle, D: D, tint: tint); return
        }

        // Relleno de vidrio: claro en el centro, más denso en el borde (da volumen de esfera).
        let fill = Gradient(stops: [
            .init(color: rgb(mix(white, tint, 0.35), 0.30), location: 0),
            .init(color: rgb(tint, 0.16), location: 0.55),
            .init(color: rgb(mix(tint, deep, 0.35), 0.42), location: 0.9),
            .init(color: rgb(mix(tint, white, 0.4), 0.62), location: 1),
        ])
        ctx.fill(circle, with: .radialGradient(fill, center: CGPoint(x: -0.14 * D, y: -0.18 * D),
                                               startRadius: 0, endRadius: 0.62 * D))

        // Luz rebotada abajo (refracción simulada).
        let bounce = Gradient(colors: [rgb(mix(tint, white, 0.5), 0.22), rgb(tint, 0)])
        ctx.fill(circle, with: .radialGradient(bounce, center: CGPoint(x: 0.1 * D, y: 0.42 * D),
                                               startRadius: 0, endRadius: 0.45 * D))

        // Borde (rim light): más brillante arriba a la izquierda.
        ctx.stroke(circle, with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.85), rgb(mix(tint, white, 0.3), 0.35), Color.white.opacity(0.55)]),
            startPoint: CGPoint(x: -r, y: -r), endPoint: CGPoint(x: r, y: r)),
                   lineWidth: max(0.8, 0.022 * D))

        // Reflejo grande tipo "ventana" arriba a la izquierda.
        var hl = ctx
        hl.translateBy(x: -0.2 * D, y: -0.27 * D)
        hl.rotate(by: .degrees(-35))
        let hlRect = CGRect(x: -0.19 * D, y: -0.075 * D, width: 0.38 * D, height: 0.15 * D)
        hl.fill(Path(ellipseIn: hlRect), with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.62), Color.white.opacity(0.0)]),
            startPoint: CGPoint(x: 0, y: -0.075 * D), endPoint: CGPoint(x: 0, y: 0.075 * D)))

        // Punto especular.
        let dot = 0.05 * D
        ctx.fill(Path(ellipseIn: CGRect(x: -0.33 * D - dot / 2, y: -0.2 * D - dot / 2, width: dot, height: dot * 0.8)),
                 with: .color(Color.white.opacity(0.9)))

        // Arco de luz abajo a la derecha.
        var arc = Path()
        arc.addArc(center: .zero, radius: r * 0.86, startAngle: .degrees(15), endAngle: .degrees(70), clockwise: false)
        ctx.stroke(arc, with: .color(Color.white.opacity(0.28)),
                   style: StrokeStyle(lineWidth: max(0.6, 0.02 * D), lineCap: .round))
    }

    /// macOS limpio: cuerpo sólido, sobrio, con sombreado suave.
    static func drawSolidBody(_ ctx: inout GraphicsContext, circle: Path, D: CGFloat, tint: (r: Double, g: Double, b: Double)) {
        let r = D / 2
        let base = mix(tint, white, 0.35)
        ctx.fill(circle, with: .radialGradient(
            Gradient(colors: [rgb(mix(base, white, 0.55), 1), rgb(base, 1), rgb(mix(base, deep, 0.45), 1)]),
            center: CGPoint(x: -0.18 * D, y: -0.22 * D), startRadius: 0, endRadius: 0.75 * D))
        ctx.stroke(circle, with: .color(Color.black.opacity(0.18)), lineWidth: max(0.6, 0.012 * D))
        let dot = 0.09 * D
        ctx.fill(Path(ellipseIn: CGRect(x: -0.28 * D, y: -0.3 * D, width: dot * 1.4, height: dot)),
                 with: .color(Color.white.opacity(0.55)))
        _ = r
    }

    /// Y2K metálico: esfera cromada con bandas de reflejo y brillos duros (tipo Winamp).
    static func drawChromeBody(_ ctx: inout GraphicsContext, circle: Path, D: CGFloat, tint: (r: Double, g: Double, b: Double)) {
        let r = D / 2
        let t = mix(tint, white, 0.2)
        ctx.fill(circle, with: .linearGradient(
            Gradient(stops: [
                .init(color: rgb(mix(t, white, 0.9), 1), location: 0),
                .init(color: rgb(mix(t, white, 0.5), 1), location: 0.28),
                .init(color: rgb(mix(t, deep, 0.75), 1), location: 0.5),
                .init(color: rgb(mix(t, white, 0.65), 1), location: 0.58),
                .init(color: rgb(mix(t, deep, 0.35), 1), location: 0.82),
                .init(color: rgb(mix(t, white, 0.4), 1), location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: -r), endPoint: CGPoint(x: 0, y: r)))
        ctx.stroke(circle, with: .linearGradient(
            Gradient(colors: [Color.white, Color.black.opacity(0.7)]),
            startPoint: CGPoint(x: -r, y: -r), endPoint: CGPoint(x: r, y: r)), lineWidth: max(1, 0.03 * D))
        // Brillos duros.
        ctx.fill(Path(ellipseIn: CGRect(x: -0.32 * D, y: -0.4 * D, width: 0.3 * D, height: 0.1 * D)),
                 with: .color(Color.white.opacity(0.95)))
        ctx.fill(Path(ellipseIn: CGRect(x: 0.18 * D, y: 0.26 * D, width: 0.12 * D, height: 0.05 * D)),
                 with: .color(Color.white.opacity(0.7)))
    }

    static func drawEyes(_ ctx: inout GraphicsContext, f: CharacterFrame, D: CGFloat) {
        let e = f.eye
        for side in [-1.0, 1.0] {
            let cx = CGFloat(side * (EyeShape.baseSeparation + e.spread) + f.look.x) * D
            let cy = CGFloat(EyeShape.baseY + e.offsetY + f.look.y) * D
            var eye = ctx
            eye.translateBy(x: cx, y: cy)
            eye.rotate(by: .radians(-side * e.tilt))
            let w = CGFloat(e.width) * D
            let h = CGFloat(e.height) * D

            switch e.glyph {
            case .oval:
                let open = CGFloat(max(0.07, f.eyeOpenness))
                let eh = max(0.012 * D, h * open)
                let rect = CGRect(x: -w / 2, y: -eh / 2, width: w, height: eh)
                if e.topCut > 0.001 {
                    eye.clip(to: Path(CGRect(x: -w, y: -eh / 2 + eh * CGFloat(e.topCut), width: 2 * w, height: eh)))
                }
                eye.fill(Path(ellipseIn: rect), with: .color(eyeColor))
                if open > 0.5 {
                    let g = w * 0.32
                    eye.fill(Path(ellipseIn: CGRect(x: -w * 0.28, y: -eh * 0.36, width: g, height: g * 1.3)),
                             with: .color(Color.white.opacity(0.38)))
                }
            case .arcUp:
                var p = Path()
                p.move(to: CGPoint(x: -w / 2, y: h / 2))
                p.addQuadCurve(to: CGPoint(x: w / 2, y: h / 2), control: CGPoint(x: 0, y: -h))
                eye.stroke(p, with: .color(eyeColor), style: StrokeStyle(lineWidth: max(1.2, 0.03 * D), lineCap: .round))
            case .line:
                var p = Path()
                p.move(to: CGPoint(x: -w / 2, y: 0))
                p.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: 0, y: 0.03 * D))
                eye.stroke(p, with: .color(eyeColor), style: StrokeStyle(lineWidth: max(1, 0.024 * D), lineCap: .round))
            case .spiral:
                eye.rotate(by: .radians(side * f.eyeSpin))
                eye.stroke(spiral(radius: w / 2), with: .color(eyeColor),
                           style: StrokeStyle(lineWidth: max(0.9, 0.02 * D), lineCap: .round))
            case .heart:
                eye.fill(heart(size: w), with: .color(Color(red: 0.95, green: 0.3, blue: 0.45)))
            case .star:
                eye.fill(sparkle(size: w), with: .color(Color(red: 1, green: 0.93, blue: 0.6)))
            }
        }
    }

    /// Brazo en forma de gota: punta arriba (hombro), bulbo abajo. `raise` lo levanta hacia afuera.
    /// `length` acorta o alarga el brazo (1 = normal; la mano en la oreja usa ~0,88).
    static func drawArm(_ ctx: inout GraphicsContext, side: Double, raise: Double, D: CGFloat,
                        tint: (r: Double, g: Double, b: Double), material: OrbexMaterial = .glass,
                        length: CGFloat = 1) {
        var arm = ctx
        arm.translateBy(x: CGFloat(side) * 0.45 * D, y: 0.0)
        arm.rotate(by: .radians(-side * raise))
        let L = 0.38 * D * max(0.5, length), w = 0.12 * D
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -0.02 * D))
        p.addCurve(to: CGPoint(x: 0, y: L), control1: CGPoint(x: w * 1.1, y: L * 0.35), control2: CGPoint(x: w * 1.25, y: L))
        p.addCurve(to: CGPoint(x: 0, y: -0.02 * D), control1: CGPoint(x: -w * 1.25, y: L), control2: CGPoint(x: -w * 1.1, y: L * 0.35))
        p.closeSubpath()
        drawGlassPart(&arm, p, bounds: CGRect(x: -w, y: 0, width: 2 * w, height: L), D: D, tint: tint, material: material)
    }

    static func drawLeg(_ ctx: inout GraphicsContext, side: Double, bodyCenter: CGPoint, footY: CGFloat,
                        D: CGFloat, tint: (r: Double, g: Double, b: Double), crouch: Double,
                        material: OrbexMaterial = .glass) {
        let x = bodyCenter.x + CGFloat(side) * 0.17 * D
        let top = bodyCenter.y + 0.34 * D
        let legW = 0.11 * D
        let legH = max(0.02 * D, footY - top)
        let leg = Path(roundedRect: CGRect(x: x - legW / 2, y: top, width: legW, height: legH),
                       cornerRadius: legW / 2)
        drawGlassPart(&ctx, leg, bounds: CGRect(x: x - legW / 2, y: top, width: legW, height: legH), D: D, tint: tint,
                      material: material)

        let footW = 0.22 * D, footH = 0.1 * D
        let fx = x + CGFloat(side) * 0.02 * D
        let foot = Path(roundedRect: CGRect(x: fx - footW / 2, y: footY - footH / 2, width: footW, height: footH),
                        cornerRadius: footH / 2)
        drawGlassPart(&ctx, foot, bounds: CGRect(x: fx - footW / 2, y: footY - footH / 2, width: footW, height: footH),
                      D: D, tint: tint, material: material)
    }

    /// Relleno de vidrio para brazos, piernas y pies.
    static func drawGlassPart(_ ctx: inout GraphicsContext, _ path: Path, bounds: CGRect, D: CGFloat,
                              tint: (r: Double, g: Double, b: Double), material: OrbexMaterial = .glass) {
        let alpha: (Double, Double, Double)
        switch material {
        case .glass: alpha = (0.42, 0.2, 0.45)
        case .solid, .chrome: alpha = (1, 1, 1)
        }
        let light = material == .chrome ? mix(tint, white, 0.85) : mix(white, tint, 0.4)
        let dark = material == .chrome ? mix(tint, deep, 0.7) : mix(tint, deep, 0.3)
        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [rgb(light, alpha.0), rgb(material == .glass ? tint : mix(tint, white, 0.3), alpha.1), rgb(dark, alpha.2)]),
            startPoint: CGPoint(x: bounds.minX, y: bounds.minY), endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)))
        ctx.stroke(path, with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.8), Color.white.opacity(0.3)]),
            startPoint: CGPoint(x: bounds.minX, y: bounds.minY), endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)),
                   lineWidth: max(0.6, 0.014 * D))
        // Brillito.
        let s = min(bounds.width, bounds.height) * 0.28
        ctx.fill(Path(ellipseIn: CGRect(x: bounds.minX + bounds.width * 0.22, y: bounds.minY + bounds.height * 0.18,
                                        width: s * 0.7, height: s)),
                 with: .color(Color.white.opacity(0.45)))
    }

    // MARK: - Extras

    static func drawExtras(_ ctx: inout GraphicsContext, _ extras: [CharacterFrame.Extra], D: CGFloat, t: Double) {
        for extra in extras {
            switch extra {
            case .zzz(let phase):
                for i in 0..<3 {
                    let p = (phase * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let size = 0.13 * D * CGFloat(0.6 + p)
                    let pos = CGPoint(x: 0.36 * D + CGFloat(p) * 0.22 * D, y: -0.42 * D - CGFloat(p) * 0.38 * D)
                    ctx.draw(Text("z").font(.system(size: max(6, size), weight: .heavy, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.85 * sin(.pi * p))), at: pos)
                }
            case .hearts(let phase):
                for i in 0..<2 {
                    let p = (phase * 0.5 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    var h = ctx
                    h.translateBy(x: (i == 0 ? -0.34 : 0.38) * D, y: -0.45 * D - CGFloat(p) * 0.3 * D)
                    h.opacity = sin(.pi * p)
                    h.fill(heart(size: 0.12 * D), with: .color(Color(red: 1, green: 0.38, blue: 0.52)))
                }
            case .sparkles(let phase):
                for i in 0..<4 {
                    let a = Double(i) * .pi / 2 + 0.6
                    let tw = abs(sin(phase * 5 + Double(i) * 1.7))
                    var s = ctx
                    s.translateBy(x: CGFloat(cos(a)) * 0.68 * D, y: CGFloat(sin(a)) * 0.6 * D - 0.1 * D)
                    s.opacity = tw
                    s.fill(sparkle(size: 0.12 * D * CGFloat(0.5 + tw)), with: .color(Color(red: 1, green: 0.95, blue: 0.7)))
                }
            case .notes(let phase):
                for i in 0..<2 {
                    let p = (phase * 0.6 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    let pos = CGPoint(x: (i == 0 ? -0.5 : 0.52) * D + CGFloat(sin(p * 6)) * 0.04 * D,
                                      y: -0.35 * D - CGFloat(p) * 0.35 * D)
                    ctx.draw(Text(i == 0 ? "♪" : "♫").font(.system(size: max(7, 0.16 * D), weight: .bold))
                                .foregroundColor(Color.white.opacity(0.9 * sin(.pi * p))), at: pos)
                }
            case .exclamation(let phase):
                let bounce = abs(sin(phase * 6)) * 0.05
                ctx.draw(Text("!").font(.system(size: max(8, 0.22 * D), weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 1, green: 0.8, blue: 0.3)),
                         at: CGPoint(x: 0.5 * D, y: -0.52 * D - CGFloat(bounce) * D))
            case .dot(let x, let y):
                let s = 0.045 * D
                ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(x) * 0.9 * D - s / 2, y: CGFloat(y) * 0.9 * D - s / 2, width: s, height: s)),
                         with: .color(Color.white.opacity(0.9)))
            case .sweat(let phase):
                let p = (phase * 0.8).truncatingRemainder(dividingBy: 1)
                var drop = ctx
                drop.translateBy(x: 0.3 * D, y: -0.34 * D + CGFloat(p) * 0.18 * D)
                drop.opacity = 1 - p
                drop.fill(teardrop(size: 0.08 * D), with: .color(Color(red: 0.6, green: 0.85, blue: 1)))
            }
        }
    }

    // MARK: - Formas

    static func spiral(radius: CGFloat) -> Path {
        var p = Path()
        let turns = 2.2
        let steps = 40
        for i in 0...steps {
            let k = Double(i) / Double(steps)
            let a = k * turns * 2 * .pi
            let r = radius * CGFloat(k)
            let pt = CGPoint(x: r * CGFloat(cos(a)), y: r * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    static func heart(size s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: s * 0.38))
        p.addCurve(to: CGPoint(x: -s * 0.5, y: -s * 0.1), control1: CGPoint(x: -s * 0.2, y: s * 0.2), control2: CGPoint(x: -s * 0.5, y: s * 0.1))
        p.addArc(center: CGPoint(x: -s * 0.25, y: -s * 0.12), radius: s * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: s * 0.25, y: -s * 0.12), radius: s * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: 0, y: s * 0.38), control1: CGPoint(x: s * 0.5, y: s * 0.1), control2: CGPoint(x: s * 0.2, y: s * 0.2))
        p.closeSubpath()
        return p
    }

    static func sparkle(size s: CGFloat) -> Path {
        var p = Path()
        let r = s / 2, k = s * 0.12
        p.move(to: CGPoint(x: 0, y: -r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: k, y: -k))
        p.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: k, y: k))
        p.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -k, y: k))
        p.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -k, y: -k))
        p.closeSubpath()
        return p
    }

    static func teardrop(size s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -s * 0.6))
        p.addCurve(to: CGPoint(x: 0, y: s * 0.5), control1: CGPoint(x: s * 0.55, y: 0), control2: CGPoint(x: s * 0.5, y: s * 0.5))
        p.addCurve(to: CGPoint(x: 0, y: -s * 0.6), control1: CGPoint(x: -s * 0.5, y: s * 0.5), control2: CGPoint(x: -s * 0.55, y: 0))
        p.closeSubpath()
        return p
    }
}

// MARK: - Piezas de ORBEX para el motor de la isla (`BotEngine`)
//
// Todo centrado en el origen salvo que se diga otra cosa. Nada de blur ni cientos de paths:
// se dibuja en cada cuadro.

extension OrbexPainter {
    typealias RGB = (r: Double, g: Double, b: Double)

    // MARK: Ojos

    /// Ojo de ORBEX con cualquier forma del motor. `w`×`h` = óvalo base (vertical); `open` = párpado
    /// (1 abierto, ~0 cerrado); `side` = −1 izquierdo, +1 derecho; `detail` = dibujar el brillito.
    static func drawEye(_ ctx: inout GraphicsContext, shape: BotEyeShape, w: CGFloat, h: CGFloat,
                        open: CGFloat, side: CGFloat, t: Double, detail: Bool, ink: Color? = nil) {
        let ink = ink ?? eyeColor
        switch shape {
        case .pill:
            ovalEye(&ctx, w: w, h: h, open: open, ink: ink, detail: detail, eager: false)
        case .wide:
            // Sorpresa / atención: óvalos más grandes.
            ovalEye(&ctx, w: w * 1.2, h: h * 1.14, open: open, ink: ink, detail: detail, eager: false)
        case .cup:
            // Ganas (archivo encima del portal): óvalos brillosos, con dos brillitos.
            ovalEye(&ctx, w: w * 1.12, h: h * 1.05, open: open, ink: ink, detail: detail, eager: true)
        case .dot:
            // Pasmado: ojitos redondos.
            let d = max(1.4, w * 1.3)
            ovalEye(&ctx, w: d, h: d, open: max(open, 0.3), ink: ink, detail: detail, eager: false)
        case .line:
            // Molesto: achatados arriba, con las puntas de adentro hacia abajo.
            var c = ctx
            c.rotate(by: .radians(Double(-side) * 0.26))
            cutEye(&c, w: w * 1.12, h: h * 0.84, open: open, cut: 0.46, ink: ink)
        case .flat:
            // Error / preocupado: achatados arriba, con las puntas de adentro hacia arriba.
            var c = ctx
            c.rotate(by: .radians(Double(side) * 0.26))
            cutEye(&c, w: w * 1.08, h: h * 0.8, open: open, cut: 0.4, ink: ink)
        case .tired:
            // Cansado: medio cerrados, con la rayita del párpado.
            let eh = h * 0.9
            cutEye(&ctx, w: w * 1.05, h: eh, open: 1, cut: 0.5, ink: ink)
            var lid = Path()
            lid.move(to: CGPoint(x: -w * 0.7, y: 0))
            lid.addLine(to: CGPoint(x: w * 0.7, y: 0))
            ctx.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: max(0.8, w * 0.22), lineCap: .round))
        case .happy:
            happyArc(&ctx, w: w, h: h, ink: ink)
        case .wink:
            if side < 0 {
                ovalEye(&ctx, w: w, h: h, open: open, ink: ink, detail: detail, eager: false)
            } else {
                happyArc(&ctx, w: w, h: h, ink: ink)
            }
        case .closed:
            // Dormido: rayitas apenas curvas.
            var p = Path()
            p.move(to: CGPoint(x: -w * 0.8, y: 0))
            p.addQuadCurve(to: CGPoint(x: w * 0.8, y: 0), control: CGPoint(x: 0, y: h * 0.2))
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: max(1, w * 0.42), lineCap: .round))
        case .spiral:
            var c = ctx
            c.rotate(by: .radians(t * 7 * Double(side)))
            c.stroke(spiral(radius: w * 0.95), with: .color(ink),
                     style: StrokeStyle(lineWidth: max(0.9, w * 0.3), lineCap: .round))
        case .heart:
            let s = w * 2.2
            ctx.fill(heart(size: s), with: .color(Color(red: 1, green: 0.34, blue: 0.5)))
            if detail {
                ctx.fill(Path(ellipseIn: CGRect(x: -s * 0.36, y: -s * 0.26, width: s * 0.16, height: s * 0.12)),
                         with: .color(Color.white.opacity(0.7)))
            }
        case .star:
            var c = ctx
            c.rotate(by: .radians(t * 1.2 * Double(side)))
            let s = w * 2.6
            c.fill(sparkle(size: s), with: .color(Color(red: 1, green: 0.86, blue: 0.36)))
            c.fill(Path(ellipseIn: CGRect(x: -s * 0.08, y: -s * 0.08, width: s * 0.16, height: s * 0.16)),
                   with: .color(Color.white.opacity(0.85)))
        }
    }

    /// Óvalo vertical negro; al parpadear se aplasta. `eager` suma un segundo brillito.
    private static func ovalEye(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, open: CGFloat,
                                ink: Color, detail: Bool, eager: Bool) {
        let eh = max(w * 0.3, h * max(0.06, min(1, open)))
        ctx.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -eh / 2, width: w, height: eh)), with: .color(ink))
        guard detail, open > 0.55 else { return }
        let g = w * 0.36
        ctx.fill(Path(ellipseIn: CGRect(x: -w * 0.3, y: -eh * 0.4, width: g, height: g * 1.35)),
                 with: .color(Color.white.opacity(0.5)))
        if eager {
            let s = w * 0.22
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.06, y: eh * 0.1, width: s, height: s)),
                     with: .color(Color.white.opacity(0.4)))
        }
    }

    /// Óvalo con la parte de arriba cortada en recta (`cut` = fracción del alto que se saca).
    private static func cutEye(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, open: CGFloat,
                               cut: CGFloat, ink: Color) {
        let eh = max(w * 0.3, h * max(0.06, min(1, open)))
        let a = w / 2, b = eh / 2
        let yc = -b + eh * cut
        let a0 = asin(max(-1, min(1, yc / b)))
        var p = Path()
        let n = 12
        for i in 0...n {
            // De la punta derecha del corte, por abajo, a la punta izquierda.
            let th = a0 + (CGFloat.pi - 2 * a0) * CGFloat(i) / CGFloat(n)
            let pt = CGPoint(x: a * cos(th), y: b * sin(th))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        ctx.fill(p, with: .color(ink))
    }

    /// Ojo feliz: arquito hacia arriba.
    private static func happyArc(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, ink: Color) {
        var p = Path()
        p.move(to: CGPoint(x: -w * 0.8, y: h * 0.1))
        p.addQuadCurve(to: CGPoint(x: w * 0.8, y: h * 0.1), control: CGPoint(x: 0, y: -h * 0.42))
        ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: max(1.2, w * 0.5), lineCap: .round))
    }

    // MARK: Cuerpo

    /// Mini-ORBEX (pastillas y grilla compacta, 12–22 pt): cuenta de vidrio opaca del color `tint`,
    /// luz detrás de los ojos para que se lean, borde del color del estado y brillito.
    static func drawMiniBody(_ ctx: inout GraphicsContext, D: CGFloat, tint: RGB, rim: RGB, rimAlpha: Double) {
        let r = D / 2
        let circle = Path(ellipseIn: CGRect(x: -r, y: -r, width: D, height: D))
        ctx.fill(circle, with: .radialGradient(
            Gradient(stops: [
                .init(color: rgb(mix(tint, white, 0.55), 1), location: 0),
                .init(color: rgb(tint, 1), location: 0.55),
                .init(color: rgb(mix(tint, deep, 0.35), 1), location: 1),
            ]),
            center: CGPoint(x: -0.3 * r, y: -0.35 * r), startRadius: 0, endRadius: 1.35 * r))
        ctx.fill(circle, with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0)]),
            center: CGPoint(x: 0, y: -0.1 * r), startRadius: 0, endRadius: 0.72 * r))
        ctx.stroke(circle, with: .color(rgb(rim, rimAlpha)), lineWidth: max(0.6, 0.09 * D))
        ctx.fill(Path(ellipseIn: CGRect(x: -0.64 * r, y: -0.74 * r, width: 0.4 * r, height: 0.24 * r)),
                 with: .color(Color.white.opacity(0.6)))
    }

    /// Luz interior detrás de los ojos: da contraste a la cara sobre la isla negra (material vidrio).
    static func drawInnerLight(_ ctx: inout GraphicsContext, D: CGFloat, tint: RGB, alpha: Double) {
        let r = D / 2
        let c = mix(tint, white, 0.55)
        ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: D, height: D)), with: .radialGradient(
            Gradient(colors: [rgb(c, alpha), rgb(c, 0)]),
            center: CGPoint(x: 0, y: -0.1 * r), startRadius: 0, endRadius: 0.8 * r))
    }

    /// Vidrio que se entibia (cariño, orgullo): resplandor rosado en la parte de abajo de la esfera.
    static func drawWarmth(_ ctx: inout GraphicsContext, D: CGFloat, amount: Double) {
        let r = D / 2
        ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: D, height: D)), with: .radialGradient(
            Gradient(colors: [Color(red: 1, green: 0.45, blue: 0.6).opacity(0.32 * amount), Color.clear]),
            center: CGPoint(x: 0, y: 0.3 * r), startRadius: 0, endRadius: 0.8 * r))
    }

    /// Halo suave del color del estado, en coordenadas del lienzo. Detrás del vidrio también
    /// ilumina la esfera por dentro.
    static func drawHalo(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: RGB, alpha: Double) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(stops: [
                .init(color: rgb(color, alpha * 0.9), location: 0),
                .init(color: rgb(color, alpha * 0.7), location: 0.55),
                .init(color: rgb(color, alpha * 0.25), location: 0.76),
                .init(color: rgb(color, 0), location: 1),
            ]),
            center: center, startRadius: 0, endRadius: radius))
    }

    /// Reflejo de contacto en el piso, sin blur (degradado radial aplastado), en coordenadas del lienzo.
    static func drawFloorGlow(_ ctx: inout GraphicsContext, center: CGPoint, width: CGFloat, height: CGFloat,
                              alpha: Double) {
        guard width > 0.5, height > 0.1 else { return }
        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        c.scaleBy(x: 1, y: height / width)
        let r = width / 2
        c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: width, height: width)), with: .radialGradient(
            Gradient(colors: [Color.white.opacity(alpha), Color.white.opacity(0)]),
            center: .zero, startRadius: 0, endRadius: r))
    }

    // MARK: Portal (subir archivo)

    /// Portal de vidrio: aro alrededor de la abertura, interior profundo con remolino y labio brillante.
    /// `hole` = radio de la abertura; `swirl` = giro del remolino (radianes); `strength` = 0…1.
    static func drawPortal(_ ctx: inout GraphicsContext, D: CGFloat, hole: CGFloat, swirl: Double,
                           tint: RGB, strength: Double) {
        let r = D / 2
        let ringR = max(hole, 0.18 * r) + 0.1 * r
        ctx.stroke(Path(ellipseIn: CGRect(x: -ringR, y: -ringR, width: 2 * ringR, height: 2 * ringR)),
                   with: .color(rgb(mix(tint, white, 0.6), 0.35 * strength)), lineWidth: max(0.8, 0.05 * D))
        guard hole > 0.8 else { return }
        let disc = Path(ellipseIn: CGRect(x: -hole, y: -hole, width: 2 * hole, height: 2 * hole))
        ctx.fill(disc, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.01, green: 0.015, blue: 0.035).opacity(strength), location: 0),
                .init(color: rgb(mix(tint, deep, 0.7), 0.95 * strength), location: 0.62),
                .init(color: rgb(mix(tint, white, 0.25), 0.9 * strength), location: 1),
            ]),
            center: .zero, startRadius: 0, endRadius: hole))
        // Remolino: tres brazos en espiral que giran.
        var arms = Path()
        for i in 0..<3 {
            let base = swirl + Double(i) * 2 * .pi / 3
            for j in 0...8 {
                let k = Double(j) / 8
                let rr = hole * CGFloat(0.16 + 0.78 * k)
                let a = base + k * 2.2
                let pt = CGPoint(x: rr * CGFloat(cos(a)), y: rr * CGFloat(sin(a)))
                if j == 0 { arms.move(to: pt) } else { arms.addLine(to: pt) }
            }
        }
        var inner = ctx
        inner.clip(to: disc)
        inner.stroke(arms, with: .color(rgb(mix(tint, white, 0.55), 0.42 * strength)),
                     style: StrokeStyle(lineWidth: max(0.7, hole * 0.09), lineCap: .round, lineJoin: .round))
        ctx.stroke(disc, with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.8 * strength), rgb(tint, 0.3 * strength)]),
            startPoint: CGPoint(x: -hole, y: -hole), endPoint: CGPoint(x: hole, y: hole)),
                   lineWidth: max(0.8, 0.035 * D))
    }

    /// Ondita que sale del portal al tragar (`k` = 0…1 del recorrido).
    static func drawRipple(_ ctx: inout GraphicsContext, from r0: CGFloat, to r1: CGFloat, k: Double,
                           tint: RGB, D: CGFloat) {
        let alpha = 0.55 * (1 - k)
        guard alpha > 0.01 else { return }
        let e = 1 - pow(1 - k, 3)
        let rr = r0 + (r1 - r0) * CGFloat(e)
        ctx.stroke(Path(ellipseIn: CGRect(x: -rr, y: -rr, width: 2 * rr, height: 2 * rr)),
                   with: .color(rgb(mix(tint, white, 0.6), alpha)), lineWidth: max(0.8, 0.05 * D * CGFloat(1 - k)))
    }

    // MARK: Insignias y partículas

    enum BadgeGlyph { case dots, bang, question, check, clock, plain }

    /// Insignia de vidrio: burbuja teñida (cápsula para `dots`) con su glifo. `size` = radio de la burbuja.
    static func drawBadge(_ ctx: inout GraphicsContext, glyph: BadgeGlyph, color: RGB, size r: CGFloat, t: Double) {
        let bounds = glyph == .dots
            ? CGRect(x: -1.25 * r, y: -0.62 * r, width: 2.5 * r, height: 1.24 * r)
            : CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)
        let bead = glyph == .dots
            ? Path(roundedRect: bounds, cornerRadius: 0.62 * r)
            : Path(ellipseIn: bounds)
        ctx.fill(bead, with: .linearGradient(
            Gradient(colors: [rgb(mix(color, white, 0.35), 0.96), rgb(color, 0.92), rgb(mix(color, deep, 0.3), 0.95)]),
            startPoint: CGPoint(x: 0, y: bounds.minY), endPoint: CGPoint(x: 0, y: bounds.maxY)))
        ctx.stroke(bead, with: .color(Color.white.opacity(0.55)), lineWidth: max(0.6, 0.1 * r))
        ctx.fill(Path(ellipseIn: CGRect(x: bounds.minX + bounds.width * 0.18, y: bounds.minY + bounds.height * 0.12,
                                        width: bounds.width * 0.3, height: bounds.height * 0.22)),
                 with: .color(Color.white.opacity(0.45)))

        // Glifo blanco sobre vidrio oscuro, casi negro sobre vidrio claro.
        let luma = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b
        let ink = luma > 0.6 ? Color(red: 0.05, green: 0.07, blue: 0.1) : Color.white
        let lw = max(0.9, 0.2 * r)
        switch glyph {
        case .dots:
            for i in 0..<3 {
                let hop = max(0, sin(t * 6.5 - Double(i) * 0.7))
                let d = 0.26 * r
                let x = CGFloat(i - 1) * 0.68 * r
                let y = -CGFloat(hop) * 0.2 * r
                ctx.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)), with: .color(ink))
            }
        case .bang:
            ctx.fill(Path(roundedRect: CGRect(x: -0.13 * r, y: -0.6 * r, width: 0.26 * r, height: 0.72 * r),
                          cornerRadius: 0.13 * r), with: .color(ink))
            ctx.fill(Path(ellipseIn: CGRect(x: -0.14 * r, y: 0.28 * r, width: 0.28 * r, height: 0.28 * r)),
                     with: .color(ink))
        case .question:
            var p = Path()
            p.move(to: CGPoint(x: -0.3 * r, y: -0.24 * r))
            p.addQuadCurve(to: CGPoint(x: 0, y: -0.56 * r), control: CGPoint(x: -0.3 * r, y: -0.56 * r))
            p.addQuadCurve(to: CGPoint(x: 0.3 * r, y: -0.26 * r), control: CGPoint(x: 0.3 * r, y: -0.56 * r))
            p.addQuadCurve(to: CGPoint(x: 0, y: 0.1 * r), control: CGPoint(x: 0.3 * r, y: -0.02 * r))
            p.addLine(to: CGPoint(x: 0, y: 0.14 * r))
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: -0.13 * r, y: 0.36 * r, width: 0.26 * r, height: 0.26 * r)),
                     with: .color(ink))
        case .check:
            var p = Path()
            p.move(to: CGPoint(x: -0.36 * r, y: 0.02 * r))
            p.addLine(to: CGPoint(x: -0.1 * r, y: 0.3 * r))
            p.addLine(to: CGPoint(x: 0.38 * r, y: -0.28 * r))
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        case .clock:
            let cr = 0.46 * r
            ctx.stroke(Path(ellipseIn: CGRect(x: -cr, y: -cr, width: 2 * cr, height: 2 * cr)),
                       with: .color(ink), lineWidth: max(0.8, 0.13 * r))
            var hands = Path()
            hands.move(to: CGPoint(x: 0, y: -0.28 * r))
            hands.addLine(to: .zero)
            hands.addLine(to: CGPoint(x: 0.2 * r, y: 0.06 * r))
            ctx.stroke(hands, with: .color(ink),
                       style: StrokeStyle(lineWidth: max(0.8, 0.12 * r), lineCap: .round, lineJoin: .round))
        case .plain:
            break
        }
    }

    /// Burbujita de vidrio (partícula).
    static func drawBubble(_ ctx: inout GraphicsContext, radius r: CGFloat, tint: RGB) {
        let circle = Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
        ctx.fill(circle, with: .color(rgb(mix(tint, white, 0.5), 0.14)))
        ctx.stroke(circle, with: .color(Color.white.opacity(0.6)), lineWidth: max(0.5, 0.14 * r))
        ctx.fill(Path(ellipseIn: CGRect(x: -0.5 * r, y: -0.55 * r, width: 0.36 * r, height: 0.3 * r)),
                 with: .color(Color.white.opacity(0.75)))
    }

    // MARK: Extras por estado y de la relación con el usuario (todo liviano: pocos paths por cuadro)

    /// Trabajando: burbujitas que suben dentro del vidrio. Centrado en el cuerpo, `t` en segundos.
    static func drawInnerBubbles(_ ctx: inout GraphicsContext, D: CGFloat, t: Double, tint: RGB, alpha: Double) {
        let r = D / 2
        var c = ctx
        c.clip(to: Path(ellipseIn: CGRect(x: -r, y: -r, width: D, height: D)))
        for i in 0..<5 {
            let fi = Double(i)
            let p = (t * (0.32 + 0.05 * fi) + fi / 5).truncatingRemainder(dividingBy: 1)
            let x = CGFloat(sin(fi * 2.3) * 0.5 + sin(t * 3 + fi) * 0.06) * r
            let y = CGFloat(0.85 - 1.7 * p) * r
            let br = r * CGFloat(0.045 + 0.02 * (fi.truncatingRemainder(dividingBy: 3))) * CGFloat(0.7 + 0.3 * p)
            var b = c
            b.translateBy(x: x, y: y)
            b.opacity = alpha * sin(.pi * p)
            drawBubble(&b, radius: max(0.8, br), tint: tint)
        }
    }

    /// Buscando: reflejo diagonal que barre el cuerpo de izquierda a derecha (`k` = 0…1).
    static func drawSweep(_ ctx: inout GraphicsContext, D: CGFloat, k: Double, alpha: Double) {
        let r = D / 2
        var c = ctx
        c.clip(to: Path(ellipseIn: CGRect(x: -r, y: -r, width: D, height: D)))
        c.translateBy(x: CGFloat(k * 3 - 1.5) * r, y: 0)
        c.rotate(by: .radians(0.45))
        let w = 0.32 * r
        c.fill(Path(CGRect(x: -w / 2, y: -1.6 * r, width: w, height: 3.2 * r)), with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.38 * alpha), Color.white.opacity(0)]),
            startPoint: CGPoint(x: -w / 2, y: 0), endPoint: CGPoint(x: w / 2, y: 0)))
    }

    /// Error: vidrio empañado (velo blanquecino con manchitas fijas).
    static func drawFog(_ ctx: inout GraphicsContext, D: CGFloat, amount: Double) {
        let r = D / 2
        ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: D, height: D)), with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.10 * amount), Color.white.opacity(0.30 * amount)]),
            center: .zero, startRadius: 0, endRadius: r))
        let spots: [(CGFloat, CGFloat, CGFloat)] = [(-0.45, 0.35, 0.3), (0.4, 0.45, 0.24), (0.1, -0.55, 0.22), (-0.2, 0.62, 0.18)]
        for (x, y, s) in spots {
            ctx.fill(Path(ellipseIn: CGRect(x: (x - s / 2) * r, y: (y - s / 2) * r, width: s * r, height: s * 0.8 * r)),
                     with: .color(Color.white.opacity(0.16 * amount)))
        }
    }

    /// Pensando: tres puntitos en órbita alrededor de la cabeza (los de atrás, más chicos y tenues).
    /// En coordenadas del lienzo.
    static func drawOrbitDots(_ ctx: GraphicsContext, center: CGPoint, R: CGFloat, t: Double, color: RGB) {
        let col = mix(color, white, 0.45)
        for i in 0..<3 {
            let a = t * 2.4 + Double(i) * 2 * .pi / 3
            let depth = sin(a)                        // > 0 adelante
            let x = center.x + CGFloat(cos(a)) * 1.25 * R
            let y = center.y - 0.35 * R + CGFloat(depth) * 0.28 * R
            let d = max(1.5, R * CGFloat(0.13 + 0.05 * depth))
            var c = ctx
            c.opacity = depth > 0 ? 0.95 : 0.35
            c.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)), with: .color(rgb(col, 1)))
        }
    }

    /// Escuchando: anillos que salen de la esfera y crecen con el nivel de la voz (`level` 0…1).
    /// En coordenadas del lienzo; `phase` avanza con el tiempo. `count` = 1 (compacto y mini): un solo
    /// anillo que respira con la voz. `still` ("reducir movimiento"): radios fijos, solo cambia la opacidad.
    /// `earSide` ≠ 0: más brillantes del lado de la oreja que escucha. Un trazo por anillo.
    static func drawListenRings(_ ctx: GraphicsContext, center: CGPoint, R: CGFloat, phase: Double, level: Double,
                                count: Int, still: Bool, color: RGB, alpha: Double, earSide: Double) {
        guard count > 0, alpha > 0.01, R > 0.5 else { return }
        let col = mix(color, white, 0.2)
        let lv = max(0, min(1, level))
        for i in 0..<count {
            let fi = Double(i)
            let rr: CGFloat
            var a: Double
            let lw: CGFloat
            if still {
                rr = R * CGFloat(1.2 + 0.2 * fi)
                a = (0.2 + 0.6 * lv) * (1 - 0.3 * fi / Double(count))
                lw = max(0.7, R * 0.05)
            } else if count == 1 {
                rr = R * CGFloat(1.14 + 0.28 * lv + 0.04 * sin(phase * 2 * .pi))
                a = 0.32 + 0.55 * lv
                lw = max(0.7, R * CGFloat(0.045 + 0.04 * lv))
            } else {
                // Sale de la esfera y se desvanece; con la voz, llega más lejos y brilla más.
                let p = (phase + fi / Double(count)).truncatingRemainder(dividingBy: 1)
                rr = R * CGFloat(1.05 + p * (0.3 + 0.32 * lv))
                a = (1 - p) * min(1, p * 6) * (0.24 + 0.7 * lv)
                lw = max(0.7, R * CGFloat(0.04 + 0.05 * lv) * CGFloat(1 - 0.5 * p))
            }
            a *= alpha
            guard a > 0.01 else { continue }
            let ring = Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: 2 * rr, height: 2 * rr))
            if earSide != 0 {
                let x = CGFloat(earSide) * rr
                ctx.stroke(ring, with: .linearGradient(
                    Gradient(colors: [rgb(col, min(1, a)), rgb(col, min(1, a) * 0.4)]),
                    startPoint: CGPoint(x: center.x + x, y: center.y), endPoint: CGPoint(x: center.x - x, y: center.y)),
                           lineWidth: lw)
            } else {
                ctx.stroke(ring, with: .color(rgb(col, min(1, a))), lineWidth: lw)
            }
        }
    }

    /// Mareado: estrellitas doradas que giran sobre la cabeza. En coordenadas del lienzo.
    static func drawDizzyStars(_ ctx: GraphicsContext, center: CGPoint, R: CGFloat, t: Double) {
        for i in 0..<3 {
            let a = t * 4 + Double(i) * 2 * .pi / 3
            let depth = sin(a)
            var c = ctx
            c.translateBy(x: center.x + CGFloat(cos(a)) * 0.8 * R, y: center.y - 1.05 * R + CGFloat(depth) * 0.18 * R)
            c.rotate(by: .radians(t * 3 + Double(i)))
            c.opacity = depth > 0 ? 1 : 0.45
            let s = max(3, R * CGFloat(0.3 + 0.08 * depth))
            c.fill(sparkle(size: s), with: .color(Color(red: 1, green: 0.86, blue: 0.36)))
        }
    }

    /// Confeti de vidrio: esquirla redondeada de un color de la paleta de estados.
    static func drawConfetti(_ ctx: inout GraphicsContext, size s: CGFloat, hue: Int) {
        let palette: [RGB] = [(0.23, 0.62, 1), (0.55, 0.36, 0.97), (0.2, 0.83, 0.6), (0.96, 0.65, 0.14), (0.96, 0.45, 0.71)]
        let c = palette[((hue % palette.count) + palette.count) % palette.count]
        let rect = CGRect(x: -s / 2, y: -s * 0.3, width: s, height: s * 0.6)
        ctx.fill(Path(roundedRect: rect, cornerRadius: s * 0.15), with: .color(rgb(mix(c, white, 0.25), 0.9)))
        ctx.fill(Path(CGRect(x: -s * 0.35, y: -s * 0.22, width: s * 0.35, height: s * 0.12)),
                 with: .color(Color.white.opacity(0.6)))
    }

    /// Signo de pregunta hecho con trazos (para `stroke`): el punto es un circulito que al trazarse se llena.
    static func questionGlyph(size s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: -0.3 * s, y: -0.24 * s))
        p.addQuadCurve(to: CGPoint(x: 0, y: -0.52 * s), control: CGPoint(x: -0.3 * s, y: -0.52 * s))
        p.addQuadCurve(to: CGPoint(x: 0.3 * s, y: -0.24 * s), control: CGPoint(x: 0.3 * s, y: -0.52 * s))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0.1 * s), control: CGPoint(x: 0.3 * s, y: 0))
        p.addLine(to: CGPoint(x: 0, y: 0.16 * s))
        p.addEllipse(in: CGRect(x: -0.02 * s, y: 0.4 * s, width: 0.04 * s, height: 0.04 * s))
        return p
    }

    /// "z" de dormir hecha con líneas (más liviana que dibujar texto en cada cuadro).
    static func zGlyph(size s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: -0.4 * s, y: -0.42 * s))
        p.addLine(to: CGPoint(x: 0.4 * s, y: -0.42 * s))
        p.addLine(to: CGPoint(x: -0.4 * s, y: 0.42 * s))
        p.addLine(to: CGPoint(x: 0.4 * s, y: 0.42 * s))
        return p
    }
}

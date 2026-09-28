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
                        D: D, tint: tint, crouch: f.crouch)
            }
        }

        // Transformación del cuerpo: rotación + squash & stretch anclado abajo.
        var body = ctx
        body.translateBy(x: bodyCenter.x, y: bodyCenter.y)
        body.rotate(by: .radians(f.rotation))
        body.translateBy(x: 0, y: 0.5 * D)
        body.scaleBy(x: CGFloat(f.scaleX), y: CGFloat(f.scaleY))
        body.translateBy(x: 0, y: -0.5 * D)

        drawBody(&body, D: D, tint: tint)
        drawEyes(&body, f: f, D: D)
        if layout.showLimbs {
            drawArm(&body, side: -1, raise: f.leftArmRaise, D: D, tint: tint)
            drawArm(&body, side: 1, raise: f.rightArmRaise, D: D, tint: tint)
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

    static func drawBody(_ ctx: inout GraphicsContext, D: CGFloat, tint: (r: Double, g: Double, b: Double)) {
        let r = D / 2
        let circle = Path(ellipseIn: CGRect(x: -r, y: -r, width: D, height: D))

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
    static func drawArm(_ ctx: inout GraphicsContext, side: Double, raise: Double, D: CGFloat,
                        tint: (r: Double, g: Double, b: Double)) {
        var arm = ctx
        arm.translateBy(x: CGFloat(side) * 0.45 * D, y: 0.0)
        arm.rotate(by: .radians(-side * raise))
        let L = 0.38 * D, w = 0.12 * D
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -0.02 * D))
        p.addCurve(to: CGPoint(x: 0, y: L), control1: CGPoint(x: w * 1.1, y: L * 0.35), control2: CGPoint(x: w * 1.25, y: L))
        p.addCurve(to: CGPoint(x: 0, y: -0.02 * D), control1: CGPoint(x: -w * 1.25, y: L), control2: CGPoint(x: -w * 1.1, y: L * 0.35))
        p.closeSubpath()
        drawGlassPart(&arm, p, bounds: CGRect(x: -w, y: 0, width: 2 * w, height: L), D: D, tint: tint)
    }

    static func drawLeg(_ ctx: inout GraphicsContext, side: Double, bodyCenter: CGPoint, footY: CGFloat,
                        D: CGFloat, tint: (r: Double, g: Double, b: Double), crouch: Double) {
        let x = bodyCenter.x + CGFloat(side) * 0.17 * D
        let top = bodyCenter.y + 0.34 * D
        let legW = 0.11 * D
        let legH = max(0.02 * D, footY - top)
        let leg = Path(roundedRect: CGRect(x: x - legW / 2, y: top, width: legW, height: legH),
                       cornerRadius: legW / 2)
        drawGlassPart(&ctx, leg, bounds: CGRect(x: x - legW / 2, y: top, width: legW, height: legH), D: D, tint: tint)

        let footW = 0.22 * D, footH = 0.1 * D
        let fx = x + CGFloat(side) * 0.02 * D
        let foot = Path(roundedRect: CGRect(x: fx - footW / 2, y: footY - footH / 2, width: footW, height: footH),
                        cornerRadius: footH / 2)
        drawGlassPart(&ctx, foot, bounds: CGRect(x: fx - footW / 2, y: footY - footH / 2, width: footW, height: footH),
                      D: D, tint: tint)
    }

    /// Relleno de vidrio para brazos, piernas y pies.
    static func drawGlassPart(_ ctx: inout GraphicsContext, _ path: Path, bounds: CGRect, D: CGFloat,
                              tint: (r: Double, g: Double, b: Double)) {
        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [rgb(mix(white, tint, 0.4), 0.42), rgb(tint, 0.2), rgb(mix(tint, deep, 0.3), 0.45)]),
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

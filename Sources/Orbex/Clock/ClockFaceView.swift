import AppKit
import SwiftUI
import OrbexCore

/// La esfera del reloj flotante: ORBEX *es* el dial (vidrio, ojos, respiración), las agujas van encima.
struct ClockFaceView: View {
    var face: ClockFace
    var showSeconds: Bool
    var ringProgress: Double?
    /// Tamaño mini: solo dial + horas y minutos.
    var compact: Bool = false
    var paused: Bool = false

    @Environment(\.orbexTheme) private var theme
    @Environment(\.hostWindow) private var hostWindow

    var body: some View {
        GeometryReader { geo in
            let global = geo.frame(in: .global)
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: paused)) { _ in
                Canvas { ctx, size in
                    let painter = ClockPainter(face: face, seconds: showSeconds && !compact, ring: ringProgress,
                                               compact: compact, accent: theme.accent, calm: theme.reduceMotion,
                                               date: Date(), t: CACurrentMediaTime(),
                                               look: { p in lookTarget(p, global) })
                    painter.draw(&ctx, size: size)
                }
            }
        }
        .accessibilityLabel("Reloj \(face.label)")
    }

    private func lookTarget(_ p: CGPoint, _ global: CGRect) -> (x: Double, y: Double)? {
        guard let window = hostWindow.window else { return nil }
        let content = window.contentRect(forFrameRect: window.frame)
        let sx = content.minX + global.minX + p.x
        let sy = content.maxY - (global.minY + p.y)
        let m = NSEvent.mouseLocation
        return (Double(m.x - sx), Double(sy - m.y))
    }
}

private struct ClockPainter {
    let face: ClockFace
    let seconds: Bool
    let ring: Double?
    let compact: Bool
    let accent: Color
    let calm: Bool
    let date: Date
    let t: Double
    let look: (CGPoint) -> (x: Double, y: Double)?

    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(red: r, green: g, blue: b).opacity(a)
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        var R = side / 2
        let c = CGPoint(x: size.width / 2, y: face == .retroWall ? R : size.height / 2)
        if face == .retroWall && size.height > side * 1.1 { pendulum(&ctx, c: c, R: R, bottom: size.height) }
        if let p = ring {
            let lw = max(2, R * 0.05)
            timerRing(&ctx, c: c, r: R - lw / 2, lw: lw, p: p)
            R -= lw + max(1.5, R * 0.025)
        }
        let a = ClockMath.angles(for: date, smooth: true)
        let f = CharacterBrain.shared.frame(at: t, lookTarget: look(c))
        switch face {
        case .classic: classic(&ctx, c: c, R: R, a: a, f: f)
        case .retroWall: retro(&ctx, c: c, R: R, a: a, f: f)
        case .orbit: orbit(&ctx, c: c, R: R, a: a, f: f)
        }
    }

    // MARK: - Piezas comunes

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    private func point(_ c: CGPoint, _ deg: Double, _ r: CGFloat) -> CGPoint {
        let p = ClockMath.orbitPoint(angle: deg, radius: Double(r))
        return CGPoint(x: c.x + CGFloat(p.x), y: c.y + CGFloat(p.y))
    }

    /// ORBEX vivo: cuerpo de vidrio (opcional) + ojos, con la respiración del cerebro.
    private func orbex(_ ctx: inout GraphicsContext, c: CGPoint, D: CGFloat, f: CharacterFrame,
                       body: Bool, eyeScale: CGFloat, eyeLift: CGFloat) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        let k = calm ? 0.2 : 0.5
        g.scaleBy(x: CGFloat(1 + (f.scaleX - 1) * k), y: CGFloat(1 + (f.scaleY - 1) * k))
        if body { OrbexPainter.drawBody(&g, D: D, tint: f.tint.rgb) }
        var e = g
        e.translateBy(x: 0, y: -eyeLift + CGFloat(f.offsetY) * D * 0.2)
        OrbexPainter.drawEyes(&e, f: f, D: D * eyeScale)
    }

    private func hand(_ ctx: inout GraphicsContext, c: CGPoint, deg: Double, len: CGFloat, width: CGFloat,
                      tail: CGFloat, color: Color, outline: Color?, shadow: Bool = true) {
        let rect = CGRect(x: -width / 2, y: -len, width: width, height: len + tail)
        let p = Path(roundedRect: rect, cornerRadius: width / 2)
        if shadow {
            var s = ctx
            s.translateBy(x: c.x + width * 0.25 + 0.5, y: c.y + width * 0.5 + 1)
            s.rotate(by: .degrees(deg))
            s.fill(p, with: .color(.black.opacity(0.3)))
        }
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(deg))
        g.fill(p, with: .color(color))
        if let o = outline { g.stroke(p, with: .color(o), lineWidth: max(0.5, width * 0.18)) }
    }

    private func timerRing(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, lw: CGFloat, p: Double) {
        ctx.stroke(circle(c, r), with: .color(.white.opacity(0.12)), lineWidth: lw)
        var arc = Path()
        arc.addArc(center: c, radius: r, startAngle: .degrees(-90),
                   endAngle: .degrees(-90 + 360 * min(1, max(0, p))), clockwise: false)
        ctx.stroke(arc, with: .color(accent), style: StrokeStyle(lineWidth: lw, lineCap: .round))
    }

    // MARK: - Clásica (tipo Rolex)

    private func classic(_ ctx: inout GraphicsContext, c: CGPoint, R: CGFloat, a: HandAngles, f: CharacterFrame) {
        let metal = Gradient(colors: [.init(white: 0.92), .init(white: 0.5), .init(white: 0.95), .init(white: 0.45),
                                      .init(white: 0.9), .init(white: 0.55), .init(white: 0.92)])
        ctx.fill(circle(c, R), with: .conicGradient(metal, center: c, angle: .degrees(-30)))
        ctx.fill(circle(c, R), with: .color(accent.opacity(0.22)))
        if !compact {
            for i in 0..<72 {
                var p = Path()
                p.move(to: point(c, Double(i) * 5, R * 0.87))
                p.addLine(to: point(c, Double(i) * 5, R * 0.985))
                ctx.stroke(p, with: .color(i % 2 == 0 ? .white.opacity(0.4) : .black.opacity(0.28)),
                           lineWidth: max(0.5, R * 0.018))
            }
        }
        ctx.stroke(circle(c, R), with: .color(.black.opacity(0.35)), lineWidth: max(0.6, R * 0.015))
        let dr = R * 0.86
        ctx.fill(circle(c, dr), with: .radialGradient(
            Gradient(colors: [Self.rgb(0.22, 0.3, 0.42), Self.rgb(0.05, 0.07, 0.12)]),
            center: CGPoint(x: c.x - dr * 0.2, y: c.y - dr * 0.25), startRadius: 0, endRadius: dr * 1.2))
        orbex(&ctx, c: c, D: dr * 2, f: f, body: true, eyeScale: 0.62, eyeLift: R * 0.2)
        ctx.stroke(circle(c, dr), with: .color(.black.opacity(0.5)), lineWidth: max(0.8, R * 0.02))

        if !compact {
            for i in 0..<60 where i % 5 != 0 {
                var p = Path()
                p.move(to: point(c, Double(i) * 6, R * 0.79))
                p.addLine(to: point(c, Double(i) * 6, R * 0.83))
                ctx.stroke(p, with: .color(.white.opacity(0.55)), lineWidth: max(0.4, R * 0.008))
            }
        }
        for i in 0..<12 {
            let deg = Double(i) * 30
            if i == 0 {
                var tri = Path()
                tri.move(to: point(c, deg, R * 0.62))
                tri.addLine(to: point(c, deg - 5, R * 0.8))
                tri.addLine(to: point(c, deg + 5, R * 0.8))
                tri.closeSubpath()
                ctx.fill(tri, with: .color(.white.opacity(0.95)))
                ctx.stroke(tri, with: .color(accent.opacity(0.6)), lineWidth: max(0.5, R * 0.01))
                continue
            }
            if i == 3 && !compact { continue }
            var g = ctx
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .degrees(deg))
            let w = R * (compact ? 0.07 : 0.05)
            let bar = Path(roundedRect: CGRect(x: -w / 2, y: -R * 0.8, width: w, height: R * 0.15), cornerRadius: w * 0.3)
            g.fill(bar, with: .color(.white.opacity(0.92)))
            g.stroke(bar, with: .color(accent.opacity(0.5)), lineWidth: max(0.4, R * 0.008))
        }
        if !compact {
            let box = CGRect(x: c.x + R * 0.54, y: c.y - R * 0.08, width: R * 0.24, height: R * 0.16)
            ctx.fill(Path(roundedRect: box, cornerRadius: R * 0.02), with: .color(.white.opacity(0.95)))
            ctx.stroke(Path(roundedRect: box, cornerRadius: R * 0.02), with: .color(.black.opacity(0.4)), lineWidth: 0.6)
            ctx.draw(Text(ClockMath.dayText(date)).font(.system(size: R * 0.12, weight: .bold, design: .serif))
                        .foregroundColor(.black), at: CGPoint(x: box.midX, y: box.midY))
            ctx.draw(Text("ORBEX").font(.system(size: R * 0.075, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75)), at: CGPoint(x: c.x, y: c.y + R * 0.36))
        }
        let silver = Color(white: 0.96)
        hand(&ctx, c: c, deg: a.hour, len: R * 0.46, width: R * 0.075, tail: R * 0.08, color: silver, outline: .black.opacity(0.45))
        hand(&ctx, c: c, deg: a.minute, len: R * 0.7, width: R * 0.05, tail: R * 0.1, color: silver, outline: .black.opacity(0.45))
        if seconds {
            hand(&ctx, c: c, deg: a.second, len: R * 0.78, width: max(0.8, R * 0.014), tail: R * 0.2,
                 color: accent, outline: nil)
            var g = ctx
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .degrees(a.second))
            g.fill(circle(CGPoint(x: 0, y: -R * 0.6), R * 0.035), with: .color(accent))
        }
        ctx.fill(circle(c, R * 0.045), with: .color(silver))
        ctx.stroke(circle(c, R * 0.045), with: .color(.black.opacity(0.4)), lineWidth: 0.5)
    }

    // MARK: - Retro de pared

    private func pendulum(_ ctx: inout GraphicsContext, c: CGPoint, R: CGFloat, bottom: CGFloat) {
        let panel = CGRect(x: c.x - R * 0.36, y: c.y, width: R * 0.72, height: bottom - c.y - 2)
        ctx.fill(Path(roundedRect: panel, cornerRadius: R * 0.14), with: .linearGradient(
            Gradient(colors: [Self.rgb(0.36, 0.2, 0.1, 0.95), Self.rgb(0.18, 0.09, 0.04, 0.95)]),
            startPoint: CGPoint(x: panel.minX, y: panel.minY), endPoint: CGPoint(x: panel.maxX, y: panel.maxY)))
        let pivot = CGPoint(x: c.x, y: c.y + R * 0.5)
        let bob = R * 0.2
        let len = max(R * 0.2, bottom - pivot.y - bob - R * 0.12)
        let swing = (calm ? 4.0 : 12.0) * sin(2 * .pi * t / 2)
        var g = ctx
        g.translateBy(x: pivot.x, y: pivot.y)
        g.rotate(by: .degrees(swing))
        let brass = Gradient(colors: [Self.rgb(1, 0.88, 0.55), Self.rgb(0.72, 0.52, 0.22), Self.rgb(0.45, 0.3, 0.1)])
        g.fill(Path(roundedRect: CGRect(x: -R * 0.025, y: 0, width: R * 0.05, height: len), cornerRadius: R * 0.02),
               with: .linearGradient(brass, startPoint: CGPoint(x: -R * 0.03, y: 0), endPoint: CGPoint(x: R * 0.03, y: 0)))
        let bc = CGPoint(x: 0, y: len)
        g.fill(circle(bc, bob), with: .radialGradient(brass, center: CGPoint(x: -bob * 0.35, y: len - bob * 0.35),
                                                      startRadius: 0, endRadius: bob * 1.4))
        g.fill(circle(bc, bob), with: .color(accent.opacity(0.12)))
        g.stroke(circle(bc, bob), with: .color(.black.opacity(0.35)), lineWidth: 0.8)
    }

    private func retro(_ ctx: inout GraphicsContext, c: CGPoint, R: CGFloat, a: HandAngles, f: CharacterFrame) {
        ctx.fill(circle(c, R), with: .linearGradient(
            Gradient(colors: [Self.rgb(0.5, 0.3, 0.15), Self.rgb(0.2, 0.1, 0.04)]),
            startPoint: CGPoint(x: c.x - R, y: c.y - R), endPoint: CGPoint(x: c.x + R, y: c.y + R)))
        ctx.stroke(circle(c, R * 0.97), with: .color(.white.opacity(0.18)), lineWidth: max(0.6, R * 0.015))
        ctx.stroke(circle(c, R * 0.84), with: .color(Self.rgb(0.88, 0.7, 0.36)), lineWidth: max(1, R * 0.035))
        let dr = R * 0.82
        ctx.fill(circle(c, dr), with: .radialGradient(
            Gradient(colors: [Self.rgb(0.99, 0.96, 0.88), Self.rgb(0.86, 0.8, 0.67)]),
            center: CGPoint(x: c.x - dr * 0.2, y: c.y - dr * 0.25), startRadius: 0, endRadius: dr * 1.2))
        ctx.fill(circle(c, dr), with: .color(accent.opacity(0.06)))
        let ink = Self.rgb(0.16, 0.1, 0.06)
        if !compact {
            for i in 0..<60 {
                var p = Path()
                p.move(to: point(c, Double(i) * 6, R * (i % 5 == 0 ? 0.72 : 0.76)))
                p.addLine(to: point(c, Double(i) * 6, R * 0.8))
                ctx.stroke(p, with: .color(ink.opacity(0.8)), lineWidth: max(0.4, R * (i % 5 == 0 ? 0.018 : 0.008)))
            }
        }
        let nums = ClockMath.numerals(roman: false)
        for (i, n) in nums.enumerated() where !compact || i % 3 == 0 {
            ctx.draw(Text(n).font(.system(size: R * (compact ? 0.26 : 0.19), weight: .bold, design: .serif))
                        .foregroundColor(ink), at: point(c, Double(i) * 30, R * (compact ? 0.6 : 0.58)))
        }
        orbex(&ctx, c: c, D: dr * 2, f: f, body: false, eyeScale: 0.55, eyeLift: R * 0.2)
        hand(&ctx, c: c, deg: a.hour, len: R * 0.44, width: R * 0.08, tail: R * 0.06, color: ink, outline: nil)
        hand(&ctx, c: c, deg: a.minute, len: R * 0.68, width: R * 0.05, tail: R * 0.08, color: ink, outline: nil)
        if seconds {
            hand(&ctx, c: c, deg: a.second, len: R * 0.72, width: max(0.8, R * 0.014), tail: R * 0.16,
                 color: Self.rgb(0.8, 0.12, 0.1), outline: nil)
        }
        ctx.fill(circle(c, R * 0.05), with: .color(Self.rgb(0.85, 0.66, 0.3)))
        var gl = ctx
        gl.translateBy(x: c.x - dr * 0.25, y: c.y - dr * 0.45)
        gl.rotate(by: .degrees(-30))
        gl.fill(Path(ellipseIn: CGRect(x: -dr * 0.45, y: -dr * 0.14, width: dr * 0.9, height: dr * 0.28)),
                with: .color(.white.opacity(0.16)))
    }

    // MARK: - ORBIT futurista

    private func orbit(_ ctx: inout GraphicsContext, c: CGPoint, R: CGFloat, a: HandAngles, f: CharacterFrame) {
        ctx.fill(circle(c, R), with: .radialGradient(
            Gradient(colors: [Self.rgb(0.07, 0.08, 0.16, 0.94), Self.rgb(0.01, 0.01, 0.03, 0.96)]),
            center: c, startRadius: 0, endRadius: R))
        ctx.stroke(circle(c, R * 0.99), with: .color(accent.opacity(0.35)), lineWidth: max(0.6, R * 0.012))
        if !compact {
            for i in 0..<24 {
                let s1 = frac(sin(Double(i) * 12.9898) * 43758.5453)
                let s2 = frac(sin(Double(i) * 78.233) * 12345.678)
                let r = R * CGFloat(0.25 + 0.7 * s1)
                let deg = s2 * 360 + t * (6 + 14 * s1) * (i % 2 == 0 ? 1 : -1)
                let op = 0.12 + 0.3 * (0.5 + 0.5 * sin(t * (0.8 + s2) + Double(i)))
                ctx.fill(circle(point(c, deg, r), max(0.6, R * 0.011)), with: .color(.white.opacity(op)))
            }
        }
        for i in 0..<12 {
            ctx.fill(circle(point(c, Double(i) * 30, R * 0.9), max(0.7, R * (i % 3 == 0 ? 0.018 : 0.01))),
                     with: .color(.white.opacity(0.35)))
        }
        var rings: [(deg: Double, r: CGFloat, color: Color)] = [
            (a.hour, R * 0.9, accent),
            (a.minute, R * (compact ? 0.66 : 0.72), Self.rgb(0.62, 0.9, 1)),
        ]
        if seconds { rings.append((a.second, R * 0.54, Self.rgb(1, 0.45, 0.65))) }
        for ring in rings {
            ctx.stroke(circle(c, ring.r), with: .color(.white.opacity(0.1)), lineWidth: max(0.5, R * 0.008))
            var arc = Path()
            arc.addArc(center: c, radius: ring.r, startAngle: .degrees(-90), endAngle: .degrees(-90 + ring.deg), clockwise: false)
            ctx.stroke(arc, with: .color(ring.color.opacity(0.4)), style: StrokeStyle(lineWidth: max(1, R * 0.018), lineCap: .round))
            let p = point(c, ring.deg, ring.r)
            var glow = ctx
            glow.addFilter(.blur(radius: R * 0.05))
            glow.fill(circle(p, R * 0.07), with: .color(ring.color.opacity(0.85)))
            ctx.fill(circle(p, R * 0.04), with: .color(ring.color))
            ctx.fill(circle(p, R * 0.018), with: .color(.white.opacity(0.95)))
        }
        let D = R * (seconds ? 0.8 : 1.0)
        var halo = ctx
        halo.addFilter(.blur(radius: R * 0.08))
        halo.fill(circle(c, D * 0.5), with: .color(accent.opacity(0.18)))
        orbex(&ctx, c: c, D: D, f: f, body: true, eyeScale: 1, eyeLift: 0)
    }

    private func frac(_ x: Double) -> Double { x - floor(x) }
}

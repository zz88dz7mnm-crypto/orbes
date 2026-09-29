import SwiftUI

/// Silueta de la isla: bloque que baja del borde superior con esquinas inferiores redondeadas
/// y "hombreras" cóncavas arriba para fundirse con la barra de menú (como el notch real).
/// El rectángulo incluye las hombreras: el cuerpo ocupa `rect.width − 2 × shoulder`.
struct OrbexIslandShape: Shape {
    var bottomRadius: CGFloat
    var shoulder: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, shoulder) }
        set { bottomRadius = newValue.first; shoulder = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let s = max(0, min(shoulder, rect.width / 4))
        let bodyW = rect.width - 2 * s
        let r = max(0, min(bottomRadius, bodyW / 2, (rect.height - s) / 1))
        let left = rect.minX + s
        let right = rect.maxX - s
        let top = rect.minY
        let bottom = rect.maxY

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: top))
        p.addLine(to: CGPoint(x: rect.maxX, y: top))
        // Hombrera derecha (cóncava).
        p.addQuadCurve(to: CGPoint(x: right, y: top + s), control: CGPoint(x: right, y: top))
        p.addLine(to: CGPoint(x: right, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
        p.addLine(to: CGPoint(x: left + r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: left, y: bottom - r), control: CGPoint(x: left, y: bottom))
        p.addLine(to: CGPoint(x: left, y: top + s))
        // Hombrera izquierda (cóncava).
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: top), control: CGPoint(x: left, y: top))
        p.closeSubpath()
        return p
    }
}

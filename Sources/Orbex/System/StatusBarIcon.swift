import AppKit

/// Ícono de la barra de menú (informe §13.6): silueta de una sola tinta de la esfera con los dos ojos
/// ovalados. Es "template", así macOS lo pinta solo en modo claro/oscuro.
enum StatusBarIcon {
    /// Imagen de 18 × 18 pt.
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()

            // Esfera: contorno.
            let lineWidth: CGFloat = 1.5
            let sphereRect = rect.insetBy(dx: 1 + lineWidth / 2, dy: 1 + lineWidth / 2)
            let sphere = NSBezierPath(ovalIn: sphereRect)
            sphere.lineWidth = lineWidth
            sphere.stroke()

            // Reflejo: arquito arriba a la izquierda (se lee como vidrio).
            let shine = NSBezierPath()
            shine.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY),
                            radius: sphereRect.width / 2 - 2.0,
                            startAngle: 112, endAngle: 150, clockwise: false)
            shine.lineWidth = 1.1
            shine.lineCapStyle = .round
            shine.stroke()

            // Ojos: dos óvalos verticales, un poco arriba del centro.
            let eyeWidth: CGFloat = 2.6
            let eyeHeight: CGFloat = 4.6
            let eyeGap: CGFloat = 2.5
            let eyeCenterY = rect.midY + 0.3
            for side in [CGFloat(-1), CGFloat(1)] {
                let cx = rect.midX + side * eyeGap
                let eye = NSRect(x: cx - eyeWidth / 2, y: eyeCenterY - eyeHeight / 2,
                                 width: eyeWidth, height: eyeHeight)
                NSBezierPath(ovalIn: eye).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ORBEX"
        return image
    }
}

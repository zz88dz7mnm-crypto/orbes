import AppKit
import SwiftUI
import OrbexCore

/// Referencia débil a la ventana que contiene una vista (para convertir coordenadas a pantalla).
final class HostWindowRef {
    weak var window: NSWindow?
    init(_ window: NSWindow? = nil) { self.window = window }
}

private struct HostWindowKey: EnvironmentKey {
    static let defaultValue = HostWindowRef()
}

extension EnvironmentValues {
    var hostWindow: HostWindowRef {
        get { self[HostWindowKey.self] }
        set { self[HostWindowKey.self] = newValue }
    }
}

/// ORBEX animado. Siempre hay al menos una animación en curso mientras está visible.
struct OrbexView: View {
    @ObservedObject var brain: CharacterBrain = .shared
    /// `false` = solo la esfera con los ojos (para las alitas y el estado asomado).
    var showLimbs: Bool = true
    var paused: Bool = false
    var fps: Double = 60
    var scale: CGFloat = 1

    @Environment(\.hostWindow) private var hostWindow

    var body: some View {
        GeometryReader { geo in
            let global = geo.frame(in: .global)
            TimelineView(.animation(minimumInterval: 1.0 / max(10, fps), paused: paused)) { _ in
                Canvas { ctx, size in
                    let t = CACurrentMediaTime()
                    let layout = OrbexPainter.Layout(size: size, showLimbs: showLimbs, scale: scale)
                    let target = lookTarget(bodyCenter: layout.center, global: global)
                    let frame = brain.frame(at: t, lookTarget: target)
                    OrbexPainter.draw(frame, in: &ctx, layout: layout, t: t)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { brain.tap() }
        .accessibilityLabel("ORBEX")
    }

    /// Vector del centro del cuerpo al cursor (puntos, y hacia abajo), o `nil` si no se conoce la ventana.
    private func lookTarget(bodyCenter: CGPoint, global: CGRect) -> (x: Double, y: Double)? {
        guard let window = hostWindow.window else { return nil }
        let content = window.contentRect(forFrameRect: window.frame)
        // Centro del cuerpo en coordenadas de pantalla (AppKit: y hacia arriba).
        let sx = content.minX + global.minX + bodyCenter.x
        let sy = content.maxY - (global.minY + bodyCenter.y)
        let m = brain.mouseOnScreen
        return (Double(m.x - sx), Double(sy - m.y))
    }
}

/// Mini ORBEX asomando: la parte de arriba de la esfera con los ojos.
struct OrbexPeekView: View {
    @ObservedObject var brain: CharacterBrain = .shared
    var diameter: CGFloat
    var paused: Bool = false
    var fps: Double = 30

    var body: some View {
        OrbexView(brain: brain, showLimbs: false, paused: paused, fps: fps)
            .frame(width: diameter, height: diameter)
    }
}

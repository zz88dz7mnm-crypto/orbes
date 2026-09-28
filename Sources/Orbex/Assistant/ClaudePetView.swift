import QuartzCore
import SwiftUI
import OrbexCore

/// Clawd, la mascota pixelada de Claude Code, acompañando a ORBEX en el asistente.
/// Pinta los píxeles que devuelve `ClawdSprite.frame` (Core); acá solo hay dibujo.
struct ClaudePetView: View {
    var mood: ClawdMood
    var size: CGFloat = 28

    @Environment(\.orbexTheme) private var theme
    @State private var moodStart: Double = CACurrentMediaTime()

    private static let bodyColor = Color(red: 0.851, green: 0.467, blue: 0.341)       // #D97757
    private static let shade = Color(red: 0.66, green: 0.33, blue: 0.23)
    private static let highlight = Color(red: 0.96, green: 0.64, blue: 0.52)
    private static let eye = Color(red: 0.08, green: 0.06, blue: 0.06)
    private static let dot = Color.white.opacity(0.9)
    private static let tear = Color(red: 0.55, green: 0.8, blue: 1)
    private static let sparkle = Color(red: 1, green: 0.93, blue: 0.6)

    var body: some View {
        let cols = CGFloat(ClawdSprite.columns)
        let rows = CGFloat(ClawdSprite.rows)
        let height = size * rows / cols
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { _ in
            Canvas { ctx, canvasSize in
                let t = CACurrentMediaTime()
                let cell = min(canvasSize.width / cols, canvasSize.height / rows)
                let pixels = ClawdSprite.frame(mood: mood, time: t, moodElapsed: t - moodStart,
                                               reduceMotion: theme.reduceMotion)
                for p in pixels {
                    let rect = CGRect(x: CGFloat(p.x) * cell, y: CGFloat(p.y) * cell,
                                      width: cell + 0.3, height: cell + 0.3)
                    ctx.fill(Path(rect), with: .color(Self.color(for: p.kind)))
                }
            }
        }
        .frame(width: size, height: height)
        .onChange(of: mood) { _, _ in moodStart = CACurrentMediaTime() }
        .accessibilityLabel("Clawd")
    }

    private static func color(for kind: ClawdPixel.Kind) -> Color {
        switch kind {
        case .body: return bodyColor
        case .shade: return shade
        case .highlight: return highlight
        case .eye: return eye
        case .dot: return dot
        case .tear: return tear
        case .sparkle: return sparkle
        }
    }
}

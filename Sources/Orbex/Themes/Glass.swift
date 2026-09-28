import SwiftUI
import OrbexCore

/// Estilo visual activo (tema + preferencias de transparencia/movimiento).
/// Se inyecta en el entorno de SwiftUI con `.environment(\.orbexTheme, ...)`.
struct ThemeStyle: Equatable {
    var id: ThemeID = .liquidGlass
    var useGlass: Bool = true
    /// 0 = vidrio claro, 1 = vidrio teñido.
    var glassTint: Double = 0.35
    var reduceTransparency: Bool = false
    var reduceMotion: Bool = false

    var accent: Color {
        switch id {
        case .liquidGlass: return Color(red: 0.56, green: 0.80, blue: 1.0)
        case .macClean: return Color(red: 0.25, green: 0.56, blue: 1.0)
        case .y2k: return Color(red: 0.45, green: 1.0, blue: 0.62)
        }
    }

    var text: Color { .white }
    var secondaryText: Color { Color.white.opacity(0.62) }
    var tertiaryText: Color { Color.white.opacity(0.4) }

    /// Texto de pantallita LCD (tema Y2K) o normal.
    var displayFont: Font {
        switch id {
        case .y2k: return .system(size: 12, weight: .semibold, design: .monospaced)
        default: return .system(size: 12, weight: .medium, design: .rounded)
        }
    }

    var titleFont: Font {
        switch id {
        case .y2k: return .system(size: 13, weight: .heavy, design: .monospaced)
        case .macClean: return .system(size: 13, weight: .semibold)
        case .liquidGlass: return .system(size: 13, weight: .semibold, design: .rounded)
        }
    }

    /// Animación de resorte estándar (o casi nada si "reducir movimiento").
    var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.46, dampingFraction: 0.74)
    }

    var softSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.8)
    }

    /// El vidrio real se usa solo si el usuario lo quiere y el sistema no pide menos transparencia.
    var glassAllowed: Bool { useGlass && !reduceTransparency }
}

private struct ThemeStyleKey: EnvironmentKey {
    static let defaultValue = ThemeStyle()
}

extension EnvironmentValues {
    var orbexTheme: ThemeStyle {
        get { self[ThemeStyleKey.self] }
        set { self[ThemeStyleKey.self] = newValue }
    }
}

// MARK: - Tarjetas

extension View {
    /// Fondo de tarjeta según el tema activo (Liquid Glass, macOS limpio o Y2K).
    func orbexCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(OrbexCardModifier(cornerRadius: cornerRadius))
    }

    /// Botón con forma de cápsula de vidrio.
    func orbexPill() -> some View {
        modifier(OrbexCardModifier(cornerRadius: 999))
    }
}

struct OrbexCardModifier: ViewModifier {
    @Environment(\.orbexTheme) private var theme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return styled(content, shape: shape)
    }

    @ViewBuilder
    private func styled(_ content: Content, shape: RoundedRectangle) -> some View {
        switch theme.id {
        case .liquidGlass:
            if theme.glassAllowed {
                nativeGlass(content, shape: shape)
            } else {
                content
                    .background(shape.fill(Color(white: 0.15)))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
            }
        case .macClean:
            content
                .background(shape.fill(Color(white: 0.13)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75))
        case .y2k:
            content
                .background(Y2KBevelBackground(shape: shape))
        }
    }

    #if compiler(>=6.2)
    @ViewBuilder
    private func nativeGlass(_ content: Content, shape: RoundedRectangle) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(Color.white.opacity(0.03 + 0.16 * theme.glassTint)), in: shape)
        } else {
            GlassFallback(content: content, shape: shape, tint: theme.glassTint)
        }
    }
    #else
    @ViewBuilder
    private func nativeGlass(_ content: Content, shape: RoundedRectangle) -> some View {
        GlassFallback(content: content, shape: shape, tint: theme.glassTint)
    }
    #endif
}

/// Vidrio simulado para macOS < 26 (o Xcode viejo): material + brillo en el borde.
private struct GlassFallback<C: View>: View {
    let content: C
    let shape: RoundedRectangle
    let tint: Double

    var body: some View {
        content
            .background(shape.fill(.ultraThinMaterial))
            .background(shape.fill(Color.white.opacity(0.03 + 0.10 * tint)))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.06), Color.white.opacity(0.16)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8)
            )
    }
}

/// Cromo con bisel (tema Y2K / Winamp).
struct Y2KBevelBackground: View {
    let shape: RoundedRectangle

    var body: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.28), Color(white: 0.18), Color(white: 0.35)],
                                      startPoint: .top, endPoint: .bottom))
            shape.inset(by: 2).fill(Color(red: 0.05, green: 0.09, blue: 0.07))
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.85), Color.black.opacity(0.6)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
        }
    }
}

// MARK: - Botón de acción rápida

struct OrbexActionButton: View {
    @Environment(\.orbexTheme) private var theme
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(title)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .orbexCard(cornerRadius: 12)
            .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(theme.softSpring) { hovering = h } }
    }
}

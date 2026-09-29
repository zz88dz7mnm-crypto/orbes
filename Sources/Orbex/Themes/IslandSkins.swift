import SwiftUI
import OrbexCore

// Pieles por tema para las piezas de la isla heredadas de la base (tarjetas, botones, pastillas).
// Las vistas de `Base/` no cambian de API: solo delegan su fondo a estas piezas.
// Todas observan `AppModel.shared`, así la isla sigue al tema aunque no tenga el entorno inyectado.

/// Tipo de superficie de botón: principal (clara, para texto oscuro) o secundaria (oscura, texto claro).
enum IslandButtonRole { case primary, secondary }

// MARK: - Tarjeta

/// Fondo de tarjeta de la isla según el tema. `wash` es el resplandor de color de abajo (puede ser `.clear`).
struct IslandCardSurface: View {
    @ObservedObject private var model = AppModel.shared
    let wash: Color
    var cornerRadius: CGFloat = 20

    var body: some View {
        let theme = model.themeStyle
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            IslandCardBase(theme: theme, shape: shape)
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: wash, location: 0),
                    .init(color: .clear, location: 0.7)
                ]),
                center: UnitPoint(x: 0.5, y: 1.3),
                startRadius: 0,
                endRadius: 280
            )
            .clipShape(shape)
            IslandCardBorder(theme: theme, shape: shape)
        }
        .allowsHitTesting(false)
    }
}

private struct IslandCardBase: View {
    let theme: ThemeStyle
    let shape: RoundedRectangle

    @ViewBuilder
    var body: some View {
        switch theme.id {
        case .liquidGlass:
            if theme.glassAllowed {
                LiquidGlassFill(shape: shape, tint: theme.glassTint)
            } else {
                shape.fill(Color(white: 0.12))
            }
        case .macClean:
            shape.fill(Color(white: 0.105))
        case .y2k:
            ZStack {
                // Marco cromado…
                shape.fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.30), Color(white: 0.16), Color(white: 0.42)],
                                          startPoint: .top, endPoint: .bottom))
                // …y panel de metal oscuro hundido.
                shape.inset(by: 2.5)
                    .fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.075)],
                                         startPoint: .top, endPoint: .bottom))
                shape.inset(by: 2.5)
                    .stroke(LinearGradient(colors: [Color.black.opacity(0.75), Color.white.opacity(0.22)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
        }
    }
}

/// Vidrio: Liquid Glass nativo en macOS 26 (compilado con Xcode 26), si no un degradé traslúcido con reflejo.
private struct LiquidGlassFill: View {
    let shape: RoundedRectangle
    let tint: Double

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(Color.white.opacity(0.02 + 0.10 * tint)), in: shape)
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var fallback: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.10 + 0.06 * tint), Color.white.opacity(0.035 + 0.04 * tint)],
                                      startPoint: .top, endPoint: .bottom))
            // Reflejo diagonal arriba.
            shape.fill(LinearGradient(stops: [
                .init(color: Color.white.opacity(0.10), location: 0),
                .init(color: Color.white.opacity(0), location: 0.35)
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

private struct IslandCardBorder: View {
    let theme: ThemeStyle
    let shape: RoundedRectangle

    @ViewBuilder
    var body: some View {
        switch theme.id {
        case .liquidGlass:
            if theme.glassAllowed {
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.42), Color.white.opacity(0.05), Color.white.opacity(0.16)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9)
            } else {
                shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
            }
        case .macClean:
            shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
        case .y2k:
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.9), Color.black.opacity(0.6)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }
}

// MARK: - Botones

/// Fondo + color de texto de un botón de la isla con la forma dada (cápsula o círculo).
struct IslandButtonSkin<S: InsettableShape>: ViewModifier {
    @ObservedObject private var model = AppModel.shared
    let role: IslandButtonRole
    let shape: S
    /// Si es `false` no se toca el color del texto (lo decide quien llama).
    var setsForeground: Bool = true
    var pressed: Bool = false

    func body(content: Content) -> some View {
        let theme = model.themeStyle
        return tinted(content, theme)
            .background(IslandButtonFill(theme: theme, role: role, shape: shape, pressed: pressed))
            .clipShape(shape)
    }

    /// Solo pisa el color si corresponde (no anular el `foregroundColor` que ponga quien llama).
    @ViewBuilder
    private func tinted(_ content: Content, _ theme: ThemeStyle) -> some View {
        if setsForeground {
            content.foregroundColor(foreground(theme))
        } else {
            content
        }
    }

    private func foreground(_ theme: ThemeStyle) -> Color {
        switch role {
        case .primary: return Color(hex: "#0B0C0E")
        case .secondary: return theme.id == .y2k ? Color(red: 0.78, green: 1, blue: 0.82) : Color(hex: "#F1F2F4")
        }
    }
}

private struct IslandButtonFill<S: InsettableShape>: View {
    let theme: ThemeStyle
    let role: IslandButtonRole
    let shape: S
    let pressed: Bool

    @ViewBuilder
    var body: some View {
        switch (theme.id, role) {
        case (.liquidGlass, .primary):
            ZStack {
                shape.fill(LinearGradient(colors: [Color.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 0.75)
            }
            .brightness(pressed ? -0.08 : 0)
        case (.liquidGlass, .secondary):
            if theme.glassAllowed {
                ZStack {
                    shape.fill(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)],
                                              startPoint: .top, endPoint: .bottom))
                    shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.08)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                }
                .opacity(pressed ? 0.7 : 1)
            } else {
                shape.fill(Color(white: pressed ? 0.26 : 0.2))
            }
        case (.macClean, .primary):
            shape.fill(Color(hex: pressed ? "#D9DBDF" : "#F5F6F8"))
        case (.macClean, .secondary):
            shape.fill(Color.white.opacity(pressed ? 0.14 : 0.09))
        case (.y2k, .primary):
            // Botón cromado con bisel (claro arriba, oscuro abajo; se invierte al apretar).
            ZStack {
                shape.fill(LinearGradient(colors: pressed
                                          ? [Color(white: 0.62), Color(white: 0.85)]
                                          : [Color(white: 0.97), Color(white: 0.72), Color(white: 0.82)],
                                          startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(LinearGradient(colors: [Color.white, Color(white: 0.3)],
                                                  startPoint: pressed ? .bottom : .top,
                                                  endPoint: pressed ? .top : .bottom), lineWidth: 1.2)
            }
        case (.y2k, .secondary):
            ZStack {
                shape.fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.10)],
                                          startPoint: pressed ? .bottom : .top,
                                          endPoint: pressed ? .top : .bottom))
                shape.strokeBorder(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.25)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
        }
    }
}

extension View {
    func islandButtonSkin<S: InsettableShape>(_ role: IslandButtonRole, shape: S,
                                              setsForeground: Bool = true, pressed: Bool = false) -> some View {
        modifier(IslandButtonSkin(role: role, shape: shape, setsForeground: setsForeground, pressed: pressed))
    }
}

// MARK: - Pastillas de agentes

/// Fondo de la pastilla de un agente (sin hover: superficie del tema; con hover: teñida del color del agente).
struct AgentPillSurface: View {
    @ObservedObject private var model = AppModel.shared
    let color: Color
    let hovered: Bool

    var body: some View {
        let theme = model.themeStyle
        ZStack {
            fill(theme)
            stroke(theme)
        }
    }

    @ViewBuilder
    private func fill(_ theme: ThemeStyle) -> some View {
        let shape = Capsule()
        if hovered {
            shape.fill(color.opacity(0.18))
        } else {
            switch theme.id {
            case .liquidGlass:
                if theme.glassAllowed {
                    shape.fill(LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.03)],
                                              startPoint: .top, endPoint: .bottom))
                } else {
                    shape.fill(Color(white: 0.11))
                }
            case .macClean:
                shape.fill(Color(hex: "#0E0F11"))
            case .y2k:
                shape.fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    @ViewBuilder
    private func stroke(_ theme: ThemeStyle) -> some View {
        let shape = Capsule()
        switch theme.id {
        case .liquidGlass where theme.glassAllowed && !hovered:
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.32), color.opacity(0.18)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        case .y2k:
            shape.strokeBorder(LinearGradient(colors: [Color(white: 0.85), hovered ? color : Color(white: 0.25)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        default:
            shape.stroke(color.opacity(hovered ? 0.55 : 0.14), lineWidth: 1)
        }
    }
}

/// Aro exterior del globito de alerta de una pastilla.
struct PillBadgeRing: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        switch model.themeStyle.id {
        case .y2k:
            Circle().fill(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.3)], startPoint: .top, endPoint: .bottom))
        case .liquidGlass:
            Circle().fill(Color(hex: "#0B0C0E"))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
        case .macClean:
            Circle().fill(Color(hex: "#0B0C0E"))
        }
    }
}

/// Lucecita de estado (conectado / no) según el tema: LED con brillo en Y2K, punto plano en los demás.
struct StatusLight: View {
    @ObservedObject private var model = AppModel.shared
    let color: Color

    var body: some View {
        let id = model.themeStyle.id
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Color.white.opacity(id == .y2k ? 0.5 : 0), lineWidth: 0.5))
            .frame(width: 6, height: 6)
            .shadow(color: id == .macClean ? .clear : color.opacity(id == .y2k ? 0.9 : 0.5),
                    radius: id == .y2k ? 3 : 2)
    }
}

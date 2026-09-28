import SwiftUI
import UniformTypeIdentifiers
import OrbexCore

/// Vista raíz del panel: la isla pegada arriba y centrada, que cambia de tamaño con resorte.
struct IslandRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let size = model.islandSize
        let shoulder = CGFloat(size.shoulderRadius)
        let w = CGFloat(size.width)
        let h = CGFloat(size.height)
        let expanded = model.islandState.isExpanded
        let shape = IslandShape(bottomRadius: CGFloat(size.bottomRadius), shoulder: shoulder)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(Color.black)
                    .overlay(
                        // Brillo sutil de vidrio en el borde cuando está desplegada.
                        shape.stroke(
                            LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(expanded ? 0.16 : 0.05)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    )
                IslandContentView(model: model)
                    .frame(width: w, height: h, alignment: .top)
                    .clipShape(IslandShape(bottomRadius: CGFloat(size.bottomRadius), shoulder: 0))
            }
            .frame(width: w + 2 * shoulder, height: h)
            .contentShape(shape)
            .onTapGesture { model.islandClicked() }
            // Arrastrar un archivo al notch: ORBEX lo "traga" y abre el asistente con el archivo adjunto (informe §5.7).
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                model.receiveDroppedFiles(providers)
            }
            .shadow(color: Color.black.opacity(expanded ? 0.5 : 0), radius: expanded ? 20 : 0, y: expanded ? 10 : 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.orbexTheme, model.themeStyle)
        .ignoresSafeArea()
    }
}

/// Contenido según el estado de la isla.
struct IslandContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        let nh = CGFloat(model.notch.height)
        let size = model.islandSize
        let wing = (CGFloat(size.width) - CGFloat(model.notch.width)) / 2

        ZStack(alignment: .top) {
            switch model.islandState {
            case .hidden, .clock:
                HiddenPulseView(enabled: model.settings.hiddenPulse && !theme.reduceMotion)
            case .peek:
                PeekContent(model: model, notchHeight: nh, sleeping: false)
            case .sleeping:
                PeekContent(model: model, notchHeight: nh, sleeping: true)
            case .active:
                WingsContent(model: model, notchHeight: nh, wing: wing, attention: false)
            case .needsYou:
                WingsContent(model: model, notchHeight: nh, wing: wing, attention: true)
            case .open:
                IslandOpenView(model: model, notchHeight: nh, wing: wing)
            case .assistant:
                AssistantPanelView()
            }
            if let toast = model.toast, model.islandState != .open, model.islandState != .assistant {
                ToastView(toast: toast)
                    .padding(.top, nh + 1)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(theme.spring, value: model.islandState)
    }
}

// MARK: - Oculto

/// Latido casi imperceptible en reposo (informe §4.4): un brillo muy tenue en el borde inferior.
struct HiddenPulseView: View {
    let enabled: Bool
    @State private var on = false

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Capsule()
                .fill(Color.white.opacity(enabled && on ? 0.09 : 0.0))
                .frame(height: 1)
                .padding(.horizontal, 14)
        }
        .onAppear {
            guard enabled else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

// MARK: - Asomado / dormido

struct PeekContent: View {
    @ObservedObject var model: AppModel
    let notchHeight: CGFloat
    let sleeping: Bool

    var body: some View {
        let d: CGFloat = 22
        ZStack(alignment: .top) {
            // La esfera asoma desde abajo del notch: se ve el techo y los ojos.
            OrbexPeekView(diameter: d, fps: min(30, model.characterFPS))
                .offset(y: notchHeight - d * 0.35)
            if sleeping {
                HStack {
                    Spacer()
                    SleepyZ()
                        .padding(.trailing, 3)
                        .padding(.top, notchHeight - 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct SleepyZ: View {
    @State private var up = false
    var body: some View {
        Text("z")
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.white.opacity(up ? 0.1 : 0.7))
            .offset(y: up ? -4 : 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) { up = true }
            }
    }
}

// MARK: - Trabajando / te necesita

struct WingsContent: View {
    @ObservedObject var model: AppModel
    let notchHeight: CGFloat
    let wing: CGFloat
    let attention: Bool
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Alita izquierda: ORBEX.
                OrbexPeekView(diameter: min(wing - 4, notchHeight - 6), fps: min(30, model.characterFPS))
                    .frame(width: wing, height: notchHeight)
                Spacer(minLength: 0)
                // Alita derecha: indicador.
                Group {
                    if attention {
                        AttentionBadge()
                    } else {
                        ActivitySpinner(color: theme.accent)
                    }
                }
                .frame(width: wing, height: notchHeight)
            }
            .frame(height: notchHeight)

            Text(statusText)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(attention ? Color(red: 1, green: 0.8, blue: 0.4) : theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }

    private var statusText: String {
        if !model.statusLine.isEmpty { return model.statusLine }
        return attention ? "Te necesito — tocá para ver" : "Trabajando…"
    }
}

struct ActivitySpinner: View {
    let color: Color
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.8)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

struct AttentionBadge: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 1, green: 0.62, blue: 0.2).opacity(pulse ? 0.15 : 0.45))
                .frame(width: pulse ? 20 : 12, height: pulse ? 20 : 12)
            Circle()
                .fill(Color(red: 1, green: 0.66, blue: 0.24))
                .frame(width: 12, height: 12)
            Text("!")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(Color.black)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

// MARK: - Aviso corto

struct ToastView: View {
    let toast: OrbexBus.Toast
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: toast.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.accent)
            Text(toast.text)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }
}

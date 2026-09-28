import SwiftUI
import OrbexCore

/// Isla abierta (home): hora en las alitas, páginas y contenido.
struct IslandOpenView: View {
    @ObservedObject var model: AppModel
    let notchHeight: CGFloat
    let wing: CGFloat
    @Environment(\.orbexTheme) private var theme

    /// Páginas disponibles. Las fases siguientes agregan las suyas acá
    /// (Fase 3: .sessions · Fase 6: .music, .integrations).
    private var pages: [IslandPage] { [.home, .sessions, .timers, .notes] }

    var body: some View {
        VStack(spacing: 0) {
            // Franja del notch: hora a la izquierda, ajustes a la derecha.
            HStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(width: wing, height: notchHeight)
                Spacer(minLength: 0)
                Button {
                    model.perform("settings")
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: wing, height: notchHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Configuración")
            }
            .frame(height: notchHeight)

            if pages.count > 1 {
                PageTabs(pages: pages, selection: $model.page)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
            }

            Group {
                switch model.page {
                case .home:
                    HomePageView(model: model)
                case .sessions:
                    SessionsPageView()
                case .timers:
                    TimersPageView()
                case .notes:
                    NotesPageView()
                default:
                    // Fases siguientes.
                    HomePageView(model: model)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .transition(.opacity)
        }
    }
}

struct PageTabs: View {
    let pages: [IslandPage]
    @Binding var selection: IslandPage
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(pages) { page in
                Button {
                    withAnimation(theme.softSpring) { selection = page }
                } label: {
                    Image(systemName: page.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selection == page ? theme.accent : theme.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(Color.white.opacity(selection == page ? 0.1 : 0))
                        )
                }
                .buttonStyle(.plain)
                .help(page.title)
            }
        }
    }
}

/// Página de inicio: ORBEX de cuerpo entero, saludo y acciones rápidas.
struct HomePageView: View {
    @ObservedObject var model: AppModel
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                OrbexView(fps: model.characterFPS, scale: CGFloat(model.settings.characterScale))
                    .frame(width: 96, height: 112)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Greeting.text(hour: Calendar.current.component(.hour, from: Date()),
                                       name: model.settings.userName))
                        .font(theme.titleFont)
                        .foregroundStyle(theme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                    }
                    Text(moodLine)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                OrbexActionButton(symbol: "sparkles", title: "Asistente") { model.perform("assistant") }
                OrbexActionButton(symbol: "timer", title: "Timer 5′") {
                    Task { @MainActor in
                        let result = await CommandExecutor.shared.execute(.timer(seconds: 300, label: nil))
                        OrbexBus.toast(result.message, symbol: "timer")
                    }
                }
                OrbexActionButton(symbol: "note.text.badge.plus", title: "Nota") { model.page = .notes }
                OrbexActionButton(symbol: "slider.horizontal.3", title: "Ajustes") { model.perform("settings") }
            }
        }
    }

    private var moodLine: String {
        switch model.brain.mood.pose {
        case .dance: return "Bailando con tu música ♪"
        case .focused: return "Concentrado con tu timer"
        default: return "Tocame, arrastrame un archivo o pedime algo."
        }
    }
}

import SwiftUI
import OrbexCore

/// Secciones de Configuración. Las de fases siguientes se suman cuando llegue su fase.
enum SettingsSection: String, CaseIterable, Identifiable {
    case personaje, isla, tema, sonidos, reloj, asistente, voz, vozOrbi, claudeCode, timers, notas, acciones, programadas, memoria, musica, integraciones, general, accesibilidad, acercaDe
    // Fase 6 / cierre: privacidad (qué ve ORBEX, qué se guarda, permisos de macOS)

    var id: Self { self }

    var title: String {
        switch self {
        case .personaje: return "Personaje"
        case .isla: return "Isla"
        case .tema: return "Tema"
        case .sonidos: return "Sonidos"
        case .reloj: return "Reloj"
        case .musica: return "Música"
        case .integraciones: return "Integraciones"
        case .programadas: return "Acciones programadas"
        case .memoria: return "Memoria"
        case .asistente: return "Asistente (Claude)"
        case .voz: return "Voz"
        case .vozOrbi: return "Voz de Orbi"
        case .claudeCode: return "Claude Code"
        case .timers: return "Timers"
        case .notas: return "Notas"
        case .acciones: return "Acciones y apps"
        case .general: return "General"
        case .accesibilidad: return "Accesibilidad y rendimiento"
        case .acercaDe: return "Acerca de"
        }
    }

    var symbol: String {
        switch self {
        case .personaje: return "face.smiling"
        case .isla: return "rectangle.topthird.inset.filled"
        case .tema: return "paintpalette"
        case .sonidos: return "speaker.wave.2"
        case .reloj: return "clock"
        case .musica: return "music.note"
        case .integraciones: return "square.grid.2x2"
        case .programadas: return "calendar.badge.clock"
        case .memoria: return "brain"
        case .asistente: return "sparkles"
        case .voz: return "waveform"
        case .vozOrbi: return "speaker.wave.2"
        case .claudeCode: return "terminal"
        case .timers: return "timer"
        case .notas: return "note.text"
        case .acciones: return "bolt.circle"
        case .general: return "gearshape"
        case .accesibilidad: return "accessibility"
        case .acercaDe: return "info.circle"
        }
    }
}

/// Raíz de la ventana de Configuración: barra lateral + vista previa en vivo + sección elegida.
/// Todo se guarda y se aplica solo: las secciones escriben en `AppModel.shared.settings`.
struct SettingsRootView: View {
    @ObservedObject var model = AppModel.shared
    @State private var selection: SettingsSection? = .personaje

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 280)
        } detail: {
            VStack(spacing: 0) {
                SettingsPreviewPanel()
                detail(for: selection ?? .personaje)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.orbexTheme, model.themeStyle)
        .frame(minWidth: 680, minHeight: 480)
    }

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        switch section {
        case .personaje: PersonajeSettingsView()
        case .isla: IslaSettingsView()
        case .tema: TemaSettingsView()
        case .sonidos: SonidosSettingsView()
        case .reloj: ClockSettingsView()
        case .musica: MusicSettingsView()
        case .integraciones: IntegrationsSettingsView()
        case .programadas: ScheduledActionsSettingsView()
        case .memoria: MemorySettingsView()
        case .asistente: AssistantSettingsView()
        case .voz: VozSettingsView()
        case .vozOrbi: VozSalidaSettingsView()
        case .claudeCode: ClaudeCodeSettingsView()
        case .timers: TimersSettingsView()
        case .notas: NotesSettingsView()
        case .acciones: ActionsSettingsView()
        case .general: GeneralSettingsView()
        case .accesibilidad: AccesibilidadSettingsView()
        case .acercaDe: AcercaDeSettingsView()
        }
    }
}

// MARK: - Vista previa en vivo

/// Estados de la isla que se pueden mirar en la vista previa.
private enum PreviewIslandState: String, CaseIterable, Identifiable {
    case hidden, peek, active, needsYou, open

    var id: Self { self }

    var state: IslandState {
        switch self {
        case .hidden: return .hidden
        case .peek: return .peek
        case .active: return .active
        case .needsYou: return .needsYou
        case .open: return .open
        }
    }

    var label: String {
        switch self {
        case .hidden: return "Oculto"
        case .peek: return "Asomado"
        case .active: return "Trabajando"
        case .needsYou: return "Te necesita"
        case .open: return "Abierto"
        }
    }
}

/// Panel oscuro arriba del detalle: ORBEX animado + la isla en miniatura.
/// Cualquier cambio de ajustes se ve al instante (color, nivel de vida, tamaño, alitas, tema…).
struct SettingsPreviewPanel: View {
    @ObservedObject var model = AppModel.shared
    @Environment(\.orbexTheme) private var theme
    @AppStorage("orbex.settings.previewCollapsed") private var collapsed = false
    @State private var previewState: PreviewIslandState = .peek

    var body: some View {
        VStack(spacing: 8) {
            if collapsed {
                HStack {
                    Text("Vista previa")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Spacer()
                    collapseButton
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    characterStage
                    VStack(spacing: 5) {
                        IslandMiniPreview(state: previewState.state)
                        Text(notchCaption)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .overlay(alignment: .topTrailing) {
                    collapseButton
                        .padding(4)
                }
                Picker("Estado de la isla", selection: $previewState) {
                    ForEach(PreviewIslandState.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(panelBackground)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private var collapseButton: some View {
        Button {
            withAnimation(theme.softSpring) { collapsed.toggle() }
        } label: {
            Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? "Mostrar la vista previa" : "Ocultar la vista previa")
    }

    private var characterStage: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(gradient: Gradient(colors: [theme.accent.opacity(0.22), Color.clear]),
                                     center: .center, startRadius: 4, endRadius: 70))
            // El marco es fijo y la escala va adentro: así el tamaño 130 % entra sin recortarse.
            OrbexView(showLimbs: true, paused: false, fps: model.characterFPS,
                      scale: CGFloat(model.settings.characterScale) * 0.85)
        }
        .frame(width: 136, height: 136)
        .help("Tocalo: se achata. Tres toques rápidos: se marea.")
    }

    private var notchCaption: String {
        let n = model.notch
        let kind = n.isHardware ? "real" : "simulado"
        return "Notch \(Int(n.width.rounded())) × \(Int(n.height.rounded())) pt · \(kind)"
    }

    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [Color(white: 0.10), Color(white: 0.03)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// La isla en miniatura sobre una "barra de menú" gris, calculada con la medida en vivo del notch.
struct IslandMiniPreview: View {
    @ObservedObject var model = AppModel.shared
    @Environment(\.orbexTheme) private var theme
    let state: IslandState

    /// Alto del área de la vista previa.
    private let areaHeight: CGFloat = 116

    var body: some View {
        GeometryReader { geo in
            let k = scale(forWidth: geo.size.width)
            let size = model.size(for: state)
            let shoulder = CGFloat(size.shoulderRadius) * k
            let shapeW = CGFloat(size.width) * k + 2 * shoulder
            let shapeH = CGFloat(size.height) * k
            let barH = CGFloat(model.notch.height) * k

            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.17, green: 0.22, blue: 0.36),
                                        Color(red: 0.30, green: 0.20, blue: 0.40)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                menuBar(height: barH)
                OrbexIslandShape(bottomRadius: CGFloat(size.bottomRadius) * k, shoulder: shoulder)
                    .fill(Color.black)
                    .overlay {
                        islandContent(size: size, k: k, width: shapeW, height: shapeH)
                    }
                    .clipShape(OrbexIslandShape(bottomRadius: CGFloat(size.bottomRadius) * k, shoulder: shoulder))
                    .frame(width: shapeW, height: shapeH)
                    .mask(alignment: .top) {
                        // El estado "abierto" es más alto que la vista previa: se desvanece abajo.
                        LinearGradient(gradient: Gradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.8),
                            .init(color: state == .open ? Color.clear : Color.black, location: 1),
                        ]), startPoint: .top, endPoint: .bottom)
                        .frame(height: areaHeight)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .frame(height: areaHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(theme.spring, value: model.size(for: state))
        .animation(theme.spring, value: state)
    }

    /// Escala fija para todos los estados (así el cambio de estado no salta).
    /// El ancho considera todos; el alto, todos menos "abierto" (que se recorta con un desvanecido).
    private func scale(forWidth width: CGFloat) -> CGFloat {
        var maxW = 1.0
        var maxH = 1.0
        for s in PreviewIslandState.allCases {
            let z = model.size(for: s.state)
            maxW = max(maxW, z.width + 2 * z.shoulderRadius)
            if s.state != .open { maxH = max(maxH, z.height) }
        }
        let byWidth = (width - 12) / CGFloat(maxW)
        let byHeight = (areaHeight - 16) / CGFloat(maxH)
        return max(0.2, min(1, byWidth, byHeight))
    }

    private func menuBar(height: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "apple.logo")
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.75")
        }
        .font(.system(size: max(6, height * 0.36)))
        .foregroundStyle(Color.white.opacity(0.75))
        .padding(.horizontal, 8)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.34))
    }

    /// Lo que se ve adentro de la isla en cada estado (orientativo).
    @ViewBuilder
    private func islandContent(size: IslandSize, k: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        let shoulder = CGFloat(size.shoulderRadius) * k
        let notchW = CGFloat(model.notch.width) * k
        let notchH = CGFloat(model.notch.height) * k
        let wing = max(0, (width - 2 * shoulder - notchW) / 2)
        let leftX = shoulder + wing / 2
        let rightX = width - shoulder - wing / 2
        let bandY = notchH + max(0, height - notchH) / 2

        ZStack {
            switch state {
            case .hidden:
                if model.settings.hiddenPulse && !theme.reduceMotion {
                    PhaseAnimator([0.12, 0.55]) { phase in
                        Capsule()
                            .fill(theme.accent.opacity(phase))
                            .frame(width: notchW * 0.35, height: 2)
                    } animation: { _ in
                        .easeInOut(duration: 1.8)
                    }
                    .position(x: width / 2, y: max(2, height - 3))
                }
            case .peek:
                HStack(spacing: 4 * k) {
                    Capsule().fill(Color.white).frame(width: 3 * k, height: 6 * k)
                    Capsule().fill(Color.white).frame(width: 3 * k, height: 6 * k)
                }
                .position(x: width / 2, y: bandY)
            case .active, .needsYou:
                if wing > 6 {
                    OrbexPeekView(diameter: min(wing, notchH) * 0.8, fps: 30)
                        .position(x: leftX, y: notchH / 2)
                }
                if state == .active {
                    Image(systemName: "ellipsis")
                        .font(.system(size: max(6, 11 * k), weight: .bold))
                        .foregroundStyle(theme.accent)
                        .symbolEffect(.variableColor.iterative, isActive: !theme.reduceMotion)
                        .position(x: rightX, y: notchH / 2)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: max(6, 12 * k), weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .symbolEffect(.pulse, isActive: !theme.reduceMotion)
                        .position(x: rightX, y: notchH / 2)
                }
                Text(state == .active ? "Trabajando…" : "Te necesita")
                    .font(.system(size: max(6, 9 * k), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                    .position(x: width / 2, y: bandY)
            case .open:
                OrbexView(showLimbs: true, paused: false, fps: 30)
                    .frame(width: 62 * k, height: 62 * k)
                    .position(x: width / 2, y: notchH + 38 * k)
                VStack(spacing: 5 * k) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 6 * k, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 16 * k)
                    }
                }
                .frame(width: max(10, width - 2 * shoulder - 36 * k))
                .position(x: width / 2, y: notchH + 110 * k)
            default:
                EmptyView()
            }
        }
        .frame(width: width, height: height)
    }
}

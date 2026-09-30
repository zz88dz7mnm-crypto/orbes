import AppKit
import SwiftUI
import OrbexCore

/// Una línea de la conversación del panel (de la voz o de lo escrito).
struct SmartTurn: Identifiable, Equatable {
    let id: String
    let isUser: Bool
    let text: String
    let date: Date
    var live = false
}

// MARK: - Raíz

/// Contenido del panel del modo inteligente: forma de vidrio que se despliega desde el notch,
/// la cara de Orbi, la conversación, "Memoria", "Acciones rápidas" y la barra para hablar o escribir.
struct SmartModeRootView: View {
    @ObservedObject var controller: SmartModeController
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var conversation = VoiceConversation.shared
    @ObservedObject private var voice = VoiceController.shared
    @ObservedObject private var assistant = AssistantStore.shared
    @State private var orbiSpeaking = false

    private static let margin: CGFloat = 14

    var body: some View {
        let theme = model.themeStyle
        let reduce = theme.reduceMotion
        GeometryReader { geo in
            let full = CGRect(x: Self.margin, y: 0, width: geo.size.width - 2 * Self.margin,
                              height: geo.size.height - Self.margin)
            let progress: CGFloat = controller.expanded ? 1 : 0
            let shape = SmartMorphShape(progress: progress, from: controller.notchLocal, to: full)
            ZStack(alignment: .topLeading) {
                background(shape: shape, theme: theme)
                content
                    .frame(width: full.width, height: full.height)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .opacity(controller.expanded ? 1 : 0)
                    .scaleEffect(controller.expanded || reduce ? 1 : 0.94, anchor: .top)
                    .animation(reduce ? .easeOut(duration: 0.15)
                               : .easeOut(duration: controller.expanded ? 0.28 : 0.12).delay(controller.expanded ? 0.1 : 0),
                               value: controller.expanded)
                    .clipShape(shape)
            }
            .animation(reduce ? .easeOut(duration: 0.18) : .spring(response: 0.5, dampingFraction: 0.78),
                       value: controller.expanded)
        }
        .environment(\.orbexTheme, theme)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("orbex.voice.speaking"))) { note in
            orbiSpeaking = (note.object as? Bool) ?? false
        }
    }

    @ViewBuilder
    private func background(shape: SmartMorphShape, theme: ThemeStyle) -> some View {
        ZStack {
            if theme.glassAllowed {
                SmartBlurView()
                Color.black.opacity(0.38 + 0.3 * theme.glassTint)
            } else {
                Color(red: 0.05, green: 0.055, blue: 0.075)
            }
            // Reflejo de vidrio arriba y un rastro del color de la fase abajo.
            LinearGradient(colors: [Color.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center)
            RadialGradient(colors: [phaseColor.opacity(0.16), .clear], center: .init(x: 0.3, y: 0.45),
                           startRadius: 10, endRadius: 320)
                .animation(.easeInOut(duration: 0.4), value: facePhase)
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(controller.expanded ? 0.45 : 0), radius: 18, y: 8)
    }

    private var phaseColor: Color {
        let g = facePhase.glow
        return Color(red: g.r, green: g.g, blue: g.b)
    }

    // MARK: - Fase de la cara

    private var facePhase: SmartFacePhase {
        switch conversation.phase {
        case .listening: return .listening
        case .thinking: return .thinking
        case .speaking: return .speaking
        default: break
        }
        if voice.phase == .listeningCommand { return .listening }
        if orbiSpeaking { return .speaking }
        if voice.phase == .working || assistant.isStreaming || assistant.isRunningCommand { return .thinking }
        return .idle
    }

    // MARK: - Contenido

    private var content: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    ZStack(alignment: .bottom) {
                        SmartFaceView(phase: facePhase, levels: controller.levels, paused: !controller.isActive)
                            .frame(height: 176)
                        SmartPhaseChip(phase: facePhase)
                            .offset(y: 6)
                    }
                    .frame(height: 188)
                    SmartConversationView(turns: turns, partial: partialText, thinking: facePhase == .thinking)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    SmartMemoryCard(controller: controller)
                    SmartActionsCard(controller: controller)
                }
                .frame(width: 214)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            SmartInputBar(controller: controller, listening: facePhase == .listening, orbiSpeaking: orbiSpeaking)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .foregroundStyle(.white)
    }

    /// Franja del notch: título a la izquierda, cerrar a la derecha (el medio es la cámara).
    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(phaseColor)
                Text("Modo inteligente")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            Spacer(minLength: controller.notchLocal.width + 24)
            Button {
                controller.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help("Cerrar (Esc) · también: \"Orbi, desactivar modo inteligente\"")
            .accessibilityLabel("Cerrar modo inteligente")
        }
        .padding(.horizontal, 18)
        .frame(height: max(28, controller.topInset))
    }

    // MARK: - Conversación (voz + escrito)

    private var turns: [SmartTurn] {
        var all: [SmartTurn] = conversation.turns.map { t in
            let isUser: Bool
            if case .user = t.role { isUser = true } else { isUser = false }
            return SmartTurn(id: "v-\(t.id)", isUser: isUser, text: t.text, date: t.date)
        }
        let messages = assistant.messages
        if messages.count > controller.assistantBaseCount {
            for m in messages[controller.assistantBaseCount...] where !m.text.isEmpty || m.isStreaming {
                all.append(SmartTurn(id: "a-\(m.id)", isUser: m.role == .user, text: m.text, date: m.date,
                                     live: m.isStreaming))
            }
        }
        return all.sorted { $0.date < $1.date }
    }

    private var partialText: String {
        let p = conversation.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty { return p }
        return voice.phase == .listeningCommand ? voice.liveText : ""
    }
}

// MARK: - Forma que se despliega

/// Del rectángulo del notch (píldora) al panel entero. Arriba casi recto (cuelga del borde de la
/// pantalla, como la isla), abajo bien redondeado.
struct SmartMorphShape: Shape {
    var progress: CGFloat
    let from: CGRect
    let to: CGRect

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = progress
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        let r = CGRect(x: lerp(from.minX, to.minX), y: lerp(from.minY, to.minY),
                       width: max(1, lerp(from.width, to.width)), height: max(1, lerp(from.height, to.height)))
        let bottom = min(r.height / 2, lerp(from.height / 2, 30))
        let top = min(r.height / 2, lerp(4, 14))
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom, topTrailingRadius: top,
                                      style: .continuous).path(in: r)
    }
}

/// Desenfoque del escritorio detrás del panel (vidrio de verdad).
struct SmartBlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Piezas

struct SmartPhaseChip: View {
    let phase: SmartFacePhase

    var body: some View {
        let g = phase.glow
        HStack(spacing: 5) {
            Image(systemName: phase.symbol)
                .font(.system(size: 9, weight: .bold))
            Text(phase.label)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
        }
        .foregroundStyle(Color(red: g.r, green: g.g, blue: g.b))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.25), value: phase)
    }
}

/// Conversación en vivo: burbujas de vidrio, lo que vas diciendo en cursiva y autoscroll.
struct SmartConversationView: View {
    let turns: [SmartTurn]
    let partial: String
    let thinking: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 7) {
                    if turns.isEmpty && partial.isEmpty {
                        Text("Hablame o escribime abajo. Probá: «¿qué hora es?», «poné un timer de 10 minutos», «acordate que mañana juego al pádel».")
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            .padding(.top, 18)
                            .padding(.horizontal, 20)
                    }
                    ForEach(turns) { turn in
                        SmartBubble(text: turn.text, isUser: turn.isUser, live: turn.live, partial: false)
                            .id(turn.id)
                    }
                    if !partial.isEmpty {
                        SmartBubble(text: partial, isUser: true, live: true, partial: true)
                            .id("partial")
                    }
                    if thinking && partial.isEmpty && !(turns.last.map { !$0.isUser && $0.live } ?? false) {
                        SmartBubble(text: "…", isUser: false, live: true, partial: true)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 6)
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                         .init(color: .black, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onChange(of: turns.count) { _, _ in scroll(proxy) }
            .onChange(of: turns.last?.text) { _, _ in scroll(proxy) }
            .onChange(of: partial) { _, _ in scroll(proxy) }
            .onAppear { scroll(proxy, animated: false) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

struct SmartBubble: View {
    let text: String
    let isUser: Bool
    let live: Bool
    let partial: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isUser { Spacer(minLength: 50) }
            if !isUser {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.9), Color(red: 0.62, green: 0.74, blue: 0.95).opacity(0.5)],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 9))
                    .frame(width: 14, height: 14)
                    .padding(.bottom, 4)
            }
            Text(text)
                .font(.system(size: 12.5, design: .rounded))
                .italic(partial)
                .foregroundStyle(.white.opacity(partial ? 0.7 : 0.94))
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isUser ? Color(red: 0.878, green: 0.251, blue: 0.984).opacity(partial ? 0.12 : 0.22)
                                     : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(live ? 0.22 : 0.1),
                                style: StrokeStyle(lineWidth: 0.8, dash: partial ? [3, 3] : []))
                )
            if !isUser { Spacer(minLength: 50) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

/// Tarjeta de vidrio de las columnas de la derecha.
struct SmartCard<Content: View>: View {
    let title: String
    let symbol: String
    var trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                Spacer()
                if let trailing {
                    Text(trailing).font(.system(size: 10, design: .rounded)).foregroundStyle(.white.opacity(0.45))
                }
            }
            .foregroundStyle(.white.opacity(0.85))
            content
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 0.6))
    }
}

/// "Memoria": lo que Orbi recuerda (`MemoryStore`). Clic derecho → olvidar.
struct SmartMemoryCard: View {
    @ObservedObject var controller: SmartModeController
    @ObservedObject private var memory = MemoryStore.shared

    var body: some View {
        let facts = memory.facts.sorted { $0.createdAt > $1.createdAt }
        SmartCard(title: "Memoria", symbol: "brain", trailing: facts.isEmpty ? nil : "\(facts.count)") {
            if facts.isEmpty {
                Text("Todavía no recuerdo nada. Decime «Orbi, acordate que…».")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(facts) { fact in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Circle().fill(Color.white.opacity(0.4)).frame(width: 4, height: 4)
                                Text(fact.text)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .contextMenu {
                                Button("Olvidar esto", role: .destructive) { controller.forget(fact.id) }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// "Acciones rápidas": disparan comandos existentes de ORBEX (`CommandExecutor`) o preparan la frase.
struct SmartActionsCard: View {
    @ObservedObject var controller: SmartModeController

    var body: some View {
        SmartCard(title: "Acciones rápidas", symbol: "bolt.fill") {
            let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
            LazyVGrid(columns: columns, spacing: 6) {
                action("Timer", "timer") { controller.run(.timer(seconds: 0, label: nil)) }
                action("Nota", "note.text") {
                    let text = controller.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty {
                        controller.prefill("anotá ")
                    } else {
                        controller.draft = ""
                        controller.run(.note(text: text))
                    }
                }
                action("Abrir app", "square.grid.2x2") { controller.prefill("abrí ") }
                action("Reloj", "clock") { controller.run(.showClock) }
                action("Recordar", "brain.head.profile") { controller.prefill("acordate que ") }
                action("Pomodoro", "leaf") { controller.run(.pomodoro) }
            }
        }
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        SmartActionButton(title: title, symbol: symbol, run: run)
    }
}

struct SmartActionButton: View {
    let title: String
    let symbol: String
    let run: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: run) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                Text(title).font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.14 : 0.07)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

/// Barra de abajo: micrófono grande, campo para escribir, silenciar a Orbi y el motor de voz.
struct SmartInputBar: View {
    @ObservedObject var controller: SmartModeController
    let listening: Bool
    let orbiSpeaking: Bool
    @FocusState private var focused: Bool
    @State private var pulse = false
    @Environment(\.orbexTheme) private var theme

    private static let magenta = Color(red: 0.878, green: 0.251, blue: 0.984)

    var body: some View {
        HStack(spacing: 10) {
            Button { controller.talk() } label: {
                ZStack {
                    if listening && !theme.reduceMotion {
                        Circle().stroke(Self.magenta.opacity(0.5), lineWidth: 2)
                            .scaleEffect(pulse ? 1.35 : 1)
                            .opacity(pulse ? 0 : 1)
                    }
                    Circle().fill(listening ? Self.magenta : Color.white.opacity(0.12))
                    Image(systemName: listening ? "waveform" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .help(listening ? "Terminar de hablar" : "Hablar (sin decir «Orbi»)")
            .accessibilityLabel(listening ? "Terminar de hablar" : "Hablar")
            .onChange(of: listening) { _, on in
                pulse = false
                guard on, !theme.reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true }
            }

            TextField("Escribile a Orbi…", text: $controller.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .rounded))
                .focused($focused)
                .onSubmit { controller.send(controller.draft) }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().stroke(Color.white.opacity(focused ? 0.28 : 0.1), lineWidth: 0.8))
                .onChange(of: controller.focusTick) { _, _ in focused = true }

            Button { controller.send(controller.draft) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 24))
                    .foregroundStyle(.white.opacity(controller.draft.isEmpty ? 0.25 : 0.9))
            }
            .buttonStyle(.plain)
            .disabled(controller.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Enviar")

            Button { controller.orbiMuted.toggle() } label: {
                Image(systemName: controller.orbiMuted ? "speaker.slash.fill"
                      : (orbiSpeaking ? "speaker.wave.2.fill" : "speaker.wave.1.fill"))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(controller.orbiMuted ? 0.16 : 0.08)))
            }
            .buttonStyle(.plain)
            .help(controller.orbiMuted ? "Volver a escuchar a Orbi" : "Silenciar la voz de Orbi")
            .accessibilityLabel(controller.orbiMuted ? "Activar voz de Orbi" : "Silenciar voz de Orbi")

            HStack(spacing: 5) {
                Circle()
                    .fill(controller.orbiMuted ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                Text(controller.orbiMuted ? "Voz silenciada" : controller.voiceBackendLabel)
                    .font(.system(size: 10, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: 120, alignment: .leading)
            .help("Motor de la voz de Orbi")
        }
    }
}

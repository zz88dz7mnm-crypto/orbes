// Basado en Coucou (https://github.com/louis-cfm/coucou) © 2026 Louis Raillé — licencia MIT.
// Modificado para ORBEX (solo el código; ningún asset de Coucou). Ver THIRD_PARTY_NOTICES.md.

import SwiftUI
import OrbexCore

// MARK: - Dispatch view content by IslandView

struct IslandViewContent: View {
    let view: IslandView
    @ObservedObject var state: AppState

    var body: some View {
        switch view {
        case .overview:  OverviewView(state: state)
        case .empty:     EmptyStateView(state: state)
        case .approval:  ApprovalView(state: state)
        case .question:  QuestionView(state: state)
        case .error:     ErrorView(state: state)
        case .finished:  FinishedView(state: state)
        case .confused:  ConfusedView()
        case .upload:    UploadView(state: state)
        case .uploading: UploadingView(state: state)
        case .choose:    ChooseView(state: state)
        case .prompt:    PromptView(state: state)
        case .searching: SearchingView(state: state)
        case .result:    ResultView(state: state)
        case .note:      NoteView(state: state)
        case .settings:  SettingsIslandView(state: state)
        case .greeting:  EmptyView()  // GreetingCanvasView overlaid in IslandRootView
        case .timers, .notes, .music: EmptyView()  // ORBEX: se dibujan en IslandContentView (IslandRootView.swift)
        }
    }
}

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var state: AppState

    var agent: AgentTask? { state.focusTask }

    var body: some View {
        HStack(spacing: 10) {
            // Left card: title row + ticker below + ↗ button overlay
            ZStack(alignment: .topLeading) {
                CardBackground(wash: nil)

                // Title row + ticker stacked (or integration card)
                if let agent = agent {
                    if agent.isIntegration {
                        IntegrationCardView(task: agent)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: agent.color))
                                    .frame(width: 7, height: 7)
                                Text(agent.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(hex: "#F5F6F8"))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .layoutPriority(1)
                                Text(agent.source == .claudeCode ? "Claude Code" : "Integración")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#8E939C"))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 2)
                                if agent.steps.count > 1 {
                                    Text("\(min(agent.stepIndex + 1, agent.steps.count))/\(agent.steps.count)")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(hex: "#6B7079"))
                                        .fixedSize()
                                }
                            }
                            .padding(.top, 6)
                            .padding(.leading, 108)
                            .padding(.trailing, 36)

                            TickerView(task: agent)
                                .frame(height: 44)
                                .padding(.top, 6)
                                .padding(.leading, 108)
                                .padding(.trailing, 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, 4)
                    }
                }

                // ↗ saltar a la terminal / al servicio — último en el ZStack para quedar arriba
                Button(action: { openAgentTarget(agent) }) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(hex: "#5F646D"))
                        .frame(width: 16, height: 16)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: 322)

            // Right card: agent pills
            CardBackground(wash: nil) {
                VStack(spacing: 4) {
                    TimerSummaryRow()   // ORBEX: timers corriendo (no ocupa lugar si no hay)
                    AgentPillsView(state: state)
                }
            }
        }
    }

    private func openAgentTarget(_ task: AgentTask?) {
        guard let task else { return }
        switch task.id {
        case "integration_claude":
            // La terminal (o el editor) donde corre Claude Code.
            SessionsBridge.shared.jumpToTerminal()
        case "integration_stripe":
            NSWorkspace.shared.open(URL(string: "https://dashboard.stripe.com/payments")!)
        case "integration_notion":
            NSWorkspace.shared.open(URL(string: "https://notion.so")!)
        case "integration_calcom":
            NSWorkspace.shared.open(URL(string: "https://app.cal.com/bookings")!)
        default:
            // Pastilla de una sesión de Claude Code: saltar a su pestaña exacta.
            if let sid = SessionsBridge.sessionID(fromTask: task.id) {
                SessionsBridge.shared.jumpToTerminal(sessionID: sid)
                return
            }
            // Otra tarea: traer la terminal que esté abierta.
            #if !APPSTORE
            let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2",
                                     "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
            if let hit = terminalBundleIds.compactMap({ id in
                NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
            }).first {
                hit.activate(options: .activateIgnoringOtherApps)
            }
            #endif
        }
    }
}

// MARK: - Empty

struct EmptyStateView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No hay nada corriendo ahora.")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Soltá un archivo o una ventana, o preguntame lo que quieras.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#9398A1"))
                }
                Spacer()
                PrimaryButton("Preguntarle a Claude") {
                    state.view = .prompt
                }
            }
            .padding(.leading, 118)
            .padding(.trailing, 18)
        }
    }
}

// MARK: - Approval

/// ORBEX: permiso pendiente de Claude Code / Codex (el primero de la cola de `SessionsStore`).
/// Permitir / Siempre (con segunda confirmación) / Denegar: nada se aprueba sin un clic.
struct ApprovalView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = SessionsStore.shared
    @State private var confirmingAlways = false

    private var bridge: SessionsBridge { SessionsBridge.shared }
    private var approval: PendingApproval? { store.approvals.first }

    var body: some View {
        if approval?.event.isQuestion == true || (approval == nil && bridge.questionSession != nil) {
            QuestionView(state: state)
        } else if let approval {
            content(approval)
        } else {
            terminalFallback
        }
    }

    private func content(_ a: PendingApproval) -> some View {
        let e = a.event
        let tool = e.toolName ?? "Herramienta"
        let project = e.projectName
        return ZStack {
            CardBackground(wash: .amber)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    AgentWho(task: bridge.task(forSession: e.sessionID) ?? state.focusTask,
                             label: "necesita tu permiso")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if store.approvals.count > 1 {
                        Text("1 de \(store.approvals.count)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .fixedSize()
                    }
                    TerminalLinkButton { bridge.jumpToTerminal(sessionID: e.sessionID) }
                }
                HStack(alignment: .top, spacing: 6) {
                    Text(tool)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5A524"))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color(hex: "#F5A524").opacity(0.14))
                        .clipShape(Capsule())
                        .fixedSize()
                    CodeBlock(text: e.toolInputSummary ?? e.message ?? e.stepDescription)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                HStack(spacing: 8) {
                    SecondaryButton("Denegar") {
                        confirmingAlways = false
                        bridge.decide(.deny)
                    }
                    PrimaryButton("Permitir") {
                        confirmingAlways = false
                        bridge.decide(.allow)
                    }
                    if confirmingAlways {
                        PrimaryButton("¿Seguro? Confirmar") {
                            confirmingAlways = false
                            bridge.decide(.allowAlways)
                        }
                        .help("Permitir siempre \(tool) en \(project), sin volver a preguntar")
                    } else {
                        SecondaryButton("Siempre") {
                            confirmingAlways = true
                            let id = a.id
                            // La confirmación vence sola: un clic distraído no queda armado.
                            let flag = $confirmingAlways
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                MainActor.assumeIsolated {
                                    if SessionsStore.shared.approvals.first?.id == id { flag.wrappedValue = false }
                                }
                            }
                        }
                        .help("Permitir siempre \(tool) en \(project) (te pido confirmación)")
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: a.id) { _, _ in confirmingAlways = false }
    }

    /// Sin permiso en la cola: Claude pregunta en su terminal (el hook no respondió a tiempo).
    private var terminalFallback: some View {
        let s = store.sessions.first { $0.status == .needsPermission }
        return ZStack {
            CardBackground(wash: .amber)
            VStack(alignment: .leading, spacing: 6) {
                AgentWho(task: s.flatMap { bridge.task(forSession: $0.id) } ?? state.focusTask,
                         label: s == nil ? "Claude Code" : "necesita tu permiso")
                Text(s == nil ? "No hay permisos pendientes." : "Te está pidiendo permiso en la terminal.")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 8) {
                    if let s {
                        PrimaryButton("Ir a la terminal") { bridge.jumpToTerminal(sessionID: s.id) }
                    }
                    SecondaryButton("Cerrar") {
                        state.isPinned = false
                        OrbexBridge.shared.close()
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// ORBEX: botoncito "Ir a la terminal" de las vistas de sesión.
struct TerminalLinkButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .semibold))
                Text("Ir a la terminal")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(Color(hex: "#C9CCD2"))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.white.opacity(0.07))
            .clipShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .help("Saltar a la terminal de esta sesión")
    }
}

// MARK: - Question

/// ORBEX: pregunta de Claude (`AskUserQuestion`). Se muestra la pregunta y sus opciones, pero se
/// contesta en la terminal: ORBEX nunca elige por vos.
struct QuestionView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = SessionsStore.shared

    private var bridge: SessionsBridge { SessionsBridge.shared }

    var body: some View {
        let approval = store.approvals.first.flatMap { $0.event.isQuestion ? $0 : nil }
        let session = approval == nil ? bridge.questionSession : nil
        let sessionID = approval?.event.sessionID ?? session?.id
        let askedStep: SessionStep? = session?.steps.last(where: { $0.text.hasPrefix("Pregunta") })
        var askedText: String? = nil
        if let step = askedStep {
            askedText = step.text.hasPrefix("Pregunta: ") ? String(step.text.dropFirst("Pregunta: ".count)) : step.text
        }
        let question: String = approval?.event.toolInputSummary ?? askedText ?? "Claude te está preguntando algo."
        let options = approval?.event.questionOptions ?? []

        return ZStack {
            CardBackground(wash: .cyan)
            VStack(alignment: .leading, spacing: 6) {
                AgentWho(task: sessionID.flatMap { bridge.task(forSession: $0) } ?? state.focusTask,
                         label: "te pregunta")
                    .lineLimit(1)
                Text(question)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                if !options.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(options.prefix(3).enumerated()), id: \.offset) { _, opt in
                            Text(opt)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundColor(Color(hex: "#C9CCD2"))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.white.opacity(0.07))
                                .clipShape(Capsule())
                        }
                        if options.count > 3 {
                            Text("+\(options.count - 3)")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#8E939C"))
                                .fixedSize()
                        }
                    }
                }
                HStack(spacing: 8) {
                    PrimaryButton("Responder en la terminal") { bridge.answerInTerminal() }
                    Text("ORBEX no elige por vos.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Error

/// ORBEX: una sesión se detuvo por un error (datos reales de la sesión).
struct ErrorView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var bridge = SessionsBridge.shared

    var body: some View {
        let s = bridge.endedSession(for: .failed)
        let task = s.flatMap { bridge.task(forSession: $0.id) } ?? state.focusTask
        let detail = s?.steps.last?.text ?? task?.steps.last ?? "Se detuvo por un error."
        let prompt = s.flatMap { SessionsBridge.lastPrompt($0) }

        return ZStack {
            CardBackground(wash: .red)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: task, label: "se detuvo")
                    .lineLimit(1)
                Text(prompt.map { "No pudo terminar: \($0)" } ?? "No pudo terminar.")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#FF8D97"))
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    if let s {
                        PrimaryButton("Ir a la terminal") {
                            bridge.jumpToTerminal(sessionID: s.id)
                            OrbexBridge.shared.close()
                        }
                    }
                    SecondaryButton("Cerrar") { OrbexBridge.shared.close() }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Finished

/// ORBEX: una sesión terminó (qué se pidió, cuánto tardó y el último paso).
struct FinishedView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var bridge = SessionsBridge.shared

    var body: some View {
        let s = bridge.endedSession(for: .finished)
        let task = s.flatMap { bridge.task(forSession: $0.id) } ?? state.focusTask
        let prompt = s.flatMap { SessionsBridge.lastPrompt($0) }
        let work = s.flatMap { SessionsBridge.lastWork($0) }
        let duration = s.flatMap { SessionsBridge.durationText($0) }
        let title = prompt ?? work ?? task?.steps.last ?? "Listo"

        return ZStack {
            CardBackground(wash: .green)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: task, label: duration.map { "terminó en \($0)" } ?? "terminó")
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if prompt != nil, let work {
                    Text("Último paso: \(work)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: 8) {
                    if let s {
                        PrimaryButton("Ir a la terminal") {
                            bridge.jumpToTerminal(sessionID: s.id)
                            OrbexBridge.shared.close()
                        }
                    }
                    SecondaryButton("Listo") { OrbexBridge.shared.close() }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Confused

struct ConfusedView: View {
    var body: some View {
        ZStack {
            CardBackground(wash: .pink)
            VStack(alignment: .leading, spacing: 5) {
                Text("Demasiados toques de golpe.").font(.system(size: 15, weight: .semibold))
                Text("Dame un segundo: vuelvo en tres.")
                    .font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1"))
            }
            .padding(.leading, 128)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Upload (drop zone)

struct UploadView: View {
    @ObservedObject var state: AppState
    @State private var dashPhase: CGFloat = 0
    @State private var breathAngle: Double = 0
    // Timer only runs while this is the active tab — killed on deactivation
    @State private var animTimer: Timer? = nil

    private var borderOpacity: Double {
        let breathe = 0.11 + 0.04 * (sin(breathAngle) * 0.5 + 0.5)
        return state.fileDragOver ? 0.65 : breathe
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#0E0F11"))
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    state.fileDragOver
                        ? Color(hex: "#22C55E").opacity(borderOpacity)
                        : Color.white.opacity(borderOpacity),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5], dashPhase: dashPhase)
                )
            RoundedRectangle(cornerRadius: 20)
                .fill(RadialGradient(
                    colors: [Color(hex: "#22C55E").opacity(state.fileDragOver ? 0.13 : 0), Color.clear],
                    center: .bottom, startRadius: 0, endRadius: 200
                ))
            VStack(alignment: .leading, spacing: 8) {
                Text("Soltá tus archivos acá")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(state.fileDragOver ? Color(hex: "#34D399") : Color(hex: "#D5D7DB"))
                HStack(spacing: 6) {
                    ForEach(["PDF", "Imágenes", "Código", "Docs"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 11))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.07))
                            .foregroundColor(Color(hex: "#B9BDC4"))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.leading, 196)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: state.view) { _, newView in
            newView == .upload ? startTimer() : stopTimer()
        }
        .onAppear {
            if state.view == .upload { startTimer() }
        }
        .onDisappear { stopTimer() }
    }

    private func startTimer() {
        guard animTimer == nil else { return }
        // 20 fps — smooth enough for slow dash, 3× lighter than 60fps
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0/20.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                dashPhase  += 1.0          // 20 pt/s march
                breathAngle += 0.9 / 20.0  // advance sin phase at 0.9 rad/s
            }
        }
    }

    private func stopTimer() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

// MARK: - Uploading

struct UploadingView: View {
    @ObservedObject var state: AppState

    // Bar geometry in content coords (content has 10pt H padding each side).
    // Island bar: left=36, right=562 (640-78), width=526.
    // Content bar: left=26, width=526.
    // barTop=58 → island y = content_start(42)+58 = 100; bot cy=103 (center = barTop+3).
    private let barLeft: CGFloat  = 26
    private let barWidth: CGFloat = 526
    private let barTop: CGFloat   = 58

    var body: some View {
        // TimelineView fires at display refresh rate — progress derived from elapsed wall time,
        // not from @Published uploadProgress (which only flips to 1.0 at completion).
        TimelineView(.animation) { tl in
            let elapsed: Double = {
                guard let start = state.uploadStartTime else { return 0 }
                return tl.date.timeIntervalSince(start)
            }()
            let t        = min(1.0, max(0, elapsed / state.uploadDuration))
            let progress = CGFloat(t * (2 - t))          // ease-out quad
            let fillWidth = max(0, barWidth * progress)
            let isDone   = state.uploadProgress >= 0.999  // only true after handle() sets it

            ZStack(alignment: .topLeading) {
                // Background: dark base
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "#141518"))

                // Permanent green radial wash — brighter at completion
                RoundedRectangle(cornerRadius: 20)
                    .fill(RadialGradient(
                        colors: [Color(hex: "#34D399").opacity(isDone ? 0.28 : 0.14), Color.clear],
                        center: UnitPoint(x: 0.5, y: 1.4),
                        startRadius: 0,
                        endRadius: 260
                    ))

                // Bar track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.09))
                    .frame(width: barWidth, height: 6)
                    .offset(x: barLeft, y: barTop)

                // Bar fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#1FA87A"), Color(hex: "#34D399")],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: fillWidth, height: 6)
                    .offset(x: barLeft, y: barTop)

                // Glow trail behind dot leading edge
                if progress > 0.01 {
                    Ellipse()
                        .fill(Color(hex: "#6EE7B7").opacity(0.45))
                        .frame(width: 28, height: 12)
                        .blur(radius: 5)
                        .offset(x: barLeft + fillWidth - 14, y: barTop - 3)
                }

                // Text row — filename + % (above bar)
                HStack(spacing: 0) {
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#34D399"))
                        Text("  \(state.droppedFile?.name ?? "Archivo")")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Color(hex: "#34D399"))
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("Subiendo \(state.droppedFile?.name ?? "archivo")")
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(hex: "#A9ADB5"))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(Int(progress * 100)) %")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Color(hex: "#A9ADB5"))
                            .monospacedDigit()
                    }
                }
                .frame(width: barWidth)
                .offset(x: barLeft, y: barTop - 22)

                // Subtle top border (same as CardBackground)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.035), lineWidth: 1)
            }
        }
    }
}

// MARK: - Choose

struct ChooseView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                let fileName = state.droppedFile?.name ?? "archivo"
                (Text(fileName).font(.system(size: 14, weight: .semibold)) + Text(" está listo.").font(.system(size: 14, weight: .semibold)))
                Text("¿Qué querés hacer con el archivo?").font(.system(size: 12.5)).foregroundColor(Color(hex: "#9398A1"))
                PrimaryButton("Preguntar sobre esto") { state.view = .prompt }
            }
            .padding(.leading, 98)
            .padding(.trailing, 18)
        }
    }
}

// MARK: - Prompt (chat)

/// Chat de la isla: usa `AssistantStore` directo (comandos de ORBEX primero, después Claude por el CLI local).
struct PromptView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = AssistantStore.shared
    @FocusState private var focused: Bool
    /// Último contexto de ventana mandado (para no repetirlo en cada mensaje de la misma sesión).
    @State private var sentContextKey: String?

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .indigo)

            VStack(alignment: .leading, spacing: 6) {
                topBar
                content
                if let error = store.lastError, error.kind != .notInstalled || !store.messages.isEmpty {
                    ChatErrorBanner(failure: error, onRetry: { store.retry() })
                        .transition(.opacity)
                }
                if !store.pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(store.pendingAttachments, id: \.name) { a in
                                ChatAttachmentChip(name: a.name, bytes: a.bytes, truncated: a.truncated) {
                                    store.removeAttachment(named: a.name)
                                }
                            }
                        }
                    }
                }
                inputBar
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .overlay(alignment: .bottomLeading) {
            // Clawd acompaña a ORBEX mientras Claude responde.
            if showsClawd {
                ClaudePetView(mood: store.petMood, size: 24)
                    .padding(.leading, 40)
                    .padding(.bottom, 26)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: showsClawd)
        .animation(.easeOut(duration: 0.18), value: store.lastError)
        .padding(.bottom, 10)
        .dropDestination(for: URL.self) { urls, _ in
            var any = false
            for u in urls where store.attach(fileURL: u) { any = true }
            return any
        }
        .onAppear {
            store.panelDidAppear()
            attachDroppedFile(state.promptContext)
            focused = true
        }
        .onDisappear { store.panelDidDisappear() }
        .onChange(of: droppedFileURL) { _, _ in attachDroppedFile(state.promptContext) }
    }

    private var showsClawd: Bool {
        store.isStreaming || store.petMood != .idle
    }

    // MARK: Barra de arriba

    private var topBar: some View {
        HStack(spacing: 8) {
            if let ctx = state.promptContext, case .window = ctx {
                ContextChip(context: ctx)
            }
            Text(subtitle)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(store.isStreaming ? claudeOrange : Color(hex: "#6E737C"))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if !store.messages.isEmpty {
                Button {
                    store.newConversation()
                    sentContextKey = nil
                    focused = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#B0B5BE"))
                }
                .buttonStyle(.plain)
                .help("Nueva conversación (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .padding(.top, 2)
    }

    private var subtitle: String {
        if store.isStreaming { return store.statusNote ?? "Pensando…" }
        if store.isRunningCommand { return "ORBEX está en eso…" }
        switch store.cliStatus {
        case .missing: return "No encontré Claude Code"
        case .checking: return "Buscando Claude Code…"
        default:
            let m = store.model.isEmpty ? "" : " · \(store.model)"
            return "Claude vía Claude Code\(m)"
        }
    }

    // MARK: Conversación

    @ViewBuilder
    private var content: some View {
        if store.cliStatus == .missing && store.messages.isEmpty {
            ChatMissingCLIView(checking: store.cliStatus == .checking, onRetry: { store.refreshCLIStatus() })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if store.messages.isEmpty {
            ChatEmptyHints { suggestion in
                if suggestion.hasSuffix("…") {
                    store.draft = String(suggestion.dropLast()) + " "
                    focused = true
                } else {
                    store.send(suggestion)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(store.messages) { msg in
                            ChatBubble(message: msg,
                                       showsConfirmation: msg.needsConfirmation && store.pendingConfirmationID == msg.id,
                                       statusNote: msg.isStreaming ? store.statusNote : nil,
                                       onConfirm: { store.confirmPending() },
                                       onCancel: { store.cancelPending() })
                                .id(msg.id)
                        }
                        if store.isRunningCommand {
                            HStack { TypingDotsView(); Spacer(minLength: 32) }
                        }
                        Color.clear.frame(height: 1).id("fondo")
                    }
                    .padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo("fondo", anchor: .bottom) }
                .onChange(of: store.scrollTick) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("fondo", anchor: .bottom) }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: Entrada

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button(action: pickFiles) {
                Image(systemName: "paperclip")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#9398A1"))
            }
            .buttonStyle(.plain)
            .disabled(store.isStreaming)
            .help("Adjuntar archivo de texto")

            TextField(store.messages.isEmpty ? "Preguntale a Claude o pedile algo a ORBEX…" : "Seguí…",
                      text: $store.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { sendMessage() }

            Button {
                if store.isStreaming { store.stop() } else { sendMessage() }
            } label: {
                Image(systemName: store.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#0B0C0E"))
            }
            .buttonStyle(SendButtonStyle())
            .disabled(!store.isStreaming && !store.canSend(store.draft))
            .keyboardShortcut(store.isStreaming ? "." : "\r", modifiers: .command)
            .help(store.isStreaming ? "Cortar la respuesta (⌘.)" : "Enviar (↩)")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(claudeOrange.opacity(store.isStreaming ? 0.5 : 0), lineWidth: 1))
        .simultaneousGesture(TapGesture().onEnded { focused = true })
    }

    // MARK: Acciones

    private func sendMessage() {
        guard store.canSend(store.draft) else { return }
        store.sendDraft(context: pendingWindowContext())
        focused = true
    }

    /// El contexto de ventana se manda como DATO (adjunto envuelto), una vez por conversación y ventana.
    private func pendingWindowContext() -> ClaudeAttachment? {
        guard case .window(let app, let title, let url)? = state.promptContext else { return nil }
        let key = "\(app)|\(title)|\(url ?? "")"
        if key == sentContextKey && store.sessionID != nil { return nil }
        sentContextKey = key
        return AssistantStore.windowContext(app: app, title: title, url: url)
    }

    private var droppedFileURL: URL? {
        if case .file(_, let url)? = state.promptContext { return url }
        return nil
    }

    /// Archivo soltado sobre la isla → adjunto del asistente (y se limpia el contexto para no repetirlo).
    private func attachDroppedFile(_ ctx: PromptContext?) {
        guard case .file(_, let url?)? = ctx else { return }
        store.attach(fileURL: url)
        state.promptContext = nil
    }

    private func pickFiles() {
        for url in ChatClipboard.pickTextFiles() { store.attach(fileURL: url) }
        focused = true
    }
}

/// Un mensaje del chat: usuario (derecha), Claude (Markdown + herramientas) u ORBEX (comandos, errores).
struct ChatBubble: View {
    let message: ChatMessage
    var showsConfirmation: Bool = false
    var statusNote: String? = nil
    var onConfirm: () -> Void = {}
    var onCancel: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 32)
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(message.attachments) { a in
                        Label(a.name, systemImage: "doc.text")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(Color(hex: "#9398A1"))
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(hex: "#F1F2F4"))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    author
                    if !message.toolChips.isEmpty { ChatToolChips(chips: message.toolChips) }
                    if message.isStreaming && message.text.isEmpty {
                        HStack(spacing: 6) {
                            TypingDotsView(color: claudeOrange)
                            Text(statusNote ?? "Pensando…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "#9398A1"))
                                .lineLimit(1)
                        }
                    } else if !message.text.isEmpty {
                        ChatMarkdownText(text: message.text, streaming: message.isStreaming,
                                         color: message.isError ? Color(red: 1, green: 0.62, blue: 0.55)
                                                                : Color(hex: "#DADDE2"))
                            .textSelection(.enabled)
                    }
                    if showsConfirmation {
                        HStack(spacing: 8) {
                            Button("Confirmar", action: onConfirm)
                                .buttonStyle(.borderedProminent)
                                .tint(claudeOrange)
                            Button("Cancelar", action: onCancel)
                                .buttonStyle(.bordered)
                        }
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                    if let foot = message.footnote, !message.isStreaming, hovering {
                        Text(foot)
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "#6E737C"))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if hovering && !message.text.isEmpty && !message.isStreaming {
                        Button { ChatClipboard.copy(message.text) } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color(hex: "#B0B5BE"))
                        }
                        .buttonStyle(.plain)
                        .help("Copiar")
                    }
                }
                Spacer(minLength: 8)
            }
        }
        .onHover { hovering = $0 }
    }

    private var author: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(message.role == .assistant ? claudeOrange : Color(hex: "#A78BFA"))
                .frame(width: 5, height: 5)
            Text(message.role == .assistant ? "Claude" : "ORBEX")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(Color(hex: "#6E737C"))
            if let m = message.model, message.role == .assistant {
                Text("· \(m)")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#6E737C"))
                    .lineLimit(1)
            }
        }
    }
}

struct TypingDotsView: View {
    var color: Color = Color(hex: "#6B7079")
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: theme.reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .offset(y: theme.reduceMotion ? 0 : -3 * max(0, sin(t * 6 - Double(i) * 0.7)))
                }
            }
        }
        .frame(height: 10)
        .padding(.horizontal, 2).padding(.vertical, 2)
    }
}

// MARK: - Searching

/// Claude está usando herramientas (buscar, leer…). Vuelve sola al chat cuando termina.
struct SearchingView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = AssistantStore.shared

    var label: String {
        if let tool = store.runningToolTitle { return tool }
        if store.isStreaming, let note = store.statusNote { return note }
        switch state.promptContext {
        case .window(_, let title, _): return "Claude está leyendo \(title)…"
        case .file(let name, _): return "Claude está leyendo \(name)…"
        case nil: return "Claude está buscando…"
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .indigo)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let ctx = state.promptContext {
                        ContextChip(context: ctx)
                    }
                    ClaudePetView(mood: store.petMood, size: 20)
                }
                ShimmeringText(label)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    SecondaryButton("Ver el chat") { state.view = .prompt }
                    if store.isStreaming {
                        SecondaryButton("Detener") { store.stop() }
                    }
                }
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
        }
        .onChange(of: store.isStreaming) { _, streaming in
            if !streaming && state.view == .searching {
                state.view = store.lastReply != nil ? .result : .prompt
            }
        }
    }
}

// MARK: - Result

/// Respuesta corta de Claude (la última). Para seguir, se abre el chat.
struct ResultView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = AssistantStore.shared

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .green)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Circle().fill(claudeOrange).frame(width: 6, height: 6)
                    Text("Claude")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#9398A1"))
                }
                if let reply = store.lastReply {
                    Text(ChatMarkdownText.attributed(reply.text))
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#DADDE2"))
                        .lineLimit(4)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        PrimaryButton("Seguir en el chat") { state.view = .prompt }
                        SecondaryButton("Copiar") { ChatClipboard.copy(reply.text) }
                        SecondaryButton("Cerrar") { state.view = state.tasks.isEmpty ? .empty : .overview }
                    }
                } else {
                    Text("Todavía no hay respuestas.")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#9398A1"))
                    PrimaryButton("Abrir el chat") { state.view = .prompt }
                }
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
        }
    }
}

// MARK: - Note (short message, auto-closes)

struct NoteView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.noteMessage ?? "")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.leading, 98)
        }
    }
}

// MARK: - Integration card (overview left card when an integration pill is focused)

struct IntegrationCardView: View {
    let task: AgentTask
    @ObservedObject private var appState = AppState.shared

    private var isConfigured: Bool {
        switch task.id {
        case "integration_claude":
            return ClaudeHooksFile.isInstalled
        case "integration_stripe":  return KeychainStore.shared.get("stripe-api-key") != nil
        case "integration_notion":  return KeychainStore.shared.get("notion-api-key") != nil
        case "integration_calcom":  return KeychainStore.shared.get("calcom-api-key") != nil
        default: return false
        }
    }

    private var openURL: URL? {
        switch task.id {
        case "integration_claude":  return nil  // uses terminal button below
        case "integration_stripe":  return URL(string: "https://dashboard.stripe.com/payments")
        case "integration_notion":  return URL(string: "https://notion.so")
        case "integration_calcom":  return URL(string: "https://app.cal.com/bookings")
        default: return nil
        }
    }

    // VS Code with active session: show ticker layout (same as overview)
    private var vsCodeSessionActive: Bool {
        task.id == "integration_claude" && (task.state != .idle || !task.steps.isEmpty)
    }

    // Stripe: show card as soon as first poll completes (balance OR payments)
    private var stripeHasData: Bool {
        task.id == "integration_stripe" && appState.stripeLoaded
    }

    // Cal.com: show calendar as soon as first poll completes
    private var calcomHasData: Bool {
        task.id == "integration_calcom" && appState.calcomLoaded
    }

    // Notion: show pages as soon as first poll completes
    private var notionHasData: Bool {
        task.id == "integration_notion" && appState.notionLoaded
    }

    var body: some View {
        if stripeHasData {
            StripeCardView()
                .transition(.opacity)
        } else if calcomHasData {
            CalcomCardView()
                .transition(.opacity)
        } else if notionHasData {
            NotionCardView()
                .transition(.opacity)
        } else if vsCodeSessionActive {
            // Active session view — reuse overview layout
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: task.color))
                        .frame(width: 7, height: 7)
                    Text(task.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1).truncationMode(.tail)
                        .layoutPriority(1)
                    Text("Claude Code")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 2)
                    if task.steps.count > 1 {
                        Text("\(min(task.stepIndex + 1, task.steps.count))/\(task.steps.count)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .fixedSize()
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                TickerView(task: task)
                    .frame(height: 44)
                    .padding(.top, 6)
                    .padding(.leading, 108)
                    .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
        } else {
            // Sin datos todavía / sin configurar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: task.color))
                        .frame(width: 7, height: 7)
                    Text(task.id == "integration_claude" ? "Claude Code" : task.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Text("Integración")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                HStack(spacing: 5) {
                    let stripeErr = task.id == "integration_stripe" ? appState.stripeError
                                  : task.id == "integration_calcom"  ? appState.calcomError
                                  : nil
                    let dot = stripeErr != nil ? Color(hex: "#F4505E")
                            : isConfigured    ? Color(hex: "#22C55E")
                            :                   Color(hex: "#F4505E")
                    let label = stripeErr ?? (isConfigured ? "Conectado · cargando…" : "Falta configurar la clave")
                    Circle().fill(dot).frame(width: 5, height: 5)
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                .padding(.leading, 108)
                .padding(.top, 2)

                HStack(spacing: 8) {
                    if task.id == "integration_claude" {
                        Button("Abrir Visual Studio Code") { openVSCode() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.7))
                            .buttonStyle(.plain)
                    } else if let url = openURL {
                        Button("Abrir \(task.name)") { NSWorkspace.shared.open(url) }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    if task.id == "integration_stripe" {
                        if isConfigured {
                            Button("Actualizar") { Task { @MainActor in StripePoller.shared.pollNow() } }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "#0570DE").opacity(0.85))
                                .buttonStyle(.plain)
                        }
                    }
                    if task.id == "integration_calcom" && isConfigured {
                        Button("Actualizar") { Task { @MainActor in CalcomPoller.shared.pollNow() } }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#C9956A").opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    if !isConfigured {
                        Button("Ajustes…") {
                            NotificationCenter.default.post(name: .openFullSettings, object: nil)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 108)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .transition(.opacity)
        }
    }

    private func openVSCode() {
        let ids = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium.codium"]
        let appURL = ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first

        // If we have a project folder, open it directly in VS Code
        if let cwd = task.sessionCwd, !cwd.isEmpty, let appURL = appURL {
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: cwd)],
                withApplicationAt: appURL,
                configuration: .init(),
                completionHandler: nil
            )
            return
        }

        // No cwd: activate running instance or launch fresh
        if let running = ids.compactMap({ id in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
        }).first {
            running.activate(options: .activateIgnoringOtherApps)
            return
        }
        if let appURL = appURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
        }
    }
}

// MARK: - Stripe Card View

struct StripeCardView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#0570DE"))
                    .frame(width: 7, height: 7)
                Text("Stripe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Pagos")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Balance
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(balanceFormatted)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.easeOut(duration: 1.2), value: appState.stripeDisplayBalance)
                Text(appState.stripeCurrency.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .padding(.bottom, 1)
            }
            .padding(.leading, 108)
            .padding(.top, 4)

            // Payment rows (animated list)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(appState.stripePayments) { payment in
                    StripePaymentRow(payment: payment)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal:   .move(edge: .bottom).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82),
                        value: appState.stripePayments.map(\.id))
            .padding(.leading, 108)
            .padding(.trailing, 12)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private var balanceFormatted: String {
        String(format: "%.2f", Double(appState.stripeDisplayBalance) / 100.0)
    }
}

private struct StripePaymentRow: View {
    let payment: StripePayment

    var body: some View {
        let accent = payment.isSuccess ? Color(hex: "#22C55E") : Color(hex: "#F4505E")
        HStack(spacing: 5) {
            Circle().fill(accent).frame(width: 5, height: 5)
            Text(payment.description ?? "Pago")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .lineLimit(1).truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text("+\(payment.amountFormatted)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "#22C55E"))
                .fixedSize()
            Text(payment.timeAgo)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#6B7079"))
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Cal.com Card View

struct CalcomCardView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var selectedDate: Date? = nil
    @State private var selectedBooking: CalcomBooking? = nil
    @State private var displayMonth: Date = Date()
    @State private var displayHalf: Int = 1  // 1 = first half, 2 = second half

    var body: some View {
        Group {
            if let booking = selectedBooking {
                CalcomBookingDetailView(booking: booking) {
                    withAnimation(.easeOut(duration: 0.2)) { selectedBooking = nil }
                }
            } else if let date = selectedDate {
                CalcomDayView(
                    date: date,
                    bookings: bookingsFor(date),
                    onSelect: { b in withAnimation(.easeOut(duration: 0.2)) { selectedBooking = b } },
                    onBack:   { withAnimation(.easeOut(duration: 0.2)) { selectedDate = nil } }
                )
            } else {
                CalcomCalendarView(
                    displayMonth: $displayMonth,
                    displayHalf: $displayHalf,
                    bookings: appState.calcomBookings,
                    onSelect: { d in withAnimation(.easeOut(duration: 0.2)) { selectedDate = d } }
                )
            }
        }
        .onChange(of: appState.focusId) { _, _ in
            selectedDate = nil; selectedBooking = nil; displayHalf = 1
        }
    }

    private func bookingsFor(_ date: Date) -> [CalcomBooking] {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let key = "\(c.year!)-\(String(format: "%02d", c.month!))-\(String(format: "%02d", c.day!))"
        return appState.calcomBookings.filter { $0.dayKey == key }
                                      .sorted { $0.startTime < $1.startTime }
    }
}

struct CalcomCalendarView: View {
    @Binding var displayMonth: Date
    @Binding var displayHalf: Int
    let bookings: [CalcomBooking]
    let onSelect: (Date) -> Void

    private let cal = Calendar.current

    private var navLabel: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_AR"); f.dateFormat = "MMMM yyyy"
        return "\(f.string(from: displayMonth).capitalized(with: Locale(identifier: "es_AR"))) · \(displayHalf)ª quincena"
    }

    // 7 consecutive days per row, day 1 always at far left — no weekday alignment
    private var allWeeks: [[Date?]] {
        let comps = cal.dateComponents([.year, .month], from: displayMonth)
        let monthStart = cal.date(from: comps)!
        let daysInMonth = cal.range(of: .day, in: .month, for: displayMonth)!.count
        var result: [[Date?]] = []
        var chunk: [Date?] = []
        for i in 0..<daysInMonth {
            chunk.append(cal.date(byAdding: .day, value: i, to: monthStart)!)
            if chunk.count == 7 { result.append(chunk); chunk = [] }
        }
        if !chunk.isEmpty {
            while chunk.count < 7 { chunk.append(nil) }
            result.append(chunk)
        }
        return result
    }

    // Visible weeks for current half
    private var visibleWeeks: [[Date?]] {
        let all = allWeeks
        let splitAt = 2  // always 2 weeks per Q
        return displayHalf == 1 ? Array(all[0..<splitAt]) : Array(all[splitAt...])
    }

    private func hasBookings(_ d: Date) -> Bool {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        let key = "\(c.year!)-\(String(format: "%02d", c.month!))-\(String(format: "%02d", c.day!))"
        return bookings.contains { $0.dayKey == key }
    }

    private func goBack() {
        if displayHalf == 1 {
            displayMonth = cal.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
            displayHalf = 2
        } else {
            displayHalf = 1
        }
    }

    private func goForward() {
        if displayHalf == 1 {
            displayHalf = 2
        } else {
            displayMonth = cal.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
            displayHalf = 1
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#C9956A")).frame(width: 7, height: 7)
                Text("Cal.com").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text("Agenda").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6).padding(.leading, 108).padding(.trailing, 36)

            HStack(spacing: 0) {
                Button { goBack() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 18, height: 16)
                }.buttonStyle(.plain)
                Text(navLabel).font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#C5C8CD")).frame(maxWidth: .infinity)
                Button { goForward() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 18, height: 16)
                }.buttonStyle(.plain)
            }
            .padding(.leading, 108).padding(.trailing, 12).padding(.top, 2)

            VStack(spacing: 1) {
                ForEach(visibleWeeks.indices, id: \.self) { i in
                    CalcomWeekRow(week: visibleWeeks[i], hasBookings: hasBookings,
                                  isToday: cal.isDateInToday, onSelect: onSelect)
                }
            }
            .padding(.leading, 108).padding(.trailing, 12).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
}

private struct CalcomWeekRow: View {
    let week: [Date?]
    let hasBookings: (Date) -> Bool
    let isToday: (Date) -> Bool
    let onSelect: (Date) -> Void

    private var weekLabel: String {
        guard let first = week.compactMap({ $0 }).first else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "es_AR"); f.dateFormat = "dd/MM"
        return f.string(from: first)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(weekLabel).font(.system(size: 7)).foregroundColor(Color(hex: "#4B5563"))
                .frame(width: 26, alignment: .leading)
            ForEach(0..<7, id: \.self) { i in
                if let day = week[i] {
                    CalcomDayCell(day: day, hasEvents: hasBookings(day), isToday: isToday(day))
                        .contentShape(Rectangle()).onTapGesture { onSelect(day) }.frame(maxWidth: .infinity)
                } else {
                    Color.clear.frame(maxWidth: .infinity).frame(height: 18)
                }
            }
        }
    }
}

private struct CalcomDayCell: View {
    let day: Date
    let hasEvents: Bool
    let isToday: Bool
    var body: some View {
        VStack(spacing: 1) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .white : Color(hex: "#9398A1"))
                .frame(width: 13, height: 13)
                .background(isToday ? Color(hex: "#C9956A").opacity(0.55) : Color.clear)
                .clipShape(Circle())
            Circle().fill(hasEvents ? Color(hex: "#C9956A") : Color.clear).frame(width: 3, height: 3)
        }
        .frame(height: 18)
    }
}

struct CalcomDayView: View {
    let date: Date
    let bookings: [CalcomBooking]
    let onSelect: (CalcomBooking) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 22, height: 22).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.leading, 108)
                Text(dayLabel).font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#C5C8CD"))
                Spacer()
            }
            .padding(.top, 6).padding(.trailing, 12)

            if bookings.isEmpty {
                Text("No hay llamadas agendadas").font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                    .padding(.leading, 116).padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(bookings) { b in
                        Button { onSelect(b) } label: {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: "#C9956A")).frame(width: 4, height: 4)
                                Text(b.timeLabel)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color(hex: "#C9956A")).fixedSize()
                                Text(b.title).font(.system(size: 11)).foregroundColor(Color(hex: "#C5C8CD"))
                                    .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.right").font(.system(size: 8))
                                    .foregroundColor(Color(hex: "#4B5563"))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(hex: "#C9956A").opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.leading, 108).padding(.trailing, 12).padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
    private var dayLabel: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_AR"); f.dateFormat = "EEEE d 'de' MMMM"; let t = f.string(from: date); return t.prefix(1).uppercased() + t.dropFirst()
    }
}

struct CalcomBookingDetailView: View {
    let booking: CalcomBooking
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 22, height: 22).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.leading, 108)
                Text(booking.timeLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "#C9956A"))
                Spacer()
            }
            .padding(.top, 6).padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(booking.title).font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1)
                if let name = booking.attendeeName, !name.isEmpty {
                    CalcomDetailRow(icon: "person.fill", text: name, size: 11)
                }
                if let email = booking.attendeeEmail, !email.isEmpty {
                    CalcomDetailRow(icon: "envelope.fill", text: email, size: 10, truncate: true)
                }
                if let notes = booking.attendeeNotes, !notes.isEmpty {
                    CalcomDetailRow(icon: "note.text", text: notes, size: 10, lines: 2)
                }
            }
            .padding(.leading, 114).padding(.trailing, 12).padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
}

private struct CalcomDetailRow: View {
    let icon: String
    let text: String
    var size: CGFloat = 11
    var truncate: Bool = false
    var lines: Int = 1
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(Color(hex: "#6B7079")).frame(width: 10)
            Text(text).font(.system(size: size)).foregroundColor(Color(hex: "#9398A1"))
                .lineLimit(lines).truncationMode(truncate ? .middle : .tail)
        }
    }
}

// MARK: - Notion Card View

struct NotionCardView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#E8E8E8")).frame(width: 7, height: 7)
                Text("Notion").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text("Recientes").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6).padding(.leading, 108).padding(.trailing, 36)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(appState.notionPages.prefix(3)) { page in
                    Button {
                        if let url = URL(string: page.url) { NSWorkspace.shared.open(url) }
                    } label: {
                        HStack(spacing: 6) {
                            if let emoji = page.emoji {
                                Text(emoji).font(.system(size: 10)).frame(width: 14)
                            } else {
                                Image(systemName: "doc.text").font(.system(size: 9))
                                    .foregroundColor(Color(hex: "#6B7079")).frame(width: 14)
                            }
                            Text(page.title).font(.system(size: 11))
                                .foregroundColor(Color(hex: "#C5C8CD"))
                                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                            Spacer(minLength: 4)
                            Text(page.timeAgo).font(.system(size: 9))
                                .foregroundColor(Color(hex: "#4B5563"))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 102).padding(.trailing, 12).padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
}

// MARK: - Ticker (overview scrolling task steps) V2

struct TickerView: View {
    let task: AgentTask?

    @State private var rowA: String = "…"   // completed (above, left-shifted)
    @State private var rowB: String = "…"   // current (below) → animates diagonally up-left
    @State private var rowC: String = ""    // incoming current — slides in from below

    @State private var rowAOffset: CGFloat = 0
    @State private var rowAOpacity: Double = 1
    @State private var rowBOffset: CGFloat = 22
    @State private var rowBPhase:  Double  = 0   // 0=current, 1=completed (drives X+scale)
    @State private var rowCOffset: CGFloat = 44
    @State private var rowCOpacity: Double = 0

    @State private var displayIndex: Int = -1
    @State private var isTransitioning = false

    private let completedScale: CGFloat = 11.5 / 13   // 0.885 — matches completed font size

    var steps: [String] {
        let raw = task?.steps ?? []
        return raw.isEmpty ? ["…"] : raw
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // Row A: completed row — always rendered at phase=1 + completedScale
            TickerRowView(text: rowA, phase: 1.0)
                .scaleEffect(completedScale, anchor: .leading)
                .offset(x: -10, y: rowAOffset)
                .opacity(rowAOpacity)

            // Row B: current step → animates diagonally up-left, phase 0→1, scale 1→completedScale
            TickerRowView(text: rowB, phase: rowBPhase)
                .scaleEffect(1 - rowBPhase * (1 - completedScale), anchor: .leading)
                .offset(x: -rowBPhase * 10, y: rowBOffset)

            // Row C: incoming new step — slides in from below at phase=0
            TickerRowView(text: rowC, phase: 0.0)
                .offset(y: rowCOffset)
                .opacity(rowCOpacity)
        }
        .frame(height: 44)
        .clipped()
        .mask(LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.85),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        ))
        .onAppear {
            let idx = task?.stepIndex ?? -1
            displayIndex = idx
            if idx >= 0, !steps.isEmpty {
                rowA = idx > 0 ? steps[max(0, idx - 1)] : "…"
                rowB = steps[min(idx, steps.count - 1)]
            }
        }
        .onChange(of: task?.steps.count) { _, _ in
            guard let task, !task.steps.isEmpty, !isTransitioning else { return }
            let newIdx = task.stepIndex
            if displayIndex < 0 {
                displayIndex = newIdx
                rowA = newIdx > 0 ? steps[max(0, newIdx - 1)] : "…"
                rowB = steps[min(newIdx, steps.count - 1)]
                return
            }
            guard newIdx != displayIndex else { return }
            tickerAnimate(to: newIdx)
        }
    }

    private func tickerAnimate(to newIdx: Int) {
        isTransitioning = true
        rowC = steps[min(newIdx, steps.count - 1)]
        rowCOffset = 44
        rowCOpacity = 0

        // Old completed (rowA): fades + slides further up
        withAnimation(.easeOut(duration: 0.28)) {
            rowAOffset  = -22
            rowAOpacity = 0
        }

        // Current (rowB): moves diagonally up-left + shrinks to completed size
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38)) {
            rowBOffset = 0
            rowBPhase  = 1
        }

        // New current (rowC): slides in from below
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38)) {
            rowCOffset  = 22
            rowCOpacity = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            self.displayIndex    = newIdx
            self.rowA            = self.rowB
            self.rowAOffset      = 0
            self.rowAOpacity     = 1
            self.rowB            = self.rowC
            self.rowBOffset      = 22
            self.rowBPhase       = 0
            self.rowCOffset      = 44
            self.rowCOpacity     = 0
            self.isTransitioning = false
        }
    }
}

struct TickerRowView: View {
    let text: String
    let phase: Double   // 0 = current (shimmer, large), 1 = completed (dim, scaled down by caller)

    var body: some View {
        HStack(spacing: 6) {
            // Icon: chevron fades out first half, checkmark fades in second half
            ZStack {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .opacity(max(0, 1 - phase * 2))
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundColor(Color(hex: "#454850"))
                    .opacity(max(0, phase * 2 - 1))
            }
            .frame(width: 12, alignment: .center)

            // Text: shimmer fades out, dim completed text fades in (overlapping cross-fade)
            ZStack(alignment: .leading) {
                TickerShimmerText(text: text)
                    .opacity(max(0, 1 - phase * 1.6))
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .lineLimit(1).truncationMode(.tail)
                    .opacity(min(1, max(0, phase * 2 - 0.4)))
            }
        }
        .frame(height: 22, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TickerShimmerText: View {
    let text: String

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let p = CGFloat(t.truncatingRemainder(dividingBy: 2.2) / 2.2)
            // phase sweeps -0.1 → 1.1 so white peak enters from left and exits right
            let phase = p * 1.2 - 0.1
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(LinearGradient(stops: [
                    .init(color: Color(hex: "#7c818a"), location: max(0, phase - 0.3)),
                    .init(color: Color(hex: "#F2F3F5"), location: max(0, min(1, phase))),
                    .init(color: Color(hex: "#7c818a"), location: min(1, phase + 0.3)),
                ], startPoint: .leading, endPoint: .trailing))
        }
    }
}

// MARK: - Agent pills (overview right card)

struct AgentPillsView: View {
    @ObservedObject var state: AppState
    @State private var swapping = false

    private var others: [AgentTask] {
        state.tasks.filter { $0.id != state.focusId }
    }

    private var displayTasks: [AgentTask] {
        Array(others.prefix(4))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(displayTasks) { task in
                    AgentPill(task: task, state: state, swapping: $swapping) {
                        swapping = true
                        state.setFocus(task.id)
                        SoundEngine.shared.play("blip")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
                    }
                }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentPill: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    // VS Code pill always shows "VS Code" label regardless of active project name
    private var displayName: String {
        task.id == "integration_claude" ? "Claude Code" : task.name
    }

    var body: some View {
        Button(action: { onTap() }) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    // ORBEX: superficie según el tema (Themes/IslandSkins.swift).
                    AgentPillSurface(color: Color(hex: task.color), hovered: isHovered)
                    HStack(spacing: 0) {
                        MiniBotCanvasView(task: task)
                            .frame(width: 22 / 0.6, height: 22 / 0.6)
                            .frame(width: 22, height: 22, alignment: .center)
                            .padding(.leading, 8)
                        Spacer()
                    }
                    Text(displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isHovered
                                         ? Color(hex: task.color).lighter(by: 0.3)
                                         : Color(hex: "#6B7079"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .shadow(color: Color(hex: task.color).opacity(isHovered ? 0.35 : 0), radius: 10, x: 0, y: 2)

                // Alert badge (approval / finished / error)
                if let badge = task.pillBadge {
                    PillBadgeView(badge: badge, taskColor: task.color)
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .onHover { newHover in
            guard !swapping else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}

struct PillBadgeView: View {
    let badge: PillBadge
    let taskColor: String

    private var badgeColor: Color {
        switch badge {
        case .approval: return Color(hex: "#F5A524")
        case .finished: return Color(hex: "#22C55E")
        case .error:    return Color(hex: "#F4505E")
        }
    }

    private var icon: String {
        switch badge {
        case .approval: return "exclamationmark"
        case .finished: return "checkmark"
        case .error:    return "xmark"
        }
    }

    var body: some View {
        ZStack {
            PillBadgeRing()
                .frame(width: 14, height: 14)
            Circle()
                .fill(badgeColor)
                .frame(width: 12, height: 12)
            Image(systemName: icon)
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.black)
        }
        .shadow(color: badgeColor.opacity(0.6), radius: 4, x: 0, y: 0)
    }
}

// MARK: - Card background

struct CardBackground<Content: View>: View {
    enum Wash { case red, green, pink, amber, cyan, indigo, soft }

    let wash: Wash?
    let content: (() -> Content)?

    init(wash: Wash?, @ViewBuilder content: @escaping () -> Content) {
        self.wash = wash
        self.content = content
    }

    var washColor: Color {
        switch wash {
        case .red:    return Color(hex: "#F4505E").opacity(0.55)
        case .green:  return Color(hex: "#34D399").opacity(0.5)
        case .pink:   return Color(hex: "#F472B6").opacity(0.55)
        case .amber:  return Color(hex: "#F5A524").opacity(0.42)
        case .cyan:   return Color(hex: "#22D3EE").opacity(0.38)
        case .indigo: return Color(hex: "#6366F1").opacity(0.5)
        case .soft:   return Color.white.opacity(0.08)
        case nil:     return Color.clear
        }
    }

    var body: some View {
        ZStack {
            // ORBEX: el fondo sigue al tema activo (Themes/IslandSkins.swift).
            IslandCardSurface(wash: washColor)

            if let content = content {
                content()
            }
        }
    }
}

extension CardBackground where Content == EmptyView {
    init(wash: Wash?) {
        self.wash = wash
        self.content = nil
    }

    var body: some View {
        ZStack {
            IslandCardSurface(wash: washColor)
        }
    }
}

// MARK: - Shared sub-components

struct AgentWho: View {
    let task: AgentTask?
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            if let task = task {
                Circle().fill(Color(hex: task.color)).frame(width: 8, height: 8)
                Text(task.name).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            }
            Text(label).font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
        }
    }
}

struct CodeBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundColor(Color(hex: "#E8E9EC"))
    }
}

struct ContextChip: View {
    let context: PromptContext
    @State private var glowing = false

    var label: String {
        switch context {
        case .window(let app, _, let url):
            if let url = url, let host = URL(string: url)?.host { return "\(app) · \(host)" }
            return app
        case .file(let name, _): return name
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: "#FF6B5B"), Color(hex: "#F7B32B"), Color(hex: "#2DD4A7"), Color(hex: "#38BDF8"), Color(hex: "#A78BFA")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(Color(hex: "#F1F2F4"))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(glowing ? 0.75 : 0), lineWidth: 1.5))
        .scaleEffect(glowing ? 1.06 : 1.0)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { glowing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeOut(duration: 0.3)) { glowing = false }
            }
        }
    }
}

struct ShimmeringText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#7c818a"), location: 0),
                        .init(color: .white, location: 0.4),
                        .init(color: Color(hex: "#7c818a"), location: 0.7)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

struct ShimmerOverlay: View {
    @State private var phase: CGFloat = 0.0

    var body: some View {
        LinearGradient(
            stops: [
                // Clamp all locations to [0,1] and keep them ordered
                .init(color: .clear,                   location: max(0, phase - 0.3)),
                .init(color: Color.white.opacity(0.6), location: max(0, min(1, phase))),
                .init(color: .clear,                   location: min(1, phase + 0.3))
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .blendMode(.overlay)
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                phase = 1.3  // travels left→right, exits right edge cleanly
            }
        }
    }
}

// MARK: - Button styles

struct PrimaryButton: View {
    let title: String
    let kbd: String?
    let action: () -> Void

    init(_ title: String, kbd: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.kbd = kbd; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let k = kbd {
                    Text(k).font(.system(size: 10.5))
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.4)))
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .islandButtonSkin(.primary, shape: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    let kbd: String?
    let action: () -> Void

    init(_ title: String, kbd: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.kbd = kbd; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let k = kbd {
                    Text(k).font(.system(size: 10.5))
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.4)))
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .islandButtonSkin(.secondary, shape: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .islandButtonSkin(.secondary, shape: Circle(), setsForeground: false, pressed: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct SendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .islandButtonSkin(.primary, shape: Circle(), setsForeground: false, pressed: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

// MARK: - Settings island view (Point 7)

struct SettingsIslandView: View {
    @ObservedObject var state: AppState

    /// Hooks de ORBEX instalados en `~/.claude/settings.json`.
    private var claudeConnected: Bool { ClaudeHooksFile.isInstalled }

    /// El asistente usa `claude` local (sin clave de API): ¿se encontró el programa?
    private var apiConnected: Bool {
        if case .found = AssistantStore.shared.cliStatus { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 10) {
                // Sound row
                HStack(spacing: 10) {
                    Toggle("", isOn: $state.soundEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.75)
                        .frame(width: 44)
                    Text("Sonido")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Slider(value: $state.soundVolume, in: 0...0.2)
                        .frame(width: 72)
                        .opacity(state.soundEnabled ? 1 : 0.4)
                }

                // Auto-close row
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .frame(width: 16)
                    Text("Cierre automático · \(Int(state.autoCloseInterval)) s")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach([10, 15, 30], id: \.self) { s in
                            Button("\(s) s") {
                                state.autoCloseInterval = Double(s)
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(state.autoCloseInterval == Double(s) ? Color(hex: "#252830") : Color.clear)
                            .foregroundColor(state.autoCloseInterval == Double(s) ? Color(hex: "#F5F6F8") : Color(hex: "#6B7079"))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Connection status
                HStack(spacing: 14) {
                    StatusBadge(label: "Claude Code", ok: claudeConnected)
                    StatusBadge(label: "claude", ok: apiConnected)
                    Spacer()
                    Button("Ajustes…") {
                        NotificationCenter.default.post(name: .openFullSettings, object: nil)
                    }
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
    }
}

struct StatusBadge: View {
    let label: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 4) {
            StatusLight(color: ok ? Color(hex: "#22C55E") : Color(hex: "#F4505E"))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
        }
    }
}

// MARK: - Color extension (lighten)

extension Color {
    func lighter(by amount: Double) -> Color {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(
            red: min(1, Double(components.redComponent) + amount),
            green: min(1, Double(components.greenComponent) + amount),
            blue: min(1, Double(components.blueComponent) + amount)
        )
    }
}

import SwiftUI
import OrbexCore

// MARK: - Página "Código" de la isla

/// Página de sesiones de Claude Code / Codex (≈ 270 × 230 pt): permisos arriba, sesiones abajo.
struct SessionsPageView: View {
    @ObservedObject private var store = SessionsStore.shared
    @Environment(\.orbexTheme) private var theme

    init() {}

    var body: some View {
        Group {
            if store.sessions.isEmpty && store.approvals.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(Array(store.approvals.enumerated()), id: \.element.id) { index, approval in
                            ApprovalCardView(approval: approval, isPrimary: index == 0)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                        ForEach(store.sessions) { session in
                            SessionRowView(session: session)
                        }
                    }
                    .animation(theme.softSpring, value: store.approvals.map(\.id))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
            Text("No hay sesiones de Claude Code. Instalá los hooks en Configuración › Claude Code.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                OrbexBus.perform("settings")
            } label: {
                Text("Abrir Configuración")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Fila de sesión

/// Fila compacta: estado, proyecto, último paso. Clic → salta a la terminal de la sesión.
struct SessionRowView: View {
    let session: SessionInfo
    @Environment(\.orbexTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button {
            TerminalJumper.jump(to: session)
        } label: {
            HStack(spacing: 8) {
                SessionStatusIndicator(status: session.status, size: 12)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(session.project)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        if session.source == .codex {
                            Text("Codex")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.secondaryText)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                    }
                    Text(SessionsStore.detail(for: session))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(SessionFormat.ago(session.lastUpdate, now: context.date))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.tertiaryText)
                }
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovering ? theme.accent : theme.tertiaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .orbexCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(theme.softSpring) { hovering = h } }
        .help("Ir a la terminal de esta sesión")
    }

    private var detailColor: Color {
        switch session.status {
        case .needsPermission, .question: return .orange
        case .failed: return Color(red: 1, green: 0.42, blue: 0.42)
        default: return theme.secondaryText
        }
    }
}

/// Punto de estado: ruedita si trabaja, naranja si te necesita, tilde si terminó.
struct SessionStatusIndicator: View {
    let status: SessionStatus
    var size: CGFloat = 12
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        switch status {
        case .working, .thinking:
            if theme.reduceMotion {
                Circle().fill(theme.accent).frame(width: size * 0.6, height: size * 0.6)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    Circle()
                        .trim(from: 0.05, to: status == .thinking ? 0.45 : 0.72)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: max(1.5, size * 0.16), lineCap: .round))
                        .frame(width: size, height: size)
                        .rotationEffect(.degrees((t * (status == .thinking ? 200 : 360)).truncatingRemainder(dividingBy: 360)))
                }
            }
        case .needsPermission, .question:
            Circle()
                .fill(Color.orange)
                .frame(width: size * 0.66, height: size * 0.66)
                .shadow(color: .orange.opacity(0.7), radius: 3)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.5))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42))
        default:
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: size * 0.5, height: size * 0.5)
        }
    }
}

// MARK: - Tarjeta de permiso

/// Permiso pendiente: herramienta, qué quiere hacer y Permitir / Siempre / Denegar.
/// Return = Permitir (solo en la primera tarjeta). "Siempre" pide una segunda confirmación.
struct ApprovalCardView: View {
    let approval: PendingApproval
    var isPrimary: Bool = true
    @Environment(\.orbexTheme) private var theme
    @State private var confirmingAlways = false

    init(approval: PendingApproval, isPrimary: Bool = true) {
        self.approval = approval
        self.isPrimary = isPrimary
    }

    private var event: HookEvent { approval.event }

    private var toolName: String {
        if let t = event.toolName, !t.isEmpty { return t }
        return "Permiso"
    }

    private var description: String {
        let step = event.stepDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !step.isEmpty { return step }
        if let m = event.message?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty { return m }
        return "\(SessionsStore.sourceName(event)) quiere usar \(toolName)"
    }

    private var inputPreview: String? {
        guard let s = event.toolInputSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: SessionFormat.symbol(forTool: toolName))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text(toolName)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(SessionsStore.sourceName(event)) · \(event.projectName)")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(description)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let input = inputPreview {
                Text(input)
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.text.opacity(0.85))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.07)))
                    .textSelection(.enabled)
            }

            if confirmingAlways {
                confirmRow
            } else {
                buttonsRow
            }
        }
        .padding(8)
        .orbexCard(cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.55), lineWidth: 1)
        )
    }

    private var buttonsRow: some View {
        HStack(spacing: 5) {
            Button { decide(.allow) } label: {
                buttonLabel("Permitir", symbol: "checkmark", filled: true)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(isPrimary ? KeyboardShortcut.defaultAction : nil)
            .help("Permitir esta vez (Return)")

            Button {
                withAnimation(theme.softSpring) { confirmingAlways = true }
            } label: {
                buttonLabel("Siempre", symbol: "checkmark.seal", filled: false)
            }
            .buttonStyle(.plain)
            .help("Permitir siempre \(toolName) en \(event.projectName)")

            Button { decide(.deny) } label: {
                buttonLabel("Denegar", symbol: "xmark", filled: false, tint: Color(red: 1, green: 0.45, blue: 0.45))
            }
            .buttonStyle(.plain)
            .help("Denegar")
        }
    }

    private var confirmRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("¿Permitir siempre \(toolName) en \(event.projectName)? No te va a volver a preguntar.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Button { decide(.allowAlways) } label: {
                    buttonLabel("Sí, siempre", symbol: "checkmark.seal.fill", filled: true)
                }
                .buttonStyle(.plain)
                Button {
                    withAnimation(theme.softSpring) { confirmingAlways = false }
                } label: {
                    buttonLabel("Cancelar", symbol: "arrow.uturn.backward", filled: false)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(isPrimary ? KeyboardShortcut.cancelAction : nil)
            }
        }
    }

    private func decide(_ d: ApprovalDecision) {
        let id = approval.id
        withAnimation(theme.softSpring) {
            SessionsStore.shared.decide(id, d)
        }
    }

    private func buttonLabel(_ title: String, symbol: String, filled: Bool, tint: Color? = nil) -> some View {
        let color = tint ?? theme.accent
        return HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(filled ? Color.black : color)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .background(Capsule().fill(filled ? color : Color.white.opacity(0.08)))
        .contentShape(Capsule())
    }
}

// MARK: - Insignia para las alitas

/// Insignia chiquita para las alitas de la isla: punto de color + cantidad de sesiones.
/// Naranja = te necesita, color del tema = trabajando, verde = terminaron. No muestra nada si no hay sesiones.
struct SessionsBadge: View {
    @ObservedObject private var store = SessionsStore.shared
    @Environment(\.orbexTheme) private var theme

    init() {}

    var body: some View {
        let pending = store.approvals.count
        let active = store.activeCount
        let count = pending > 0 ? pending : active
        if count > 0 || !store.sessions.isEmpty {
            HStack(spacing: 3) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: dotColor.opacity(0.7), radius: store.needsAttention ? 2.5 : 0)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .help(store.statusLine.isEmpty ? "Sesiones de código" : store.statusLine)
        }
    }

    private var dotColor: Color {
        if store.needsAttention { return .orange }
        if store.isWorking { return theme.accent }
        if store.sessions.contains(where: { $0.status == .failed }) { return Color(red: 1, green: 0.42, blue: 0.42) }
        if store.sessions.contains(where: { $0.status == .finished }) { return Color(red: 0.35, green: 0.85, blue: 0.5) }
        return Color.white.opacity(0.35)
    }
}

// MARK: - Formato

enum SessionFormat {
    /// "ahora", "3 min", "2 h", "1 d".
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 45 { return "ahora" }
        if s < 3600 { return "\(Int((s / 60).rounded())) min" }
        if s < 86_400 { return "\(Int(s / 3600)) h" }
        return "\(Int(s / 86_400)) d"
    }

    /// Ícono SF Symbol para cada herramienta de Claude Code / Codex.
    static func symbol(forTool tool: String) -> String {
        switch tool.lowercased() {
        case "bash", "shell", "exec", "local_shell": return "terminal"
        case "edit", "multiedit", "write", "notebookedit", "apply_patch": return "pencil"
        case "read", "notebookread": return "doc.text"
        case "glob", "grep", "ls": return "magnifyingglass"
        case "webfetch", "websearch": return "globe"
        case "task", "agent": return "person.2"
        default:
            return tool.lowercased().hasPrefix("mcp__") ? "puzzlepiece.extension" : "wrench.and.screwdriver"
        }
    }
}

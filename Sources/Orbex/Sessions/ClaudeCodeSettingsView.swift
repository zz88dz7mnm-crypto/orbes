import AppKit
import SwiftUI
import OrbexCore

/// Configuración › Claude Code: instalar/desinstalar hooks (con diff), terminal preferida y avisos.
struct ClaudeCodeSettingsView: View {
    @AppStorage(SessionsKeys.terminal) private var terminal = "auto"
    @AppStorage(SessionsKeys.autoOpen) private var autoOpen = true
    @AppStorage(SessionsKeys.showCodex) private var showCodex = true

    @State private var claudeInstalled = ClaudeHooksFile.isInstalled
    @State private var codexInstalled = CodexHooksFile.isInstalled
    @State private var legacyHooks = ClaudeHooksFile.hasLegacyHooks
    @State private var pending: HooksTarget?
    @State private var errorText: String?
    @State private var rulesCount = 0

    var body: some View {
        Form {
            Section("Claude Code") {
                hooksRow(.claude, installed: claudeInstalled)
                SettingsFootnote(text: "Los hooks van en \(ClaudeHooksFile.url.path). Antes de escribir se hace una copia con fecha y se muestra el cambio.",
                                 symbol: "doc.badge.gearshape")
                if legacyHooks {
                    SettingsFootnote(text: "Encontré hooks viejos de Coucou/NotchBuddy (nb-hook). Al instalar los de ORBEX se quitan; vas a ver el cambio antes de confirmar.",
                                     symbol: "exclamationmark.triangle")
                }
            }

            Section("Codex") {
                hooksRow(.codex, installed: codexInstalled)
                Toggle("Mostrar sesiones de Codex", isOn: $showCodex)
                SettingsFootnote(text: "Experimental: los hooks de Codex CLI van en \(CodexHooksFile.url.path).",
                                 symbol: "flask")
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Terminal y avisos") {
                Picker("Terminal preferida", selection: $terminal) {
                    Text("Automática (la de cada sesión)").tag("auto")
                    Text("Terminal").tag("terminal")
                    Text("iTerm2").tag("iterm")
                }
                Toggle("Abrir la isla cuando Claude pide permiso", isOn: $autoOpen)
                LabeledContent("Permisos \"Siempre\"") {
                    HStack(spacing: 10) {
                        Text(rulesCount == 1 ? "1 regla" : "\(rulesCount) reglas")
                            .foregroundStyle(.secondary)
                        Button("Olvidar todas") {
                            SessionsStore.shared.forgetAlwaysAllowRules()
                            rulesCount = 0
                        }
                        .disabled(rulesCount == 0)
                    }
                }
                SettingsFootnote(text: "Al saltar a una sesión, Terminal e iTerm2 van a la pestaña exacta (macOS puede pedir permiso de Automatización). En VS Code, Cursor, Warp o Ghostty se trae la app al frente.",
                                 symbol: "arrow.up.forward.app")
            }

            Section {
                SettingsFootnote(text: "Si ORBEX no está abierto, Claude Code sigue normal: nunca se bloquea.",
                                 symbol: "checkmark.shield")
                SettingsFootnote(text: "Los permisos siempre los decidís vos con un clic: ORBEX no aprueba nada solo, salvo las reglas \"Siempre\" que confirmaste.",
                                 symbol: "hand.raised")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .sheet(item: $pending) { target in
            HooksDiffSheet(target: target) {
                pending = nil
                install(target)
            } onCancel: {
                pending = nil
            }
        }
    }

    // MARK: - Filas

    private func hooksRow(_ target: HooksTarget, installed: Bool) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Button(installed && !(target == .claude && legacyHooks) ? "Reinstalar…" : "Instalar hooks…") {
                    errorText = nil
                    pending = target
                }
                if installed {
                    Button("Desinstalar", role: .destructive) { uninstall(target) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: installed ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(installed ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.title)
                    Text(installed ? "Hooks instalados" : "Hooks sin instalar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Acciones

    private func refresh() {
        claudeInstalled = ClaudeHooksFile.isInstalled
        codexInstalled = CodexHooksFile.isInstalled
        legacyHooks = ClaudeHooksFile.hasLegacyHooks
        rulesCount = SessionsStore.shared.alwaysAllowRules.count
    }

    private func install(_ target: HooksTarget) {
        do {
            switch target {
            case .claude: try ClaudeHooksFile.install()
            case .codex: try CodexHooksFile.install()
            }
            errorText = nil
            OrbexBus.toast("Hooks de \(target.title) instalados", symbol: "checkmark.circle")
        } catch {
            errorText = "No se pudieron instalar los hooks de \(target.title): \(error.localizedDescription)"
        }
        refresh()
    }

    private func uninstall(_ target: HooksTarget) {
        do {
            switch target {
            case .claude: try ClaudeHooksFile.uninstall()
            case .codex: try CodexHooksFile.uninstall()
            }
            errorText = nil
            OrbexBus.toast("Hooks de \(target.title) desinstalados", symbol: "trash")
        } catch {
            errorText = "No se pudieron desinstalar los hooks de \(target.title): \(error.localizedDescription)"
        }
        refresh()
    }
}

/// A qué herramienta se le instalan los hooks.
enum HooksTarget: String, Identifiable {
    case claude, codex
    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var path: String {
        switch self {
        case .claude: return ClaudeHooksFile.url.path
        case .codex: return CodexHooksFile.url.path
        }
    }

    func preview() -> (old: String, new: String, diff: String) {
        switch self {
        case .claude: return ClaudeHooksFile.preview()
        case .codex: return CodexHooksFile.preview()
        }
    }
}

/// Hoja con el diff del archivo de ajustes antes de escribir: verde lo que se agrega, rojo lo que se quita.
struct HooksDiffSheet: View {
    let target: HooksTarget
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var diff: String = ""
    @State private var loaded = false

    init(target: HooksTarget, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.target = target
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    private var lines: [String] {
        diff.components(separatedBy: "\n")
    }

    private var hasChanges: Bool {
        lines.contains { ($0.hasPrefix("+") && !$0.hasPrefix("+++")) || ($0.hasPrefix("-") && !$0.hasPrefix("---")) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Instalar hooks de \(target.title)")
                    .font(.headline)
                Text(target == .claude && ClaudeHooksFile.hasLegacyHooks
                     ? "Así va a quedar \(target.path). Se quitan los hooks viejos de Coucou/NotchBuddy (en rojo); lo demás tuyo queda igual. Se guarda una copia con fecha antes de escribir."
                     : "Así va a quedar \(target.path). Se guarda una copia con fecha antes de escribir; nada de lo tuyo se borra.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .background(background(for: line))
                    }
                }
                .textSelection(.enabled)
                .padding(.vertical, 6)
            }
            .frame(minHeight: 260, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))

            if loaded && !hasChanges {
                Label("Los hooks ya están instalados: no hay nada que cambiar.", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Confirmar", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!loaded)
            }
        }
        .padding(18)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 440, idealHeight: 520)
        .onAppear {
            guard !loaded else { return }
            diff = target.preview().diff
            loaded = true
        }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color.green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color.red }
        if line.hasPrefix("@@") { return Color.secondary }
        return Color.primary
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color.green.opacity(0.12) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color.red.opacity(0.12) }
        return Color.clear
    }
}

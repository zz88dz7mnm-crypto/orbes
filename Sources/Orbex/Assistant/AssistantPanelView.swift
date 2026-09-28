import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OrbexCore

/// Naranja de Claude (Clawd).
let claudeOrange = Color(red: 0.851, green: 0.467, blue: 0.341)

/// Panel del asistente dentro de la isla (estado `.assistant`). Arriba queda libre la franja del notch.
@MainActor
struct AssistantPanelView: View {
    @ObservedObject private var store: AssistantStore
    @ObservedObject private var app: AppModel
    @Environment(\.orbexTheme) private var theme
    @FocusState private var inputFocused: Bool

    init() {
        _store = ObservedObject(wrappedValue: AssistantStore.shared)
        _app = ObservedObject(wrappedValue: AppModel.shared)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: CGFloat(app.notch.height))
            header
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 6)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
            content
            if let error = store.lastError {
                ErrorBanner(failure: error, onRetry: { store.retry() })
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            inputBar
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(theme.softSpring, value: store.lastError)
        .dropDestination(for: URL.self) { urls, _ in
            var any = false
            for u in urls where store.attach(fileURL: u) { any = true }
            return any
        }
        .onAppear {
            store.panelDidAppear()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                inputFocused = true
            }
        }
        .onDisappear { store.panelDidDisappear() }
    }

    // MARK: - Encabezado

    private var header: some View {
        HStack(spacing: 8) {
            OrbexView(showLimbs: false, fps: min(30, app.characterFPS))
                .frame(width: 30, height: 30)
            ClaudePetView(mood: store.petMood, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("Asistente")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.text)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(store.isStreaming ? claudeOrange : theme.secondaryText)
                    .lineLimit(1)
                    .animation(nil, value: subtitle)
            }
            Spacer(minLength: 4)
            modelChip
            HeaderIconButton(symbol: "square.and.pencil", help: "Nueva conversación (⌘N)") {
                store.newConversation()
                inputFocused = true
            }
            .keyboardShortcut("n", modifiers: .command)
            HeaderIconButton(symbol: "gearshape", help: "Configuración del asistente") {
                OrbexBus.perform("settings")
            }
        }
    }

    private var subtitle: String {
        if store.isStreaming { return store.statusNote ?? "Pensando…" }
        if store.isRunningCommand { return "ORBEX está en eso…" }
        switch store.cliStatus {
        case .missing: return "No encontré Claude Code"
        case .checking: return "Buscando Claude Code…"
        default: return "Claude vía Claude Code · Esc para cerrar"
        }
    }

    private var modelChip: some View {
        let name = store.model.isEmpty ? "predeterminado" : store.model
        return HStack(spacing: 4) {
            Circle().fill(claudeOrange).frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .orbexPill()
        .help("Modelo de Claude (cambialo en Configuración › Asistente)")
    }

    // MARK: - Conversación

    @ViewBuilder
    private var content: some View {
        if store.cliStatus == .missing && store.messages.isEmpty {
            MissingCLIView(onRetry: { store.refreshCLIStatus() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.messages.isEmpty {
            EmptyChatView { suggestion in
                if suggestion.hasSuffix("…") {
                    store.draft = String(suggestion.dropLast()) + " "
                    inputFocused = true
                } else {
                    store.send(suggestion)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.messages) { msg in
                            MessageBubble(message: msg,
                                          showsConfirmation: msg.needsConfirmation && store.pendingConfirmationID == msg.id,
                                          statusNote: msg.isStreaming ? store.statusNote : nil,
                                          onConfirm: { store.confirmPending() },
                                          onCancel: { store.cancelPending() })
                                .equatable()
                                .id(msg.id)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9, anchor: msg.role == .user ? .bottomTrailing : .bottomLeading)
                                        .combined(with: .opacity),
                                    removal: .opacity))
                        }
                        Color.clear.frame(height: 1).id("fondo")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .animation(theme.spring, value: store.messages.count)
                }
                .onAppear { proxy.scrollTo("fondo", anchor: .bottom) }
                .onChange(of: store.scrollTick) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("fondo", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Entrada

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !store.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.pendingAttachments, id: \.name) { a in
                            AttachmentChip(name: a.name, bytes: a.bytes, truncated: a.truncated) {
                                store.removeAttachment(named: a.name)
                            }
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                HeaderIconButton(symbol: "paperclip", help: "Adjuntar archivo de texto") { pickFiles() }
                    .disabled(store.isStreaming)
                TextField("Preguntale a Claude o pedile algo a ORBEX…", text: $store.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(theme.text)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                            store.draft += "\n"
                            return .handled
                        }
                        store.sendDraft()
                        return .handled
                    }
                    .onSubmit { store.sendDraft() }
                    .padding(.vertical, 3)
                sendButton
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .orbexCard(cornerRadius: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(claudeOrange.opacity(inputFocused ? 0.55 : 0.0), lineWidth: 1)
            )
            .animation(theme.softSpring, value: inputFocused)
        }
    }

    private var sendButton: some View {
        let canSend = store.canSend(store.draft)
        return Button {
            if store.isStreaming { store.stop() } else { store.sendDraft() }
        } label: {
            Image(systemName: store.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(store.isStreaming ? Color.white : (canSend ? claudeOrange : theme.tertiaryText))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(!store.isStreaming && !canSend)
        .keyboardShortcut(store.isStreaming ? "." : "\r", modifiers: .command)
        .help(store.isStreaming ? "Cortar la respuesta (⌘.)" : "Enviar (↩ · ⇧↩ nueva línea)")
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .text, .sourceCode, .json, .xml, .commaSeparatedText, .log]
        panel.message = "Elegí archivos de texto para que Claude los lea (se mandan como dato, hasta ~50 KB)."
        panel.prompt = "Adjuntar"
        panel.level = .popUpMenu
        if panel.runModal() == .OK {
            for url in panel.urls { store.attach(fileURL: url) }
        }
        inputFocused = true
    }
}

// MARK: - Burbujas

private struct MessageBubble: View, Equatable {
    let message: ChatMessage
    let showsConfirmation: Bool
    let statusNote: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.orbexTheme) private var theme
    @State private var hovering = false
    @State private var copied = false

    static func == (a: MessageBubble, b: MessageBubble) -> Bool {
        a.message == b.message && a.showsConfirmation == b.showsConfirmation && a.statusNote == b.statusNote
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == .user { Spacer(minLength: 44) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role != .user { author }
                bubble
                if let foot = message.footnote, !message.isStreaming {
                    Text(foot)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.horizontal, 4)
                }
            }
            if message.role != .user { Spacer(minLength: 28) }
        }
        .onHover { h in withAnimation(theme.softSpring) { hovering = h } }
    }

    private var author: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(message.role == .assistant ? claudeOrange : theme.accent)
                .frame(width: 5, height: 5)
            Text(message.role == .assistant ? "Claude" : "ORBEX")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.tertiaryText)
            if let m = message.model, message.role == .assistant {
                Text("· \(m)")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private var bubble: some View {
        let inner = VStack(alignment: .leading, spacing: 6) {
            if !message.attachments.isEmpty {
                ForEach(message.attachments) { a in
                    Label(a.name, systemImage: "doc.text")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            if !message.toolChips.isEmpty { ToolChipsView(chips: message.toolChips) }
            if message.isStreaming && message.text.isEmpty {
                ThinkingRow(note: statusNote ?? "Pensando…")
            } else if !message.text.isEmpty {
                MarkdownBody(text: message.text, streaming: message.isStreaming)
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
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .textSelection(.enabled)

        Group {
            switch message.role {
            case .user:
                inner
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(theme.accent.opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(theme.accent.opacity(0.35), lineWidth: 0.75)
                    )
            case .system where message.isError:
                inner
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.red.opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.35), lineWidth: 0.75)
                    )
            case .assistant, .system, .tool:
                inner.orbexCard(cornerRadius: 14)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering && !message.text.isEmpty && !message.isStreaming {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .help("Copiar")
                .offset(x: 6, y: -6)
                .transition(.opacity)
            }
        }
    }
}

/// Texto con Markdown en línea + bloques de código; con cursor titilando mientras llega.
private struct MarkdownBody: View {
    let text: String
    let streaming: Bool
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        let blocks = ChatMarkdown.blocks(text)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                let isLast = index == blocks.count - 1
                switch block {
                case .text(let s):
                    if streaming && isLast {
                        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                            let on = Int(ctx.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                            (Text(Self.attributed(s)) + Text(" ▍").foregroundColor(claudeOrange.opacity(on ? 1 : 0.15)))
                                .font(.system(size: 12.5, design: .rounded))
                                .foregroundStyle(theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(Self.attributed(s))
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundStyle(theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code, streaming: streaming && isLast)
                }
            }
        }
    }

    static func attributed(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String
    let streaming: Bool
    @Environment(\.orbexTheme) private var theme
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "código")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(streaming)
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(red: 0.93, green: 0.9, blue: 0.86))
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

private struct ToolChipsView: View {
    let chips: [ToolChip]
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(chips) { chip in
                HStack(spacing: 5) {
                    switch chip.state {
                    case .running:
                        ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 10, height: 10)
                    case .done:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(claudeOrange)
                    case .failed:
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.red.opacity(0.8))
                    }
                    Text(chip.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.07)))
            }
        }
    }
}

private struct ThinkingRow: View {
    let note: String
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: theme.reduceMotion)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(claudeOrange)
                            .frame(width: 5, height: 5)
                            .offset(y: theme.reduceMotion ? 0 : -3 * max(0, sin(t * 6 - Double(i) * 0.7)))
                    }
                }
            }
            .frame(height: 10)
            Text(note)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Piezas chicas

private struct HeaderIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.orbexTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? theme.text : theme.secondaryText)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0.0)))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { h in withAnimation(theme.softSpring) { hovering = h } }
    }
}

private struct AttachmentChip: View {
    let name: String
    let bytes: Int
    let truncated: Bool
    let onRemove: () -> Void
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.text.fill").foregroundStyle(claudeOrange)
            Text(name).lineLimit(1).truncationMode(.middle)
            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) + (truncated ? " · cortado" : ""))
                .foregroundStyle(theme.tertiaryText)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Quitar")
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(theme.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .orbexPill()
    }
}

private struct ErrorBanner: View {
    let failure: ClaudeFailure
    let onRetry: () -> Void
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.35))
            Text(failure.message)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if failure.kind == .notLoggedIn || failure.kind == .notInstalled {
                Button("Abrir Terminal") {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                                       configuration: NSWorkspace.OpenConfiguration(),
                                                       completionHandler: nil)
                }
                .controlSize(.small)
            }
            if failure.isRetryable && failure.kind != .cancelled {
                Button("Reintentar", action: onRetry)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(claudeOrange)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.35, green: 0.16, blue: 0.08).opacity(0.85)))
    }
}

private struct EmptyChatView: View {
    let onSuggestion: (String) -> Void
    @Environment(\.orbexTheme) private var theme
    private let symbols = ["timer", "note.text", "app.badge", "lightbulb"]
    private let texts = ["Timer 5 min", "Anotá…", "Abrime…", "Explicame algo…"]

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            ClaudePetView(mood: .idle, size: 40)
            Text("¿En qué te doy una mano?")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.text)
            Text("Los timers, notas y apps los resuelve ORBEX al toque.\nLo demás se lo pregunto a Claude.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(texts.indices, id: \.self) { i in
                    OrbexActionButton(symbol: symbols[i], title: texts[i]) { onSuggestion(texts[i]) }
                }
            }
            .padding(.horizontal, 30)
            Text("Arrastrá un archivo de texto acá para adjuntarlo.")
                .font(.system(size: 9.5, design: .rounded))
                .foregroundStyle(theme.tertiaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

private struct MissingCLIView: View {
    let onRetry: () -> Void
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ClaudePetView(mood: .sad, size: 34)
                Text(ClaudeFailure.notInstalledMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            step(1, "Instalá Claude Code (en la Terminal):", code: "curl -fsSL https://claude.ai/install.sh | bash")
            step(2, "Abrí Claude Code y logueate con tu cuenta:", code: "claude")
            step(3, "Volvé acá y tocá “Volver a buscar”.", code: nil)
            HStack {
                Button("Volver a buscar", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(claudeOrange)
                Button("Abrir Terminal") {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                                       configuration: NSWorkspace.OpenConfiguration(),
                                                       completionHandler: nil)
                }
            }
            .controlSize(.small)
            Text("ORBEX usa tu Claude Code local con tu suscripción: no hacen falta claves de API.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(theme.tertiaryText)
        }
        .padding(16)
        .orbexCard(cornerRadius: 16)
        .padding(16)
    }

    private func step(_ n: Int, _ text: String, code: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(n). \(text)")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(theme.secondaryText)
            if let code {
                Text(code)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.5)))
            }
        }
    }
}

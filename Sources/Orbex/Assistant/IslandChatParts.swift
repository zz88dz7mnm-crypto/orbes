import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OrbexCore

// Piezas del chat de la isla (`PromptView` en Base/IslandViewContent.swift).
// Estilo de la isla: texto claro sobre fondo oscuro; acentos en naranja Claude.

/// Texto con Markdown en línea + bloques de código; con cursor titilando mientras llega.
struct ChatMarkdownText: View {
    let text: String
    let streaming: Bool
    var color: Color = Color(hex: "#DADDE2")

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
                                .font(.system(size: 12.5))
                                .foregroundColor(color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(Self.attributed(s))
                            .font(.system(size: 12.5))
                            .foregroundColor(color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .code(let language, let code):
                    ChatCodeBlock(language: language, code: code, streaming: streaming && isLast)
                }
            }
        }
    }

    static func attributed(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
    }
}

struct ChatCodeBlock: View {
    let language: String?
    let code: String
    let streaming: Bool
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "código")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: "#7C818A"))
                Spacer()
                Button {
                    ChatClipboard.copy(code)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(hex: "#9398A1"))
                }
                .buttonStyle(.plain)
                .disabled(streaming)
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(red: 0.93, green: 0.9, blue: 0.86))
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

/// Chips de herramientas que usa Claude (leer, buscar, editar…).
struct ChatToolChips: View {
    let chips: [ToolChip]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(chips) { chip in
                HStack(spacing: 5) {
                    switch chip.state {
                    case .running:
                        ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 10, height: 10)
                    case .done:
                        Image(systemName: "checkmark.circle.fill").foregroundColor(claudeOrange)
                    case .failed:
                        Image(systemName: "xmark.circle.fill").foregroundColor(Color.red.opacity(0.8))
                    }
                    Text(chip.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(Color(hex: "#9398A1"))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.07)))
            }
        }
    }
}

/// Adjunto pendiente (archivo soltado o elegido) antes de mandar.
struct ChatAttachmentChip: View {
    let name: String
    let bytes: Int
    let truncated: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.text.fill").foregroundColor(claudeOrange)
            Text(name).lineLimit(1).truncationMode(.middle)
            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) + (truncated ? " · cortado" : ""))
                .foregroundColor(Color(hex: "#7C818A"))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundColor(Color(hex: "#9398A1"))
            }
            .buttonStyle(.plain)
            .help("Quitar")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(Color(hex: "#F1F2F4"))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

/// Error de Claude con "Reintentar" (y "Abrir Terminal" si falta instalar o loguearse).
struct ChatErrorBanner: View {
    let failure: ClaudeFailure
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(red: 1, green: 0.72, blue: 0.35))
            Text(failure.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#F1F2F4"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if failure.kind == .notLoggedIn || failure.kind == .notInstalled {
                Button("Abrir Terminal") { ChatClipboard.openTerminal() }
                    .controlSize(.small)
            }
            if failure.isRetryable && failure.kind != .cancelled {
                Button("Reintentar", action: onRetry)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(claudeOrange)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(red: 0.35, green: 0.16, blue: 0.08).opacity(0.85)))
    }
}

/// "No encontré `claude`": pasos para instalarlo y loguearse.
struct ChatMissingCLIView: View {
    let checking: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ClaudePetView(mood: .sad, size: 24)
                Text(ClaudeFailure.notInstalledMessage)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color(hex: "#F1F2F4"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            step(1, "Instalá Claude Code en la Terminal:", code: "curl -fsSL https://claude.ai/install.sh | bash")
            step(2, "Abrilo y logueate con tu cuenta:", code: "claude")
            HStack(spacing: 8) {
                Button(checking ? "Buscando…" : "Volver a buscar", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(claudeOrange)
                    .disabled(checking)
                Button("Abrir Terminal") { ChatClipboard.openTerminal() }
                Text("Sin claves de API: usa tu suscripción.")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(hex: "#6E737C"))
            }
            .controlSize(.small)
        }
    }

    private func step(_ n: Int, _ text: String, code: String) -> some View {
        HStack(spacing: 6) {
            Text("\(n). \(text)")
                .font(.system(size: 10.5))
                .foregroundColor(Color(hex: "#9398A1"))
            Text(code)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(hex: "#F1F2F4"))
                .textSelection(.enabled)
                .lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.5)))
        }
    }
}

/// Sugerencias cuando la conversación está vacía.
struct ChatEmptyHints: View {
    let onSuggestion: (String) -> Void
    private let texts = ["Timer 5 min", "Anotá…", "Abrime…", "Explicame algo…"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("¿En qué te doy una mano?")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "#F1F2F4"))
            Text("Timers, notas y apps los resuelve ORBEX al toque; lo demás se lo pregunto a Claude. Soltá un archivo de texto para adjuntarlo.")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#9398A1"))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(texts, id: \.self) { t in
                    Button { onSuggestion(t) } label: {
                        Text(t)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Color(hex: "#F1F2F4"))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

enum ChatClipboard {
    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    /// Selector de archivos de texto para adjuntar (van como dato, hasta ~50 KB).
    @MainActor
    static func pickTextFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .text, .sourceCode, .json, .xml, .commaSeparatedText, .log]
        panel.message = "Elegí archivos de texto para que Claude los lea (van como dato, hasta ~50 KB)."
        panel.prompt = "Adjuntar"
        panel.level = .popUpMenu
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func openTerminal() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
    }
}

import Foundation

/// Bloque de una respuesta: texto (Markdown en línea) o código.
public enum ChatBlock: Equatable, Sendable {
    case text(String)
    case code(language: String?, code: String)
}

/// Parte una respuesta en bloques para pintarla: párrafos con Markdown en línea y bloques de código.
/// Tolera respuestas a medio llegar (un ``` sin cerrar se muestra como código hasta el final).
public enum ChatMarkdown {
    public static func blocks(_ source: String) -> [ChatBlock] {
        var blocks: [ChatBlock] = []
        var textLines: [String] = []
        var codeLines: [String] = []
        var inCode = false
        var language: String?

        func flushText() {
            let joined = textLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.trimmingCharacters(in: .whitespaces).isEmpty { blocks.append(.text(joined)) }
            textLines.removeAll()
        }

        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(language: language, code: codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                    language = nil
                } else {
                    flushText()
                    inCode = true
                    let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    language = lang.isEmpty ? nil : lang
                }
                continue
            }
            if inCode { codeLines.append(line) } else { textLines.append(prettify(line)) }
        }
        if inCode {
            blocks.append(.code(language: language, code: codeLines.joined(separator: "\n")))
        } else {
            flushText()
        }
        return blocks
    }

    /// Adapta una línea para el Markdown "solo en línea" de SwiftUI:
    /// títulos → negrita, viñetas → "•", citas → barra.
    public static func prettify(_ line: String) -> String {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(leading.count)
        // Títulos: "## Algo" → "**Algo**"
        if rest.hasPrefix("#") {
            let hashes = rest.prefix { $0 == "#" }
            let after = rest.dropFirst(hashes.count)
            if hashes.count <= 6, after.hasPrefix(" ") {
                let title = after.trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? "" : "**\(title)**"
            }
        }
        // Viñetas: "- algo" / "* algo" / "+ algo" → "• algo" (conserva la sangría).
        for marker in ["- ", "* ", "+ "] where rest.hasPrefix(marker) {
            return String(leading) + "• " + rest.dropFirst(2)
        }
        // Citas: "> algo" → "▎ algo"
        if rest.hasPrefix("> ") { return String(leading) + "▎ " + rest.dropFirst(2) }
        // Regla horizontal.
        if rest == "---" || rest == "***" || rest == "___" { return "———" }
        return line
    }
}

import Foundation

/// Una nota rápida (informe §9.4).
public struct Note: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public let created: Date
    /// Dónde quedó guardada (ruta del .md) o "Apple Notas".
    public var savedTo: String?

    public init(id: UUID = UUID(), text: String, created: Date = Date(), savedTo: String? = nil) {
        self.id = id
        self.text = text
        self.created = created
        self.savedTo = savedTo
    }

    /// Título corto: la primera línea, sin espacios de más y con mayúscula inicial.
    public var title: String { NoteFormat.title(for: text) }
}

/// Arma el nombre y el contenido de los archivos Markdown y el script de Apple Notas.
public enum NoteFormat {
    /// Primera línea recortada (máx. `maxLength` caracteres, con "…").
    public static func title(for text: String, maxLength: Int = 48) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var t = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if t.count > maxLength {
            t = String(t.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
        }
        guard let first = t.first else { return "Nota" }
        return first.uppercased() + t.dropFirst()
    }

    /// "2026-09-28 14.30 Comprar pan.md" (sin caracteres prohibidos en el Finder).
    public static func fileName(for note: Note, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: note.created)
        let stamp = String(format: "%04d-%02d-%02d %02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                           c.hour ?? 0, c.minute ?? 0)
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]{}").union(.newlines).union(.controlCharacters)
        var safeTitle = title(for: note.text, maxLength: 40)
            .components(separatedBy: forbidden).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while safeTitle.hasPrefix(".") { safeTitle.removeFirst() }
        safeTitle = safeTitle.trimmingCharacters(in: .whitespaces)
        return safeTitle.isEmpty ? "\(stamp) Nota.md" : "\(stamp) \(safeTitle).md"
    }

    /// Si `name` ya existe, agrega " 2", " 3"... antes de la extensión.
    public static func uniqueName(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !existing.contains(candidate) { return candidate }
            n += 1
        }
    }

    /// Contenido del archivo: título, texto y fecha.
    public static func markdown(for note: Note, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: note.created)
        let date = String(format: "%02d/%02d/%04d %02d:%02d", c.day ?? 0, c.month ?? 0, c.year ?? 0,
                          c.hour ?? 0, c.minute ?? 0)
        let body = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "# \(title(for: note.text))\n\n\(body)\n\n---\n_Anotado por ORBEX · \(date)_\n"
    }

    // MARK: - Apple Notas

    /// Escapa texto para HTML (el cuerpo de una nota de Apple Notas es HTML).
    public static func htmlEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Escapa texto para meterlo entre comillas en AppleScript.
    public static func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Cuerpo HTML: título en negrita y cada línea en su `<div>`.
    public static func appleNotesHTML(for note: Note) -> String {
        let lines = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).map { "<div>\(htmlEscaped(String($0)))</div>" }
        return "<div><b>\(htmlEscaped(title(for: note.text)))</b></div>" + lines.joined()
    }

    /// Script que crea la nota en la carpeta por defecto de Apple Notas.
    public static func appleNotesScript(for note: Note) -> String {
        let body = appleScriptEscaped(appleNotesHTML(for: note))
        return """
        tell application "Notes"
            try
                make new note with properties {body:"\(body)"}
            on error
                make new note at first folder of default account with properties {body:"\(body)"}
            end try
        end tell
        """
    }
}

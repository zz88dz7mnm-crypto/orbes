import AppKit
import OrbexCore

/// Notas rápidas: se guardan como Markdown en una carpeta o en Apple Notas (informe §9.4).
@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    enum Destination: Equatable {
        case markdownFolder(URL)
        case appleNotes
    }

    static let destinationKey = "orbex.utilities.notesDestination"
    static let folderKey = "orbex.utilities.notesFolder"
    static let defaultFolderPath = "~/Documents/ORBEX Notas"

    /// Últimas notas (la más nueva primero).
    @Published private(set) var recent: [Note] = []
    @Published private(set) var lastError: String?

    private let fileURL = AppPaths.dataFile("notes-recent.json")
    private let maxRecent = 30

    private init() {
        UserDefaults.standard.register(defaults: [
            Self.destinationKey: "markdown",
            Self.folderKey: Self.defaultFolderPath,
        ])
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Note].self, from: data) {
            recent = saved
        }
    }

    var destination: Destination {
        if UserDefaults.standard.string(forKey: Self.destinationKey) == "appleNotes" { return .appleNotes }
        return .markdownFolder(folderURL)
    }

    var folderURL: URL {
        let raw = UserDefaults.standard.string(forKey: Self.folderKey) ?? Self.defaultFolderPath
        let path = (raw.isEmpty ? Self.defaultFolderPath : raw) as NSString
        return URL(fileURLWithPath: path.expandingTildeInPath, isDirectory: true)
    }

    // MARK: - Guardar

    /// Guarda una nota. Devuelve el mensaje para mostrar ("Nota guardada" o el error).
    @discardableResult
    func add(_ text: String) async -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "La nota está vacía." }
        var note = Note(text: clean)
        switch destination {
        case .markdownFolder(let folder):
            do {
                note.savedTo = try Self.writeMarkdown(note, in: folder).path
            } catch {
                return fail("No pude guardar la nota en \(folder.path): \(error.localizedDescription)")
            }
        case .appleNotes:
            if let error = await Self.runAppleNotes(NoteFormat.appleNotesScript(for: note)) {
                return fail("No pude crear la nota en Apple Notas (\(error)). Revisá en Ajustes del Sistema › Privacidad › Automatización que ORBEX pueda usar Notas.")
            }
            note.savedTo = "Apple Notas"
        }
        recent.insert(note, at: 0)
        if recent.count > maxRecent { recent.removeLast(recent.count - maxRecent) }
        lastError = nil
        save()
        OrbexBus.play(.noteSaved)
        OrbexBus.toast("Nota guardada", symbol: "note.text")
        return "Nota guardada 📝"
    }

    func remove(_ id: UUID) {
        recent.removeAll { $0.id == id }
        save()
    }

    // MARK: - Acciones de la lista

    func copy(_ note: Note) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.text, forType: .string)
        OrbexBus.toast("Copiada", symbol: "doc.on.doc")
    }

    func reveal(_ note: Note) {
        if let path = note.savedTo, path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else if note.savedTo == "Apple Notas" {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(),
                                                   completionHandler: nil)
            }
        } else {
            copy(note)
        }
    }

    func openFolder() {
        let folder = folderURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    // MARK: - Internos

    private func fail(_ message: String) -> String {
        lastError = message
        OrbexBus.play(.error)
        OrbexBus.react(.worry)
        return message
    }

    private func save() {
        do {
            try JSONEncoder().encode(recent).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("ORBEX: no pude guardar las notas recientes: \(error.localizedDescription)")
        }
    }

    private static func writeMarkdown(_ note: Note, in folder: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let existing = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        let name = NoteFormat.uniqueName(NoteFormat.fileName(for: note), existing: existing)
        let url = folder.appendingPathComponent(name)
        try NoteFormat.markdown(for: note).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Corre el AppleScript en segundo plano. Devuelve el error (o nil si salió bien).
    nonisolated private static func runAppleNotes(_ source: String) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorInfo: NSDictionary?
                let script = NSAppleScript(source: source)
                _ = script?.executeAndReturnError(&errorInfo)
                if script == nil {
                    cont.resume(returning: "script inválido")
                } else if let info = errorInfo {
                    let msg = info[NSAppleScript.errorMessage] as? String ?? "error desconocido"
                    cont.resume(returning: msg)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

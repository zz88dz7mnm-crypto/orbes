import Foundation
import OrbexCore

/// Memoria local de ORBEX (informe §9.7): cosas que el usuario le pide recordar.
/// Todo queda en esta Mac (`memory.json`); solo sale como contexto en una consulta al asistente.
@MainActor
final class MemoryStore: ObservableObject {
    static let shared = MemoryStore()

    @Published private(set) var book = MemoryBook()

    var facts: [MemoryFact] { book.facts }
    var factTexts: [String] { book.facts.map(\.text) }

    private let url = AppPaths.dataFile("memory.json")

    private init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(MemoryBook.self, from: data) {
            book = saved
        }
        // El asistente manda estos datos como contexto.
        AssistantStore.shared.memoryProvider = { MemoryStore.shared.factTexts }
    }

    @discardableResult
    func add(_ text: String) -> Bool {
        let ok = book.add(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if ok { save() }
        return ok
    }

    @discardableResult
    func edit(id: UUID, text: String) -> Bool {
        let ok = book.edit(id: id, text: text)
        if ok { save() }
        return ok
    }

    func delete(id: UUID) {
        book.delete(id: id)
        save()
    }

    func clearAll() {
        book.clearAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(book) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

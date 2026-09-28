import SwiftUI
import OrbexCore

/// Configuración › Memoria: ver, editar y borrar todo lo que ORBEX aprendió.
struct MemorySettingsView: View {
    @ObservedObject private var store = MemoryStore.shared
    @State private var newFact = ""
    @State private var editingID: UUID?
    @State private var editingText = ""
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Lo que ORBEX sabe de vos") {
                if store.facts.isEmpty {
                    Text("Todavía no le pediste que se acuerde de nada. Probá: \"acordate que mi perro se llama Toto\".")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.facts) { fact in
                    HStack {
                        if editingID == fact.id {
                            TextField("Dato", text: $editingText)
                                .onSubmit { saveEdit(fact.id) }
                            Button("Guardar") { saveEdit(fact.id) }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fact.text)
                                Text(fact.createdAt, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                editingID = fact.id
                                editingText = fact.text
                            } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            Button(role: .destructive) {
                                store.delete(id: fact.id)
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                HStack {
                    TextField("Agregar un dato", text: $newFact)
                        .onSubmit(add)
                    Button("Agregar", action: add)
                        .disabled(newFact.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                Button("Borrar todo", role: .destructive) { confirmClear = true }
                    .disabled(store.facts.isEmpty)
                Text("Todo queda en esta Mac. Solo se manda como contexto cuando le preguntás algo al asistente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("¿Borrar todo lo que ORBEX recuerda?", isPresented: $confirmClear) {
            Button("Borrar todo", role: .destructive) { store.clearAll() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func add() {
        if store.add(newFact) { newFact = "" }
    }

    private func saveEdit(_ id: UUID) {
        store.edit(id: id, text: editingText)
        editingID = nil
    }
}

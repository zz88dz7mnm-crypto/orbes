import SwiftUI
import OrbexCore

/// Vista "Notas" de la isla: anotar algo rápido y ver las últimas (tocar copia, la carpeta la muestra).
struct NotesIslandView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = NotesStore.shared
    @State private var draft = ""
    @State private var saving = false
    @FocusState private var focused: Bool

    private var savesToFolder: Bool { store.destination != .appleNotes }
    private var canSave: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving }

    var body: some View {
        CardBackground(wash: nil) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Anotá algo y apretá Enter…", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundColor(IslandPalette.text)
                        .focused($focused)
                        .onSubmit(save)
                    Button(action: save) {
                        Image(systemName: saving ? "hourglass" : "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#0B0C0E"))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(canSave ? IslandPalette.text : IslandPalette.tertiary))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .help("Guardar nota")
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                .simultaneousGesture(TapGesture().onEnded { focused = true })
                .background(IslandKeyWindowGrabber())

                if let error = store.lastError {
                    Text(error)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(Color(hex: "#F5A524"))
                        .lineLimit(2)
                }

                HStack {
                    Text(store.recent.isEmpty ? "Últimas notas" : "Últimas notas · tocá una para copiarla")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(IslandPalette.tertiary)
                    Spacer(minLength: 0)
                    if savesToFolder {
                        IslandChipButton(title: "Carpeta", symbol: "folder", tint: IslandPalette.secondary,
                                         height: 18, help: "Abrir la carpeta de notas") {
                            store.openFolder()
                        }
                    }
                }

                if store.recent.isEmpty {
                    Text("Todavía no hay notas. Escribí una o decime \"anotá que…\" 📝")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(IslandPalette.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(store.recent) { note in
                                IslandNoteRow(note: note)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.leading, IslandPalette.botGutter)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .onAppear { focused = true }
    }

    private func save() {
        let text = draft
        guard canSave else { return }
        saving = true
        Task { @MainActor in
            let message = await store.add(text)
            saving = false
            if message.hasPrefix("Nota guardada") { draft = "" }
            focused = true
        }
    }
}

/// Fila de nota en la isla: tocar copia; el botón la muestra en el Finder (o abre Notas); la cruz la saca de la lista.
struct IslandNoteRow: View {
    let note: Note
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(note.title)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundColor(IslandPalette.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(note.created, format: .dateTime.day().month(.abbreviated).hour().minute())
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(IslandPalette.tertiary)
                .lineLimit(1)
            IslandIconButton(symbol: note.savedTo == "Apple Notas" ? "note.text" : "folder", size: 18, font: 9,
                             help: note.savedTo == "Apple Notas" ? "Abrir Notas" : "Mostrar en el Finder") {
                NotesStore.shared.reveal(note)
            }
            if hovered {
                IslandIconButton(symbol: "xmark", size: 18, font: 8.5, help: "Sacar de la lista (el archivo queda)") {
                    NotesStore.shared.remove(note.id)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hovered ? 0.08 : 0.05)))
        .contentShape(Rectangle())
        .onTapGesture { NotesStore.shared.copy(note) }
        .onHover { hovered = $0 }
        .help("Tocá para copiar")
    }
}

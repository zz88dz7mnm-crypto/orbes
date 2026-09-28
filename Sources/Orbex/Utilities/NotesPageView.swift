import SwiftUI
import OrbexCore

/// Página "Notas" de la isla abierta (≈ 270 × 230 pt): anotar rápido y ver las últimas.
struct NotesPageView: View {
    @ObservedObject private var store = NotesStore.shared
    @Environment(\.orbexTheme) private var theme
    @State private var draft = ""
    @State private var saving = false

    init() {}

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TextField("Anotá algo…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(theme.text)
                    .onSubmit(save)
                Button(action: save) {
                    Image(systemName: saving ? "hourglass" : "arrow.up.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(draft.isEmpty ? theme.tertiaryText : theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                .help("Guardar nota")
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .orbexCard(cornerRadius: 12)

            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(Color.orange)
                    .lineLimit(2)
            }

            if store.recent.isEmpty {
                Spacer(minLength: 0)
                Text("Todavía no hay notas. Escribí una o decime \"anotá que…\" 📝")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(store.recent) { note in
                            NoteRow(note: note)
                        }
                    }
                }
            }
        }
        .background(Color.black)
    }

    private func save() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !saving else { return }
        saving = true
        Task { @MainActor in
            let message = await store.add(text)
            saving = false
            if message.hasPrefix("Nota guardada") { draft = "" }
        }
    }
}

/// Fila de nota: tocar copia; el botón la muestra en el Finder (o abre Notas).
struct NoteRow: View {
    let note: Note
    @Environment(\.orbexTheme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(note.created, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(theme.tertiaryText)
            }
            Spacer(minLength: 0)
            Button {
                NotesStore.shared.reveal(note)
            } label: {
                Image(systemName: note.savedTo == "Apple Notas" ? "note.text" : "folder")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(note.savedTo == "Apple Notas" ? "Abrir Notas" : "Mostrar en el Finder")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .orbexCard(cornerRadius: 10)
        .opacity(hovering ? 1 : 0.92)
        .contentShape(Rectangle())
        .onTapGesture { NotesStore.shared.copy(note) }
        .onHover { hovering = $0 }
        .help("Tocá para copiar")
    }
}

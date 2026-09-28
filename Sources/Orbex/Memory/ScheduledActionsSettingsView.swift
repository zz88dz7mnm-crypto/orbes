import SwiftUI
import OrbexCore

/// Configuración › Programados: recordatorios y acciones con hora (informe §9.6).
struct ScheduledActionsSettingsView: View {
    @ObservedObject private var store = SchedulerStore.shared
    @AppStorage(SchedulerStore.missedPolicyKey) private var missedPolicy = MissedPolicy.runOnWake.rawValue
    @State private var newDate = Date().addingTimeInterval(3600)
    @State private var newText = ""

    var body: some View {
        Form {
            Section("Pendientes") {
                if store.actions.filter({ !$0.done }).isEmpty {
                    Text("No hay nada programado. Decile a ORBEX: \"recordame a las 18 llamar a mamá\".")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.actions.filter { !$0.done }) { item in
                    row(item)
                }
            }

            Section("Nuevo recordatorio") {
                DatePicker("Cuándo", selection: $newDate, in: Date()...)
                HStack {
                    TextField("Qué te recuerdo", text: $newText)
                        .onSubmit(addReminder)
                    Button("Agregar", action: addReminder)
                        .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Si la Mac estaba dormida") {
                Picker("Lo que venció mientras dormía", selection: $missedPolicy) {
                    Text("Hacerlo al despertar").tag(MissedPolicy.runOnWake.rawValue)
                    Text("Solo avisarme").tag(MissedPolicy.notifyOnly.rawValue)
                }
                Text("Las acciones que no están en tu lista de acciones siempre piden confirmación.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ item: ScheduledAction) -> some View {
        HStack {
            Image(systemName: isReminder(item) ? "bell" : "bolt")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text("\(isReminder(item) ? "Recordatorio" : "Acción") · \(item.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                store.remove(id: item.id)
            } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless)
            .help("Borrar")
        }
    }

    private func isReminder(_ item: ScheduledAction) -> Bool {
        if case .reminder = item.kind { return true }
        return false
    }

    private func addReminder() {
        let text = newText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        store.addReminder(at: newDate, text: text)
        newText = ""
    }
}

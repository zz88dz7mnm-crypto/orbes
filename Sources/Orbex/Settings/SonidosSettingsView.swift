import SwiftUI
import OrbexCore

/// Configuración › Sonidos: volumen, horario silencioso, ducking y cada evento con vista previa.
struct SonidosSettingsView: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject private var island = AppState.shared

    var body: some View {
        Form {
            Section {
                Toggle("Activar sonidos", isOn: $model.settings.soundEnabled)
                SettingsSliderRow(title: "Volumen", value: $model.settings.volume,
                                  range: 0...1, step: 0.05, format: SettingsFormat.percent)
                    .disabled(!model.settings.soundEnabled)
                Toggle("Bajar el volumen cuando suena música", isOn: $model.settings.duckWithMusic)
                    .disabled(!model.settings.soundEnabled)
                SettingsFootnote(text: "Todos los sonidos se sintetizan en la misma escala, así nunca desafinan entre sí. De noche suenan un poco más bajo.")
            } header: {
                Text("General")
            }

            Section {
                Toggle("Sonidos de la isla", isOn: $island.soundEnabled)
                    .disabled(!model.settings.soundEnabled)
                SettingsSliderRow(title: "Volumen de la isla", value: $island.soundVolume,
                                  range: 0...0.2, step: 0.01, format: { SettingsFormat.percent($0 / 0.2) })
                    .disabled(!model.settings.soundEnabled || !island.soundEnabled)
                SettingsFootnote(text: "Asomarse, abrir, tragar un archivo, caricias… Se suma al volumen general de arriba.")
            } header: {
                Text("Isla")
            }

            Section {
                Toggle("Horario silencioso", isOn: $model.settings.quietHoursEnabled)
                SettingsHourPicker(title: "Desde", hour: $model.settings.quietStartHour)
                    .disabled(!model.settings.quietHoursEnabled)
                SettingsHourPicker(title: "Hasta", hour: $model.settings.quietEndHour)
                    .disabled(!model.settings.quietHoursEnabled)
            } header: {
                Text("Silencio")
            }

            ForEach(Self.groups, id: \.title) { group in
                Section {
                    ForEach(group.sounds, id: \.self) { sound in
                        row(sound)
                    }
                } header: {
                    Text(group.title)
                }
            }

            Section {
                HStack {
                    Button("Activar todos") {
                        model.settings.mutedSounds = []
                    }
                    .disabled(model.settings.mutedSounds.isEmpty)
                    Button("Silenciar todos") {
                        model.settings.mutedSounds = OrbexSound.allCases.map { $0.rawValue }
                    }
                    Spacer()
                }
                SettingsFootnote(text: "▶︎ hace sonar el evento con el tema actual, aunque esté silenciado.")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ sound: OrbexSound) -> some View {
        HStack(spacing: 10) {
            Button {
                SoundEngine.shared.preview(sound, theme: model.settings.theme)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .help("Escuchar")
            .accessibilityLabel("Escuchar \(Self.label(for: sound))")

            Toggle(isOn: $model.settings.mutedSounds.excluding(sound.rawValue)) {
                Text(Self.label(for: sound))
            }
        }
    }

    // MARK: - Nombres y grupos

    private struct SoundGroup {
        let title: String
        let sounds: [OrbexSound]
    }

    private static let groups: [SoundGroup] = {
        var list: [SoundGroup] = [
            SoundGroup(title: "Personaje", sounds: [.greet, .tap, .annoyed, .dizzy, .rareBlink, .sleep, .wake, .surprise]),
            SoundGroup(title: "Isla", sounds: [.peek, .open, .close, .needsYou, .toClock, .toNotch]),
            SoundGroup(title: "Asistente y código", sounds: [.assistantMessage, .thinking, .fileSwallowed, .answered,
                                                             .permissionGranted, .permissionDenied, .sessionDone, .error]),
            SoundGroup(title: "Timers y notas", sounds: [.timerStart, .tick, .timerDone, .alarm, .lap, .noteSaved]),
            SoundGroup(title: "Música", sounds: [.newSong]),
        ]
        // Si se agregan sonidos nuevos y nadie los agrupó, que aparezcan igual.
        let grouped = Set(list.flatMap { $0.sounds })
        let others = OrbexSound.allCases.filter { !grouped.contains($0) }
        if !others.isEmpty { list.append(SoundGroup(title: "Otros", sounds: others)) }
        return list
    }()

    private static let labels: [OrbexSound: String] = [
        .greet: "Saludo al arrancar",
        .peek: "Asomarse",
        .open: "Abrir la isla",
        .close: "Cerrar la isla",
        .tap: "Toque",
        .annoyed: "Molesto",
        .dizzy: "Mareado",
        .rareBlink: "Parpadeo especial",
        .sleep: "Dormirse",
        .wake: "Despertarse",
        .needsYou: "Te necesita",
        .permissionGranted: "Permiso concedido",
        .permissionDenied: "Permiso denegado",
        .answered: "Pregunta respondida",
        .sessionDone: "Terminó una tarea",
        .error: "Error",
        .assistantMessage: "Mensaje del asistente",
        .thinking: "Pensando",
        .fileSwallowed: "Archivo tragado",
        .timerStart: "Timer iniciado",
        .tick: "Tic",
        .timerDone: "Timer terminado",
        .alarm: "Alarma",
        .lap: "Vuelta del cronómetro",
        .noteSaved: "Nota guardada",
        .newSong: "Canción nueva",
        .toClock: "Pasar a reloj",
        .toNotch: "Volver al notch",
        .surprise: "Sorpresa",
    ]

    static func label(for sound: OrbexSound) -> String {
        labels[sound] ?? sound.rawValue
    }
}

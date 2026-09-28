import SwiftUI
import OrbexCore

/// Configuración › Personaje: nivel de vida, color, nombre, saludo, sueño y tamaño.
struct PersonajeSettingsView: View {
    @ObservedObject var model = AppModel.shared

    var body: some View {
        Form {
            Section {
                Picker("Nivel de vida", selection: $model.settings.lifeLevel) {
                    ForEach(LifeLevel.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                SettingsFootnote(text: lifeHint)
            } header: {
                Text("Vida")
            }

            Section {
                LabeledContent("Color") {
                    HStack(spacing: 8) {
                        ForEach(OrbexTint.allCases, id: \.self) { tint in
                            swatch(tint)
                        }
                        Text(model.settings.tint.label)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 84, alignment: .leading)
                    }
                }
                SettingsFootnote(text: "Algunas funciones lo tiñen un rato (por ejemplo, el asistente lo pone naranja) y después vuelve a este color.")
            } header: {
                Text("Color")
            }

            Section {
                TextField("Tu nombre", text: $model.settings.userName, prompt: Text("Opcional"))
                Toggle("Saludar al arrancar", isOn: $model.settings.greetOnLaunch)
                SettingsFootnote(text: "Así te saluda ahora: \(Greeting.text(hour: currentHour, name: trimmedName))",
                                 symbol: "text.bubble")
            } header: {
                Text("Personalidad")
            }

            Section {
                Toggle("Dormir de noche", isOn: $model.settings.sleep.enabled)
                SettingsHourPicker(title: "Se duerme a las", hour: $model.settings.sleep.startHour)
                    .disabled(!model.settings.sleep.enabled)
                SettingsHourPicker(title: "Se despierta a las", hour: $model.settings.sleep.endHour)
                    .disabled(!model.settings.sleep.enabled)
                Stepper(value: $model.settings.sleep.idleMinutes, in: 0...120, step: 5) {
                    Text("Dormirse sin actividad: \(idleText)")
                }
                .disabled(!model.settings.sleep.enabled)
                SettingsFootnote(text: sleepSummary, symbol: "moon.zzz")
            } header: {
                Text("Dormir")
            }

            Section {
                SettingsSliderRow(title: "Tamaño", value: $model.settings.characterScale,
                                  range: 0.8...1.3, step: 0.05, format: SettingsFormat.percent)
            } header: {
                Text("Tamaño")
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        CharacterBrain.shared.greet()
                        OrbexBus.play(.greet)
                    } label: {
                        Label("Saludar", systemImage: "hand.wave")
                    }
                    Button {
                        CharacterBrain.shared.celebrate()
                        OrbexBus.play(.sessionDone)
                    } label: {
                        Label("Festejar", systemImage: "party.popper")
                    }
                    Button {
                        for _ in 0..<3 { CharacterBrain.shared.tap() }
                    } label: {
                        Label("Marear", systemImage: "tornado")
                    }
                    Spacer()
                }
                SettingsFootnote(text: "También podés tocarlo en la vista previa: un toque lo achata, tres rápidos lo marean.")
            } header: {
                Text("Probar")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Piezas

    private func swatch(_ tint: OrbexTint) -> some View {
        let c = tint.rgb
        let selected = model.settings.tint == tint
        return Button {
            model.settings.tint = tint
        } label: {
            Circle()
                .fill(Color(red: c.r, green: c.g, blue: c.b).opacity(tint == .clear ? 0.45 : 1))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                .frame(width: 20, height: 20)
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(tint.label)
        .accessibilityLabel(tint.label)
    }

    // MARK: - Textos

    private var lifeHint: String {
        switch model.settings.lifeLevel {
        case .calm: return "Se mueve poco: ideal para concentrarse."
        case .normal: return "Parpadea, respira y hace gestitos cada tanto."
        case .hyper: return "Siempre está haciendo algo."
        }
    }

    private var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    private var trimmedName: String {
        model.settings.userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var idleText: String {
        let m = model.settings.sleep.idleMinutes
        return m == 0 ? "nunca" : SettingsFormat.minutes(m)
    }

    private var sleepSummary: String {
        let s = model.settings.sleep
        guard s.enabled else { return "ORBEX no se va a dormir nunca." }
        var text = "Duerme de \(SettingsFormat.hour(s.startHour)) a \(SettingsFormat.hour(s.endHour))"
        if s.idleMinutes > 0 {
            text += " o después de \(SettingsFormat.minutes(s.idleMinutes)) sin usar la Mac"
        }
        return text + "."
    }
}

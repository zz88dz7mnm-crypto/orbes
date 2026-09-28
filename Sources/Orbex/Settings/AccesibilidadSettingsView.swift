import SwiftUI
import OrbexCore

/// Configuración › Accesibilidad y rendimiento: movimiento, ahorro de energía y cuadros por segundo.
struct AccesibilidadSettingsView: View {
    @ObservedObject var model = AppModel.shared

    private static let fpsOptions = [24, 30, 60, 120]

    var body: some View {
        Form {
            Section {
                Toggle("Reducir movimiento", isOn: $model.settings.reduceMotion)
                if model.systemReduceMotion {
                    SettingsFootnote(text: "“Reducir movimiento” está activado en macOS: ORBEX ya se mueve menos (respira y parpadea, sin saltos ni giros).",
                                     symbol: "figure.walk")
                } else {
                    SettingsFootnote(text: "Sin saltos, giros ni microgestos: solo respira y parpadea. También se activa solo si lo pedís en Ajustes del Sistema › Accesibilidad.")
                }
            } header: {
                Text("Movimiento")
            }

            Section {
                Toggle("Modo ahorro", isOn: $model.settings.lowPowerMode)
                Picker("Cuadros por segundo (máx.)", selection: $model.settings.maxFPS) {
                    ForEach(Self.fpsOptions, id: \.self) { fps in
                        Text("\(fps)").tag(fps)
                    }
                    if !Self.fpsOptions.contains(model.settings.maxFPS) {
                        Text("\(model.settings.maxFPS)").tag(model.settings.maxFPS)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.settings.lowPowerMode)
                LabeledContent("Ahora") {
                    Text("\(Int(model.characterFPS)) cuadros por segundo")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                SettingsFootnote(text: powerNote, symbol: model.lowPower ? "battery.25" : "bolt")
            } header: {
                Text("Rendimiento")
            }
        }
        .formStyle(.grouped)
    }

    private var powerNote: String {
        if model.lowPower {
            return "El Modo de bajo consumo de macOS está activado: ORBEX baja solo a 24 cuadros por segundo."
        }
        if model.settings.lowPowerMode {
            return "Modo ahorro: 24 cuadros por segundo y menos trabajo en segundo plano."
        }
        return "Con la isla oculta ORBEX casi no usa CPU. Si también activás el Modo de bajo consumo de macOS, baja solo a 24 cuadros."
    }
}

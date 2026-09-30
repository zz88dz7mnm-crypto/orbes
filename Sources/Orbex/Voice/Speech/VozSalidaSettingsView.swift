import AppKit
import SwiftUI

/// Configuración › Voz de Orbi: que Orbi conteste hablando, con qué motor y qué voz.
struct VozSalidaSettingsView: View {
    @ObservedObject private var voice = OrbiVoice.shared
    @AppStorage(OrbiVoiceSettings.Keys.enabled) private var enabled = true
    @AppStorage(OrbiVoiceSettings.Keys.backend) private var backendPref = "auto"
    @AppStorage(OrbiVoiceSettings.Keys.speed) private var speed = 1.0
    @AppStorage(OrbiVoiceSettings.Keys.kokoroVoice) private var kokoroVoice = OrbiVoiceSettings.defaultKokoroVoice
    @AppStorage(OrbiVoiceSettings.Keys.cartesiaVoice) private var cartesiaVoice = ""
    @AppStorage(OrbiVoiceSettings.Keys.systemVoice) private var systemVoice = ""
    @State private var cartesiaKey = ""
    @State private var hasCartesiaKey = CartesiaClient.isConfigured
    @State private var systemOptions: [SystemVoicePicker.Option] = []
    @State private var onlyBasic = false
    @State private var copied = false

    private static let sample = "¡Hola! Soy Orbi."

    var body: some View {
        Form {
            Section {
                Toggle("Orbi contesta hablando", isOn: $enabled)
                    .onChange(of: enabled) { _, on in if !on { voice.stop() } }
                SettingsFootnote(text: "Cuando le pedís algo, Orbi te responde en voz alta. Mientras habla, el micrófono deja de escucharlo para no confundirse con su propia voz.",
                                 symbol: "speaker.wave.2")
            } header: {
                Text("Voz de Orbi")
            }

            Section("Motor") {
                Picker("Usar", selection: $backendPref) {
                    Text("Automático (el mejor disponible)").tag("auto")
                    ForEach(OrbiVoiceBackend.allCases) { b in
                        Text(b.title).tag(b.rawValue)
                    }
                }
                .onChange(of: backendPref) { _, _ in voice.refreshAvailability() }
                LabeledContent("Ahora usa") {
                    Text(voice.backendLabel).foregroundStyle(.secondary)
                }
                SettingsSliderRow(title: "Velocidad", value: $speed, range: 0.7...1.4, step: 0.05) {
                    String(format: "%.2f×", $0)
                }
                HStack {
                    Button {
                        voice.speak(Self.sample)
                    } label: {
                        Label("Probar", systemImage: "play.fill")
                    }
                    .disabled(!enabled)
                    if voice.isSpeaking {
                        Button {
                            voice.stop()
                        } label: {
                            Label("Callar", systemImage: "stop.fill")
                        }
                    }
                }
                if let problem = voice.lastProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SettingsFootnote(text: "Orden automático: Kokoro (local) → Cartesia (si cargaste la clave) → voz de macOS. Si uno falla, sigue con el siguiente.")
            }

            Section("Kokoro · voz natural, en tu Mac") {
                LabeledContent("Estado") {
                    if voice.kokoroInstalled {
                        Label("Instalado", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("No instalado", systemImage: "xmark.circle").foregroundStyle(.secondary)
                    }
                }
                Picker("Voz", selection: $kokoroVoice) {
                    ForEach(OrbiVoiceSettings.kokoroVoices) { v in
                        Text(v.name).tag(v.id)
                    }
                }
                .onChange(of: kokoroVoice) { _, _ in voice.refreshAvailability() }
                if !voice.kokoroInstalled {
                    SettingsFootnote(text: "Para instalarla, abrí Terminal y corré este comando (crea un entorno de Python, instala Kokoro y baja el modelo, unos 330 MB; la primera vez tarda unos minutos):",
                                     symbol: "terminal")
                    Text(OrbiVoicePaths.installCommand)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                }
                HStack {
                    if !voice.kokoroInstalled {
                        Button(copied ? "Copiado" : "Copiar comando") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(OrbiVoicePaths.installCommand, forType: .string)
                            copied = true
                        }
                        Button("Abrir Terminal") {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    Button("Volver a comprobar") { voice.refreshAvailability() }
                }
                SettingsFootnote(text: "Kokoro corre en tu Mac: el texto no sale a internet.", symbol: "lock")
            }

            Section("Cartesia · en la nube (opcional)") {
                if hasCartesiaKey {
                    LabeledContent("Clave") {
                        HStack {
                            Text("Guardada en el Llavero").foregroundStyle(.secondary)
                            Button("Borrar") {
                                KeychainStore.shared.remove(OrbiVoiceSettings.cartesiaKeyAccount)
                                hasCartesiaKey = false
                                voice.refreshAvailability()
                            }
                        }
                    }
                } else {
                    HStack {
                        SecureField("Clave de API de Cartesia", text: $cartesiaKey)
                        Button("Guardar") {
                            KeychainStore.shared.set(OrbiVoiceSettings.cartesiaKeyAccount, value: cartesiaKey)
                            cartesiaKey = ""
                            hasCartesiaKey = CartesiaClient.isConfigured
                            voice.refreshAvailability()
                        }
                        .disabled(cartesiaKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                TextField("ID de la voz", text: $cartesiaVoice, prompt: Text(OrbiVoiceSettings.defaultCartesiaVoice))
                    .font(.system(.body, design: .monospaced))
                SettingsFootnote(text: "Con Cartesia, el texto de las respuestas de Orbi viaja a sus servidores para convertirlo en voz. La clave queda solo en el Llavero de esta Mac. Elegí una voz en español en play.cartesia.ai y pegá su ID.",
                                 symbol: "cloud")
            }

            Section("Voz de macOS (respaldo)") {
                Picker("Voz", selection: $systemVoice) {
                    Text("La mejor en español").tag("")
                    ForEach(systemOptions) { o in
                        Text(o.label).tag(o.id)
                    }
                }
                if onlyBasic {
                    SettingsFootnote(text: "Solo tenés voces básicas en español y suenan robóticas. Bajá una mejorada o premium (por ejemplo, Mónica o Paulina) en Ajustes del Sistema › Accesibilidad › Contenido leído › Voz del sistema › Administrar voces.",
                                     symbol: "arrow.down.circle")
                    Button("Abrir Contenido leído") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
    }

    private func reload() {
        voice.refreshAvailability()
        hasCartesiaKey = CartesiaClient.isConfigured
        systemOptions = SystemVoicePicker.options()
        onlyBasic = SystemVoicePicker.onlyBasicAvailable
        if !systemVoice.isEmpty && !systemOptions.contains(where: { $0.id == systemVoice }) {
            systemVoice = ""
        }
        copied = false
    }
}

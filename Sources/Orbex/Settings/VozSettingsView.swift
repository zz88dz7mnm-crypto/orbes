import SwiftUI
import OrbexCore

/// Configuración › Voz: hablarle a ORBEX ("Orbex, abrí Spotify") y que lo haga.
struct VozSettingsView: View {
    @ObservedObject private var voice = VoiceController.shared
    @AppStorage(VoiceSettings.Keys.enabled) private var enabled = false
    @AppStorage(VoiceSettings.Keys.alwaysListening) private var alwaysListening = false
    @AppStorage(VoiceSettings.Keys.pauseOnLowPower) private var pauseOnLowPower = true
    @AppStorage(VoiceSettings.Keys.pushToTalk) private var pushToTalk = true
    @AppStorage(VoiceSettings.Keys.longPress) private var longPress = false
    @AppStorage(VoiceSettings.Keys.chime) private var chime = true
    @AppStorage(VoiceSettings.Keys.locale) private var localeID = "auto"
    @AppStorage(VoiceSettings.Keys.allowCloud) private var allowCloud = false
    @AppStorage(VoiceSettings.Keys.extraNames) private var extraNames = ""
    @State private var probe: (id: String, onDevice: Bool)?
    @State private var probed = false

    private static let examples: [(String, String)] = [
        ("Orbex, abrí Spotify", "abre la app"),
        ("Orbi, poné un timer de 10 minutos", "timer"),
        ("Orbex, anotá comprar pan", "nota"),
        ("Orbex, recordame a las 6 llamar a mamá", "recordatorio"),
        ("Orbex, modo reloj", "reloj flotante"),
        ("Orbex, ¿qué es un agujero negro?", "se lo pregunta a Claude"),
        ("Orbex… cancelá", "no hace nada"),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Hablarle a ORBEX", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in voice.settingsDidChange() }
                SettingsFootnote(text: "Le decís \"Orbex, …\" y lo hace, sin contestarte hablando: abre apps, pone timers, anota, te recuerda cosas o le pregunta a Claude. Mientras te escucha se pone magenta y pone la mano en la oreja.",
                                 symbol: "waveform")
                if enabled && !voice.permissionsGranted {
                    SettingsFootnote(text: "La primera vez, macOS te va a pedir permiso para el micrófono y para el reconocimiento de voz. El audio se procesa en tu Mac: no se graba ni sale a internet.",
                                     symbol: "lock.shield")
                }
                if let problem = voice.problem, enabled || voice.isTesting {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Voz")
            }

            Section("Cómo lo activás") {
                Toggle("Siempre atento a su nombre", isOn: $alwaysListening)
                    .onChange(of: alwaysListening) { _, _ in voice.settingsDidChange() }
                    .disabled(!enabled)
                SettingsFootnote(text: "El micrófono queda abierto esperando \"Orbex\" (vas a ver el punto naranja en la barra de menús). Gasta algo de batería; se pausa solo con la pantalla bloqueada o la Mac dormida.",
                                 symbol: "ear")
                Toggle("Pausar en bajo consumo o modo ahorro", isOn: $pauseOnLowPower)
                    .onChange(of: pauseOnLowPower) { _, _ in voice.settingsDidChange() }
                    .disabled(!enabled || !alwaysListening)
                if voice.pausedForPower && alwaysListening && enabled {
                    SettingsFootnote(text: "En pausa: la Mac está en bajo consumo. El atajo sigue andando.", symbol: "battery.25")
                }

                Toggle("Atajo de teclado para hablarle", isOn: $pushToTalk)
                    .onChange(of: pushToTalk) { _, _ in voice.settingsDidChange() }
                    .disabled(!enabled)
                LabeledContent("Atajo") {
                    Text(voice.hotKeyLabel ?? (enabled && pushToTalk ? "No disponible" : "⌃⌥Espacio"))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(voice.hotKeyLabel == nil ? Color.secondary : Color.primary)
                }
                SettingsFootnote(text: "Tocalo, decí el pedido (sin el nombre) y callate: ORBEX entiende que terminaste. Tocalo de nuevo para cortar antes. Si macOS usa ⌃⌥Espacio para cambiar la fuente de entrada, ORBEX usa ⌃⌥V.")
                Toggle("Mantener apretado ORBEX en la isla para hablarle", isOn: $longPress)
                    .onChange(of: longPress) { _, _ in voice.settingsDidChange() }
                    .disabled(!enabled)
                Toggle("Sonidito cuando empieza a escuchar", isOn: $chime)
                    .disabled(!enabled)
            }

            Section("Estado") {
                LabeledContent("Ahora") {
                    HStack(spacing: 6) {
                        Circle().fill(phaseColor).frame(width: 8, height: 8)
                        Text(voice.phase.label).foregroundStyle(.secondary)
                    }
                }
                permissionRow("Micrófono", voice.micPermission, url: VoicePermissions.microphoneSettings)
                permissionRow("Reconocimiento de voz", voice.speechPermission, url: VoicePermissions.speechSettings)
                if voice.micPermission == .denied || voice.speechPermission == .denied
                    || voice.micPermission == .restricted || voice.speechPermission == .restricted {
                    SettingsFootnote(text: "Para habilitarlo: Ajustes del Sistema › Privacidad y seguridad › Micrófono (y Reconocimiento de voz) › prendé ORBEX. Después volvé acá.",
                                     symbol: "hand.raised")
                }
                LabeledContent("Reconocimiento") {
                    Text(recognizerText).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                if probed, let probe, !probe.onDevice {
                    SettingsFootnote(text: "Tu Mac todavía no tiene el modelo de voz en español, así que ORBEX no escucha (tu audio no sale de la Mac). Activá el Dictado en español en Ajustes del Sistema › Teclado para que se descargue.",
                                     symbol: "arrow.down.circle")
                    Button("Abrir Teclado › Dictado") { VoicePermissions.open(VoicePermissions.dictationSettings) }
                    Toggle("Usar el reconocimiento en la nube de Apple mientras tanto", isOn: $allowCloud)
                        .onChange(of: allowCloud) { _, _ in voice.settingsDidChange() }
                    if allowCloud {
                        SettingsFootnote(text: "Con esto prendido, lo que decís viaja a los servidores de Apple para transcribirse.",
                                         symbol: "icloud")
                    }
                }
                if let last = voice.lastUnderstood {
                    LabeledContent("Último pedido", value: last)
                }
            }

            Section("Prueba de micrófono") {
                HStack(spacing: 12) {
                    Button(voice.isTesting ? "Parar" : "Probar") {
                        if voice.isTesting { voice.stopMicTest() } else { voice.startMicTest() }
                    }
                    .disabled(voice.phase == .listeningCommand || voice.phase == .working)
                    LevelMeter(level: voice.isTesting ? voice.level : 0)
                        .frame(height: 8)
                }
                if voice.isTesting {
                    Text(voice.testText.isEmpty ? "Decí algo… por ejemplo \"Orbex, abrí Spotify\"." : "“\(voice.testText)”")
                        .font(.callout)
                        .foregroundStyle(voice.testText.isEmpty ? Color.secondary : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if voice.testHeardName {
                        Label("¡Escuché su nombre!", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
                SettingsFootnote(text: "En la prueba ORBEX solo te muestra lo que entiende: no hace nada con eso.")
            }

            Section("Nombres") {
                LabeledContent("Responde a") {
                    Text(VoiceSettings.builtInNames.joined(separator: ", ") + "…")
                        .foregroundStyle(.secondary)
                }
                TextField("Nombres extra (separados por coma)", text: $extraNames, prompt: Text("Jarvis, Robotito"))
                    .onSubmit { voice.settingsDidChange() }
                SettingsFootnote(text: "Una palabra por nombre. El nombre va al principio: \"Orbi, poné un timer\" sí; \"poné un timer, Orbi\" no.")
                Picker("Idioma", selection: $localeID) {
                    ForEach(VoiceSettings.languages) { lang in
                        Text(lang.name).tag(lang.id)
                    }
                }
                .onChange(of: localeID) { _, _ in
                    refreshProbe()
                    voice.settingsDidChange()
                }
            }

            Section("Qué le podés pedir") {
                ForEach(0..<Self.examples.count, id: \.self) { i in
                    LabeledContent {
                        Text(Self.examples[i].1).foregroundStyle(.secondary)
                    } label: {
                        Text("“\(Self.examples[i].0)”")
                    }
                }
                SettingsFootnote(text: "Lo que no es un comando de ORBEX va al chat con Claude. Si tenés prendidas las herramientas de Claude, el pedido queda escrito en el chat y lo mandás vos.")
            }

            Section("Privacidad") {
                SettingsFootnote(text: "Lo que decís se usa solo para entender el pedido: no se graba ni se guarda, y se reconoce en tu Mac. ORBEX nunca aprueba un permiso, manda un mail ni hace algo delicado sin tu clic: eso lo confirmás en el chat de la isla.",
                                 symbol: "lock")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            voice.refreshPermissions()
            refreshProbe()
        }
        .onDisappear {
            voice.stopMicTest()
            if extraNames != VoiceSettings.extraNames.joined(separator: ", ") { voice.settingsDidChange() }
        }
    }

    private var phaseColor: Color {
        switch voice.phase {
        case .off: return Color.secondary.opacity(0.4)
        case .waitingWakeWord: return .green
        case .listeningCommand: return Color(red: 0.878, green: 0.251, blue: 0.984)
        case .working: return .orange
        }
    }

    private var recognizerText: String {
        if let label = voice.recognizerLabel { return label }
        guard probed else { return "…" }
        guard let probe else { return "Sin español en esta Mac" }
        return VoiceListener.displayName(probe.id) + (probe.onDevice ? " · en tu Mac" : " · sin modelo en la Mac")
    }

    private func refreshProbe() {
        probe = VoiceListener.probe(localeID: localeID.isEmpty ? "auto" : localeID)
        probed = true
    }

    private func permissionRow(_ title: String, _ p: VoicePermission, url: URL?) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Label(p.label, systemImage: p.symbol)
                    .foregroundStyle(p == .granted ? Color.green : (p == .notAsked ? Color.secondary : Color.orange))
                if p == .denied || p == .restricted {
                    Button("Abrir Ajustes") { VoicePermissions.open(url) }
                        .controlSize(.small)
                }
            }
        }
    }
}

/// Medidor horizontal del nivel de la voz (0…1).
private struct LevelMeter: View {
    let level: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.878, green: 0.251, blue: 0.984).opacity(0.7),
                                                  Color(red: 0.878, green: 0.251, blue: 0.984)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, level)) * geo.size.width)
                    .animation(.linear(duration: 0.06), value: level)
            }
        }
        .accessibilityLabel("Nivel del micrófono")
        .accessibilityValue("\(Int((level * 100).rounded())) %")
    }
}

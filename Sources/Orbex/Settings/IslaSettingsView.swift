import AppKit
import Combine
import SwiftUI
import OrbexCore

/// Configuración › Isla: pantalla, ajuste fino del notch, alitas y comportamiento.
struct IslaSettingsView: View {
    @ObservedObject var model = AppModel.shared
    @State private var screens: [ScreenItem] = []

    private struct ScreenItem: Hashable {
        let id: UInt32
        let name: String
        let hasNotch: Bool
    }

    var body: some View {
        Form {
            Section {
                Picker("Pantalla", selection: $model.settings.screen) {
                    Text("Automática (la que tenga notch)").tag(ScreenChoice.automatic)
                    Text("Principal").tag(ScreenChoice.main)
                    ForEach(screens, id: \.self) { s in
                        Text(s.hasNotch ? "\(s.name) (con notch)" : s.name)
                            .tag(ScreenChoice.display(s.id))
                    }
                    if let missing = missingDisplayID {
                        Text("Pantalla desconectada").tag(ScreenChoice.display(missing))
                    }
                }
                LabeledContent("Notch medido") {
                    Text(notchText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if !model.notch.isHardware {
                    SettingsFootnote(text: "Esta pantalla no tiene notch: ORBEX dibuja uno del tamaño justo, centrado arriba.",
                                     symbol: "info.circle")
                }
            } header: {
                Text("Dónde vive")
            }

            Section {
                SettingsSliderRow(title: "Ancho", value: $model.settings.notchAdjustWidth,
                                  range: -10...10, step: 1, format: SettingsFormat.signedPoints)
                SettingsSliderRow(title: "Alto", value: $model.settings.notchAdjustHeight,
                                  range: -6...6, step: 1, format: SettingsFormat.signedPoints)
                HStack {
                    SettingsFootnote(text: "Si la isla no calza justo con el notch, corregila de a 1 pt.")
                    Spacer()
                    Button("Restablecer") {
                        var s = model.settings
                        s.notchAdjustWidth = 0
                        s.notchAdjustHeight = 0
                        model.settings = s
                    }
                    .disabled(model.settings.notchAdjustWidth == 0 && model.settings.notchAdjustHeight == 0)
                }
            } header: {
                Text("Ajuste fino del notch")
            }

            Section {
                SettingsSliderRow(title: "Alitas", value: $model.settings.wingScale,
                                  range: 0.5...1.5, step: 0.05, format: SettingsFormat.percent)
                Toggle("Asomarse al pasar el mouse", isOn: $model.settings.hoverPeeks)
                SettingsSliderRow(title: "Cerrarse sola a los", value: $model.settings.openAutoCloseSeconds,
                                  range: 5...60, step: 5, format: SettingsFormat.seconds)
                Toggle("Latido en reposo", isOn: $model.settings.hiddenPulse)
                SettingsFootnote(text: "Con el latido, la isla oculta brilla muy suave cada tanto para que se note que ORBEX está.")
            } header: {
                Text("Forma y comportamiento")
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshScreens() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshScreens()
        }
    }

    // MARK: - Pantallas

    private func refreshScreens() {
        screens = NSScreen.screens.map { screen in
            ScreenItem(id: NotchDetector.displayID(of: screen) ?? 0,
                       name: screen.localizedName,
                       hasNotch: NotchDetector.hasNotch(screen))
        }
    }

    /// Pantalla elegida que ya no está conectada (para que el selector no quede en blanco).
    private var missingDisplayID: UInt32? {
        guard case .display(let id) = model.settings.screen else { return nil }
        return screens.contains(where: { $0.id == id }) ? nil : id
    }

    private var notchText: String {
        let n = model.notch
        var text = "\(Int(n.width.rounded())) × \(Int(n.height.rounded())) pt · \(n.isHardware ? "real" : "simulado")"
        if model.settings.notchAdjustWidth != 0 || model.settings.notchAdjustHeight != 0 {
            text += " (con ajuste)"
        }
        return text
    }
}

import SwiftUI
import OrbexCore

/// Configuración › Reloj: esfera, tamaño, transparencia, anclaje, click-through y tic-tac.
/// Los cambios se ven al instante en el reloj abierto.
struct ClockSettingsView: View {
    @ObservedObject private var clock = ClockController.shared
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        Form {
            Section("Esfera") {
                HStack(spacing: 14) {
                    ForEach(ClockFace.allCases) { face in
                        Button {
                            clock.settings.face = face
                        } label: {
                            VStack(spacing: 6) {
                                ClockFaceView(face: face, showSeconds: true, ringProgress: nil)
                                    .frame(width: 84, height: 84)
                                    .background(Circle().fill(Color.black.opacity(0.85)))
                                    .overlay(Circle().stroke(clock.settings.face == face ? model.themeStyle.accent : Color.clear, lineWidth: 2))
                                Text(face.label).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .environment(\.orbexTheme, model.themeStyle)
                .padding(.vertical, 4)
            }

            Section("Ventana") {
                Picker("Tamaño", selection: $clock.settings.size) {
                    ForEach(ClockSize.allCases) { size in Text(size.label).tag(size) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Opacidad")
                    Slider(value: $clock.settings.opacity, in: 0.25...1)
                    Text("\(Int(clock.settings.clampedOpacity * 100)) %").monospacedDigit().frame(width: 44)
                }
                Toggle("Pegarse a los bordes", isOn: $clock.settings.snapToEdges)
                Toggle("Click-through (mantené ⌥ para moverlo)", isOn: $clock.settings.clickThrough)
            }

            Section("Detalles") {
                Toggle("Segundero", isOn: $clock.settings.showSeconds)
                Toggle("Tic-tac", isOn: $clock.settings.tickSound)
            }

            Section {
                Button(clock.isVisible ? "Volver al notch" : "Mostrar el reloj ahora") {
                    OrbexBus.perform("clock")
                }
                Text("Atajo: ⌃⌥C. Doble clic en el reloj lo devuelve al notch; clic derecho para opciones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

import SwiftUI
import OrbexCore

/// Configuración › Tema: skin, vidrio y transparencia propia (con muestra en vivo).
struct TemaSettingsView: View {
    @ObservedObject var model = AppModel.shared
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        Form {
            Section {
                Picker("Tema", selection: $model.settings.theme) {
                    ForEach(ThemeID.allCases, id: \.self) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                SettingsFootnote(text: "Liquid Glass es el tema principal. macOS limpio y Y2K metálico se completan, con sus propios sonidos, en la Fase 5.")
            } header: {
                Text("Tema")
            }

            Section {
                Toggle("Usar vidrio", isOn: $model.settings.useGlass)
                LabeledContent("Transparencia") {
                    HStack(spacing: 8) {
                        Text("Claro")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $model.settings.glassTint, in: 0...1, step: 0.05)
                            .frame(minWidth: 140)
                        Text("Teñido")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!model.settings.useGlass)
                if model.systemReduceTransparency {
                    SettingsFootnote(text: "“Reducir transparencia” está activado en macOS: ORBEX usa fondos sólidos aunque elijas vidrio.",
                                     symbol: "eye.slash")
                } else {
                    SettingsFootnote(text: "Si activás “Reducir transparencia” en Ajustes del Sistema › Accesibilidad, ORBEX lo respeta y usa fondos sólidos.")
                }
            } header: {
                Text("Vidrio")
            }

            Section {
                sample
            } header: {
                Text("Muestra")
            }
        }
        .formStyle(.grouped)
    }

    /// Tarjetas y botones como se ven en la isla, sobre un fondo oscuro con color (para notar el vidrio).
    private var sample: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tarjeta")
                        .font(theme.titleFont)
                        .foregroundStyle(theme.text)
                    Text("Así se ven las tarjetas en la isla.")
                        .font(theme.displayFont)
                        .foregroundStyle(theme.secondaryText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .orbexCard()

                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundStyle(theme.accent)
                    Text("04:59")
                        .font(theme.displayFont)
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .orbexPill()
            }
            HStack(spacing: 8) {
                OrbexActionButton(symbol: "timer", title: "Timer") {
                    CharacterBrain.shared.show(.focused, for: 1.5)
                }
                OrbexActionButton(symbol: "note.text", title: "Nota") {
                    CharacterBrain.shared.show(.happy, for: 1.5)
                }
                OrbexActionButton(symbol: "sparkles", title: "Asistente") {
                    CharacterBrain.shared.show(.thinking, for: 1.5)
                }
                OrbexActionButton(symbol: "clock", title: "Reloj") {
                    CharacterBrain.shared.show(.surprised, for: 1.5)
                }
            }
        }
        .padding(14)
        .background(sampleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
        .animation(theme.softSpring, value: theme)
    }

    private var sampleBackground: some View {
        ZStack {
            Color.black
            Circle()
                .fill(Color(red: 0.25, green: 0.45, blue: 0.95).opacity(0.55))
                .frame(width: 160, height: 160)
                .blur(radius: 40)
                .offset(x: -120, y: -30)
            Circle()
                .fill(Color(red: 0.85, green: 0.35, blue: 0.65).opacity(0.45))
                .frame(width: 140, height: 140)
                .blur(radius: 40)
                .offset(x: 140, y: 40)
        }
    }
}

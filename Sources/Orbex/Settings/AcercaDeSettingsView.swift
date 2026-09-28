import SwiftUI
import OrbexCore

/// Configuración › Acerca de: nombre, versión y notas del proyecto.
struct AcercaDeSettingsView: View {
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appName)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(versionText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                Text("Un compañero de vidrio que vive en el notch de tu Mac: se asoma, te avisa cuando algo termina o te necesita, y siempre está un poquito vivo.")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("ORBEX")
            }

            Section {
                note("waveform", "Todos los sonidos se sintetizan por código, en la misma escala musical.")
                note("paintbrush.pointed", "El personaje se dibuja y anima por código: sin imágenes ni animaciones pregrabadas.")
                note("shippingbox", "Sin assets ni dependencias de terceros. Hecho con SwiftUI y AppKit.")
                note("lock", "Las claves van solo al Llavero de la Mac y nunca se exportan.")
            } header: {
                Text("Cómo está hecho")
            }

            Section {
                Text("© 2026 — Todos los derechos reservados.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func note(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(theme.accent)
                .frame(width: 18)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Bundle

    private var appName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "ORBEX"
    }

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }

    private var versionText: String {
        build.isEmpty ? "Versión \(version)" : "Versión \(version) (\(build))"
    }

    private var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
    }
}

// Basado en Coucou (https://github.com/louis-cfm/coucou) © 2026 Louis Raillé — licencia MIT.
// Modificado para ORBEX (solo el código; ningún asset de Coucou). Ver THIRD_PARTY_NOTICES.md.

import SwiftUI
import AppKit

/// Configuración › Integraciones: servicios opcionales (Stripe, Cal.com, Notion), apagados por defecto.
/// Las claves van en el Keychain (nunca en `UserDefaults`); cada pastilla aparece en la isla solo si la
/// prendés acá. El sonido de la isla está en Configuración › Sonidos, los tiempos en Configuración › Isla
/// y los atajos son fijos (⌃⌥O/A/C/,).
struct IntegrationsSettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var statusMessage: String = ""
    // Claves de las integraciones (se leen de la caché del Keychain al abrir)
    @State private var stripeKey: String    = KeychainStore.shared.get("stripe-api-key")  ?? ""
    @State private var calcomKey: String    = KeychainStore.shared.get("calcom-api-key")  ?? ""
    @State private var notionKey: String    = KeychainStore.shared.get("notion-api-key")  ?? ""

    var body: some View {
        Form {
            Section {
                HStack {
                    serviceLabel("Claude Code", color: "#F5F6F8")
                    Spacer()
                    Text("Siempre activa")
                        .foregroundStyle(.secondary)
                }
                ForEach(AgentTask.toggleableIntegrationIds, id: \.self) { id in
                    if let task = AgentTask.integrationAgents.first(where: { $0.id == id }) {
                        Toggle(isOn: Binding(
                            get: { state.activeIntegrations.contains(id) },
                            set: { _ in state.toggleIntegration(id) }
                        )) {
                            serviceLabel(task.name, color: task.color)
                        }
                    }
                }
                SettingsFootnote(text: "Las opcionales vienen apagadas: solo aparecen en la isla si las prendés.")
            } header: {
                Text("Pastillas en la isla")
            }

            Section {
                SecureField("Clave secreta (sk_live_… o sk_test_…)", text: $stripeKey)
                SettingsFootnote(text: "Conviene una clave restringida de solo lectura.")
            } header: {
                serviceLabel("Stripe", color: "#0570DE")
            }

            Section {
                SecureField("Clave de API (cal_live_…)", text: $calcomKey)
            } header: {
                serviceLabel("Cal.com", color: "#C9956A")
            }

            Section {
                SecureField("Token de la integración (secret_…)", text: $notionKey)
            } header: {
                serviceLabel("Notion", color: "#E8E8E8")
            }

            Section {
                HStack {
                    Button("Guardar claves") { saveIntegrations() }
                        .buttonStyle(.borderedProminent)
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                SettingsFootnote(text: "Las claves se guardan en el Llavero (Keychain) de macOS. Dejar un campo vacío y guardar borra esa clave.",
                                 symbol: "lock")
            }
        }
        .formStyle(.grouped)
    }

    private func serviceLabel(_ name: String, color: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: color)).frame(width: 8, height: 8)
            Text(name)
        }
    }

    // MARK: - Acciones

    private func saveIntegrations() {
        saveKey("stripe-api-key",  value: stripeKey)
        saveKey("calcom-api-key",  value: calcomKey)
        saveKey("notion-api-key",  value: notionKey)
        statusMessage = "✓ Claves guardadas."
    }

    /// Guarda el valor si no está vacío; si está vacío, borra la clave del Keychain.
    private func saveKey(_ key: String, value: String) {
        if value.isEmpty {
            KeychainStore.shared.remove(key)
        } else {
            KeychainStore.shared.set(key, value: value)
        }
    }
}

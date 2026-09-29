// Basado en Coucou (https://github.com/louis-cfm/coucou) © 2026 Louis Raillé — licencia MIT.
// Modificado para ORBEX (solo el código; ningún asset de Coucou). Ver THIRD_PARTY_NOTICES.md.

import SwiftUI
import AppKit

/// Configuración › Integraciones: claves (en el Keychain, nunca en `UserDefaults`), filtros de Vercel y n8n
/// y qué pastillas de integraciones se muestran en la isla (máx. 4). El sonido de la isla está en
/// Configuración › Sonidos, los tiempos en Configuración › Isla y los atajos son fijos (⌃⌥O/A/C/,).
struct IntegrationsSettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var statusMessage: String = ""
    // Claves de las integraciones (se leen del Keychain al abrir)
    @State private var resendKey: String    = KeychainStore.shared.get("resend-api-key")  ?? ""
    @State private var resendFrom: String   = KeychainStore.shared.get("resend-from")     ?? ""
    @State private var n8nUrl: String       = KeychainStore.shared.get("n8n-url")         ?? ""
    @State private var n8nKey: String       = KeychainStore.shared.get("n8n-api-key")     ?? ""
    @State private var vercelToken: String  = KeychainStore.shared.get("vercel-token")    ?? ""
    @State private var githubToken: String  = KeychainStore.shared.get("github-token")    ?? ""
    @State private var stripeKey: String    = KeychainStore.shared.get("stripe-api-key")  ?? ""
    @State private var calcomKey: String    = KeychainStore.shared.get("calcom-api-key")  ?? ""
    @State private var notionKey: String    = KeychainStore.shared.get("notion-api-key")  ?? ""

    // Filtro de proyectos de Vercel
    @State private var vercelProjects: [String] = []
    @State private var loadingVercel: Bool = false

    // Filtro de flujos de n8n
    @State private var n8nWorkflows: [String] = []
    @State private var loadingN8n: Bool = false

    private static let maxPills = 4

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
                        let isOn = state.activeIntegrations.contains(id)
                        let atMax = state.activeIntegrations.count >= Self.maxPills && !isOn
                        Toggle(isOn: Binding(
                            get: { isOn },
                            set: { _ in state.toggleIntegration(id) }
                        )) {
                            serviceLabel(task.name, color: task.color)
                                .foregroundStyle(atMax ? .secondary : .primary)
                        }
                        .disabled(atMax)
                    }
                }
                SettingsFootnote(text: "Usás \(state.activeIntegrations.count) de \(Self.maxPills) lugares. Para prender otra, apagá una.",
                                 symbol: state.activeIntegrations.count >= Self.maxPills ? "exclamationmark.circle" : nil)
            } header: {
                Text("Pastillas en la isla")
            }

            Section {
                SecureField("Clave de API (re_…)", text: $resendKey)
                TextField("Remitente (vos@tudominio.com)", text: $resendFrom)
                SettingsFootnote(text: "Para mandar mails desde la isla. Nunca se manda nada sin tu clic.")
            } header: {
                serviceLabel("Resend", color: "#22C55E")
            }

            Section {
                TextField("URL de la instancia (https://…)", text: $n8nUrl)
                SecureField("Clave de API", text: $n8nKey)
                IntegrationFilterRow(
                    label: "Flujos a vigilar",
                    items: n8nWorkflows,
                    filter: $state.n8nWorkflowFilter,
                    loading: loadingN8n,
                    onLoad: loadN8nWorkflows
                )
            } header: {
                serviceLabel("n8n", color: "#F29B38")
            }

            Section {
                SecureField("Token", text: $vercelToken)
                IntegrationFilterRow(
                    label: "Proyectos a vigilar",
                    items: vercelProjects,
                    filter: $state.vercelProjectFilter,
                    loading: loadingVercel,
                    onLoad: loadVercelProjects
                )
            } header: {
                serviceLabel("Vercel", color: "#7C5CFF")
            }

            Section {
                SecureField("Token de acceso personal", text: $githubToken)
            } header: {
                serviceLabel("GitHub", color: "#F4505E")
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
                            .foregroundStyle(statusMessage.hasPrefix("❌") ? .red : .secondary)
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
        saveKey("resend-api-key",  value: resendKey)
        saveKey("resend-from",     value: resendFrom)
        saveKey("n8n-url",         value: n8nUrl)
        saveKey("n8n-api-key",     value: n8nKey)
        saveKey("vercel-token",    value: vercelToken)
        saveKey("github-token",    value: githubToken)
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

    // MARK: - Lista de proyectos de Vercel

    private func loadVercelProjects() {
        guard let token = KeychainStore.shared.get("vercel-token") else {
            statusMessage = "❌ Primero guardá el token de Vercel."
            return
        }
        loadingVercel = true
        guard let url = URL(string: "https://api.vercel.com/v9/projects?limit=100") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let names: [String]
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let projects = json["projects"] as? [[String: Any]] {
                names = projects.compactMap { $0["name"] as? String }.sorted()
            } else {
                names = []
            }
            DispatchQueue.main.async {
                self.vercelProjects = names
                self.loadingVercel = false
                if names.isEmpty { self.statusMessage = "❌ No encontré proyectos de Vercel." }
            }
        }.resume()
    }

    // MARK: - Lista de flujos de n8n

    private func loadN8nWorkflows() {
        guard let apiKey  = KeychainStore.shared.get("n8n-api-key"),
              let rawBase = KeychainStore.shared.get("n8n-url") else {
            statusMessage = "❌ Primero guardá la URL y la clave de n8n."
            return
        }
        loadingN8n = true
        let base = rawBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urls = ["\(base)/api/v1/workflows?limit=100", "\(base)/rest/workflows?limit=100"]
        fetchN8nWorkflows(urls: urls, apiKey: apiKey, idx: 0)
    }

    private func fetchN8nWorkflows(urls: [String], apiKey: String, idx: Int) {
        guard idx < urls.count, let url = URL(string: urls[idx]) else {
            DispatchQueue.main.async { self.loadingN8n = false; self.statusMessage = "❌ No encontré flujos de n8n." }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(apiKey, forHTTPHeaderField: "X-N8N-API-KEY")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, code == 200 else {
                self.fetchN8nWorkflows(urls: urls, apiKey: apiKey, idx: idx + 1)
                return
            }
            let items: [[String: Any]]
            if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let arr = obj["data"] as? [[String: Any]] { items = arr }
            else if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] { items = arr }
            else { items = [] }
            let names = items.compactMap { $0["name"] as? String }.sorted()
            DispatchQueue.main.async {
                self.n8nWorkflows = names
                self.loadingN8n = false
                if names.isEmpty { self.statusMessage = "❌ No encontré flujos de n8n." }
            }
        }.resume()
    }
}

// MARK: - Fila de filtro (Vercel / n8n)

struct IntegrationFilterRow: View {
    let label: String
    let items: [String]
    @Binding var filter: Set<String>
    let loading: Bool
    let onLoad: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if loading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button(items.isEmpty ? "Cargar lista" : "Actualizar") { onLoad() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                if !filter.isEmpty {
                    Button("Todos") { filter = [] }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .foregroundColor(.secondary)
                }
            }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items, id: \.self) { item in
                        Toggle(item, isOn: Binding(
                            get: { filter.isEmpty || filter.contains(item) },
                            set: { on in
                                if on { filter.insert(item) }
                                else  {
                                    // Primer clic: pasar de "todos" a una lista explícita
                                    if filter.isEmpty { filter = Set(items).subtracting([item]) }
                                    else { filter.remove(item) }
                                    if filter.count == items.count { filter = [] } // todos = vacío
                                }
                            }
                        ))
                        .font(.system(size: 11))
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.leading, 4)
                if !filter.isEmpty {
                    Text("Vigilando \(filter.count) de \(items.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

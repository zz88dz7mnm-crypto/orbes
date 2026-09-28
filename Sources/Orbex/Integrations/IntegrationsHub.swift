import Foundation
import OrbexCore

/// Centro de integraciones (informe §9.11): consulta SOLO LECTURA los servicios activados y con clave.
/// Cada 60 s con la isla abierta, cada 5 min cerrada; espera más tras errores.
/// Novedades con problemas → isla "te necesita" + aviso; color del personaje según el servicio.
@MainActor
final class IntegrationsHub: ObservableObject {
    static let shared = IntegrationsHub()

    @Published private(set) var summaries: [IntegrationSummary] = []
    @Published private(set) var status: [IntegrationID: String] = [:]

    private var byID: [IntegrationID: [IntegrationSummary]] = [:]
    private var nextDue: [IntegrationID: Date] = [:]
    private var failures: [IntegrationID: Int] = [:]
    private var inFlight: Set<IntegrationID> = []
    private var seenAlerts: Set<String> = []
    private var lastActivity: [IntegrationID: Date] = [:]
    private var visible = false
    private var timer: Timer?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private init() {}

    // MARK: - Preferencias

    static func key(_ id: IntegrationID, _ field: String) -> String { "orbex.integrations.\(id.rawValue).\(field)" }

    func isEnabled(_ id: IntegrationID) -> Bool { UserDefaults.standard.bool(forKey: Self.key(id, "enabled")) }

    func setEnabled(_ id: IntegrationID, _ on: Bool) {
        objectWillChange.send()
        UserDefaults.standard.set(on, forKey: Self.key(id, "enabled"))
        if on {
            nextDue[id] = .distantPast
            failures[id] = 0
            Task { await refresh(id) }
        } else {
            clear(id, status: "Desactivada")
        }
    }

    func baseURL(_ id: IntegrationID) -> String { UserDefaults.standard.string(forKey: Self.key(id, "baseURL")) ?? "" }
    func team(_ id: IntegrationID) -> String { UserDefaults.standard.string(forKey: Self.key(id, "team")) ?? "" }

    /// Configuración lista para consultar, o el motivo por el que falta.
    private func config(_ id: IntegrationID) -> Result<IntegrationConfig, ConfigError> {
        guard let key = Keychain.get(id.keychainAccount) else { return .failure(.init(text: "Falta la clave")) }
        let base = baseURL(id).trimmingCharacters(in: .whitespaces)
        if id.needsBaseURL, URL(string: base)?.scheme?.hasPrefix("http") != true {
            return .failure(.init(text: "Falta la URL de la instancia"))
        }
        return .success(IntegrationConfig(key: key, baseURL: base, team: team(id)))
    }
    private struct ConfigError: Error { let text: String }

    // MARK: - Ciclo

    func start() {
        guard timer == nil else { return }
        for id in IntegrationID.allCases {
            status[id] = isEnabled(id) ? "Esperando…" : "Desactivada"
            nextDue[id] = Date().addingTimeInterval(Double(id.hashValue & 7)) // escalonado
        }
        let t = Timer(timeInterval: 10, repeats: true) { _ in
            Task { @MainActor in IntegrationsHub.shared.tick() }
        }
        t.tolerance = 3
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    /// Con la isla abierta se consulta más seguido (y al abrirla se refresca lo viejo).
    func setVisible(_ visible: Bool) {
        guard visible != self.visible else { return }
        self.visible = visible
        guard visible else { return }
        let soon = Date().addingTimeInterval(2)
        for id in IntegrationID.allCases where (failures[id] ?? 0) == 0 {
            if let due = nextDue[id], due.timeIntervalSinceNow > 60 { nextDue[id] = soon }
        }
    }

    /// El usuario miró la página de servicios: la isla deja de pedir atención.
    func acknowledge() {
        for id in IntegrationID.allCases { OrbexBus.setActivity(source: source(id), working: false, attention: false) }
    }

    private func tick() {
        expireTints()
        let now = Date()
        for id in IntegrationID.allCases where isEnabled(id) && !inFlight.contains(id) {
            if (nextDue[id] ?? .distantPast) <= now { Task { await refresh(id) } }
        }
    }

    private func interval(_ id: IntegrationID) -> TimeInterval {
        let base: TimeInterval = visible ? 60 : 300
        let f = failures[id] ?? 0
        return f == 0 ? base : min(base * pow(2, Double(min(f, 5))), 1800)
    }

    // MARK: - Consulta

    func refresh(_ id: IntegrationID) async {
        guard isEnabled(id) else { clear(id, status: "Desactivada"); return }
        guard !inFlight.contains(id) else { return }
        let cfg: IntegrationConfig
        switch config(id) {
        case .failure(let e): clear(id, status: e.text); nextDue[id] = Date().addingTimeInterval(interval(id)); return
        case .success(let c): cfg = c
        }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        status[id] = "Consultando…"

        var rows: [IntegrationSummary] = []
        var problem: String?
        requests: for r in IntegrationAPI.requests(for: id, config: cfg) {
            do {
                let (data, resp) = try await session.data(for: r.request)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else { problem = IntegrationAPI.describe(status: code); break requests }
                rows += IntegrationAPI.summaries(for: id, tag: r.tag, data: data, config: cfg)
            } catch {
                problem = (error as? URLError)?.code == .notConnectedToInternet ? "Sin conexión" : "No se pudo conectar"
                break requests
            }
        }

        if let problem {
            failures[id, default: 0] += 1
            status[id] = problem
            let offline = problem == "Sin conexión"
            // Sin red no es culpa del servicio: se conserva lo último y no se alarma.
            if !offline { apply(id, [IntegrationSummary.failure(id, problem)]) }
        } else {
            failures[id] = 0
            status[id] = "Al día · " + Date().formatted(date: .omitted, time: .shortened) + (rows.isEmpty ? " · sin novedades" : "")
            apply(id, rows)
        }
        nextDue[id] = Date().addingTimeInterval(interval(id))
    }

    private func source(_ id: IntegrationID) -> String { "integration:\(id.rawValue)" }

    private func apply(_ id: IntegrationID, _ rows: [IntegrationSummary]) {
        let old = byID[id]
        byID[id] = rows
        publish()

        // Actividad reciente: cambió algo respecto de la consulta anterior.
        if let old, Set(old.map(\.id)) != Set(rows.map(\.id)), !rows.isEmpty { lastActivity[id] = Date() }

        let alerts = rows.filter { $0.severity >= .warning }
        let fresh = alerts.filter { !seenAlerts.contains($0.id) }
        if alerts.isEmpty {
            OrbexBus.setActivity(source: source(id), working: false, attention: false)
        } else if let top = fresh.max(by: { $0.severity < $1.severity }) {
            fresh.forEach { seenAlerts.insert($0.id) }
            lastActivity[id] = Date()
            OrbexBus.setActivity(source: source(id), working: false, attention: true)
            OrbexBus.toast("\(id.title): \(top.title)",
                           symbol: top.severity == .error ? "exclamationmark.triangle.fill" : top.symbol)
            OrbexBus.play(top.severity == .error ? .error : .needsYou)
        }
        updateTint(id)
    }

    private func updateTint(_ id: IntegrationID) {
        let active = (lastActivity[id].map { Date().timeIntervalSince($0) < 600 } ?? false) && isEnabled(id)
        OrbexBus.requestTint(active ? id.tint : nil, source: source(id))
    }

    private func clear(_ id: IntegrationID, status text: String) {
        status[id] = text
        byID[id] = nil
        lastActivity[id] = nil
        publish()
        OrbexBus.setActivity(source: source(id), working: false, attention: false)
        OrbexBus.requestTint(nil, source: source(id))
    }

    private func publish() {
        let rows = IntegrationID.allCases.flatMap { byID[$0] ?? [] }
        if rows != summaries { summaries = rows }
    }

    /// Vence los colores viejos aunque no haya novedades.
    private func expireTints() {
        for id in IntegrationID.allCases where lastActivity[id] != nil && Date().timeIntervalSince(lastActivity[id]!) >= 600 {
            lastActivity[id] = nil
            OrbexBus.requestTint(nil, source: source(id))
        }
    }
}

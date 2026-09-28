import Foundation

// Integraciones de ORBEX (informe §9.11): modelos, pedidos HTTP de SOLO LECTURA y
// traductores puros (JSON → filas para la isla). Sin red acá: la app hace los pedidos.

public enum IntegrationID: String, CaseIterable, Codable, Sendable, Identifiable {
    case github, vercel, stripe, n8n, resend, notion, calcom
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .github: return "GitHub"
        case .vercel: return "Vercel"
        case .stripe: return "Stripe"
        case .n8n: return "n8n"
        case .resend: return "Resend"
        case .notion: return "Notion"
        case .calcom: return "Cal.com"
        }
    }

    public var symbol: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .vercel: return "triangle.fill"
        case .stripe: return "creditcard"
        case .n8n: return "point.3.connected.trianglepath.dotted"
        case .resend: return "envelope"
        case .notion: return "doc.text"
        case .calcom: return "calendar"
        }
    }

    /// Cuenta del Keychain donde vive la clave ("github-token", …).
    public var keychainAccount: String {
        switch self {
        case .github, .vercel, .notion: return "\(rawValue)-token"
        case .stripe, .n8n, .resend, .calcom: return "\(rawValue)-key"
        }
    }

    public var needsBaseURL: Bool { self == .n8n }
    public var needsTeamOrProject: Bool { self == .vercel }

    /// Variante de color del personaje cuando hay novedades de este servicio.
    public var tint: OrbexTint? {
        switch self {
        case .stripe: return .violet
        case .n8n: return .orange
        case .calcom: return .green
        case .github, .vercel, .resend, .notion: return .clear
        }
    }

    /// Qué clave pegar (texto de ayuda en Configuración).
    public var keyHint: String {
        switch self {
        case .github: return "Token fine-grained con lectura de notificaciones y pull requests."
        case .vercel: return "Token de cuenta (vercel.com/account/tokens)."
        case .stripe: return "Clave restringida (rk_…) con permiso de lectura de saldo y cargos."
        case .n8n: return "API key de tu instancia (Settings › n8n API)."
        case .resend: return "API key con acceso completo o de solo lectura de emails."
        case .notion: return "Token de integración interna; compartí las páginas con ella."
        case .calcom: return "API key de Cal.com (Settings › Developer › API keys)."
        }
    }

    public var homeURL: URL? {
        switch self {
        case .github: return URL(string: "https://github.com/notifications")
        case .vercel: return URL(string: "https://vercel.com/dashboard")
        case .stripe: return URL(string: "https://dashboard.stripe.com/payments")
        case .n8n: return nil
        case .resend: return URL(string: "https://resend.com/emails")
        case .notion: return URL(string: "https://www.notion.so")
        case .calcom: return URL(string: "https://app.cal.com/bookings/upcoming")
        }
    }
}

public enum IntegrationSeverity: Int, Codable, Sendable, Comparable {
    case info, success, warning, error
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct IntegrationSummary: Identifiable, Sendable, Equatable {
    /// Estable y específico del contenido: sirve para detectar novedades.
    public var id: String
    public var integration: IntegrationID
    public var title: String
    public var subtitle: String
    public var symbol: String
    public var severity: IntegrationSeverity
    public var url: URL?

    public init(id: String, integration: IntegrationID, title: String, subtitle: String = "",
                symbol: String? = nil, severity: IntegrationSeverity = .info, url: URL? = nil) {
        self.id = "\(integration.rawValue).\(id)"
        self.integration = integration
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol ?? integration.symbol
        self.severity = severity
        self.url = url
    }

    /// Fila de error de conexión (clave inválida, sin red…).
    public static func failure(_ integration: IntegrationID, _ message: String) -> IntegrationSummary {
        IntegrationSummary(id: "failure", integration: integration, title: integration.title,
                           subtitle: message, symbol: "exclamationmark.triangle", severity: .error,
                           url: integration.homeURL)
    }
}

/// Datos que necesita cada servicio (la clave sale del Keychain).
public struct IntegrationConfig: Sendable {
    public var key: String
    public var baseURL: String
    public var team: String
    public init(key: String, baseURL: String = "", team: String = "") {
        self.key = key; self.baseURL = baseURL; self.team = team
    }
}

/// Pedido etiquetado: `tag` indica qué traductor usar con la respuesta.
public struct IntegrationRequest: Sendable {
    public var tag: String
    public var request: URLRequest
}

public enum IntegrationAPI {
    /// Pedidos de solo lectura. Todos son GET salvo Notion `/v1/search`, que es POST pero no modifica nada.
    public static func requests(for id: IntegrationID, config c: IntegrationConfig, now: Date = Date()) -> [IntegrationRequest] {
        func req(_ tag: String, _ s: String, _ headers: [String: String]) -> IntegrationRequest? {
            guard let url = URL(string: s) else { return nil }
            var r = URLRequest(url: url, timeoutInterval: 12)
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
            return IntegrationRequest(tag: tag, request: r)
        }
        let bearer = ["Authorization": "Bearer \(c.key)"]
        switch id {
        case .github:
            let gh = bearer.merging(["Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]) { $1 }
            return [req("notifications", "https://api.github.com/notifications?per_page=30", gh),
                    req("reviews", "https://api.github.com/search/issues?q=is:open+is:pr+review-requested:@me&per_page=10", gh)].compactMap { $0 }
        case .vercel:
            var q = "limit=10"
            let parts = c.team.split(separator: "/", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if let t = parts.first, !t.isEmpty { q += (t.hasPrefix("team_") ? "&teamId=" : "&slug=") + enc(t) }
            if parts.count > 1, !parts[1].isEmpty { q += "&projectId=" + enc(parts[1]) }
            return [req("deployments", "https://api.vercel.com/v6/deployments?\(q)", bearer)].compactMap { $0 }
        case .stripe:
            let start = Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
            return [req("balance", "https://api.stripe.com/v1/balance", bearer),
                    req("charges", "https://api.stripe.com/v1/charges?limit=100&created%5Bgte%5D=\(start)", bearer)].compactMap { $0 }
        case .n8n:
            let base = c.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            return [req("executions", "\(base)/api/v1/executions?status=error&limit=10&includeData=false",
                        ["X-N8N-API-KEY": c.key])].compactMap { $0 }
        case .resend:
            return [req("emails", "https://api.resend.com/emails?limit=30", bearer)].compactMap { $0 }
        case .notion:
            guard var r = req("search", "https://api.notion.com/v1/search", bearer.merging(["Notion-Version": "2022-06-28", "Content-Type": "application/json"]) { $1 }) else { return [] }
            r.request.httpMethod = "POST"
            r.request.httpBody = Data(#"{"page_size":5,"filter":{"property":"object","value":"page"},"sort":{"direction":"descending","timestamp":"last_edited_time"}}"#.utf8)
            return [r]
        case .calcom:
            return [req("bookings", "https://api.cal.com/v2/bookings?status=upcoming&take=10&sortStart=asc",
                        bearer.merging(["cal-api-version": "2024-08-13"]) { $1 })].compactMap { $0 }
        }
    }

    /// Traduce la respuesta de un pedido a filas. Nunca falla: si no entiende el JSON devuelve [].
    public static func summaries(for id: IntegrationID, tag: String, data: Data, config: IntegrationConfig, now: Date = Date()) -> [IntegrationSummary] {
        switch (id, tag) {
        case (.github, "notifications"): return GitHubFeed.notifications(from: data)
        case (.github, "reviews"): return GitHubFeed.reviews(from: data)
        case (.vercel, _): return VercelFeed.summaries(from: data)
        case (.stripe, "balance"): return StripeFeed.balance(from: data)
        case (.stripe, _): return StripeFeed.charges(from: data)
        case (.n8n, _): return N8nFeed.summaries(from: data, baseURL: config.baseURL, now: now)
        case (.resend, _): return ResendFeed.summaries(from: data, now: now)
        case (.notion, _): return NotionFeed.summaries(from: data, now: now)
        case (.calcom, _): return CalcomFeed.summaries(from: data, now: now)
        default: return []
        }
    }

    /// Mensaje corto para un código HTTP de error.
    public static func describe(status: Int) -> String {
        switch status {
        case 401: return "Clave inválida (401)"
        case 403: return "Sin permiso (403): revisá los alcances de la clave"
        case 404: return "No encontrado (404): revisá URL/equipo"
        case 429: return "Demasiados pedidos (429): espero un rato"
        case 500...599: return "El servicio falló (\(status))"
        default: return "Error HTTP \(status)"
        }
    }

    static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))) ?? s }
}

// MARK: - Utilidades

enum IntegrationDates {
    /// Acepta ISO 8601 (con o sin fracción), "2024-01-02 10:11:12.123+00" y epoch (s o ms).
    static func parse(_ s: String?) -> Date? {
        guard var s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if let n = Double(s) { return epoch(n) }
        if s.count > 10, s[s.index(s.startIndex, offsetBy: 10)] == " " {
            s.replaceSubrange(s.index(s.startIndex, offsetBy: 10)...s.index(s.startIndex, offsetBy: 10), with: "T")
        }
        if let r = s.range(of: #"[+-]\d\d$"#, options: .regularExpression) { s.replaceSubrange(r, with: s[r] + ":00") }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func epoch(_ n: Double) -> Date { Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }

    static func relative(_ d: Date, now: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: now)
    }
}

private func decode<T: Decodable>(_ t: T.Type, _ data: Data) -> T? { try? JSONDecoder().decode(t, from: data) }
private func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

// MARK: - GitHub

public enum GitHubFeed {
    struct Notification: Decodable { var id: String?; var reason: String?; var subject: Subject?; var repository: Repo? }
    struct Subject: Decodable { var title: String?; var type: String? }
    struct Repo: Decodable { var full_name: String?; var html_url: String? }
    struct Search: Decodable { var total_count: Int?; var items: [Item]? }
    struct Item: Decodable { var id: Int?; var title: String?; var html_url: String?; var repository_url: String? }

    public static func notifications(from data: Data) -> [IntegrationSummary] {
        guard let list = decode([Notification].self, data), let first = list.first else { return [] }
        let repo = first.repository?.full_name.map { " · \($0)" } ?? ""
        return [IntegrationSummary(id: "notif.\(list.count).\(first.id ?? "")", integration: .github,
                                   title: plural(list.count, "notificación sin leer", "notificaciones sin leer"),
                                   subtitle: (first.subject?.title ?? "") + repo, symbol: "bell",
                                   url: URL(string: "https://github.com/notifications"))]
    }

    public static func reviews(from data: Data) -> [IntegrationSummary] {
        guard let s = decode(Search.self, data), let items = s.items, let first = items.first else { return [] }
        let n = max(s.total_count ?? items.count, items.count)
        let key = items.compactMap { $0.id.map(String.init) }.sorted().joined(separator: ",")
        let url = n == 1 ? first.html_url.flatMap(URL.init(string:))
                         : URL(string: "https://github.com/pulls/review-requested")
        return [IntegrationSummary(id: "reviews.\(key)", integration: .github,
                                   title: n == 1 ? "Un PR espera tu revisión" : "\(n) PRs esperan tu revisión",
                                   subtitle: first.title ?? "", symbol: "arrow.triangle.pull",
                                   severity: .warning, url: url)]
    }
}

// MARK: - Vercel

public enum VercelFeed {
    struct Response: Decodable { var deployments: [Deployment]? }
    struct Deployment: Decodable {
        var uid: String?; var name: String?; var url: String?; var state: String?; var readyState: String?
        var created: Double?; var createdAt: Double?; var inspectorUrl: String?; var meta: Meta?
    }
    struct Meta: Decodable { var githubCommitMessage: String? }

    public static func summaries(from data: Data) -> [IntegrationSummary] {
        guard let list = decode(Response.self, data)?.deployments else { return [] }
        var seen = Set<String>(), out: [IntegrationSummary] = []
        for d in list {
            let name = d.name ?? "Proyecto"
            guard seen.insert(name).inserted, out.count < 3 else { continue }
            let state = (d.state ?? d.readyState ?? "").uppercased()
            let (label, sev): (String, IntegrationSeverity) = {
                switch state {
                case "READY": return ("Publicado", .success)
                case "ERROR": return ("Falló el despliegue", .error)
                case "BUILDING", "INITIALIZING": return ("Construyendo…", .info)
                case "QUEUED": return ("En cola", .info)
                case "CANCELED": return ("Cancelado", .info)
                default: return (state.isEmpty ? "Sin estado" : state.capitalized, .info)
                }
            }()
            let msg = d.meta?.githubCommitMessage?.split(separator: "\n").first.map { " · \($0)" } ?? ""
            let link = d.inspectorUrl ?? d.url.map { "https://\($0)" }
            out.append(IntegrationSummary(id: "\(d.uid ?? name).\(state)", integration: .vercel, title: name,
                                          subtitle: label + msg, severity: sev, url: link.flatMap(URL.init(string:))))
        }
        return out
    }
}

// MARK: - Stripe

public enum StripeFeed {
    struct Money: Decodable { var amount: Int?; var currency: String? }
    struct Balance: Decodable { var available: [Money]?; var pending: [Money]? }
    struct Charges: Decodable { var data: [Charge]? }
    struct Charge: Decodable {
        var id: String?; var amount: Int?; var currency: String?; var status: String?
        var paid: Bool?; var refunded: Bool?; var failure_message: String?
    }

    static let zeroDecimal: Set<String> = ["jpy", "krw", "clp", "pyg", "vnd", "xaf", "xof", "ugx", "rwf", "isk", "kmf", "gnf", "mga", "djf", "bif", "vuv", "xpf"]

    static func money(_ cents: Int, _ currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "es_AR")
        f.currencyCode = currency.uppercased()
        let value = zeroDecimal.contains(currency.lowercased()) ? Double(cents) : Double(cents) / 100
        return f.string(from: NSNumber(value: value)) ?? "\(value) \(currency.uppercased())"
    }

    public static func balance(from data: Data) -> [IntegrationSummary] {
        guard let b = decode(Balance.self, data), let avail = b.available, !avail.isEmpty else { return [] }
        let text = avail.map { money($0.amount ?? 0, $0.currency ?? "usd") }.joined(separator: " · ")
        let pend = (b.pending ?? []).filter { ($0.amount ?? 0) != 0 }
            .map { money($0.amount ?? 0, $0.currency ?? "usd") }.joined(separator: " · ")
        return [IntegrationSummary(id: "balance", integration: .stripe, title: "Saldo \(text)",
                                   subtitle: pend.isEmpty ? "Disponible" : "Pendiente \(pend)",
                                   symbol: "banknote", url: URL(string: "https://dashboard.stripe.com/balance/overview"))]
    }

    public static func charges(from data: Data) -> [IntegrationSummary] {
        guard let list = decode(Charges.self, data)?.data else { return [] }
        let ok = list.filter { $0.status == "succeeded" && $0.paid != false && $0.refunded != true }
        let failed = list.filter { $0.status == "failed" }
        var out: [IntegrationSummary] = []
        var totals: [String: Int] = [:]
        for c in ok { totals[c.currency ?? "usd", default: 0] += c.amount ?? 0 }
        let sum = totals.sorted { $0.key < $1.key }.map { money($0.value, $0.key) }.joined(separator: " · ")
        out.append(IntegrationSummary(id: "today.\(ok.count)", integration: .stripe,
                                      title: ok.isEmpty ? "Sin cobros hoy" : "Hoy: \(sum)",
                                      subtitle: plural(ok.count, "cobro exitoso", "cobros exitosos"),
                                      symbol: "creditcard", severity: ok.isEmpty ? .info : .success,
                                      url: URL(string: "https://dashboard.stripe.com/payments")))
        if let f = failed.first {
            out.append(IntegrationSummary(id: "failed.\(f.id ?? "")", integration: .stripe,
                                          title: plural(failed.count, "cobro fallido hoy", "cobros fallidos hoy"),
                                          subtitle: f.failure_message ?? money(f.amount ?? 0, f.currency ?? "usd"),
                                          symbol: "xmark.octagon", severity: .error,
                                          url: URL(string: "https://dashboard.stripe.com/payments?status[0]=failed")))
        }
        return out
    }
}

// MARK: - n8n

public enum N8nFeed {
    struct Response: Decodable { var data: [Execution]? }
    struct Execution: Decodable {
        var id: String?; var workflowId: String?; var status: String?; var startedAt: String?; var stoppedAt: String?
        var workflowData: WF?
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: K.self)
            id = (try? c.decode(String.self, forKey: .id)) ?? (try? c.decode(Int.self, forKey: .id)).map(String.init)
            workflowId = (try? c.decode(String.self, forKey: .workflowId)) ?? (try? c.decode(Int.self, forKey: .workflowId)).map(String.init)
            status = try? c.decode(String.self, forKey: .status)
            startedAt = try? c.decode(String.self, forKey: .startedAt)
            stoppedAt = try? c.decode(String.self, forKey: .stoppedAt)
            workflowData = try? c.decode(WF.self, forKey: .workflowData)
        }
        enum K: String, CodingKey { case id, workflowId, status, startedAt, stoppedAt, workflowData }
    }
    struct WF: Decodable { var name: String? }

    /// Fallos de las últimas 24 h (o "todo bien").
    public static func summaries(from data: Data, baseURL: String, now: Date = Date()) -> [IntegrationSummary] {
        guard let list = decode(Response.self, data)?.data else { return [] }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let recent = list.filter { ["error", "crashed", "failed"].contains($0.status ?? "error") }
            .filter { (IntegrationDates.parse($0.stoppedAt ?? $0.startedAt) ?? now) > now.addingTimeInterval(-86_400) }
        guard let last = recent.first else {
            return [IntegrationSummary(id: "ok", integration: .n8n, title: "Workflows sin fallos",
                                       subtitle: "Últimas 24 h", symbol: "checkmark.seal", severity: .success,
                                       url: URL(string: "\(base)/home/workflows"))]
        }
        let when = IntegrationDates.parse(last.stoppedAt ?? last.startedAt).map { " · " + IntegrationDates.relative($0, now: now) } ?? ""
        let link = last.workflowId.map { "\(base)/workflow/\($0)/executions/\(last.id ?? "")" } ?? "\(base)/home/executions"
        return [IntegrationSummary(id: "fail.\(last.id ?? "")", integration: .n8n,
                                   title: plural(recent.count, "ejecución fallida", "ejecuciones fallidas"),
                                   subtitle: (last.workflowData?.name ?? "Workflow \(last.workflowId ?? "?")") + when,
                                   symbol: "exclamationmark.triangle", severity: .error, url: URL(string: link))]
    }
}

// MARK: - Resend

public enum ResendFeed {
    struct Response: Decodable { var data: [Email]? }
    struct Email: Decodable { var id: String?; var to: [String]?; var subject: String?; var created_at: String?; var last_event: String? }

    static func label(_ e: String) -> String {
        switch e {
        case "delivered": return "entregado"
        case "opened": return "abierto"
        case "clicked": return "con clic"
        case "bounced": return "rebotó"
        case "complained": return "marcado como spam"
        case "delivery_delayed": return "demorado"
        case "sent": return "enviado"
        case "failed": return "falló"
        default: return e.isEmpty ? "sin estado" : e
        }
    }

    public static func summaries(from data: Data, now: Date = Date()) -> [IntegrationSummary] {
        guard let list = decode(Response.self, data)?.data else { return [] }
        let day = list.filter { (IntegrationDates.parse($0.created_at) ?? now) > now.addingTimeInterval(-86_400) }
        let bad = day.filter { ["bounced", "complained", "failed"].contains($0.last_event ?? "") }
        var out: [IntegrationSummary] = []
        if let b = bad.first {
            out.append(IntegrationSummary(id: "bad.\(b.id ?? "")", integration: .resend,
                                          title: plural(bad.count, "email con problemas", "emails con problemas"),
                                          subtitle: "\(b.to?.first ?? "") · \(label(b.last_event ?? ""))",
                                          symbol: "envelope.badge", severity: .warning,
                                          url: b.id.flatMap { URL(string: "https://resend.com/emails/\($0)") }))
        }
        if let last = day.first {
            out.append(IntegrationSummary(id: "sent.\(day.count).\(last.last_event ?? "")", integration: .resend,
                                          title: plural(day.count, "email hoy", "emails en 24 h"),
                                          subtitle: "Último: \(last.subject ?? "sin asunto") · \(label(last.last_event ?? ""))",
                                          severity: .info,
                                          url: last.id.flatMap { URL(string: "https://resend.com/emails/\($0)") }))
        }
        return out
    }
}

// MARK: - Notion

public enum NotionFeed {
    struct Response: Decodable { var results: [Page]? }
    struct Page: Decodable { var id: String?; var url: String?; var last_edited_time: String?; var properties: [String: Prop]? }
    struct Prop: Decodable { var type: String?; var title: [Text]? }
    struct Text: Decodable { var plain_text: String? }

    public static func summaries(from data: Data, now: Date = Date()) -> [IntegrationSummary] {
        guard let list = decode(Response.self, data)?.results else { return [] }
        return list.prefix(3).map { p in
            let title = p.properties?.values.first { $0.type == "title" }?.title?
                .compactMap(\.plain_text).joined() ?? ""
            let when = IntegrationDates.parse(p.last_edited_time).map { "Editada " + IntegrationDates.relative($0, now: now) } ?? ""
            return IntegrationSummary(id: "\(p.id ?? title).\(p.last_edited_time ?? "")", integration: .notion,
                                      title: title.isEmpty ? "Sin título" : title, subtitle: when,
                                      url: p.url.flatMap(URL.init(string:)))
        }
    }
}

// MARK: - Cal.com

public enum CalcomFeed {
    struct Response: Decodable {
        var data: [Booking]?
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: K.self)
            if let a = try? c.decode([Booking].self, forKey: .data) { data = a }
            else { data = (try? c.decode(Nested.self, forKey: .data))?.bookings }
        }
        enum K: String, CodingKey { case data }
    }
    struct Nested: Decodable { var bookings: [Booking]? }
    struct Booking: Decodable {
        var uid: String?; var title: String?; var start: String?; var startTime: String?
        var status: String?; var meetingUrl: String?; var location: String?; var attendees: [Person]?
    }
    struct Person: Decodable { var name: String? }

    /// Próxima reserva; "warning" si empieza en ≤ 10 min (para asomar antes de empezar).
    public static func summaries(from data: Data, now: Date = Date()) -> [IntegrationSummary] {
        guard let list = decode(Response.self, data)?.data else { return [] }
        let next = list.compactMap { b -> (Booking, Date)? in
            guard let d = IntegrationDates.parse(b.start ?? b.startTime), d > now.addingTimeInterval(-300),
                  !["cancelled", "canceled", "rejected"].contains((b.status ?? "").lowercased()) else { return nil }
            return (b, d)
        }.min { $0.1 < $1.1 }
        guard let pair = next else { return [] }
        let (b, date) = pair
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "HH:mm" : "EEE d · HH:mm"
        let who = b.attendees?.first?.name.map { " · con \($0)" } ?? ""
        let soon = date.timeIntervalSince(now) <= 600
        let link = [b.meetingUrl, b.location].compactMap { $0 }.first { $0.hasPrefix("http") }
            ?? b.uid.map { "https://app.cal.com/booking/\($0)" }
        return [IntegrationSummary(id: "next.\(b.uid ?? "").\(soon ? "soon" : "later")", integration: .calcom,
                                   title: b.title ?? "Reunión",
                                   subtitle: (soon ? "Empieza " + IntegrationDates.relative(date, now: now) : f.string(from: date)) + who,
                                   symbol: soon ? "bell.badge" : "calendar", severity: soon ? .warning : .info,
                                   url: link.flatMap(URL.init(string:)))]
    }
}

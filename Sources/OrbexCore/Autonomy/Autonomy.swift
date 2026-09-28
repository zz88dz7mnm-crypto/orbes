import Foundation

/// Niveles de autonomía (informe §11.2).
public enum AutonomyLevel: Int, Codable, Comparable, CaseIterable, Sendable {
    /// Solo lectura o efectos internos (timers, notas en su carpeta).
    case free = 0
    /// Efecto leve y reversible: se hace y se avisa (abrir apps, carpetas).
    case notify = 1
    /// Tiene efecto hacia afuera o riesgo: siempre confirmar.
    case confirm = 2
    /// Prohibido para ORBEX.
    case never = 3

    public static func < (a: AutonomyLevel, b: AutonomyLevel) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .free: return "Libre"
        case .notify: return "Con aviso"
        case .confirm: return "Siempre confirmar"
        case .never: return "Nunca"
        }
    }

    public var summary: String {
        switch self {
        case .free: return "Solo lectura o efectos internos: timers, notas, reloj."
        case .notify: return "Efecto leve y reversible: abrir apps y carpetas conocidas."
        case .confirm: return "Tiene efecto hacia afuera o riesgo: ORBEX te pregunta antes."
        case .never: return "Prohibido: compras, borrar, credenciales, seguridad del sistema."
        }
    }
}

/// Un paso de una acción predefinida: abrir una app, una carpeta o una dirección web.
public struct ActionItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case app, folder, url

        public var title: String {
            switch self {
            case .app: return "App"
            case .folder: return "Carpeta"
            case .url: return "Web"
            }
        }

        public var symbol: String {
            switch self {
            case .app: return "app"
            case .folder: return "folder"
            case .url: return "globe"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    /// Nombre de la app, ruta de la carpeta o dirección web.
    public var value: String

    public init(id: UUID = UUID(), kind: Kind, value: String) {
        self.id = id
        self.kind = kind
        self.value = value
    }
}

/// Acción con nombre ("setup de trabajo" → Slack + Figma + ~/Proyectos).
public struct AllowedAction: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [ActionItem]

    public init(id: UUID = UUID(), name: String, items: [ActionItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

/// Lista de acciones y apps permitidas (editable en Configuración). Fuera de la lista, ORBEX pide confirmación.
public struct ActionAllowlist: Codable, Equatable, Sendable {
    public var actions: [AllowedAction]
    /// Apps extra que se abren sin preguntar (además de las comunes).
    public var extraApps: [String]
    /// Si es `false`, solo valen las apps de `extraApps` y de las acciones.
    public var allowCommonApps: Bool

    public init(actions: [AllowedAction] = [AllowedAction(name: "setup de trabajo")],
                extraApps: [String] = [], allowCommonApps: Bool = true) {
        self.actions = actions
        self.extraApps = extraApps
        self.allowCommonApps = allowCommonApps
    }

    public static let `default` = ActionAllowlist()

    /// Apps comunes que se abren sin preguntar (nivel 1).
    public static let commonApps: [String] = [
        "Safari", "Google Chrome", "Firefox", "Arc", "Brave Browser", "Mail", "Calendar", "Notes", "Reminders",
        "Messages", "Music", "Spotify", "Photos", "Preview", "Finder", "Terminal", "iTerm", "Warp",
        "Calculator", "TextEdit", "System Settings", "App Store", "Maps", "Contacts", "FaceTime", "Clock",
        "Weather", "Podcasts", "TV", "Books", "Stickies", "Activity Monitor", "Xcode", "Visual Studio Code",
        "Cursor", "Figma", "Slack", "Discord", "Notion", "Obsidian", "WhatsApp", "Telegram", "zoom.us",
        "Microsoft Word", "Microsoft Excel", "Microsoft PowerPoint", "Microsoft Outlook", "Microsoft Teams",
        "Pages", "Numbers", "Keynote", "Claude", "ChatGPT",
    ]

    /// Apps que ORBEX nunca abre solo (credenciales / seguridad del sistema): nivel 3.
    public static let forbiddenApps: [String] = [
        "Keychain Access", "Acceso a Llaveros", "Passwords", "Contraseñas", "Disk Utility", "Utilidad de Discos",
    ]

    /// Clave para comparar nombres de acciones: sin tildes, sin "mi/el/la", espacios simples.
    static func actionKey(_ s: String) -> String {
        let words = CommandText.fold(s)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        return words.drop(while: { CommandText.articles.contains($0) }).joined(separator: " ")
    }

    /// Acción con ese nombre ("mi setup de trabajo" encuentra "Setup de trabajo").
    public func action(named name: String) -> AllowedAction? {
        let key = Self.actionKey(name)
        guard !key.isEmpty else { return nil }
        return actions.first { Self.actionKey($0.name) == key }
    }

    public func isForbiddenApp(_ name: String) -> Bool {
        let key = AppAliases.matchKey(AppAliases.canonical(name))
        return Self.forbiddenApps.contains { AppAliases.matchKey($0) == key }
    }

    /// La app se puede abrir sin preguntar (está en las comunes, en las extra o en alguna acción).
    public func isAllowedApp(_ name: String) -> Bool {
        let key = AppAliases.matchKey(AppAliases.canonical(name))
        guard !key.isEmpty, !isForbiddenApp(name) else { return false }
        var allowed = extraApps
        if allowCommonApps { allowed += Self.commonApps }
        allowed += actions.flatMap { $0.items.filter { $0.kind == .app }.map(\.value) }
        return allowed.contains { AppAliases.matchKey(AppAliases.canonical($0)) == key }
    }

    /// La carpeta está en alguna acción de la lista.
    public func isAllowedFolder(_ path: String, homeDirectory: String) -> Bool {
        let target = AutonomyPolicy.standardized(path, home: homeDirectory)
        return actions.flatMap { $0.items }.contains {
            $0.kind == .folder && AutonomyPolicy.standardized($0.value, home: homeDirectory) == target
        }
    }
}

/// Decide cuánta autonomía tiene cada comando.
public enum AutonomyPolicy {
    public static func level(for command: OrbexCommand, allowlist: ActionAllowlist,
                             homeDirectory: String = NSHomeDirectory()) -> AutonomyLevel {
        switch command {
        case .timer, .note, .stopwatch, .pomodoro, .showClock:
            return .free
        case .remind, .scheduledAction, .remember:
            // Llegan en la Fase 4 (el planificador aplicará la lista al ejecutar).
            return .free
        case .openApp(let name):
            if allowlist.action(named: name) != nil { return .notify }
            if allowlist.isForbiddenApp(name) { return .never }
            if allowlist.isAllowedApp(name) { return .notify }
            if looksLikeWebAddress(name) { return .notify }
            return .confirm
        case .openFolder(let path):
            if allowlist.isAllowedFolder(path, homeDirectory: homeDirectory) { return .notify }
            if !path.hasPrefix("/") && !path.hasPrefix("~") {
                // Nombre suelto ("proyecto"): se busca dentro de la carpeta personal.
                return path.contains("..") ? .confirm : .notify
            }
            return isInside(path, home: homeDirectory) ? .notify : .confirm
        }
    }

    /// "~/x" → "/Users/yo/x", sin "/./", "/../" ni barra final.
    public static func standardized(_ path: String, home: String) -> String {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if p == "~" { p = home } else if p.hasPrefix("~/") { p = home + String(p.dropFirst(1)) }
        var parts: [Substring] = []
        for part in p.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    /// La ruta queda dentro de la carpeta personal.
    public static func isInside(_ path: String, home: String) -> Bool {
        let p = standardized(path, home: home)
        let h = standardized(home, home: home)
        return p == h || p.hasPrefix(h + "/")
    }

    /// "youtube.com", "https://…", "www.algo.com.ar".
    public static func looksLikeWebAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return true }
        guard !t.contains(" "), t.contains("."), !t.hasSuffix(".app") else { return false }
        let parts = t.split(separator: ".")
        guard parts.count >= 2, let tld = parts.last, (2...6).contains(tld.count),
              tld.allSatisfy({ $0.isLetter }) else { return false }
        return parts.allSatisfy { !$0.isEmpty }
    }

    /// Dirección web completa ("youtube.com" → "https://youtube.com").
    public static func webURLString(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        let lower = t.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") ? t : "https://\(t)"
    }
}

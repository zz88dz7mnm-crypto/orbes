import Foundation

/// Nombres de apps dichos en castellano (o abreviados) → nombre del paquete `.app` en macOS.
/// Los paquetes de Apple están en inglés en disco ("Calculator.app") aunque el Finder los muestre traducidos.
public enum AppAliases {
    static let table: [String: String] = [
        "terminal": "Terminal", "la terminal": "Terminal", "consola": "Terminal",
        "calculadora": "Calculator", "notas": "Notes", "calendario": "Calendar", "agenda": "Calendar",
        "correo": "Mail", "mail": "Mail", "mensajes": "Messages", "musica": "Music", "fotos": "Photos",
        "recordatorios": "Reminders", "vista previa": "Preview", "safari": "Safari",
        "configuracion": "System Settings", "ajustes": "System Settings",
        "ajustes del sistema": "System Settings", "configuracion del sistema": "System Settings",
        "preferencias": "System Settings", "preferencias del sistema": "System Settings",
        "monitor de actividad": "Activity Monitor", "app store": "App Store", "tienda": "App Store",
        "facetime": "FaceTime", "mapas": "Maps", "contactos": "Contacts", "libros": "Books",
        "podcasts": "Podcasts", "tv": "TV", "notas adhesivas": "Stickies", "textedit": "TextEdit",
        "editor de texto": "TextEdit", "finder": "Finder", "xcode": "Xcode",
        "captura de pantalla": "Screenshot", "capturas": "Screenshot", "reloj": "Clock",
        "chrome": "Google Chrome", "google chrome": "Google Chrome", "firefox": "Firefox",
        "brave": "Brave Browser", "arc": "Arc", "edge": "Microsoft Edge",
        "vscode": "Visual Studio Code", "vs code": "Visual Studio Code", "visual studio code": "Visual Studio Code",
        "visual studio": "Visual Studio Code", "code": "Visual Studio Code", "cursor": "Cursor",
        "word": "Microsoft Word", "excel": "Microsoft Excel", "powerpoint": "Microsoft PowerPoint",
        "outlook": "Microsoft Outlook", "teams": "Microsoft Teams", "zoom": "zoom.us",
        "whatsapp": "WhatsApp", "wasap": "WhatsApp", "telegram": "Telegram", "spotify": "Spotify",
        "figma": "Figma", "slack": "Slack", "discord": "Discord", "notion": "Notion", "obsidian": "Obsidian",
        "iterm": "iTerm", "iterm2": "iTerm", "warp": "Warp", "claude": "Claude", "chatgpt": "ChatGPT",
        "pages": "Pages", "numbers": "Numbers", "keynote": "Keynote", "imovie": "iMovie",
        "garageband": "GarageBand", "photoshop": "Adobe Photoshop", "illustrator": "Adobe Illustrator",
    ]

    /// Nombre canónico si se conoce ("la terminal" → "Terminal"); si no, el nombre tal cual.
    public static func canonical(_ name: String) -> String {
        let key = CommandText.fold(name).trimmingCharacters(in: .whitespaces)
        if let hit = table[key] { return hit }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Clave para comparar nombres de apps: sin tildes, minúsculas, sin espacios ni signos.
    public static func matchKey(_ name: String) -> String {
        var s = CommandText.fold(name)
        if s.hasSuffix(".app") { s.removeLast(4) }
        return String(s.filter { $0.isLetter || $0.isNumber })
    }

    /// Elige la app que mejor coincide con lo pedido entre `candidates` (nombres sin ".app").
    /// Orden: igual → empieza con → alguna palabra empieza con → contiene. Ante empate, el nombre más corto.
    public static func bestMatch(_ query: String, in candidates: [String]) -> String? {
        let q = matchKey(canonical(query))
        guard !q.isEmpty else { return nil }
        let keyed = candidates.map { (name: $0, key: matchKey($0)) }
        if let exact = keyed.first(where: { $0.key == q }) { return exact.name }
        func shortest(_ list: [(name: String, key: String)]) -> String? {
            list.min { $0.key.count == $1.key.count ? $0.name < $1.name : $0.key.count < $1.key.count }?.name
        }
        if let hit = shortest(keyed.filter { $0.key.hasPrefix(q) }) { return hit }
        let wordHits = keyed.filter { item in
            CommandText.fold(item.name).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .contains { $0.hasPrefix(q) }
        }
        if let hit = shortest(wordHits) { return hit }
        if q.count >= 3, let hit = shortest(keyed.filter { $0.key.contains(q) }) { return hit }
        return nil
    }
}

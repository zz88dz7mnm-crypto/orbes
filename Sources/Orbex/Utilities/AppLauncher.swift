import AppKit
import OrbexCore

/// Abre apps por nombre (con tolerancia a tildes y alias: "la terminal" → Terminal), carpetas y webs.
enum AppLauncher {
    private static var searchDirs: [URL] {
        let fm = FileManager.default
        var dirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
        ]
        dirs.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"))
        return dirs
    }

    /// Todas las apps instaladas: nombre visible → URL.
    static func installedApps() -> [String: URL] {
        var result: [String: URL] = [:]
        let fm = FileManager.default
        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                if result[name] == nil { result[name] = url }
            }
        }
        return result
    }

    static func findApp(named name: String) -> URL? {
        let canonical = AppAliases.canonical(name)
        let apps = installedApps()
        if let exact = apps[canonical] { return exact }
        if let best = AppAliases.bestMatch(canonical, in: Array(apps.keys)) { return apps[best] }
        return nil
    }

    @discardableResult
    static func openApp(named name: String) -> Bool {
        guard let url = findApp(named: name) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { NSLog("ORBEX: no se pudo abrir %@: %@", name, error.localizedDescription) }
        }
        return true
    }

    @discardableResult
    static func openFolder(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else { return false }
        return NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
    }

    @discardableResult
    static func openURL(_ string: String) -> Bool {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Ejecuta una acción de la lista permitida (abre cada app/carpeta/web).
    @discardableResult
    static func run(_ action: AllowedAction) -> Int {
        var opened = 0
        for item in action.items {
            let ok: Bool
            switch item.kind {
            case .app: ok = openApp(named: item.value)
            case .folder: ok = openFolder(item.value)
            case .url: ok = openURL(item.value)
            }
            if ok { opened += 1 }
        }
        return opened
    }
}

import Foundation

/// Acceso directo en el Escritorio (informe §13.4): un alias de Finder `~/Desktop/ORBEX` que apunta a
/// `ORBEX.app`. Se crea en el primer arranque (si el usuario quiere), se crea/quita desde
/// Configuración > General y se borra al desinstalar (`ORBEX --remove-shortcut`).
/// Nunca borra algo que no sea un alias o un enlace simbólico.
enum DesktopShortcut {
    static let name = "ORBEX"

    /// `~/Desktop/ORBEX`
    static var shortcutURL: URL? {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name, isDirectory: false)
    }

    /// `true` si en el Escritorio hay un alias (o enlace) llamado "ORBEX".
    static var exists: Bool {
        guard let url = shortcutURL, itemExists(at: url) else { return false }
        return isAliasOrLink(url)
    }

    /// Crea (o renueva) el alias. Devuelve `false` si no se pudo; nunca lanza.
    @discardableResult
    static func create() -> Bool {
        guard let url = shortcutURL else {
            NSLog("ORBEX: no encontré la carpeta del Escritorio.")
            return false
        }
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else {
            NSLog("ORBEX: el acceso directo solo se crea desde la app empaquetada (ORBEX.app).")
            return false
        }
        if itemExists(at: url) {
            guard isAliasOrLink(url) else {
                NSLog("ORBEX: ya hay un archivo o carpeta \"%@\" en el Escritorio; no lo toco.", name)
                return false
            }
            // Es un alias viejo (quizás apunta a otra ubicación de la app): lo renovamos.
            try? FileManager.default.removeItem(at: url)
        }
        do {
            let data = try app.bookmarkData(options: .suitableForBookmarkFile,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            try URL.writeBookmarkData(data, to: url)
            return true
        } catch {
            NSLog("ORBEX: no se pudo crear el alias (%@). Pruebo con un enlace simbólico.", error.localizedDescription)
        }
        do {
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: app)
            return true
        } catch {
            NSLog("ORBEX: no se pudo crear el acceso directo: %@", error.localizedDescription)
            return false
        }
    }

    /// Quita el acceso directo solo si es un alias o un enlace. Devuelve `true` si borró algo.
    @discardableResult
    static func remove() -> Bool {
        guard let url = shortcutURL, itemExists(at: url) else { return false }
        guard isAliasOrLink(url) else {
            NSLog("ORBEX: \"%@\" en el Escritorio no es un alias; no lo borro.", name)
            return false
        }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            NSLog("ORBEX: no se pudo quitar el acceso directo: %@", error.localizedDescription)
            return false
        }
    }

    /// Flags de línea de comandos: `--remove-shortcut` (lo usa `uninstall.sh`) y `--create-shortcut`.
    /// Imprime un mensaje y devuelve `true` si manejó el flag (el llamador sale después).
    static func handleCLI(_ args: [String]) -> Bool {
        if args.contains("--remove-shortcut") {
            if remove() {
                print("ORBEX: acceso directo quitado del Escritorio.")
            } else if let url = shortcutURL, itemExists(at: url) {
                print("ORBEX: hay algo llamado \"\(name)\" en el Escritorio que no es un alias; no lo toqué.")
            } else {
                print("ORBEX: no había acceso directo en el Escritorio.")
            }
            return true
        }
        if args.contains("--create-shortcut") {
            if create() {
                print("ORBEX: acceso directo creado en el Escritorio.")
            } else {
                print("ORBEX: no se pudo crear el acceso directo en el Escritorio.")
            }
            return true
        }
        return false
    }

    // MARK: - Privado

    /// Existe algo en la ruta (sin seguir enlaces: un enlace roto también cuenta).
    private static func itemExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Alias de Finder o enlace simbólico (`isAliasFile` es `true` para ambos).
    private static func isAliasOrLink(_ url: URL) -> Bool {
        if let type = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            return true
        }
        let values = try? url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])
        return values?.isAliasFile == true || values?.isSymbolicLink == true
    }
}

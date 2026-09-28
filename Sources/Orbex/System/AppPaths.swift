import Foundation

/// Rutas fijas de ORBEX en disco.
enum AppPaths {
    static let bundleID = "com.orbex.ORBEX"

    /// `~/Library/Application Support/ORBEX/`
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ORBEX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Socket Unix que escucha la app (hooks de Claude Code / Codex).
    static var socketPath: String { supportDir.appendingPathComponent("orbex.sock").path }

    /// Copia estable del relé de hooks (la app la actualiza en cada arranque).
    static var hookBinaryPath: String { supportDir.appendingPathComponent("orbex-hook").path }

    /// El relé que viene dentro de la app: `ORBEX.app/Contents/Helpers/orbex-hook`.
    static var bundledHookBinary: URL? {
        let helpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/orbex-hook")
        if FileManager.default.isExecutableFile(atPath: helpers.path) { return helpers }
        // Ejecutando con `swift run`: el binario está al lado del ejecutable.
        let sibling = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("orbex-hook")
        if let sibling, FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        return nil
    }

    /// Datos locales (notas, memoria, temporizadores, planificador).
    static func dataFile(_ name: String) -> URL { supportDir.appendingPathComponent(name) }
}

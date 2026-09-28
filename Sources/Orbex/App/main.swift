import AppKit

// Flags de línea de comandos (los usa scripts/uninstall.sh). Imprimen y salen.
let arguments = CommandLine.arguments

if arguments.contains("--uninstall-hooks") {
    // Fase 3: acá se van a desinstalar los hooks de Claude Code / Codex.
    print("ORBEX: todavía no hay hooks instalados (llegan en la Fase 3).")
    exit(0)
}

if DesktopShortcut.handleCLI(arguments) {
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

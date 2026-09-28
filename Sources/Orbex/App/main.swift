import AppKit

// Flags de línea de comandos (los usa scripts/uninstall.sh). Imprimen y salen.
let arguments = CommandLine.arguments

if arguments.contains("--uninstall-hooks") {
    HooksCLI.uninstallAll()
    exit(0)
}

if arguments.contains("--disable-login-item") {
    LaunchAtLogin.set(false)
    print("ORBEX: inicio con la Mac desactivado.")
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

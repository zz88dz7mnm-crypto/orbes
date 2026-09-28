import AppKit
import SwiftUI

/// Ventana de Configuración (una sola instancia).
///
/// Uso: `SettingsWindowController.shared.show()`. Con `startObserving()` también se abre sola
/// cuando alguien publica `Notification.Name.orbexOpenSettings` (menú, atajo, `OrbexBus.perform("settings")`).
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private static let autosaveName = "OrbexSettingsWindow"

    private var window: NSWindow?
    /// `false` después de cerrar: se saca el contenido para que la vista previa animada no gaste CPU.
    private var hasContent = false
    private var openObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    // MARK: - API

    /// Muestra la ventana (la crea la primera vez) y la trae al frente.
    func show() {
        let win = window ?? makeWindow()
        if !hasContent { install(in: win) }
        if win.isMiniaturized { win.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    /// Escucha el pedido global de abrir Configuración. Llamar una vez al arrancar.
    func startObserving() {
        guard openObserver == nil else { return }
        openObserver = NotificationCenter.default.addObserver(forName: .orbexOpenSettings,
                                                              object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                SettingsWindowController.shared.show()
            }
        }
    }

    // MARK: - Internos

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                           styleMask: [.titled, .closable, .resizable, .miniaturizable],
                           backing: .buffered,
                           defer: false)
        win.title = "Configuración — ORBEX"
        win.isReleasedWhenClosed = false
        win.contentMinSize = NSSize(width: 680, height: 480)
        win.tabbingMode = .disallowed
        // Que aparezca en el escritorio donde está el usuario (ORBEX vive en todos).
        win.collectionBehavior = [.moveToActiveSpace]
        // La primera vez, centrada; después, donde la dejó el usuario.
        if !win.setFrameUsingName(Self.autosaveName) {
            win.center()
        }
        _ = win.setFrameAutosaveName(Self.autosaveName)

        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                               object: win, queue: .main) { _ in
            MainActor.assumeIsolated {
                SettingsWindowController.shared.scheduleContentRelease()
            }
        }
        window = win
        return win
    }

    private func install(in win: NSWindow) {
        let root = SettingsRootView()
            .environment(\.hostWindow, HostWindowRef(win))
        let hosting = NSHostingView(rootView: root)
        // Solo respetar el mínimo de SwiftUI; el tamaño lo maneja la ventana.
        hosting.sizingOptions = [.minSize]
        win.contentView = hosting
        hasContent = true
    }

    /// Después de cerrar, suelta la vista (y su animación). Se vuelve a crear en `show()`.
    private func scheduleContentRelease() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let controller = SettingsWindowController.shared
                guard let win = controller.window, !win.isVisible else { return }
                win.contentView = NSView()
                controller.hasContent = false
            }
        }
    }
}

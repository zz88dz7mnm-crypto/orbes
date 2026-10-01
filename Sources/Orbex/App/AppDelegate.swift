import AppKit
import Combine
import SwiftUI
import OrbexCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    /// La isla (base Coucou): ventana, estados, vistas.
    private(set) var islandController: IslandWindowController?
    private let model = AppModel.shared
    private var demoWorking = false
    private var demoAttention = false
    private var cancellables: [AnyCancellable] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Si un cliente cierra el socket antes de tiempo, que no se caiga la app.
        signal(SIGPIPE, SIG_IGN)
        // Leer las claves del Keychain UNA vez, en el hilo principal, antes de que un servicio las pida.
        _ = KeychainStore.shared
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupIsland()
        OrbexHotKeys.installDefaults()
        SettingsWindowController.shared.startObserving()
        startPhase2Modules()
        PersonalityDirector.shared.start()   // saludo por nombre, "te extrañé", rachas, frases, te ve tipear
        SessionsStore.shared.start()   // hooks de Claude Code / Codex (socket Unix + orbex-hook)
        SessionsBridge.shared.start()  // permisos pendientes → vista de permiso de la isla
        SchedulerStore.shared.start()  // recordatorios y acciones a hora puntual
        _ = MemoryStore.shared         // memoria local (contexto del asistente)
        MusicStore.shared.start()      // Spotify / Música
        VoiceController.shared.start() // "Orbex, …": atajo ⌃⌥Espacio y, si está activado, siempre atento
        startServices()                // Stripe, Notion, Cal.com (opcionales: solo con clave guardada)
        if UserDefaults.standard.bool(forKey: "orbex.music.beatDetection") {
            Task { @MainActor in _ = await BeatDetector.shared.start() }
        }

        // Aplicar ajustes que dependen del sistema (por si cambiaron fuera de la app).
        if model.settings.launchAtLogin != LaunchAtLogin.isEnabled {
            LaunchAtLogin.set(model.settings.launchAtLogin)
        }

        if !model.settings.firstRunDone {
            FirstRunWindowController.shared.showIfNeeded()
        } else if model.settings.greetOnLaunch {
            // Saludo de bienvenida: ORBEX sale del notch y saluda (vista `greeting` de la isla).
            islandController?.fsm.launch()
            OrbexBus.play(.greet)
        }
    }

    // MARK: - Isla

    private func setupIsland() {
        let controller = IslandWindowController()
        islandController = controller
        controller.showWindow(nil)
        OrbexBridge.shared.attach(controller)
        // "Configuración…" desde la vista de ajustes de la isla.
        NotificationCenter.default.addObserver(forName: .openFullSettings, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SettingsWindowController.shared.show() }
        }
    }

    /// Servicios opcionales: cada uno consulta solo si su clave está en el Keychain (si no, no hace nada).
    private func startServices() {
        StripePoller.shared.start()
        CalcomPoller.shared.start()
        NotionPoller.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        VoiceController.shared.stop()   // suelta el micrófono
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Abrir ORBEX desde el Dock/Finder/acceso directo cuando ya está corriendo: abrir la isla.
        model.perform("open")
        return false
    }

    /// Fase 2: timers (se recuperan los guardados), notas y asistente.
    private func startPhase2Modules() {
        // La línea de estado debajo del notch muestra el timer en curso.
        TimersStore.shared.$statusLine
            .receive(on: DispatchQueue.main)
            .sink { line in
                MainActor.assumeIsolated { AppModel.shared.statusLine = line }
            }
            .store(in: &cancellables)
        _ = NotesStore.shared
        _ = AssistantStore.shared
    }

    // MARK: - Menú de la barra

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusBarIcon.image()
        item.button?.toolTip = "ORBEX"

        let menu = NSMenu()
        menu.addItem(makeItem("Abrir ORBEX", #selector(openIsland), key: "o"))
        menu.addItem(makeItem("Asistente", #selector(openAssistant), key: "a"))
        menu.addItem(makeItem("Modo inteligente", #selector(toggleSmartMode), key: "i"))
        menu.addItem(makeItem("Modo reloj", #selector(toggleClock), key: "c"))
        menu.addItem(.separator())

        let demo = NSMenu()
        demo.addItem(makeItem("Trabajando (activar/desactivar)", #selector(demoToggleWorking)))
        demo.addItem(makeItem("Te necesito (activar/desactivar)", #selector(demoToggleAttention)))
        demo.addItem(makeItem("Festejar", #selector(demoCelebrate)))
        demo.addItem(makeItem("Preocuparse", #selector(demoWorry)))
        demo.addItem(makeItem("Mostrar aviso", #selector(demoToast)))
        demo.addItem(makeItem("Dormir / despertar", #selector(demoSleep)))
        demo.addItem(.separator())
        demo.addItem(makeItem("Saludo", #selector(demoGreet)))
        demo.addItem(makeItem("Cosquillas", #selector(demoTickle)))
        let demoItem = NSMenuItem(title: "Probar estados", action: nil, keyEquivalent: "")
        demoItem.submenu = demo
        menu.addItem(demoItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("Configuración…", #selector(openSettings), key: ","))
        menu.addItem(makeItem("Bienvenida…", #selector(showWelcome)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Salir de ORBEX", #selector(quit), key: "q"))
        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func openIsland() { model.perform("open") }
    @objc private func openAssistant() { model.perform("assistant") }
    @objc private func toggleSmartMode() { SmartModeController.shared.toggle() }
    @objc private func toggleClock() { model.perform("clock") }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func showWelcome() { FirstRunWindowController.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func demoToggleWorking() {
        demoWorking.toggle()
        model.statusLine = demoWorking ? "Probando: trabajando…" : ""
        OrbexBus.setActivity(source: "demo", working: demoWorking, attention: demoAttention)
    }

    @objc private func demoToggleAttention() {
        demoAttention.toggle()
        model.statusLine = demoAttention ? "Probando: te necesito" : ""
        OrbexBus.setActivity(source: "demo", working: demoWorking, attention: demoAttention)
    }

    @objc private func demoCelebrate() {
        OrbexBus.react(.celebrate)
        OrbexBus.play(.sessionDone)
        model.flash()
    }

    @objc private func demoWorry() {
        OrbexBus.react(.worry)
        OrbexBus.play(.error)
        model.flash()
    }

    @objc private func demoToast() {
        OrbexBus.toast("¡Hola! Esto es un aviso", symbol: "bell.fill")
    }

    @objc private func demoSleep() {
        model.setSleepy(!model.isSleepy)
    }

    /// El saludo de bienvenida: ORBEX sale del notch y saluda.
    @objc private func demoGreet() {
        if ClockController.shared.isVisible { model.perform("clock") }
        islandController?.fsm.launch()
        OrbexBus.play(.greet)
    }

    /// Cosquillas (tres seguidas = mareo). Se ven en la isla abierta: si está cerrada, primero se abre.
    @objc private func demoTickle() {
        let open = AppState.shared.mode == .expanded
        if !open { model.perform("open") }
        DispatchQueue.main.asyncAfter(deadline: .now() + (open ? 0 : 0.45)) {
            NotificationCenter.default.post(name: .triggerSlap, object: nil)
        }
    }
}

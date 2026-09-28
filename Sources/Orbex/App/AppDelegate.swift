import AppKit
import Combine
import SwiftUI
import OrbexCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let model = AppModel.shared
    private var demoWorking = false
    private var demoAttention = false
    private var cancellables: [AnyCancellable] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Si un cliente cierra el socket antes de tiempo, que no se caiga la app.
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        IslandController.shared.start()
        OrbexHotKeys.installDefaults()
        SettingsWindowController.shared.startObserving()
        startPhase2Modules()
        SessionsStore.shared.start()   // Fase 3: hooks de Claude Code / Codex
        SchedulerStore.shared.start()  // Fase 4: recordatorios y acciones a hora puntual
        _ = MemoryStore.shared         // Fase 4: memoria local (contexto del asistente)

        // Aplicar ajustes que dependen del sistema (por si cambiaron fuera de la app).
        if model.settings.launchAtLogin != LaunchAtLogin.isEnabled {
            LaunchAtLogin.set(model.settings.launchAtLogin)
        }

        if !model.settings.firstRunDone {
            FirstRunWindowController.shared.showIfNeeded()
        } else if model.settings.greetOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { self.greet() }
            }
        }
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

    private func greet() {
        model.brain.greet()
        OrbexBus.play(.greet)
        model.handle(.flash(duration: 3))
    }

    // MARK: - Menú de la barra

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusBarIcon.image()
        item.button?.toolTip = "ORBEX"

        let menu = NSMenu()
        menu.addItem(makeItem("Abrir ORBEX", #selector(openIsland), key: "o"))
        menu.addItem(makeItem("Asistente", #selector(openAssistant), key: "a"))
        menu.addItem(makeItem("Modo reloj", #selector(toggleClock), key: "c"))
        menu.addItem(.separator())

        let demo = NSMenu()
        demo.addItem(makeItem("Trabajando (activar/desactivar)", #selector(demoToggleWorking)))
        demo.addItem(makeItem("Te necesito (activar/desactivar)", #selector(demoToggleAttention)))
        demo.addItem(makeItem("Festejar", #selector(demoCelebrate)))
        demo.addItem(makeItem("Preocuparse", #selector(demoWorry)))
        demo.addItem(makeItem("Mostrar aviso", #selector(demoToast)))
        demo.addItem(makeItem("Dormir / despertar", #selector(demoSleep)))
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
        model.handle(.flash(duration: 3))
    }

    @objc private func demoWorry() {
        OrbexBus.react(.worry)
        OrbexBus.play(.error)
        model.handle(.flash(duration: 3))
    }

    @objc private func demoToast() {
        OrbexBus.toast("¡Hola! Esto es un aviso", symbol: "bell.fill")
    }

    @objc private func demoSleep() {
        let sleeping = model.islandState == .sleeping
        OrbexBus.setActivity(source: "demo-sleep", working: false, attention: false)
        if sleeping {
            model.handle(.contextChanged(IslandContext()))
        } else {
            model.handle(.contextChanged(IslandContext(isSleepy: true)))
        }
    }
}

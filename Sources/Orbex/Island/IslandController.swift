import AppKit
import SwiftUI
import OrbexCore

/// Panel de la isla: sin bordes, no activable, por encima de la barra de menú y de las apps
/// a pantalla completa, en todos los escritorios (informe §5.4).
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Que macOS no la empuje debajo de la barra de menú.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Maneja la ventana de la isla: posición sobre el notch, clics que pasan, hover, teclado.
@MainActor
final class IslandController {
    static let shared = IslandController()

    let model = AppModel.shared
    private(set) var panel: IslandPanel?
    private var placement: NotchDetector.Placement?
    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 0
    private var wasInside = false
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var lastMouse: CGPoint = .zero
    /// App que estaba al frente cuando ORBEX tomó el teclado (para devolverle el foco).
    private var previousApp: NSRunningApplication?

    private init() {}

    // MARK: - Arranque

    func start() {
        let panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let root = IslandRootView(model: model)
            .environment(\.hostWindow, HostWindowRef(panel))
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel

        reposition()
        panel.orderFrontRegardless()

        observeScreens()
        installMonitors()
        schedulePolling()

        NotificationCenter.default.addObserver(forName: .orbexIslandStateChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { IslandController.shared.stateDidChange() }
        }
    }

    // MARK: - Posición

    /// Mide el notch y coloca el panel centrado sobre él (se llama al cambiar pantallas o ajustes).
    func reposition() {
        guard let panel else { return }
        let s = model.settings
        guard let place = NotchDetector.placement(for: s.screen, adjustW: s.notchAdjustWidth, adjustH: s.notchAdjustHeight) else { return }
        placement = place
        model.updatePlacement(notch: place.notch, screenSize: place.screen.frame.size)
        let size = model.maxIslandSize
        let frame = NSRect(x: place.notchCenterX - size.width / 2, y: place.topY - size.height,
                           width: size.width, height: size.height)
        panel.setFrame(frame.integral, display: true)
    }

    /// Rectángulo actual de la isla (cuerpo, sin hombreras) en coordenadas de pantalla.
    func islandRectOnScreen() -> CGRect {
        guard let panel, let place = placement else { return .zero }
        let size = model.islandSize
        let w = CGFloat(size.width), h = CGFloat(size.height)
        _ = panel
        return CGRect(x: place.notchCenterX - w / 2, y: place.topY - h, width: w, height: h)
    }

    // MARK: - Sondeo del mouse (clics que pasan + hover)

    private func schedulePolling() {
        // Rápido cuando la isla está visible; lento en reposo oculto (ahorro de batería).
        let visible = model.islandState != .hidden && model.islandState != .clock
        let interval: TimeInterval = visible ? 1.0 / 30.0 : 1.0 / 10.0
        guard interval != pollInterval || pollTimer == nil else { return }
        pollInterval = interval
        pollTimer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { IslandController.shared.poll() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func poll() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse {
            lastMouse = mouse
            model.brain.mouseOnScreen = mouse
            model.brain.lastMouseMove = CACurrentMediaTime()
        }

        let rect = islandRectOnScreen()
        // En reposo oculto el área sensible es un poco más grande que el notch para que sea fácil asomar.
        let slop: CGFloat = model.islandState == .hidden || model.islandState == .sleeping ? 4 : 2
        let inside = model.islandState != .clock && rect.insetBy(dx: -slop, dy: -slop).contains(mouse)

        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        if inside != wasInside {
            wasInside = inside
            model.handle(inside ? .mouseEntered : .mouseExited)
        }
        model.tick()
    }

    // MARK: - Teclado y clics afuera

    private func installMonitors() {
        // Clic fuera de la isla desplegada → cerrar (no hace falta permiso de Accesibilidad para el mouse).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { IslandController.shared.clickedOutside() }
            }
        }) { monitors.append(m) }

        // Esc cuando la isla tiene el teclado.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            if event.keyCode == 53 { // Esc
                let handled: Bool = MainActor.assumeIsolated {
                    let c = IslandController.shared
                    guard c.model.islandState.isExpanded else { return false }
                    c.model.handle(.escape)
                    return true
                }
                return handled ? nil : event
            }
            return event
        }) { monitors.append(m) }
    }

    private func clickedOutside() {
        guard model.islandState.isExpanded else { return }
        let mouse = NSEvent.mouseLocation
        if !islandRectOnScreen().contains(mouse) {
            model.handle(.clickOutside)
        }
    }

    private func stateDidChange() {
        schedulePolling()
        guard let panel else { return }
        let state = model.islandState
        if state.isExpanded {
            // Tomar el teclado (Esc, campo de texto del asistente) sin activar la app.
            if !panel.isKeyWindow {
                if let front = NSWorkspace.shared.frontmostApplication,
                   front.bundleIdentifier != Bundle.main.bundleIdentifier {
                    previousApp = front
                }
                panel.makeKey()
            }
        } else if panel.isKeyWindow {
            panel.resignKey()
            // Devolver el foco a la app que estaba antes.
            previousApp?.activate()
            previousApp = nil
        }
        if state == .clock {
            panel.ignoresMouseEvents = true
        }
    }

    // MARK: - Pantallas

    private func observeScreens() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { IslandController.shared.reposition() }
        })
        observers.append(nc.addObserver(forName: .orbexPlacementNeedsUpdate, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { IslandController.shared.reposition() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { IslandController.shared.panel?.orderFrontRegardless() }
        })
    }
}

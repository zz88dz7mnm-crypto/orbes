// Basado en Coucou (https://github.com/louis-cfm/coucou) © 2026 Louis Raillé — licencia MIT.
// Modificado para ORBEX (solo el código; ningún asset de Coucou). Ver THIRD_PARTY_NOTICES.md.

import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class IslandWindowController: NSWindowController {

    private var islandPanel: IslandPanel!
    private var state: AppState { AppState.shared }

    // State machine (replaces all hover/absence/auto-close timers)
    let fsm = IslandFlowMachine()

    private var wasInIsland = false
    private var frameTimer: Timer?
    private var viewSubscription: AnyCancellable?

    // Confused recovery timer (set by handleDizzy)
    private var confusedRecoveryTimer: DispatchWorkItem?

    // Finished-pin timer
    private var finishedPinTimer: DispatchWorkItem?

    // Mouse encima de ORBEX: quieto un ratito = caricia (rubor, corazoncitos, ronroneo).
    private var hoverTimer: DispatchWorkItem?
    private var botHovering: Bool = false
    private var botHoverStartPos: CGPoint = .zero
    private var botHoverLastMove: Double = 0
    private var petting: Bool = false
    private var lastPetSound: Double = -10

    // Window attach drag (M8)
    private var attachDragStart: NSPoint? = nil
    private var pendingIslandClick = false   // any island click → expand on mouseUp
    private var inAttachDrag = false
    private var dragGhostPanel: NSPanel? = nil
    private var dragGhostSize: CGFloat = 0
    private var ghostCurrentOrigin: NSPoint = .zero
    private var highlightPanel: NSPanel? = nil
    private var highlightWindowPid: pid_t = 0

    // ORBEX: medida en vivo del notch (NotchDetector: pantalla elegida, ajuste fino, simulado).
    private var notchW: CGFloat = IslandConst.notchWidth
    private var notchH: CGFloat = IslandConst.notchHeight
    /// Centro horizontal REAL del notch y borde superior de su pantalla (coordenadas de pantalla).
    private var notchCenterX: CGFloat = 0
    private var screenTopY: CGFloat = 0

    // ORBEX: sondeo adaptativo (60 Hz con la isla visible, ~10 Hz oculta).
    private var pollInterval: TimeInterval = 0
    private var escMonitor: Any?
    private var placementObservers: [NSObjectProtocol] = []
    private var subscriptions: Set<AnyCancellable> = []

    private static let panelW: CGFloat = 720
    private static let panelH: CGFloat = 320

    convenience init() {
        let panel = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelW, height: Self.panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        self.init(window: panel)
        self.islandPanel = panel
        applyPlacement()
        setupPanel()
    }

    // MARK: - Ubicación (ORBEX)

    /// Mide el notch en vivo y centra el panel en el centro real del notch de la pantalla elegida.
    /// Nunca usa medidas fijas: si no hay notch, `NotchDetector` lo simula a partir de la pantalla.
    func applyPlacement() {
        let s = AppModel.shared.settings
        guard let panel = islandPanel,
              let place = NotchDetector.placement(for: s.screen, adjustW: s.notchAdjustWidth,
                                                  adjustH: s.notchAdjustHeight) else { return }
        let nW = CGFloat(place.notch.width)
        let nH = CGFloat(place.notch.height)
        notchW = nW
        notchH = nH
        notchCenterX = place.notchCenterX
        screenTopY = place.topY
        panel.notchWidth = nW
        panel.notchHeight = nH
        let app = AppState.shared
        if app.notchWidth != nW || app.notchHeight != nH {
            // No son @Published: avisar a SwiftUI para que la isla se redibuje con la medida nueva.
            app.objectWillChange.send()
            app.notchWidth = nW
            app.notchHeight = nH
        }

        let target = NSRect(x: (place.notchCenterX - Self.panelW / 2).rounded(),
                            y: place.topY - Self.panelH,
                            width: Self.panelW, height: Self.panelH)
        if panel.frame != target { panel.setFrame(target, display: true) }
    }

    private func observePlacement() {
        let nc = NotificationCenter.default
        for name in [NSApplication.didChangeScreenParametersNotification, Notification.Name.orbexPlacementNeedsUpdate] {
            placementObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyPlacement() }
            })
        }
        // Cambio de espacio (o de app a pantalla completa): volver a medir y quedar al frente.
        placementObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyPlacement()
                if !ClockController.shared.isVisible { self.window?.orderFrontRegardless() }
            }
        })
    }

    private func setupPanel() {
        guard let panel = window as? IslandPanel else { return }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        // Propagate real notch dimensions to AppState
        AppState.shared.notchWidth  = notchW
        AppState.shared.notchHeight = notchH

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size

        // Apple-recommended pattern: put NSHostingView and drag destination as siblings
        // inside a common superview, rather than embedding one inside the other.
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: IslandRootView().environmentObject(AppState.shared))
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]

        // FileDropNSView sits below the hosting view (hitTest returns nil → no mouse interference).
        // AppKit routes NSDraggingDestination events to registered views independently of hitTest.
        let dropView = FileDropNSView(frame: NSRect(origin: .zero, size: contentSize))
        dropView.autoresizingMask = [.width, .height]
        dropView.onDragEntered = { [weak self] loc in
            Task { @MainActor in
                let iLoc = self?.windowToIsland(loc) ?? CGPoint(x: 320, y: 88)
                AppState.shared.fileDragOver = true
                // enterZone sets isActive=true BEFORE hookExpand triggers re-render,
                // so IslandContainer sees isActive=true when state.view becomes .upload.
                UploadSequenceEngine.shared.enterZone(x: iLoc.x, y: iLoc.y)
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.upload)
                NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(1))
            }
        }
        dropView.onDragUpdated = { [weak self] loc in
            Task { @MainActor in
                let iLoc = self?.windowToIsland(loc) ?? CGPoint(x: 320, y: 88)
                UploadSequenceEngine.shared.updateCursor(x: iLoc.x, y: iLoc.y)
            }
        }
        dropView.onDragExited = {
            Task { @MainActor in
                AppState.shared.fileDragOver = false
                // Do NOT collapse — drag session still active; island stays open.
                NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))
                UploadSequenceEngine.shared.exitZone()
            }
        }
        dropView.onFilesDropped = { urls in
            Task { @MainActor in
                await FileDropHandler.handle(urls: urls, state: AppState.shared)
            }
        }

        container.addSubview(hosting)    // z-bottom: SwiftUI + mouse events
        container.addSubview(dropView)   // z-top: drag only (hitTest→nil, transparent to mouse)
        panel.contentView = container

        startPolling()
        startKeyMonitor()
        observePlacement()
        wireFSM()

        // Make panel key whenever the prompt/chat view becomes active
        // (nonactivatingPanel never auto-becomes key, but TextField needs it)
        viewSubscription = state.$view
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newView in
                MainActor.assumeIsolated {
                    guard let self, newView == .prompt else { return }
                    self.islandPanel.makeKey()
                }
            }
    }

    // MARK: - FSM wiring

    private func wireFSM() {
        fsm.isPinned = { AppState.shared.isPinned }
        fsm.onTransition = { [weak self] from, to in
            guard let self else { return }
            switch to {
            case .hidden:
                self.setMode(.hidden)

            case .petit:
                if from == .greeting {
                    // Fire interrupt first so canvas collapse starts before mode change
                    NotificationCenter.default.post(name: .greetingInterrupt, object: nil)
                } else if from == .hidden {
                    SoundEngine.shared.play("peek")
                }
                // setMode BEFORE changing view: onChange(of: state.view) guards on .expanded,
                // so setting view while already compact won't trigger a spurious open animation.
                self.setMode(.compact)
                if from == .greeting { self.state.view = self.defaultView() }
                // Start 60s hide timer if mouse is not currently over the island
                if !self.wasInIsland { self.fsm.mouseLeft() }

            case .home:
                self.expand(to: self.defaultView())
                // Start collapse timer if mouse not currently hovering
                if !self.wasInIsland {
                    self.fsm.mouseLeft()
                }

            case .greeting:
                self.expand(to: .greeting)
            }
        }

        // FSM observes greetComplete notification
        NotificationCenter.default.addObserver(
            forName: .greetComplete, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fsm.greetComplete() }
        }
    }

    // MARK: - 60 Hz polling loop

    private func startPolling() {
        setPollInterval(desiredPollInterval())
    }

    /// 60 Hz con la isla visible (30 Hz en bajo consumo); ~10 Hz con la isla oculta (casi 0 % CPU):
    /// alcanza para notar el mouse en el notch.
    private func desiredPollInterval() -> TimeInterval {
        if inAttachDrag || attachDragStart != nil { return 1.0 / 60.0 }
        if state.mode == .hidden { return 0.1 }
        let model = AppModel.shared
        if model.settings.lowPowerMode || model.lowPower { return 1.0 / 30.0 }
        return 1.0 / 60.0
    }

    private func setPollInterval(_ interval: TimeInterval) {
        guard interval != pollInterval || frameTimer == nil else { return }
        pollInterval = interval
        frameTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // El timer vive en el run loop principal.
            MainActor.assumeIsolated { self?.pollFrame() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func pollFrame() {
        guard let panel = window as? IslandPanel else { return }
        defer { setPollInterval(desiredPollInterval()) }

        let mouse = NSEvent.mouseLocation

        // Convert mouse to panel-local coords (macOS: origin bottom-left)
        let pf = panel.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)

        // Island rect in panel coords
        let islandRect = panel.currentIslandFrame(nw: notchW, nh: notchH)
        let inIsland   = islandRect.insetBy(dx: -6, dy: -6).contains(local)

        // Toggle click-through
        let shouldAcceptMouse = inIsland || inAttachDrag || attachDragStart != nil
        if panel.ignoresMouseEvents == shouldAcceptMouse {
            panel.ignoresMouseEvents = !shouldAcceptMouse
            if shouldAcceptMouse, let cv = panel.contentView {
                panel.invalidateCursorRects(for: cv)
            }
        }

        // Mouse para la mirada de ORBEX (Y desde arriba). `BotCanvasView` supone la isla centrada en
        // `NSScreen.main`; se expresa el mouse relativo al centro REAL del notch para que la mirada
        // apunte bien en cualquier pantalla. Con la isla oculta el lienzo está en pausa: no hace falta.
        if state.mode != .hidden {
            let refMidX = (NSScreen.main ?? panel.screen)?.frame.midX ?? notchCenterX
            let newPos = CGPoint(x: mouse.x - notchCenterX + refMidX, y: screenTopY - mouse.y)
            let cur = AppState.shared.mousePosition
            if abs(newPos.x - cur.x) > 1 || abs(newPos.y - cur.y) > 1 {
                AppState.shared.mousePosition = newPos
            }
        }

        // Feed FSM hover enter/leave
        if inIsland && !wasInIsland {
            guard !inAttachDrag else { wasInIsland = inIsland; return }
            // If in greeting: tell greeting to stay open (tc → infinity)
            if fsm.state == .greeting {
                NotificationCenter.default.post(name: .greetingHover, object: nil)
            }
            // ORBEX: sin "asomarse al pasar el mouse" (o con el reloj flotante afuera) la isla oculta
            // no se asoma; un clic en el notch la abre igual.
            let peekBlocked = fsm.state == .hidden
                && (!AppModel.shared.settings.hoverPeeks || ClockController.shared.isVisible)
            if !peekBlocked { fsm.mouseEntered() }
        }
        if !inIsland && wasInIsland {
            fsm.mouseLeft()
        }
        wasInIsland = inIsland

        // Mouse encima de ORBEX (vista abierta): quieto = caricia
        let overBot = state.mode == .expanded && state.stateOverride == nil
            && !inAttachDrag && attachDragStart == nil && isBotHit(local)
        if overBot && !botHovering { botHoverIn(mousePos: mouse) }
        if !overBot && botHovering { botHoverOut() }
        botHovering = overBot
        if botHovering { updatePetting(mouse: mouse) }

        // Ghost ORBEX follows cursor + window highlight during drag (60 Hz, no throttle)
        if inAttachDrag {
            updateDragGhost()
            updateWindowHighlight()
        }
    }

    private var lastMouse: CGPoint = .zero

    // MARK: - Caricia (mouse quieto encima de ORBEX)

    private func botHoverIn(mousePos: CGPoint) {
        guard state.mode == .expanded, state.stateOverride == nil else { return }
        botHoverStartPos = mousePos
        botHoverLastMove = CACurrentMediaTime()
        NotificationCenter.default.post(name: .botBlink, object: nil)
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1.08))
        SoundEngine.shared.play("hover")
    }

    private func botHoverOut() {
        setPetting(false)
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1))
    }

    /// Quieto 0,8 s encima → caricia; si el mouse se va más de 18 pt, se corta.
    private func updatePetting(mouse m: CGPoint) {
        let now = CACurrentMediaTime()
        let d = hypot(m.x - botHoverStartPos.x, m.y - botHoverStartPos.y)
        if petting {
            if d > 18 {
                setPetting(false)
                botHoverStartPos = m
                botHoverLastMove = now
            }
        } else if d > 4 {
            botHoverStartPos = m
            botHoverLastMove = now
        } else if now - botHoverLastMove > 0.8 {
            setPetting(true)
        }
    }

    private func setPetting(_ on: Bool) {
        guard on != petting else { return }
        petting = on
        NotificationCenter.default.post(name: .botPet, object: on)
        if on {
            let now = CACurrentMediaTime()
            if now - lastPetSound > 5 {
                lastPetSound = now
                SoundEngine.shared.play("love")
            }
        }
    }

    private func scheduleHover(after delay: TimeInterval, action: @escaping () -> Void) {
        hoverTimer?.cancel()
        let item = DispatchWorkItem(block: action)
        hoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Mode transitions

    private func modeLevel(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }

    func setMode(_ mode: IslandMode) {
        let prev = state.mode
        guard mode != prev else { return }
        let shrinking = modeLevel(mode) < modeLevel(prev)
        let anim: Animation = shrinking
            ? .timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
            : .spring(response: 0.5, dampingFraction: 0.72)
        withAnimation(anim) { state.mode = mode }
        if mode == .expanded { SoundEngine.shared.play("open") }
        if prev == .expanded { SoundEngine.shared.play("close"); state.isPinned = false }
    }

    func expand(to view: IslandView) {
        state.view = view
        if state.mode == .expanded {
            // Already expanded — just switch view
        } else {
            setMode(.expanded)
        }
        state.lastActivity = .now
        // ORBEX: abrir por otro camino (menú, atajo, alerta, arrastre) deja al FSM en sintonía.
        fsm.syncOpened(mouseInside: wasInIsland)
    }

    func collapse() {
        state.isPinned = false
        finishedPinTimer?.cancel()
        // ORBEX: el FSM pasa a compacta YA (antes quedaba en "home" hasta 15 s y el clic no abría).
        fsm.collapseToPetit()
        setMode(.compact)
        window?.resignKey()
    }

    /// Rectángulo del notch en pantalla (origen y destino del morph al reloj flotante).
    /// Sale de la misma medida en vivo que ubica el panel (centro real + ajuste fino).
    func notchRectOnScreen() -> CGRect {
        if screenTopY == 0 { applyPlacement() }
        guard screenTopY != 0 else { return .zero }
        return CGRect(x: notchCenterX - notchW / 2, y: screenTopY - notchH, width: notchW, height: notchH)
    }

    // MARK: - Teclado (ORBEX)
    // Sin monitores globales de teclado (pedían Accesibilidad): los atajos son Carbon (`HotKeys`)
    // y Esc se escucha con un monitor LOCAL, que solo recibe teclas cuando el panel es key.

    private func startKeyMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            let handled: Bool = MainActor.assumeIsolated {
                guard let self, event.window === self.window,
                      self.state.mode == .expanded, !self.state.isPinned else { return false }
                self.collapse()
                return true
            }
            return handled ? nil : event
        }

        // Atajo configurable de la base ("Mostrar la isla con un atajo"): ahora con Carbon.
        state.$hotkeyEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.registerCustomHotKey() }
            }
            .store(in: &subscriptions)

        // Hook server expand requests (alerts only)
        NotificationCenter.default.addObserver(forName: .hookExpand, object: nil, queue: .main) { [weak self] note in
            guard let view = note.object as? IslandView else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                // Con el reloj flotante afuera, el puente lo guarda en el notch antes de abrir.
                if ClockController.shared.isVisible {
                    OrbexBridge.shared.openIsland(view)
                } else {
                    self.expand(to: view)
                }
            }
        }

        // Hook server compact reveal (non-alert work events: session start, tool use, etc.)
        NotificationCenter.default.addObserver(forName: .hookReveal, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !ClockController.shared.isVisible else { return }
                self.fsm.reveal()
            }
        }

        // Collapse requests from views (OK button, etc.)
        NotificationCenter.default.addObserver(forName: .islandCollapse, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapse() }
        }

        // .botDizzy — lo manda BotEngine.tickle() al tercer clic rápido; show confused view + recover after 3.3s
        NotificationCenter.default.addObserver(forName: .botDizzy, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDizzy() }
        }

        // Window attach drag.
        // Uses MainActor.assumeIsolated (synchronous) to avoid race with pollFrame().
        // Global mouseUp is the reliable fallback when cursor is outside our panel frame.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard self.wasInIsland else { return }
                self.pendingIslandClick = true
                self.hoverTimer?.cancel()
                self.setPetting(false)
                self.botHovering = false
                // Drag only starts when clicking directly on the bot head
                guard self.isBotHit(event.locationInWindow) else { return }
                self.attachDragStart = NSEvent.mouseLocation
                // Cosquillas solo en la vista abierta (tres clics rápidos = mareo)
                guard self.state.mode == .expanded else { return }
                NotificationCenter.default.post(name: .triggerSlap, object: nil)
            }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard let start = self.attachDragStart, !self.inAttachDrag else { return }
                let m = NSEvent.mouseLocation
                guard hypot(m.x - start.x, m.y - start.y) > 3 else { return }
                self.inAttachDrag = true
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
                self.showDragGhost()
            }
            return event
        }

        // mouseUp — local (cursor still in panel) + global (cursor moved outside panel frame)
        let finishDrag: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self, self.inAttachDrag else { return }
                let mouse = NSEvent.mouseLocation
                self.inAttachDrag = false
                self.attachDragStart = nil
                self.state.stateOverride = nil
                self.hideDragGhost()
                #if !APPSTORE
                if let ctx = self.windowContextAtPoint(mouse) {
                    self.state.promptContext = ctx
                    SoundEngine.shared.play("approve")
                    NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                    self.expand(to: .prompt)
                }
                #endif
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                let hadPendingClick = self.pendingIslandClick
                let wasDragging     = self.inAttachDrag
                self.pendingIslandClick = false
                if wasDragging {
                    finishDrag()
                } else {
                    self.attachDragStart = nil
                    if hadPendingClick && self.state.mode != .expanded {
                        if self.fsm.state == .hidden {
                            // Sin asomarse al pasar el mouse: el clic en el notch abre directo.
                            self.expand(to: self.defaultView())
                        } else {
                            self.fsm.click()   // FSM petit→home; onTransition calls expand(to:)
                        }
                    }
                }
            }
            return event
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            finishDrag()
        }


        // Track last external app for window context capture
        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != ourBundle else { return }
            MainActor.assumeIsolated { self?.state.lastExternalApp = app }
        }
    }

    /// Registra (o quita) el atajo configurable de la base como atajo Carbon: sin Accesibilidad.
    func registerCustomHotKey() {
        let center = HotKeyCenter.shared
        guard state.hotkeyEnabled else { center.unregister(id: "custom"); return }
        let flags = NSEvent.ModifierFlags(rawValue: state.hotkeyFlags)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        guard mods != 0 else { center.unregister(id: "custom"); return }
        center.register(id: "custom", keyCode: UInt32(state.hotkeyCode), modifiers: mods) {
            OrbexBridge.shared.openIsland()
        }
    }

    // MARK: - Drag ghost window (ORBEX follows cursor during drag)

    private func showDragGhost() {
        guard dragGhostPanel == nil else { return }
        // Same size as compact bot: diameter=20 → canvasSize≈33, scale 2× for grab comfort
        let canvasSize: CGFloat = 40 / 0.6      // ~67
        dragGhostSize = canvasSize

        let mouse = NSEvent.mouseLocation
        let s = dragGhostSize
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)

        let panel = NSPanel(
            contentRect: NSRect(x: ghostCurrentOrigin.x, y: ghostCurrentOrigin.y, width: s, height: s),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let hosting = NSHostingView(
            rootView: GhostBotView(canvasSize: canvasSize)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: s, height: s)
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderFront(nil)
        dragGhostPanel = panel
        AppState.shared.isDraggingBot = true

        // Fade + scale-in handled by GhostBotView SwiftUI animation;
        // also fade in the window itself for extra smoothness
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hideDragGhost() {
        dragGhostPanel?.close()
        dragGhostPanel = nil
        highlightPanel?.close()
        highlightPanel = nil
        highlightWindowPid = 0
        AppState.shared.isDraggingBot = false
    }

    private func updateDragGhost() {
        guard let panel = dragGhostPanel else { return }
        let s = dragGhostSize
        let mouse = NSEvent.mouseLocation
        // Direct follow — bot is "held", no trailing lag
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)
        panel.setFrameOrigin(ghostCurrentOrigin)
    }

    // MARK: - Window highlight overlay (white border on target window during drag)

    private func updateWindowHighlight() {
        let mouse = NSEvent.mouseLocation
        guard let (appKitBounds, pid) = windowBoundsAtScreenPoint(mouse) else {
            // Fade out + close if no window under cursor
            if let old = highlightPanel {
                let captured = old
                highlightPanel = nil
                highlightWindowPid = 0
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.12
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    captured.animator().alphaValue = 0
                }, completionHandler: { captured.close() })
            }
            return
        }

        if pid == highlightWindowPid, let existing = highlightPanel {
            // Same window — just track position (windows rarely move, instant is fine)
            existing.setFrame(appKitBounds, display: false)
        } else {
            // New window — close old immediately, fade-in new
            highlightPanel?.close()
            highlightPanel = nil
            highlightWindowPid = pid

            let panel = NSPanel(
                contentRect: appKitBounds,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = true

            let hosting = NSHostingView(rootView:
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.75), lineWidth: 3)
                    .shadow(color: Color.white.opacity(0.5), radius: 16)
                    .padding(2)
                    .ignoresSafeArea()
            )
            hosting.frame = CGRect(origin: .zero, size: appKitBounds.size)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            panel.alphaValue = 0
            panel.orderFront(nil)
            highlightPanel = panel

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    private func windowBoundsAtScreenPoint(_ screenPoint: NSPoint) -> (CGRect, pid_t)? {
        guard let screen = window?.screen ?? NSScreen.main else { return nil }
        let screenMaxY = screen.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        for info in list {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }
            // CG → AppKit: flip Y
            return (CGRect(x: x, y: screenMaxY - y - h, width: w, height: h), pid)
        }
        return nil
    }

    // MARK: - Window context at screen point (for drag-attach)

    private func windowContextAtPoint(_ screenPoint: NSPoint) -> PromptContext? {
        let screen = window?.screen ?? NSScreen.main
        // CGWindowList uses top-left origin; NSEvent.mouseLocation uses bottom-left
        let screenMaxY = screen?.frame.maxY ?? NSScreen.main!.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""

        for info in windowList {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }

            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }

            return WindowContextCapture.captureActive(from: app)
        }
        return nil
    }

    // MARK: - Coordinate conversion: window (AppKit, y-up) → island coords (y-down, 0,0 = island top-left)

    func windowToIsland(_ loc: CGPoint) -> CGPoint {
        let panelH = window?.frame.height ?? 320
        let panelW = window?.frame.width  ?? 720
        let islandLeft = (panelW - IslandConst.expandedWidth) / 2
        // Island is glued to panel top; its bottom in AppKit = panelH - 176
        return CGPoint(
            x: loc.x - islandLeft,
            y: panelH - loc.y                // AppKit y is from bottom; island y from top
        )
    }

    // MARK: - Helpers

    func defaultView() -> IslandView {
        state.tasks.isEmpty ? .empty : .overview
    }

    func baseMode() -> IslandMode {
        guard state.isPresent else { return .hidden }
        return state.tasks.isEmpty ? .hidden : .compact
    }

    // MARK: - Activity reset (call on any user interaction in island)

    func resetActivity() {
        state.lastActivity = .now
    }

    // MARK: - Finished task pin (5.2s)

    func pinForFinished(taskId: String) {
        state.isPinned = true
        finishedPinTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.state.removeTask(id: taskId)
                self.state.isPinned = false
                self.collapse()
            }
        }
        finishedPinTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2, execute: item)
    }

    // MARK: - Dizzy recovery (BotEngine.tickle → .botDizzy)

    private func handleDizzy() {
        let prevView = state.view
        state.stateOverride = .dizzy
        expand(to: .confused)
        confusedRecoveryTimer?.cancel()
        let recovery = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.state.stateOverride = nil
                if self.state.view == .confused {
                    let fallback = self.state.tasks.isEmpty ? IslandView.empty : .overview
                    self.state.view = (prevView == .confused) ? fallback : prevView
                }
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
            }
        }
        confusedRecoveryTimer = recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3, execute: recovery)
    }

    // MARK: - Bot hit test (cosquillas, caricia, arrastre)

    private func isBotHit(_ windowPoint: CGPoint) -> Bool {
        let s = AppState.shared
        let panelH = window?.frame.height ?? 320
        let panelW = window?.frame.width  ?? 720
        let (islandW, fixedH) = islandSize(mode: s.mode, view: s.view,
                                            progress: s.uploadProgress, nw: notchW, nh: notchH)
        // Chat view resizes dynamically — must match IslandContainer.chatPromptHeight
        let islandH: CGFloat
        if s.mode == .expanded && s.view == .prompt {
            let base: CGFloat = 240
            let perMsg: CGFloat = 40
            islandH = min(300, base + CGFloat(s.chatMessageCount) * perMsg)
        } else {
            islandH = fixedH
        }
        let islandMinX = (panelW - islandW) / 2
        let (cx, cy, diameter, _) = botPosition(mode: s.mode, view: s.view,
                                                  islandW: islandW, islandH: islandH,
                                                  uploadProgress: s.uploadProgress)
        let radius = (diameter / 0.6) / 2
        // botPosition cy is from island TOP; panel AppKit coords have y=0 at bottom
        // island top in AppKit coords = panelH (island glued to top of panel/screen)
        let botX = islandMinX + cx
        let botY = panelH - cy
        let dx = windowPoint.x - botX
        let dy = windowPoint.y - botY
        return dx*dx + dy*dy <= radius * radius
    }

    // ORBEX: la medida del notch sale de `NotchDetector` (ver `applyPlacement()`).

    nonisolated func cleanup() {
        // Called explicitly before release if needed
    }
}

// MARK: - IslandPanel

final class IslandPanel: NSPanel {
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }

    /// Allow panel to sit in the menu bar / notch area — don't let macOS push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    func currentIslandFrame(nw: CGFloat, nh: CGFloat) -> CGRect {
        let s = AppState.shared
        let (w, fixedH) = islandSize(mode: s.mode, view: s.view,
                                      progress: s.uploadProgress, nw: nw, nh: nh)
        let h: CGFloat
        if s.mode == .expanded && s.view == .prompt {
            let base: CGFloat = 240
            let perMsg: CGFloat = 40
            h = min(300, base + CGFloat(s.chatMessageCount) * perMsg)
        } else {
            h = fixedH
        }
        return CGRect(x: (frame.width - w) / 2, y: frame.height - h, width: w, height: h)
    }
}

// MARK: - Ghost bot view (animated scale-in on appear)

struct GhostBotView: View {
    let canvasSize: CGFloat
    @State private var scale: CGFloat = 0.35

    var body: some View {
        // Globo que patalea mientras se lo arrastra.
        BotCanvasView(state: AppState.shared, carried: true)
            .frame(width: canvasSize, height: canvasSize)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let triggerEmote     = Notification.Name("orbex.island.triggerEmote")
    static let triggerSlap      = Notification.Name("orbex.island.triggerSlap")
    /// Caricia: `object` = `Bool` (empieza / termina).
    static let botPet           = Notification.Name("orbex.island.botPet")
    static let botDizzy         = Notification.Name("orbex.island.botDizzy")
    static let botGreet         = Notification.Name("orbex.island.botGreet")
    static let botBlink         = Notification.Name("orbex.island.botBlink")
    static let botSetTgEs       = Notification.Name("orbex.island.botSetTgEs")
    static let botGulp          = Notification.Name("orbex.island.botGulp")
    static let botMorphTo       = Notification.Name("orbex.island.botMorphTo")
    static let islandAction     = Notification.Name("orbex.island.islandAction")
    static let islandCollapse   = Notification.Name("orbex.island.islandCollapse")
    static let openFullSettings = Notification.Name("orbex.island.openFullSettings")
    static let hookReveal       = Notification.Name("orbex.island.hookReveal")
    static let hookExpand       = Notification.Name("orbex.island.hookExpand")
    // Greeting ↔ IslandWindowController
    static let greetComplete    = Notification.Name("orbex.island.greetComplete")
    static let greetingHover    = Notification.Name("orbex.island.greetingHover")
    static let greetingInterrupt = Notification.Name("orbex.island.greetingInterrupt")
}

// MARK: - islandSize (takes real notch dimensions)

func islandSize(mode: IslandMode, view: IslandView,
                progress: Double = 0,
                nw: CGFloat = IslandConst.notchWidth,
                nh: CGFloat = IslandConst.notchHeight) -> (CGFloat, CGFloat) {
    switch mode {
    case .hidden:   return (nw, nh)
    case .compact:  return (nw + 160, nh)
    case .expanded:
        let layout = IslandConst.viewLayouts[view]!
        return (IslandConst.expandedWidth, layout.height)
    }
}

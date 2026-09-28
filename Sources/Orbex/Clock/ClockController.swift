import AppKit
import SwiftUI
import OrbexCore

/// Ventana del reloj flotante: sin bordes, siempre visible (mismo nivel que la isla), arrastrable,
/// se pega a los bordes, click-through opcional (⌥ para interactuar). Informe §6.3.
final class ClockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClockController: ObservableObject {
    static let shared = ClockController()

    @Published var settings: ClockSettings {
        didSet {
            guard settings != oldValue else { return }
            if let data = settings.encoded() { UserDefaults.standard.set(data, forKey: ClockSettings.storageKey) }
            applySettings(resize: settings.size != oldValue.size || settings.face != oldValue.face)
        }
    }
    private(set) var isVisible = false

    private var panel: ClockPanel?
    private var tickTimer: Timer?
    private var modifierTimer: Timer?
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?

    private init() {
        settings = ClockSettings.decode(UserDefaults.standard.data(forKey: ClockSettings.storageKey))
    }

    // MARK: - Mostrar / ocultar (morph desde y hacia el notch)

    func show(from notchRect: CGRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        isVisible = true
        let target = targetFrame()
        panel.setFrame(notchRect == .zero ? target : notchRect, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.25, 0.35, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = CGFloat(settings.clampedOpacity)
        }
        applySettings(resize: false)
        startTimers()
    }

    func hide(to notchRect: CGRect) {
        guard let panel, isVisible else { return }
        isVisible = false
        stopTimers()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if notchRect != .zero { panel.animator().setFrame(notchRect, display: true) }
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if !ClockController.shared.isVisible { panel.orderOut(nil) }
            }
        })
    }

    // MARK: - Ventana

    private func makePanel() -> ClockPanel {
        let panel = ClockPanel(contentRect: NSRect(x: 0, y: 0, width: CGFloat(settings.windowSize.width),
                                                   height: CGFloat(settings.windowSize.height)),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let root = ClockRootView(controller: self)
            .environment(\.hostWindow, HostWindowRef(panel))
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    /// Posición guardada o, la primera vez, arriba a la derecha debajo de la barra de menú.
    private func targetFrame() -> NSRect {
        let w = CGFloat(settings.windowSize.width), h = CGFloat(settings.windowSize.height)
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: visible.maxX - w - 24, y: visible.maxY - h - 24)
        if let x = settings.originX, let y = settings.originY {
            origin = NSPoint(x: x, y: y)
        }
        var frame = NSRect(origin: origin, size: NSSize(width: w, height: h))
        // Que no quede fuera de pantalla (p. ej. si se desconectó un monitor).
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            frame.origin = NSPoint(x: visible.maxX - w - 24, y: visible.maxY - h - 24)
        }
        return frame
    }

    private func applySettings(resize: Bool) {
        guard let panel, isVisible else { return }
        panel.alphaValue = CGFloat(settings.clampedOpacity)
        panel.ignoresMouseEvents = settings.clickThrough && !NSEvent.modifierFlags.contains(.option)
        if resize {
            let w = CGFloat(settings.windowSize.width), h = CGFloat(settings.windowSize.height)
            var f = panel.frame
            f.origin.y += f.height - h
            f.size = NSSize(width: w, height: h)
            panel.setFrame(f, display: true, animate: true)
            savePosition()
        }
    }

    // MARK: - Arrastrar y pegar a los bordes

    func dragChanged() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStartMouse == nil {
            dragStartMouse = mouse
            dragStartOrigin = panel.frame.origin
        }
        guard let m0 = dragStartMouse, let o0 = dragStartOrigin else { return }
        panel.setFrameOrigin(NSPoint(x: o0.x + mouse.x - m0.x, y: o0.y + mouse.y - m0.y))
    }

    func dragEnded() {
        dragStartMouse = nil
        dragStartOrigin = nil
        guard let panel else { return }
        if settings.snapToEdges, let screen = panel.screen ?? NSScreen.main {
            let v = screen.visibleFrame
            let f = panel.frame
            let snapped = ClockMath.snap(frame: ClockRect(x: Double(f.minX), y: Double(f.minY), w: Double(f.width), h: Double(f.height)),
                                         to: ClockRect(x: Double(v.minX), y: Double(v.minY), w: Double(v.width), h: Double(v.height)),
                                         threshold: 28)
            let target = NSRect(x: snapped.x, y: snapped.y, width: snapped.w, height: snapped.h)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().setFrame(target, display: true)
            }
        }
        savePosition()
    }

    private func savePosition() {
        guard let panel else { return }
        let x = Double(panel.frame.minX), y = Double(panel.frame.minY)
        if settings.originX != x || settings.originY != y {
            settings.originX = x
            settings.originY = y
        }
    }

    // MARK: - Timers (tic-tac y ⌥ con click-through)

    private func startTimers() {
        stopTimers()
        let tick = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let c = ClockController.shared
                if c.isVisible && c.settings.tickSound { OrbexBus.play(.tick) }
            }
        }
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick

        let mods = Timer(timeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let c = ClockController.shared
                guard let panel = c.panel, c.isVisible, c.settings.clickThrough else { return }
                let ignore = !NSEvent.modifierFlags.contains(.option)
                if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
            }
        }
        RunLoop.main.add(mods, forMode: .common)
        modifierTimer = mods
    }

    private func stopTimers() {
        tickTimer?.invalidate()
        tickTimer = nil
        modifierTimer?.invalidate()
        modifierTimer = nil
    }
}

/// Contenido del reloj: la esfera con ORBEX, anillo del timer en curso, gestos y menú.
struct ClockRootView: View {
    @ObservedObject var controller: ClockController
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var timers = TimersStore.shared

    var body: some View {
        let s = controller.settings
        ClockFaceView(face: s.face, showSeconds: s.effectiveShowSeconds, ringProgress: ringProgress,
                      compact: s.isCompact)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.orbexTheme, model.themeStyle)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in controller.dragChanged() }
                    .onEnded { _ in controller.dragEnded() }
            )
            .onTapGesture(count: 2) { OrbexBus.perform("clock") }
            .onTapGesture { CharacterBrain.shared.tap() }
            .contextMenu {
                Picker("Esfera", selection: $controller.settings.face) {
                    ForEach(ClockFace.allCases) { f in Text(f.label).tag(f) }
                }
                Picker("Tamaño", selection: $controller.settings.size) {
                    ForEach(ClockSize.allCases) { z in Text(z.label).tag(z) }
                }
                Toggle("Click-through (⌥ para tocarlo)", isOn: $controller.settings.clickThrough)
                Toggle("Tic-tac", isOn: $controller.settings.tickSound)
                Divider()
                Button("Volver al notch") { OrbexBus.perform("clock") }
            }
    }

    /// Progreso del primer timer corriendo (anillo exterior), o `nil`.
    private var ringProgress: Double? {
        let now = Date()
        guard let t = timers.timers.first(where: { $0.isRunning }) else { return nil }
        return t.progress(at: now)
    }
}

import AppKit
import SwiftUI
import Combine
import OrbexCore

/// Ventana del modo inteligente: sin bordes, por encima de todo y en todos los escritorios.
/// Puede ser key (para el campo de texto y Esc) sin activar la app (`.nonactivatingPanel`).
final class SmartModePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// El panel se pega arriba de todo (sobre el notch): que macOS no lo baje.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func cancelOperation(_ sender: Any?) {
        MainActor.assumeIsolated { SmartModeController.shared.hide() }
    }
}

/// Niveles de voz en vivo. NO es observable a propósito: el `Canvas` de la cara los lee en cada cuadro
/// y así 20 Hz de niveles no re-arman toda la vista.
final class SmartLevels {
    /// Tu voz (0…1), suavizada.
    var input: CGFloat = 0
    /// La voz de Orbi (0…1), suavizada.
    var output: CGFloat = 0
    var speaking = false
    var listening = false
    fileprivate var rawInput: CGFloat = 0
    fileprivate var rawOutput: CGFloat = 0

    /// Suaviza hacia el último valor recibido (ataque rápido, caída lenta). Se llama por cuadro.
    func step(dt: Double) {
        func follow(_ v: CGFloat, _ target: CGFloat) -> CGFloat {
            let k = CGFloat(min(1, dt * (target > v ? 22 : 7)))
            return v + (target - v) * k
        }
        input = follow(input, rawInput)
        output = follow(output, speaking ? rawOutput : 0)
    }
}

/// "Orbi, activar modo inteligente": panel grande con la cara de Orbi (escucha / piensa / habla),
/// la conversación en vivo, lo que recuerda y acciones rápidas. Idea tomada de fullstack-agent
/// ("un agente con memoria, voz y cara"); diseño y código propios de ORBEX.
///
/// Se despliega desde el notch con un morph de resorte: la ventana ya tiene su tamaño final y lo que
/// se anima es la forma de vidrio (del rectángulo del notch al panel), así no se re-maqueta en cada cuadro.
/// La cara solo se anima mientras el panel está visible (casi 0 % de CPU cerrado).
@MainActor
final class SmartModeController: ObservableObject {
    static let shared = SmartModeController()

    /// Ruta del texto escrito en el panel. Si nadie la pone, el texto va a `AssistantStore`
    /// (comandos de ORBEX primero, después Claude) y la respuesta se ve igual en el panel.
    /// La conversación hablada (W2) puede engancharse acá para que lo escrito también se conteste en voz.
    var textHandler: ((String) -> Void)?

    static let backendNotification = Notification.Name("orbex.voice.backend")
    static let muteNotification = Notification.Name("orbex.voice.mute")
    private static let mutedKey = "orbex.smart.orbiMuted"

    @Published private(set) var isActive = false
    /// Forma desplegada (true) o encogida en el notch (false). La anima la vista con resorte.
    @Published private(set) var expanded = false
    /// Rectángulo del notch en coordenadas del panel (y hacia abajo), origen del morph.
    @Published private(set) var notchLocal = CGRect(x: 260, y: 0, width: 200, height: 32)
    /// Alto de la franja del notch/barra de menú arriba del contenido.
    @Published private(set) var topInset: CGFloat = 32
    /// Nombre del motor de voz de Orbi ("Kokoro · en tu Mac", "Cartesia", "Voz de macOS").
    /// Lo puede fijar la capa de voz, o avisarlo con `orbex.voice.backend` (String).
    @Published var voiceBackendLabel = "Voz de macOS"
    /// Silenciar la voz de Orbi (sigue contestando por escrito). Se avisa con `orbex.voice.mute` (Bool).
    @Published var orbiMuted: Bool {
        didSet {
            guard orbiMuted != oldValue else { return }
            UserDefaults.standard.set(orbiMuted, forKey: Self.mutedKey)
            NotificationCenter.default.post(name: Self.muteNotification, object: orbiMuted)
            if orbiMuted { OrbiVoice.shared.stop() }
        }
    }
    /// Desde qué mensaje del asistente mostrar (lo anterior a abrir el panel no se repite).
    @Published private(set) var assistantBaseCount = 0
    /// Pide foco al campo de texto (sube en cada pedido).
    @Published private(set) var focusTick = 0
    @Published var draft = ""

    let levels = SmartLevels()

    static let panelSize = CGSize(width: 720, height: 520)

    private var panel: SmartModePanel?
    private var escMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var hideWork: DispatchWorkItem?

    private init() {
        orbiMuted = UserDefaults.standard.bool(forKey: Self.mutedKey)
        observeVoice()
    }

    // MARK: - API

    func show() {
        hideWork?.cancel()
        hideWork = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !isActive {
            assistantBaseCount = AssistantStore.shared.messages.count
        }
        placePanel(panel)
        isActive = true
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        startEscMonitor()
        OrbexBus.play(.open)
        // Un cuadro encogido en el notch y después el resorte hasta el tamaño final.
        expanded = false
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard SmartModeController.shared.isActive else { return }
                SmartModeController.shared.expanded = true
                SmartModeController.shared.focusTick += 1
            }
        }
    }

    func hide() {
        guard isActive, let panel else { return }
        isActive = false
        expanded = false
        stopEscMonitor()
        panel.ignoresMouseEvents = true
        OrbexBus.play(.close)
        let reduce = AppModel.shared.effectiveReduceMotion
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                guard !SmartModeController.shared.isActive else { return }
                panel.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 0.2 : 0.5), execute: work)
    }

    func toggle() {
        isActive ? hide() : show()
    }

    // MARK: - Acciones del panel

    /// Micrófono grande: hablar sin decir el nombre (o terminar el pedido si ya está escuchando).
    func talk() {
        VoiceController.shared.talk()
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        if let textHandler {
            textHandler(text)
        } else {
            AssistantStore.shared.send(text)
        }
    }

    /// Pone un comienzo de frase en el campo ("abrí ") y le da foco.
    func prefill(_ text: String) {
        draft = text
        focusTick += 1
    }

    func run(_ command: OrbexCommand) {
        Task { @MainActor in
            let result = await CommandExecutor.shared.execute(command)
            if result.needsConfirmation {
                // Regla 12: lo que pide confirmación se decide con un clic en el chat de la isla.
                AssistantStore.shared.send(Self.phrase(for: command))
            } else if !result.message.isEmpty {
                OrbexBus.toast(result.message)
            }
        }
    }

    private static func phrase(for command: OrbexCommand) -> String {
        switch command {
        case .openApp(let name): return "abrí \(name)"
        case .showClock: return "mostrá el reloj"
        case .stopwatch: return "cronómetro"
        default: return "poné un timer"
        }
    }

    func forget(_ id: UUID) {
        MemoryStore.shared.delete(id: id)
    }

    // MARK: - Ventana

    private func makePanel() -> SmartModePanel {
        let size = Self.panelSize
        let panel = SmartModePanel(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // la sombra la dibuja la forma (sigue al morph)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isMovable = false

        let root = SmartModeRootView(controller: self)
            .environment(\.hostWindow, HostWindowRef(panel))
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    /// Centrado arriba, pegado al borde superior de la pantalla del notch (la forma "cuelga" del notch).
    private func placePanel(_ panel: SmartModePanel) {
        let notch = OrbexBridge.shared.island?.notchRectOnScreen() ?? .zero
        let screen = NSScreen.screens.first { notch != .zero && $0.frame.intersects(notch) }
            ?? NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = screen?.visibleFrame ?? frame
        let size = CGSize(width: min(Self.panelSize.width, frame.width - 24),
                          height: min(Self.panelSize.height, visible.height))
        let centerX = notch != .zero ? notch.midX : frame.midX
        let x = min(max(frame.minX + 12, centerX - size.width / 2), frame.maxX - 12 - size.width)
        let target = NSRect(x: x, y: frame.maxY - size.height, width: size.width, height: size.height)
        panel.setFrame(target, display: false)

        // Franja superior: el notch medido en vivo o, sin notch, la barra de menú.
        let safeTop = screen?.safeAreaInsets.top ?? 0
        let menuBar = frame.maxY - visible.maxY
        topInset = max(safeTop, menuBar, notch.height, 24)

        if notch != .zero {
            notchLocal = CGRect(x: notch.minX - target.minX, y: target.maxY - notch.maxY,
                                width: notch.width, height: notch.height)
        } else {
            notchLocal = CGRect(x: size.width / 2 - 100, y: 0, width: 200, height: topInset)
        }
    }

    private func startEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                let c = SmartModeController.shared
                guard c.isActive, event.window === c.panel else { return false }
                c.hide()
                return true
            }
            return handled ? nil : event
        }
    }

    private func stopEscMonitor() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }

    // MARK: - Señales de voz

    private func observeVoice() {
        let center = NotificationCenter.default
        func on(_ name: String, _ block: @escaping @MainActor (Any?) -> Void) {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { note in
                let object = note.object
                MainActor.assumeIsolated { block(object) }
            })
        }
        on("orbex.voice.level") { obj in
            SmartModeController.shared.levels.rawInput = Self.cgFloat(obj)
        }
        on("orbex.voice.outLevel") { obj in
            SmartModeController.shared.levels.rawOutput = Self.cgFloat(obj)
        }
        on("orbex.voice.speaking") { obj in
            let speaking = (obj as? Bool) ?? false
            let c = SmartModeController.shared
            c.levels.speaking = speaking
            if speaking && c.orbiMuted { OrbiVoice.shared.stop() }
        }
        on("orbex.voice.listening") { obj in
            SmartModeController.shared.levels.listening = (obj as? Bool) ?? false
            if (obj as? Bool) != true { SmartModeController.shared.levels.rawInput = 0 }
        }
        on(Self.backendNotification.rawValue) { obj in
            if let label = obj as? String, !label.isEmpty {
                SmartModeController.shared.voiceBackendLabel = label
            }
        }
    }

    private static func cgFloat(_ obj: Any?) -> CGFloat {
        if let v = obj as? CGFloat { return min(1, max(0, v)) }
        if let v = obj as? Double { return CGFloat(min(1, max(0, v))) }
        if let v = obj as? Float { return CGFloat(min(1, max(0, v))) }
        return 0
    }
}

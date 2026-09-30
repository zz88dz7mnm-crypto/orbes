import AppKit
import Carbon
import Combine
import OrbexCore

/// Hablarle a ORBEX: "Orbex, abrí Spotify" → ORBEX lo hace (sin responder hablando).
///
/// Formas de activarlo (Configuración › Voz):
/// - **Siempre atento** (apagado por defecto): el micrófono queda abierto esperando el nombre
///   ("Orbex", "Orbi", "Orbes"… y los nombres extra). Se pausa con la pantalla bloqueada, al dormir la Mac y,
///   si el usuario lo elige, en bajo consumo.
/// - **⌃⌥Espacio** (push-to-talk): tocás, hablás; se corta solo al callarte (o tocás de nuevo).
/// - **Clic largo** sobre la isla (opcional).
///
/// Mientras escucha: `AppState.stateOverride = .listening` (magenta, gesto de BotEngine), la isla se asoma,
/// y se publican `orbex.voice.listening` (Bool) y `orbex.voice.level` (CGFloat 0…1, ~20 Hz).
/// Lo que va entendiendo se ve en la vista `note` de la isla.
///
/// Lo que se oye es DATO: solo se usa como el pedido del usuario. Los comandos pasan por
/// `CommandExecutor` (niveles de autonomía); lo que pide confirmación va al chat de la isla y se
/// hace recién con un clic (regla 12). Nada del audio se graba ni se guarda.
@MainActor
final class VoiceController: ObservableObject {
    enum Phase: Equatable {
        /// Micrófono cerrado.
        case off
        /// Siempre atento: esperando el nombre.
        case waitingWakeWord
        /// Escuchando el pedido.
        case listeningCommand
        /// Haciendo lo que se pidió.
        case working

        var label: String {
            switch self {
            case .off: return "Sin escuchar"
            case .waitingWakeWord: return "Atento a su nombre"
            case .listeningCommand: return "Escuchando tu pedido…"
            case .working: return "Haciéndolo…"
            }
        }
    }

    static let shared = VoiceController()

    /// `object`: `Bool` (empezó / terminó de escuchar un pedido).
    static let listeningNotification = Notification.Name("orbex.voice.listening")
    /// `object`: `CGFloat` 0…1, nivel de la voz mientras escucha un pedido (~20 Hz como máximo).
    static let levelNotification = Notification.Name("orbex.voice.level")

    private static let hotKeyID = "voice"
    /// Silencio que cierra una frase sin nombre (siempre atento): se empieza de cero.
    private static let idleResetAfter: TimeInterval = 1.6
    private static let longPressDelay: TimeInterval = 0.6
    private static let micTestMaxDuration: TimeInterval = 45

    // MARK: - Estado publicado (Configuración › Voz)

    @Published private(set) var phase: Phase = .off
    @Published private(set) var level: CGFloat = 0
    /// Lo que va entendiendo del pedido actual.
    @Published private(set) var liveText = ""
    /// Último pedido entendido (para mostrar en Configuración).
    @Published private(set) var lastUnderstood: String?
    /// Algo que impide escuchar (permiso, modelo, micrófono). `nil` = todo bien.
    @Published private(set) var problem: String?
    @Published private(set) var micPermission: VoicePermission = VoicePermissions.microphone
    @Published private(set) var speechPermission: VoicePermission = VoicePermissions.speech
    /// Atajo registrado ("⌃⌥Espacio", o "⌃⌥V" si macOS no dejó el primero). `nil` = sin atajo.
    @Published private(set) var hotKeyLabel: String?
    /// "Español (Argentina) · en tu Mac".
    @Published private(set) var recognizerLabel: String?
    @Published private(set) var pausedForPower = false
    @Published private(set) var pausedForSystem = false
    // Prueba de micrófono
    @Published private(set) var isTesting = false
    @Published private(set) var testText = ""
    @Published private(set) var testHeardName = false

    var permissionsGranted: Bool { micPermission == .granted && speechPermission == .granted }

    // MARK: - Internos

    private let listener = VoiceListener()
    private var matcher = WakeWordMatcher()
    private var matcherNames: [String] = []
    private var activeConfig: VoiceListener.Config?
    private var endpointer: UtteranceEndpointer?
    private var endTimer: Timer?
    private var started = false
    private var requestingPermissions = false

    // Pedido en curso
    private var commandFromWake = false
    private var commandGeneration = 0
    private var commandPrefix = ""
    private var commandText = ""
    private var noteVisible = false
    private var lastNoteRefresh = Date.distantPast

    private var idleResetWork: DispatchWorkItem?
    private var testStopWork: DispatchWorkItem?
    private var longPressWork: DispatchWorkItem?
    private var longPressStart: CGPoint?
    private var isScreenLocked = false
    private var isAsleep = false

    private var cancellables: Set<AnyCancellable> = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var mouseMonitor: Any?

    private init() {}

    // MARK: - Arranque (lo llama AppDelegate)

    /// Deja la voz lista según Configuración. No pide permisos: si falta alguno, espera a que el usuario
    /// use la voz por primera vez.
    func start() {
        guard !started else { apply(userInitiated: false); return }
        started = true
        listener.onText = { [weak self] h in self?.heard(h) }
        listener.onLevel = { [weak self] value in self?.levelChanged(value) }
        listener.onStopped = { [weak self] message in self?.listenerStopped(message) }
        observeSystem()
        installLongPressMonitor()
        apply(userInitiated: false)
    }

    /// Apaga todo: micrófono, atajo, monitores (al salir de la app).
    func stop() {
        cancelCommand()
        stopMicTest()
        listener.stop()
        activeConfig = nil
        phase = .off
        unregisterHotKey()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        cancellables.removeAll()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        idleResetWork?.cancel()
        longPressWork?.cancel()
        started = false
    }

    /// Configuración › Voz cambió algo (lo llama la vista). Cuenta como uso explícito: si hace falta,
    /// acá se piden los permisos.
    func settingsDidChange() {
        apply(userInitiated: true)
    }

    // MARK: - Aplicar ajustes

    private func apply(userInitiated: Bool) {
        refreshPermissions()
        guard started else { return }
        rebuildMatcherIfNeeded()

        let enabled = VoiceSettings.enabled
        if enabled && VoiceSettings.pushToTalk { registerHotKey() } else { unregisterHotKey() }

        let model = AppModel.shared
        pausedForPower = VoiceSettings.pauseOnLowPower && (model.lowPower || model.settings.lowPowerMode)
        pausedForSystem = isScreenLocked || isAsleep

        if !enabled || pausedForSystem { cancelCommand() }
        if pausedForSystem { stopMicTest() }

        let wantsWake = enabled && VoiceSettings.alwaysListening && !pausedForPower && !pausedForSystem
        if wantsWake {
            if permissionsGranted {
                if phase == .off {
                    if ensureListener() { phase = .waitingWakeWord }
                } else if phase == .waitingWakeWord, activeConfig != currentConfig() {
                    _ = ensureListener()   // cambió el idioma o los nombres: se rearma
                }
            } else if userInitiated {
                Task { @MainActor in
                    if await VoiceController.shared.requestPermissions() {
                        VoiceController.shared.apply(userInitiated: false)
                    }
                }
            } else {
                problem = "Falta permiso de micrófono o de reconocimiento de voz: activalo desde Configuración › Voz."
            }
        } else if phase == .waitingWakeWord {
            phase = .off
            if !isTesting { stopListener() }
        }
        // Micrófono abierto solo si hay algo que lo necesita.
        if phase == .off && !isTesting && listener.isRunning { stopListener() }
        updateLevelWanted()
    }

    private func currentConfig() -> VoiceListener.Config {
        VoiceListener.Config(localeID: VoiceSettings.localeID,
                             allowCloud: VoiceSettings.allowCloud,
                             contextualStrings: ["Orbex", "Orbi", "Orbes"] + VoiceSettings.extraNames)
    }

    private func rebuildMatcherIfNeeded() {
        let extra = VoiceSettings.extraNames
        guard extra != matcherNames else { return }
        matcherNames = extra
        matcher = WakeWordMatcher(names: WakeWordMatcher.defaultNames + extra)
    }

    /// Abre el micrófono (o lo rearma si cambió la configuración). `false` = no se pudo (ver `problem`).
    @discardableResult
    private func ensureListener() -> Bool {
        let config = currentConfig()
        if listener.isRunning && activeConfig == config { return true }
        do {
            try listener.start(config)
            activeConfig = config
            problem = nil
            if let id = listener.activeLocaleID {
                recognizerLabel = VoiceListener.displayName(id) + (listener.isOnDevice ? " · en tu Mac" : " · en la nube de Apple")
            }
            return true
        } catch let e as VoiceListener.StartError {
            activeConfig = nil
            problem = e.message
            return false
        } catch {
            activeConfig = nil
            problem = error.localizedDescription
            return false
        }
    }

    private func stopListener() {
        listener.stop()
        activeConfig = nil
        level = 0
    }

    // MARK: - Permisos

    func refreshPermissions() {
        let mic = VoicePermissions.microphone
        let speech = VoicePermissions.speech
        if mic != micPermission { micPermission = mic }
        if speech != speechPermission { speechPermission = speech }
    }

    /// Pide lo que falte (macOS muestra su cartel solo la primera vez). Devuelve si está todo permitido.
    func requestPermissions() async -> Bool {
        refreshPermissions()
        if permissionsGranted { return true }
        guard !requestingPermissions else { return false }
        requestingPermissions = true
        defer { requestingPermissions = false }

        if micPermission == .notAsked {
            NSApp.activate()
            _ = await VoicePermissions.requestMicrophone()
            refreshPermissions()
        }
        guard micPermission == .granted else {
            problem = "ORBEX no tiene permiso para usar el micrófono. Habilitalo en Ajustes del Sistema › Privacidad y seguridad › Micrófono."
            return false
        }
        if speechPermission == .notAsked {
            NSApp.activate()
            _ = await VoicePermissions.requestSpeech()
            refreshPermissions()
        }
        guard speechPermission == .granted else {
            problem = "ORBEX no tiene permiso de reconocimiento de voz. Habilitalo en Ajustes del Sistema › Privacidad y seguridad › Reconocimiento de voz."
            return false
        }
        problem = nil
        return true
    }

    // MARK: - Hablar sin decir el nombre (atajo, clic largo)

    /// ⌃⌥Espacio / clic largo: empieza a escuchar un pedido; si ya estaba escuchando, lo da por terminado.
    func talk() {
        guard started, VoiceSettings.enabled, !pausedForSystem else { return }
        switch phase {
        case .listeningCommand:
            finishCommand()
        case .working:
            return
        case .off, .waitingWakeWord:
            if isTesting { stopMicTest() }
            guard permissionsGranted else {
                Task { @MainActor in
                    let ok = await VoiceController.shared.requestPermissions()
                    if ok {
                        VoiceController.shared.talk()
                    } else {
                        OrbexBridge.shared.showNote("Necesito permiso de micrófono y voz. Mirá Configuración › Voz.",
                                                    symbol: "mic.slash")
                    }
                }
                return
            }
            let wasRunning = listener.isRunning
            guard ensureListener() else {
                OrbexBridge.shared.showNote(problem ?? "No pude abrir el micrófono.", symbol: "mic.slash")
                return
            }
            if wasRunning { listener.resetTranscript() }   // lo de antes no es parte del pedido
            beginCommand(fromWake: false, generation: listener.generation, initial: "")
        }
    }

    // MARK: - Lo que se oye

    private func heard(_ h: VoiceListener.Heard) {
        if isTesting {
            testText = h.text
            if matcher.match(h.text) != nil { testHeardName = true }
            return
        }
        switch phase {
        case .off, .working:
            return
        case .waitingWakeWord:
            if let m = matcher.match(h.text) {
                idleResetWork?.cancel()
                beginCommand(fromWake: true, generation: h.generation, initial: m.command)
            } else {
                scheduleIdleReset()
            }
        case .listeningCommand:
            commandHeard(h)
        }
    }

    /// Siempre atento: si se habló sin nombre y hubo silencio, se empieza de cero (así "Orbex, …" queda al
    /// principio de la próxima frase, que es donde lo busca `WakeWordMatcher`).
    private func scheduleIdleReset() {
        idleResetWork?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                let c = VoiceController.shared
                guard c.phase == .waitingWakeWord, !c.isTesting else { return }
                c.listener.resetTranscript()
            }
        }
        idleResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleResetAfter, execute: work)
    }

    private func commandHeard(_ h: VoiceListener.Heard) {
        let piece: String
        if h.generation == commandGeneration {
            if let m = matcher.match(h.text) {
                piece = m.command
            } else if commandFromWake {
                return   // el reconocedor corrigió el nombre y ya no lo ve: se queda con lo último
            } else {
                piece = h.text
            }
        } else {
            // La tarea se renovó en medio del pedido: lo nuevo se suma a lo que ya se tenía.
            commandPrefix = commandText
            commandGeneration = h.generation
            commandFromWake = false
            piece = matcher.match(h.text)?.command ?? h.text
        }
        let full = [commandPrefix, piece]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        updateCommand(full)
    }

    private func updateCommand(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != commandText else { return }
        commandText = t
        endpointer?.heard(t, at: Self.clock)
        showLive(t)
    }

    // MARK: - Escuchar un pedido

    private func beginCommand(fromWake: Bool, generation: Int, initial: String) {
        guard phase != .listeningCommand else { return }
        phase = .listeningCommand
        commandFromWake = fromWake
        commandGeneration = generation
        commandPrefix = ""
        commandText = ""
        liveText = ""
        noteVisible = false
        listener.holdRotation = true

        var ep = UtteranceEndpointer(silenceAfterSpeech: 1.3, maxListen: 12, noSpeechTimeout: 6)
        ep.start(at: Self.clock)
        endpointer = ep

        startListeningFeedback()
        updateLevelWanted()
        startEndTimer()
        updateCommand(initial)
    }

    private func startEndTimer() {
        endTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { VoiceController.shared.checkEndOfUtterance() }
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        endTimer = timer
    }

    private func stopEndTimer() {
        endTimer?.invalidate()
        endTimer = nil
    }

    private func checkEndOfUtterance() {
        guard phase == .listeningCommand else { stopEndTimer(); return }
        if endpointer?.isFinished(at: Self.clock) == true { finishCommand() }
    }

    /// Terminó la frase: se deja de escuchar y se hace lo pedido.
    private func finishCommand() {
        guard phase == .listeningCommand else { return }
        stopEndTimer()
        endpointer = nil
        let said = commandText
        phase = .working
        listener.holdRotation = false
        endListeningFeedback()
        // Siempre atento: se olvida lo oído (que el nombre no vuelva a disparar). Si no, se cierra el micrófono.
        if wantsWakeListening && listener.isRunning { listener.resetTranscript() } else { stopListener() }
        updateLevelWanted()

        // El enrutador limpia por su cuenta (y reconoce "cancelá" en lo dicho tal cual).
        let route = VoiceIntentRouter.route(said)
        let cleaned = VoiceCommandCleaner.clean(said)
        Task { @MainActor in
            let c = VoiceController.shared
            switch route {
            case .local(let command):
                await c.runLocal(command, said: said, cleaned: cleaned)
            case .claude(let prompt):
                c.askClaude(prompt)
            case .stop:
                if c.noteVisible { OrbexBridge.shared.showNote("Listo, no hago nada 👌", symbol: "waveform") }
            case .empty:
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
                if c.noteVisible { OrbexBridge.shared.showNote("No te entendí 🤔", symbol: "waveform") }
            }
            c.returnToIdle()
        }
    }

    /// Corta un pedido a medias sin hacer nada (bloqueo de pantalla, voz apagada, salir).
    private func cancelCommand() {
        guard phase == .listeningCommand || phase == .working else { return }
        stopEndTimer()
        endpointer = nil
        listener.holdRotation = false
        if phase == .listeningCommand { endListeningFeedback() }
        phase = .off
        updateLevelWanted()
    }

    private var wantsWakeListening: Bool {
        VoiceSettings.enabled && VoiceSettings.alwaysListening && !pausedForPower && !pausedForSystem
    }

    private func returnToIdle() {
        guard phase == .working else { return }
        if wantsWakeListening && permissionsGranted && ensureListener() {
            phase = .waitingWakeWord
        } else {
            phase = .off
            if !isTesting { stopListener() }
        }
        updateLevelWanted()
    }

    // MARK: - Hacer lo pedido

    private func runLocal(_ command: OrbexCommand, said: String, cleaned: String) async {
        lastUnderstood = said
        let executor = CommandExecutor.shared
        // Lo que pide confirmación nunca se hace por voz: va al chat, donde el usuario confirma con un clic.
        if AutonomyPolicy.level(for: command, allowlist: executor.allowlist) == .confirm {
            handOffToChat([cleaned, said], expected: command)
            return
        }
        let result = await executor.execute(command)
        if result.needsConfirmation {
            executor.cancelPending()
            handOffToChat([cleaned, said], expected: command)
            return
        }
        OrbexBridge.shared.showNote("Entendí: “\(Self.clip(said))”\n\(result.message)", symbol: "waveform")
    }

    /// Abre el chat de la isla con el pedido: si el chat lo entiende igual, muestra la pregunta con el botón
    /// de confirmar; si no, queda escrito para que el usuario lo mande.
    private func handOffToChat(_ texts: [String], expected: OrbexCommand) {
        let store = AssistantStore.shared
        let usable = texts.filter { !$0.isEmpty }
        if let same = usable.first(where: { CommandParser.parse($0) == expected }), store.canSend(same) {
            store.send(same)
        } else if let first = usable.first {
            putInDraft(first)
        }
        OrbexBridge.shared.openIsland(.prompt)
    }

    /// Pregunta para Claude. Con herramientas activadas (Claude puede tocar archivos o correr comandos) el
    /// pedido queda escrito en el chat y sale recién cuando el usuario lo manda.
    private func askClaude(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lastUnderstood = text
        let store = AssistantStore.shared
        if store.allowTools || !store.canSend(text) {
            putInDraft(text)
        } else {
            store.send(text)
        }
        OrbexBridge.shared.openIsland(.prompt)
    }

    private func putInDraft(_ text: String) {
        let store = AssistantStore.shared
        let current = store.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        store.draft = current.isEmpty ? text : current + " " + text
    }

    // MARK: - Isla y personaje

    private func startListeningFeedback() {
        let state = AppState.shared
        // Si la isla estaba escondida, al asomarse ya suena "peek".
        if VoiceSettings.chime && state.mode != .hidden { SoundEngine.shared.play("peek") }
        state.stateOverride = .listening
        OrbexBridge.shared.reveal()
        NotificationCenter.default.post(name: Self.listeningNotification, object: true)
    }

    private func endListeningFeedback() {
        let state = AppState.shared
        if state.stateOverride == .listening { state.stateOverride = nil }
        level = 0
        NotificationCenter.default.post(name: Self.levelNotification, object: CGFloat(0))
        NotificationCenter.default.post(name: Self.listeningNotification, object: false)
    }

    /// Lo que va entendiendo, en la vista `note` de la isla (se refresca para que no se cierre sola).
    private func showLive(_ text: String) {
        liveText = text
        let shown = "“\(Self.clip(text))”"
        let state = AppState.shared
        let now = Date()
        if noteVisible && state.mode == .expanded && state.view == .note
            && now.timeIntervalSince(lastNoteRefresh) < 2 {
            state.noteMessage = shown
            return
        }
        lastNoteRefresh = now
        OrbexBridge.shared.showNote(shown, symbol: "waveform")
        noteVisible = state.mode == .expanded && state.view == .note
    }

    /// Reloj monótono para `UtteranceEndpointer`.
    private static var clock: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private static func clip(_ s: String, max: Int = 90) -> String {
        s.count > max ? String(s.prefix(max - 1)) + "…" : s
    }

    // MARK: - Nivel de la voz

    private func updateLevelWanted() {
        listener.wantsLevel = isTesting || phase == .listeningCommand
    }

    private func levelChanged(_ value: CGFloat) {
        level = value
        if phase == .listeningCommand {
            NotificationCenter.default.post(name: Self.levelNotification, object: value)
        }
    }

    private func listenerStopped(_ message: String) {
        problem = message
        activeConfig = nil
        if phase == .listeningCommand || phase == .working { cancelCommand() }
        phase = .off
        isTesting = false
        level = 0
        updateLevelWanted()
    }

    // MARK: - Prueba de micrófono (Configuración)

    /// Abre el micrófono para ver el nivel y lo que entiende. No hace nada con lo que oye.
    func startMicTest() {
        guard !isTesting, phase != .listeningCommand, phase != .working else { return }
        Task { @MainActor in
            let c = VoiceController.shared
            guard await c.requestPermissions() else { return }
            guard !c.isTesting, c.phase != .listeningCommand, c.phase != .working else { return }
            guard c.ensureListener() else { return }
            c.isTesting = true
            c.testText = ""
            c.testHeardName = false
            c.listener.resetTranscript()
            c.updateLevelWanted()
            c.testStopWork?.cancel()
            let work = DispatchWorkItem {
                MainActor.assumeIsolated { VoiceController.shared.stopMicTest() }
            }
            c.testStopWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.micTestMaxDuration, execute: work)
        }
    }

    func stopMicTest() {
        guard isTesting else { return }
        isTesting = false
        testStopWork?.cancel()
        testStopWork = nil
        level = 0
        if phase == .waitingWakeWord {
            listener.resetTranscript()
        } else if phase == .off {
            stopListener()
        }
        updateLevelWanted()
    }

    // MARK: - Atajo

    private func registerHotKey() {
        guard !HotKeyCenter.shared.registeredIDs.contains(Self.hotKeyID) else { return }
        let mods = UInt32(controlKey | optionKey)
        let action = { VoiceController.shared.talk() }
        if HotKeyCenter.shared.register(id: Self.hotKeyID, keyCode: UInt32(kVK_Space), modifiers: mods, action: action) {
            hotKeyLabel = "⌃⌥Espacio"
        } else if HotKeyCenter.shared.register(id: Self.hotKeyID, keyCode: UInt32(kVK_ANSI_V), modifiers: mods, action: action) {
            hotKeyLabel = "⌃⌥V"
        } else {
            hotKeyLabel = nil
        }
    }

    private func unregisterHotKey() {
        HotKeyCenter.shared.unregister(id: Self.hotKeyID)
        hotKeyLabel = nil
    }

    // MARK: - Clic largo en la isla

    private func installLongPressMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
            let type = event.type
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated {
                VoiceController.shared.mouse(type, windowNumber: windowNumber)
            }
            return event
        }
    }

    private func mouse(_ type: NSEvent.EventType, windowNumber: Int) {
        guard VoiceSettings.enabled, VoiceSettings.longPress else { return }
        switch type {
        case .leftMouseDown:
            guard let window = OrbexBridge.shared.island?.window, window.windowNumber == windowNumber else { return }
            longPressStart = NSEvent.mouseLocation
            longPressWork?.cancel()
            let work = DispatchWorkItem {
                MainActor.assumeIsolated {
                    let c = VoiceController.shared
                    guard c.longPressStart != nil else { return }
                    c.longPressStart = nil
                    c.talk()
                }
            }
            longPressWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.longPressDelay, execute: work)
        case .leftMouseDragged:
            guard let start = longPressStart else { return }
            let m = NSEvent.mouseLocation
            if hypot(m.x - start.x, m.y - start.y) > 4 { cancelLongPress() }
        case .leftMouseUp:
            cancelLongPress()
        default:
            break
        }
    }

    private func cancelLongPress() {
        longPressStart = nil
        longPressWork?.cancel()
        longPressWork = nil
    }

    // MARK: - Sistema: bajo consumo, bloqueo, reposo

    private func observeSystem() {
        let model = AppModel.shared
        model.$lowPower
            .combineLatest(model.$settings.map(\.lowPowerMode))
            .removeDuplicates { $0 == $1 }
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                MainActor.assumeIsolated { VoiceController.shared.apply(userInitiated: false) }
            }
            .store(in: &cancellables)

        // Pantalla bloqueada: no se escucha (privacidad).
        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            let token = distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { VoiceController.shared.systemChanged(locked: locked) }
            }
            observers.append((distributed as NotificationCenter, token))
        }

        let ws = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            let token = ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { VoiceController.shared.systemChanged(asleep: asleep) }
            }
            observers.append((ws, token))
        }
    }

    private func systemChanged(locked: Bool? = nil, asleep: Bool? = nil) {
        if let locked { isScreenLocked = locked }
        if let asleep { isAsleep = asleep }
        if isScreenLocked || isAsleep {
            // El micrófono se cierra del todo (aunque estuviera la prueba abierta).
            pausedForSystem = true
            cancelCommand()
            stopMicTest()
            if phase == .waitingWakeWord { phase = .off }
            stopListener()
        }
        apply(userInitiated: false)
    }
}

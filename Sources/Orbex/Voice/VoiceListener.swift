import AVFoundation
import Accelerate
import AppKit
import Speech

/// Oído de ORBEX: micrófono (`AVAudioEngine`) → reconocimiento de voz de macOS (`SFSpeechRecognizer`),
/// con resultados parciales y **en el dispositivo** (el audio no sale de la Mac) salvo que el usuario
/// active la nube a mano en Configuración › Voz.
///
/// Escucha continua: el motor de audio queda andando y la tarea de reconocimiento se renueva cada ~50 s,
/// cuando termina sola o cuando falla (límites de Speech), sin acumular tareas ni tapas de audio.
/// También mide el nivel de la voz (RMS → 0…1, suavizado, ~20 Hz) cuando alguien lo pide (`wantsLevel`).
///
/// Lo que se oye es DATO: este tipo solo entrega texto; qué se hace con él lo decide `VoiceController`.
@MainActor
final class VoiceListener {
    enum StartError: Error {
        case noSpanishRecognizer
        case needsOnDeviceModel(localeName: String)
        case recognizerUnavailable
        case noInputDevice
        case audioEngine(String)

        var message: String {
            switch self {
            case .noSpanishRecognizer:
                return "macOS no tiene reconocimiento de voz en español en esta Mac."
            case .needsOnDeviceModel(let name):
                return "Falta el modelo de voz de \(name) en tu Mac. Activá el Dictado con ese idioma en Ajustes del Sistema › Teclado para que se descargue (o permití la nube en Configuración › Voz)."
            case .recognizerUnavailable:
                return "El reconocimiento de voz no está disponible ahora. Probá de nuevo en un rato."
            case .noInputDevice:
                return "No encontré un micrófono. Conectá uno o elegilo en Ajustes del Sistema › Sonido › Entrada."
            case .audioEngine(let detail):
                return "No pude abrir el micrófono (\(detail))."
            }
        }
    }

    struct Config: Equatable {
        /// "auto" o "es-AR", "es-ES"…
        var localeID: String
        var allowCloud: Bool
        /// Palabras que conviene que el reconocedor tenga presentes ("Orbex", "Orbi", nombres extra).
        var contextualStrings: [String]
    }

    // MARK: - Salidas (siempre en el hilo principal)

    /// Texto de la tarea actual (acumulado desde que empezó) y si es el resultado final.
    var onText: ((String, Bool) -> Void)?
    /// Nivel de la voz 0…1 (solo si `wantsLevel`).
    var onLevel: ((CGFloat) -> Void)?
    /// Se paró solo por fallas repetidas (mensaje para mostrar).
    var onStopped: ((String) -> Void)?

    // MARK: - Estado

    private(set) var isRunning = false
    /// Idioma en uso ("es-AR") y si reconoce en la Mac.
    private(set) var activeLocaleID: String?
    private(set) var isOnDevice = false

    /// Pedir el nivel de la voz (medidor de prueba, animación mientras escucha un pedido).
    var wantsLevel: Bool {
        get { box.wantsLevel }
        set { box.wantsLevel = newValue }
    }

    /// Mientras escucha un pedido, no renovar la tarea (se cortaría la frase).
    var holdRotation = false

    private let engine = AVAudioEngine()
    private lazy var box = VoiceTapBox { [weak self] level in
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self?.deliverLevel(level) }
        }
    }
    private var tapInstalled = false
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var config: Config?
    private var taskStartedAt = Date()
    private var lastTextAt = Date.distantPast
    private var failures = 0
    private var restartWork: DispatchWorkItem?
    private var engineRestartWork: DispatchWorkItem?
    private var rotationTimer: Timer?
    private var configObserver: NSObjectProtocol?

    /// Cada cuánto se renueva la tarea de reconocimiento.
    private static let rotateAfter: TimeInterval = 50
    /// Tope duro (aunque el usuario esté hablando).
    private static let rotateHardLimit: TimeInterval = 58
    private static let maxFailures = 6

    // MARK: - Arrancar / parar

    func start(_ config: Config) throws {
        stop()
        let (rec, onDevice, localeID) = try Self.makeRecognizer(config)
        recognizer = rec
        isOnDevice = onDevice
        activeLocaleID = localeID
        self.config = config
        try startEngine()
        isRunning = true
        failures = 0
        beginTask()
        startRotationTimer()
        observeConfigurationChanges()
    }

    /// Para todo: tarea, tapa de audio y motor (el micrófono se libera y el punto naranja se apaga).
    func stop() {
        isRunning = false
        generation &+= 1
        restartWork?.cancel(); restartWork = nil
        engineRestartWork?.cancel(); engineRestartWork = nil
        rotationTimer?.invalidate(); rotationTimer = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        box.setRequest(nil)
        box.resetLevel()
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        stopEngine()
        recognizer = nil
        holdRotation = false
    }

    /// Empieza una tarea nueva ya mismo: olvida lo que se venía oyendo (después de atender un pedido,
    /// para que el nombre dicho no vuelva a disparar).
    func resetTranscript() {
        guard isRunning else { return }
        beginTask()
    }

    // MARK: - Motor de audio

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Sin dispositivo de entrada el formato viene vacío (y `installTap` tiraría una excepción).
        guard format.sampleRate > 0, format.channelCount > 0 else { throw StartError.noInputDevice }
        if tapInstalled { input.removeTap(onBus: 0) }
        Self.installTap(on: input, format: format, box: box)
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            throw StartError.audioEngine(error.localizedDescription)
        }
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    /// La tapa corre en el hilo de audio: se arma fuera del actor principal y solo toca `VoiceTapBox`.
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, box: VoiceTapBox) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.consume(buffer)
        }
    }

    /// Cambió el micrófono (auriculares, AirPods…): el motor se detiene solo; se rearma.
    private func observeConfigurationChanges() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                                object: engine, queue: .main) { _ in
            MainActor.assumeIsolated { VoiceController.shared.listenerNeedsEngineRestart() }
        }
    }

    /// Rearma el motor después de un cambio de dispositivo (con una pausa corta, llegan en ráfaga).
    func restartEngineSoon() {
        guard isRunning else { return }
        engineRestartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.stopEngine()
                do {
                    try self.startEngine()
                    self.beginTask()
                } catch let e as StartError {
                    self.fail(e.message)
                } catch {
                    self.fail(error.localizedDescription)
                }
            }
        }
        engineRestartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: - Tareas de reconocimiento

    private func beginTask() {
        guard isRunning, let recognizer, let config else { return }
        restartWork?.cancel(); restartWork = nil
        generation &+= 1
        let gen = generation

        // La anterior se cancela y se suelta (sus respuestas tardías se ignoran por `generation`).
        box.setRequest(nil)
        task?.cancel(); task = nil
        request?.endAudio(); request = nil

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = isOnDevice
        req.addsPunctuation = false
        req.contextualStrings = config.contextualStrings
        request = req
        box.setRequest(req)
        task = Self.startTask(recognizer: recognizer, request: req, generation: gen, owner: self)
        taskStartedAt = Date()
    }

    /// El manejador lo llama Speech en su cola: se arma fuera del actor principal, copia solo valores
    /// (texto, final, código de error) y salta al hilo principal.
    nonisolated private static func startTask(recognizer: SFSpeechRecognizer,
                                              request: SFSpeechAudioBufferRecognitionRequest,
                                              generation: Int,
                                              owner: VoiceListener) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { [weak owner] result, error in
            guard let owner else { return }
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let nsError = error.map { $0 as NSError }
            let code = nsError?.code
            let domain = nsError?.domain
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    owner.handle(generation: generation, text: text, isFinal: isFinal,
                                 errorCode: code, errorDomain: domain)
                }
            }
        }
    }

    private func handle(generation gen: Int, text: String?, isFinal: Bool, errorCode: Int?, errorDomain: String?) {
        guard isRunning, gen == generation else { return }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failures = 0
            lastTextAt = Date()
            onText?(text, isFinal)
        }
        guard isFinal || errorCode != nil else { return }

        // La tarea terminó (final, silencio largo o error): arrancar otra.
        if let errorCode, !Self.isBenign(code: errorCode, domain: errorDomain) {
            failures += 1
            NSLog("ORBEX voz: la tarea de reconocimiento falló (%@ %ld), intento %ld.",
                  errorDomain ?? "?", errorCode, failures)
            if failures >= Self.maxFailures {
                fail("El reconocimiento de voz falló varias veces seguidas. Lo apagué; probá de nuevo desde Configuración › Voz.")
                return
            }
        }
        scheduleRestart()
    }

    /// Errores normales de la escucha continua: "no se oyó nada" y "cancelada".
    private static func isBenign(code: Int, domain: String?) -> Bool {
        switch code {
        case 1110, 216, 301, 203: return true
        default: return false
        }
    }

    private func scheduleRestart() {
        restartWork?.cancel()
        let delay = failures == 0 ? 0.2 : min(8, 0.5 * pow(2, Double(failures)))
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.beginTask() }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Renueva la tarea cada ~50 s (si nadie está hablando en ese momento), con tope duro.
    private func startRotationTimer() {
        rotationTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { VoiceController.shared.listenerRotationTick() }
        }
        timer.tolerance = 1.5
        RunLoop.main.add(timer, forMode: .common)
        rotationTimer = timer
    }

    func rotateIfDue() {
        guard isRunning else { return }
        let age = Date().timeIntervalSince(taskStartedAt)
        let quiet = Date().timeIntervalSince(lastTextAt) > 2
        if age >= Self.rotateHardLimit || (age >= Self.rotateAfter && quiet && !holdRotation) {
            beginTask()
        }
    }

    private func fail(_ message: String) {
        stop()
        onStopped?(message)
    }

    private func deliverLevel(_ level: CGFloat) {
        guard isRunning, box.wantsLevel else { return }
        onLevel?(level)
    }

    // MARK: - Reconocedor

    /// Elige el reconocedor: el idioma pedido (o, en automático, el de la Mac si es español y si no
    /// es-AR, es-US, es-MX, es-ES), preferentemente con modelo en el dispositivo.
    private static func makeRecognizer(_ config: Config) throws -> (SFSpeechRecognizer, Bool, String) {
        var candidates: [String] = []
        if config.localeID == "auto" {
            let current = Locale.current
            if current.language.languageCode?.identifier == "es" {
                candidates.append(current.identifier.replacingOccurrences(of: "_", with: "-"))
            }
            candidates += ["es-AR", "es-US", "es-MX", "es-ES", "es-419"]
        } else {
            candidates = [config.localeID]
        }
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0).inserted }

        var available: [(SFSpeechRecognizer, String)] = []
        for id in candidates {
            guard let rec = SFSpeechRecognizer(locale: Locale(identifier: id)) else { continue }
            available.append((rec, id))
            if rec.supportsOnDeviceRecognition {
                guard rec.isAvailable else { throw StartError.recognizerUnavailable }
                return (rec, true, id)
            }
        }
        guard let first = available.first else { throw StartError.noSpanishRecognizer }
        guard config.allowCloud else {
            throw StartError.needsOnDeviceModel(localeName: displayName(first.1))
        }
        guard first.0.isAvailable else { throw StartError.recognizerUnavailable }
        return (first.0, false, first.1)
    }

    static func displayName(_ id: String) -> String {
        if let known = VoiceSettings.languages.first(where: { $0.id == id }) { return known.name }
        return Locale(identifier: "es").localizedString(forIdentifier: id) ?? id
    }
}

// MARK: - Tapa de audio (hilo de audio)

/// Lo único que toca el hilo de audio: el pedido de reconocimiento actual (con candado) y el cálculo del
/// nivel. Nunca toca estado del actor principal; el nivel sale por `sink` (que salta al principal).
final class VoiceTapBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var _wantsLevel = false
    private var smoothed: Float = 0
    private var lastSent: TimeInterval = 0
    private let sink: @Sendable (CGFloat) -> Void

    init(sink: @escaping @Sendable (CGFloat) -> Void) {
        self.sink = sink
    }

    var wantsLevel: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _wantsLevel }
        set { lock.lock(); _wantsLevel = newValue; lock.unlock() }
    }

    func setRequest(_ r: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); request = r; lock.unlock()
    }

    func resetLevel() {
        lock.lock(); smoothed = 0; lastSent = 0; lock.unlock()
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let req = request
        let wants = _wantsLevel
        lock.unlock()
        req?.append(buffer)

        guard wants, let channels = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var rms: Float = 0
        vDSP_rmsqa(channels[0], 1, &rms, vDSP_Length(n))
        // −55 dB (silencio de habitación) … −10 dB (voz fuerte cerca) → 0…1.
        let db = 20 * log10(max(rms, 0.000_000_1))
        let target = min(1, max(0, (db + 55) / 45))

        lock.lock()
        // Sube rápido, baja lento (se ve más vivo y no titila).
        let k: Float = target > smoothed ? 0.55 : 0.18
        smoothed += (target - smoothed) * k
        let value = smoothed
        let now = ProcessInfo.processInfo.systemUptime
        let due = now - lastSent >= 0.05   // ~20 Hz como máximo
        if due { lastSent = now }
        lock.unlock()
        if due { sink(CGFloat(value)) }
    }
}

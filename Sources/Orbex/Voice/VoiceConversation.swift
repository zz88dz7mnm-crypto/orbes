import AppKit
import Combine
import OrbexCore

/// La conversación hablada con Orbi: lo que dijo el usuario, lo que contestó Orbi y en qué está.
///
/// API para el panel de modo inteligente (y cualquier vista):
/// - `turns: [VoiceTurn]` — turnos en orden (`id`, `role` `.user`/`.orbi`, `text`, `date`); hasta `maxTurns`.
/// - `phase: Phase` — `.idle`, `.listening` (micrófono abierto esperando el pedido o el seguimiento),
///   `.thinking` (haciendo el comando o esperando a Claude), `.speaking` (Orbi hablando).
/// - `partialText` — lo que va entendiendo del usuario mientras habla ("" si no está escuchando).
/// - `handleTyped(_:)` — texto escrito en el panel: mismo camino que la voz y Orbi contesta hablando.
/// - `stopSpeaking()` — calla a Orbi y corta la respuesta en curso. `clear()` — borra la conversación.
///
/// Cómo contesta (`handle`): saludos simples al toque (`VoiceReplies.instant`), charla y preguntas con una
/// respuesta CORTA de Claude pensada para decir en voz alta (sesión propia, sin herramientas, no ensucia el
/// chat de la isla), comandos de ORBEX con una confirmación corta ("Listo, abrí Spotify"), y lo que necesita
/// confirmación (regla 12) abre la isla y dice "Necesito que lo confirmes en la isla".
///
/// Todo lo que dice el usuario y lo que devuelve Claude es DATO: se muestra y se dice, nunca se ejecuta.
@MainActor
final class VoiceConversation: ObservableObject {
    enum Phase: Equatable { case idle, listening, thinking, speaking }

    static let shared = VoiceConversation()
    static let maxTurns = 60
    /// La sesión de Claude para la voz se olvida después de este rato sin hablar.
    private static let sessionTTL: TimeInterval = 10 * 60

    @Published private(set) var turns: [VoiceTurn] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var partialText = ""

    private var claudeSessionID: String?
    private var lastExchange = Date.distantPast
    private var claudeTask: Task<String, Never>?
    private var generation = 0
    private var interrupted = false
    private var sayCounter = 0
    private var started = false

    private init() {}

    /// Engancha el texto escrito del panel de modo inteligente. Lo llama `VoiceController.start()`.
    func start() {
        guard !started else { return }
        started = true
        SmartModeController.shared.textHandler = { text in
            MainActor.assumeIsolated { VoiceConversation.shared.handleTyped(text) }
        }
    }

    // MARK: - Estado que pone VoiceController

    func setListening(_ on: Bool) {
        if on {
            partialText = ""
            phase = .listening
        } else {
            partialText = ""
            if phase == .listening { phase = .idle }
        }
    }

    func setPartial(_ text: String) {
        if partialText != text { partialText = text }
    }

    /// Orbi arranca en modo inteligente si hay que seguir escuchando aunque no haya voz de salida.
    var smartModeActive: Bool { SmartModeController.shared.isActive }

    /// ¿Tiene sentido quedarse escuchando después de responder? (Orbi habla, o el panel está abierto).
    var mayFollowUp: Bool { (OrbiVoice.shared.isEnabled && !OrbiVoice.shared.isMuted) || smartModeActive }

    // MARK: - Contestar

    /// Contesta lo que se dijo (o escribió). Devuelve si Orbi respondió y conviene quedarse escuchando el
    /// seguimiento (~6 s sin decir el nombre). `.stop` y `.empty` no responden (los maneja quien llama).
    @discardableResult
    func handle(_ route: VoiceIntentRouter.Route, said: String, cleaned: String) async -> Bool {
        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
        interrupted = false
        switch route {
        case .stop:
            stopSpeaking()
            return false
        case .empty:
            return false
        case .smartMode(let on):
            addTurn(.user, text)
            if on { SmartModeController.shared.show() } else { SmartModeController.shared.hide() }
            await say(VoiceReplies.smartMode(on))
            return on && !interrupted
        case .chat(let chat):
            addTurn(.user, text)
            if let quick = VoiceReplies.instant(for: chat) {
                await say(quick)
            } else {
                await say(await askClaude(chat))
            }
            return !interrupted
        case .claude(let prompt):
            addTurn(.user, text)
            await say(await askClaude(prompt))
            return !interrupted
        case .local(let command):
            addTurn(.user, text)
            phase = .thinking
            let reply = await VoiceController.shared.runLocal(command, said: said, cleaned: cleaned)
            guard !reply.isEmpty else {
                if phase == .thinking { phase = .idle }
                return false
            }
            await say(reply)
            return !interrupted
        }
    }

    /// Texto escrito en el panel: mismo camino que la voz (Orbi contesta hablando).
    func handleTyped(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        cancelReply()
        Task { @MainActor in
            let route = VoiceIntentRouter.route(text)
            if case .empty = route {
                VoiceConversation.shared.addTurn(.user, text)
                await VoiceConversation.shared.say(VoiceReplies.didNotUnderstand)
                return
            }
            await VoiceConversation.shared.handle(route, said: text, cleaned: VoiceCommandCleaner.clean(text))
        }
    }

    /// Calla a Orbi y corta la respuesta que se estaba pensando ("Orbi, pará").
    func stopSpeaking() {
        interrupted = true
        cancelReply()
        OrbiVoice.shared.stop()
        if phase == .speaking || phase == .thinking { phase = .idle }
    }

    func clear() {
        stopSpeaking()
        turns = []
        partialText = ""
        claudeSessionID = nil
    }

    // MARK: - Decir

    /// Agrega el turno de Orbi y lo dice; vuelve cuando terminó de hablar (o si lo cortaron).
    func say(_ raw: String) async {
        let text = VoiceReplies.speakable(raw, maxSentences: 4, maxChars: 420)
        guard !text.isEmpty else {
            if phase == .thinking { phase = .idle }
            return
        }
        interrupted = false
        addTurn(.orbi, text)
        phase = .speaking
        sayCounter += 1
        let mine = sayCounter
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            OrbiVoice.shared.speak(text, interrupt: true) { cont.resume() }
        }
        if mine == sayCounter, phase == .speaking { phase = .idle }
    }

    private func addTurn(_ role: VoiceTurn.Role, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        turns.append(VoiceTurn(role: role, text: t))
        if turns.count > Self.maxTurns { turns.removeFirst(turns.count - Self.maxTurns) }
    }

    // MARK: - Claude, en voz

    private func cancelReply() {
        generation += 1
        claudeTask?.cancel()
        claudeTask = nil
    }

    /// Respuesta corta de Claude para decir en voz alta. Sesión propia (sigue la charla de voz), sin
    /// herramientas, con lo que ORBEX recuerda del usuario como DATO.
    private func askClaude(_ prompt: String) async -> String {
        cancelReply()
        let gen = generation
        phase = .thinking
        CharacterBrain.shared.show(.thinking, for: 2)
        OrbexBus.setActivity(source: "voice", working: true, attention: false)
        defer { OrbexBus.setActivity(source: "voice", working: false, attention: false) }

        if Date().timeIntervalSince(lastExchange) > Self.sessionTTL { claudeSessionID = nil }
        let model = AssistantStore.shared.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = ClaudeRequest(
            prompt: prompt,
            model: model.isEmpty ? nil : model,
            resumeSessionID: claudeSessionID,
            toolAccess: .none,
            appendSystemPrompt: VoiceReplies.systemPrompt(memoryFacts: MemoryStore.shared.factTexts,
                                                          smartMode: smartModeActive))
        let cwd = Self.workingDirectory
        let task = Task { @MainActor () -> String in
            var builder = ClaudeReplyBuilder()
            var failure: ClaudeFailure?
            do {
                for try await event in ClaudeCLI.shared.stream(request, workingDirectory: cwd) {
                    _ = builder.apply(event)
                }
            } catch let f as ClaudeFailure {
                failure = f
            } catch {
                failure = ClaudeFailure(kind: Task.isCancelled ? .cancelled : .generic, message: error.localizedDescription)
            }
            if Task.isCancelled { return "" }
            if let sid = builder.sessionID { VoiceConversation.shared.claudeSessionID = sid }
            if failure == nil && builder.failed {
                failure = ClaudeErrorClassifier.classify(assistantError: builder.assistantError,
                                                         resultText: builder.result?.text,
                                                         errors: builder.result?.errors ?? [],
                                                         strayLines: builder.strayLines)
            }
            if let f = failure {
                if (f.detail ?? "").localizedCaseInsensitiveContains("no conversation found") {
                    VoiceConversation.shared.claudeSessionID = nil
                }
                switch f.kind {
                case .cancelled: return ""
                case .notInstalled: return "No encuentro Claude en tu Mac. Instalalo y probá de nuevo."
                case .notLoggedIn: return "Claude no tiene la sesión iniciada. Abrí la terminal y entrá con claude."
                case .usageLimit, .rateLimited: return "Claude llegó a su límite por ahora. Probá en un rato."
                default: return VoiceReplies.claudeFailed
                }
            }
            let text = builder.finalText
            return text.isEmpty ? VoiceReplies.claudeFailed : text
        }
        claudeTask = task
        let reply = await task.value
        guard gen == generation else { return "" }   // otro pedido la reemplazó o la cortaron
        claudeTask = nil
        lastExchange = Date()
        return reply
    }

    /// Carpeta de trabajo de la voz (Claude no tiene herramientas, pero el CLI necesita una).
    private static var workingDirectory: URL {
        let dir = AppPaths.supportDir.appendingPathComponent("voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

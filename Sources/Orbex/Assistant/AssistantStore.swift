import AppKit
import SwiftUI
import OrbexCore

/// Estado del asistente (solo Claude, vía el CLI `claude` local).
@MainActor
final class AssistantStore: ObservableObject {
    static let shared = AssistantStore()

    enum CLIStatus: Equatable {
        case unknown, checking, missing
        case found(path: String, version: String?)
    }

    // MARK: - Estado publicado

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var isRunningCommand = false
    @Published private(set) var sessionID: String?
    @Published private(set) var petMood: ClawdMood = .idle
    @Published private(set) var petMoodSince = Date()
    @Published private(set) var pendingAttachments: [ClaudeAttachment] = []
    @Published private(set) var cliStatus: CLIStatus = .unknown
    @Published private(set) var lastError: ClaudeFailure?
    /// "Pensando…", "Reintentando…", herramienta en curso.
    @Published private(set) var statusNote: String?
    @Published private(set) var pendingConfirmationID: UUID?
    /// Sube con cada cambio de la conversación (para el auto-scroll).
    @Published private(set) var scrollTick = 0
    @Published var draft = ""
    @Published private(set) var isPanelVisible = false

    // MARK: - Ajustes (los escribe Configuración › Asistente en UserDefaults `orbex.assistant.*`)

    /// Modelo (`sonnet`, `opus`, `haiku` o nombre completo). Vacío = el del CLI.
    var model: String { defaults.string(forKey: Keys.model) ?? "" }
    /// Herramientas de Claude Code (leer/editar archivos, comandos). Apagado por defecto.
    var allowTools: Bool { defaults.bool(forKey: Keys.allowTools) }
    /// Carpeta de trabajo elegida (vacío = la de ORBEX).
    var workingFolder: String { defaults.string(forKey: Keys.workingFolder) ?? "" }
    var maxHistory: Int {
        let v = defaults.integer(forKey: Keys.maxHistory)
        return v > 0 ? v : 20
    }
    var extraInstructions: String { defaults.string(forKey: Keys.extra) ?? "" }
    let rememberConversation = true

    /// Hechos que ORBEX recuerda del usuario (Fase 4: `MemoryStore.shared.facts`).
    var memoryProvider: () -> [String] = { [] }

    // MARK: - Internos

    private enum Keys {
        static let model = "orbex.assistant.model"
        static let allowTools = "orbex.assistant.allowTools"
        static let workingFolder = "orbex.assistant.workingFolder"
        static let maxHistory = "orbex.assistant.maxHistory"
        static let extra = "orbex.assistant.extraInstructions"
    }

    private let defaults = UserDefaults.standard
    private var runTask: Task<Void, Never>?
    private var liveReply: (id: UUID, builder: ClaudeReplyBuilder)?
    private var flushScheduled = false
    private var thinkingTimer: Timer?
    private var moodWork: DispatchWorkItem?
    private var lastAsk: (text: String, attachments: [ClaudeAttachment])?

    static var historyURL: URL { AppPaths.dataFile("assistant-chat.json") }

    private init() {
        load()
    }

    // MARK: - Panel

    func panelDidAppear() {
        isPanelVisible = true
        OrbexBus.requestTint(.orange, source: "assistant")
        if cliStatus == .unknown || cliStatus == .missing { refreshCLIStatus() }
    }

    func panelDidDisappear() {
        isPanelVisible = false
        OrbexBus.requestTint(nil, source: "assistant")
    }

    func refreshCLIStatus() {
        cliStatus = .checking
        Task { [weak self] in
            let r = await ClaudeCLI.shared.detect()
            guard let self else { return }
            if let path = r.path {
                self.cliStatus = .found(path: path, version: r.version)
                if self.lastError?.kind == .notInstalled { self.lastError = nil }
            } else {
                self.cliStatus = .missing
            }
        }
    }

    var workingDirectoryURL: URL {
        let f = workingFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !f.isEmpty { return URL(fileURLWithPath: (f as NSString).expandingTildeInPath, isDirectory: true) }
        let dir = AppPaths.supportDir.appendingPathComponent("assistant", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Enviar

    /// `context`: lo que ORBEX ve alrededor (ventana activa, etc.). Va a Claude como DATO envuelto
    /// (`ClaudeArguments.composePrompt` lo marca como no confiable), nunca como instrucciones.
    func sendDraft(context: ClaudeAttachment? = nil) {
        let text = draft
        guard canSend(text) else { return }
        draft = ""
        send(text, context: context)
    }

    func canSend(_ text: String) -> Bool {
        !isStreaming && !isRunningCommand
            && !(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty)
    }

    /// Primero ORBEX (comandos locales); si no es un comando, Claude.
    func send(_ raw: String, context: ClaudeAttachment? = nil) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend(text) else { return }
        lastError = nil
        let attachments = pendingAttachments
        pendingAttachments = []
        // Los comandos de ORBEX van primero (el contexto de ventana no les cambia nada).
        if attachments.isEmpty, let command = CommandParser.parse(text) {
            append(ChatMessage(role: .user, text: text))
            runCommand(command)
            return
        }
        let all = attachments + (context.map { [$0] } ?? [])
        append(ChatMessage(role: .user, text: text,
                           attachments: all.map { ChatAttachmentInfo(name: $0.name, bytes: $0.bytes) }))
        askClaude(text, attachments: all)
    }

    /// Contexto de la ventana activa como adjunto de datos (título, app, URL). Solo texto, nada se ejecuta.
    static func windowContext(app: String, title: String, url: String?) -> ClaudeAttachment {
        var lines = ["App: \(app)", "Título de la ventana: \(title)"]
        if let url, !url.isEmpty { lines.append("URL: \(url)") }
        return ClaudeAttachment(name: "Ventana · \(app)", content: lines.joined(separator: "\n"))
    }

    /// Hay una respuesta de Claude en curso usando herramientas (para la vista "buscando").
    var runningToolTitle: String? {
        guard isStreaming else { return nil }
        return messages.last(where: { $0.isStreaming })?.toolChips.last(where: { $0.state == .running })?.title
    }

    /// Última respuesta terminada de Claude (para la vista de resultado corto).
    var lastReply: ChatMessage? {
        messages.last { $0.role == .assistant && !$0.isStreaming && !$0.text.isEmpty }
    }

    func retry() {
        guard let ask = lastAsk, !isStreaming else { return }
        lastError = nil
        askClaude(ask.text, attachments: ask.attachments)
    }

    func stop() {
        runTask?.cancel()
    }

    func newConversation() {
        stop()
        if pendingConfirmationID != nil { CommandExecutor.shared.cancelPending() }
        pendingConfirmationID = nil
        messages = []
        sessionID = nil
        lastError = nil
        statusNote = nil
        pendingAttachments = []
        lastAsk = nil
        setPet(.idle)
        scrollTick += 1
        save()
    }

    // MARK: - Comandos de ORBEX

    private func runCommand(_ command: OrbexCommand) {
        isRunningCommand = true
        Task { [weak self] in
            let result = await CommandExecutor.shared.execute(command)
            self?.showCommandResult(result)
        }
    }

    private func showCommandResult(_ result: CommandResult) {
        isRunningCommand = false
        let msg = ChatMessage(role: .system, text: result.message, needsConfirmation: result.needsConfirmation)
        append(msg)
        pendingConfirmationID = result.needsConfirmation ? msg.id : nil
        setPet(.happy, reset: 2.4)
        save()
    }

    func confirmPending() {
        guard let id = pendingConfirmationID else { return }
        clearConfirmation(id)
        isRunningCommand = true
        Task { [weak self] in
            let result = await CommandExecutor.shared.confirmPending()
            self?.showCommandResult(result)
        }
    }

    func cancelPending() {
        guard let id = pendingConfirmationID else { return }
        clearConfirmation(id)
        CommandExecutor.shared.cancelPending()
        append(ChatMessage(role: .system, text: "Listo, no hago nada."))
        save()
    }

    private func clearConfirmation(_ id: UUID) {
        pendingConfirmationID = nil
        if let i = messages.firstIndex(where: { $0.id == id }) { messages[i].needsConfirmation = false }
    }

    // MARK: - Adjuntos

    /// Adjunta un archivo de texto (hasta ~50 KB se manda; lo demás se corta). Devuelve `false` si no se pudo.
    @discardableResult
    func attach(fileURL: URL) -> Bool {
        let name = fileURL.lastPathComponent
        guard pendingAttachments.count < 5 else {
            OrbexBus.toast("Máximo 5 adjuntos", symbol: "exclamationmark.triangle")
            return false
        }
        var data = Data()
        if let h = try? FileHandle(forReadingFrom: fileURL) {
            data = (try? h.read(upToCount: 400_000)) ?? Data()
            try? h.close()
        }
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? data.count
        guard !data.isEmpty, var att = ClaudeAttachment.fromTextData(data, name: name) else {
            append(ChatMessage(role: .system, text: "No puedo adjuntar “\(name)”: no parece un archivo de texto.", isError: true))
            OrbexBus.play(.error)
            return false
        }
        att.bytes = size
        if size > ClaudeAttachment.maxBytes { att.truncated = true }
        pendingAttachments.removeAll { $0.name == name }
        pendingAttachments.append(att)
        OrbexBus.play(.fileSwallowed)
        return true
    }

    func removeAttachment(named name: String) {
        pendingAttachments.removeAll { $0.name == name }
    }

    // MARK: - Claude

    private func askClaude(_ text: String, attachments: [ClaudeAttachment]) {
        lastAsk = (text, attachments)
        let access: ClaudeToolAccess = allowTools ? .full : .none
        let request = ClaudeRequest(
            prompt: ClaudeArguments.composePrompt(text, attachments: attachments),
            model: model,
            resumeSessionID: sessionID,
            toolAccess: access,
            appendSystemPrompt: ClaudeArguments.systemPrompt(memoryFacts: memoryProvider(),
                                                             extraInstructions: extraInstructions,
                                                             toolAccess: access))
        let reply = ChatMessage(role: .assistant, text: "", isStreaming: true,
                                model: model.isEmpty ? nil : model)
        append(reply)
        let replyID = reply.id
        liveReply = (replyID, ClaudeReplyBuilder())
        isStreaming = true
        statusNote = "Pensando…"
        setPet(.thinking)
        OrbexBus.play(.thinking)
        OrbexBus.setActivity(source: "assistant", working: true, attention: false)
        startThinkingPulse()
        let cwd = workingDirectoryURL

        runTask = Task { [weak self] in
            var failure: ClaudeFailure?
            do {
                for try await event in ClaudeCLI.shared.stream(request, workingDirectory: cwd) {
                    guard let self else { return }
                    self.handle(event, replyID: replyID)
                }
                if Task.isCancelled { failure = ClaudeFailure.cancelled() }
            } catch let f as ClaudeFailure {
                failure = f
            } catch {
                failure = Task.isCancelled ? ClaudeFailure.cancelled()
                    : ClaudeFailure(kind: .generic, message: "Claude no pudo responder.", detail: error.localizedDescription)
            }
            self?.finishReply(replyID, failure: failure)
        }
    }

    private func handle(_ event: ClaudeStreamEvent, replyID: UUID) {
        guard var live = liveReply, live.id == replyID else { return }
        let changed = live.builder.apply(event)
        liveReply = live
        switch event {
        case .sessionStarted(let sid, _):
            if let sid, !sid.isEmpty { sessionID = sid }
        case .textDelta:
            if petMood != .typing { setPet(.typing) }
        case .thinking, .toolUseStarted:
            if petMood != .thinking { setPet(.thinking) }
        default:
            break
        }
        if changed { scheduleFlush() }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            MainActor.assumeIsolated { self?.flushLive() }
        }
    }

    private func flushLive() {
        flushScheduled = false
        guard let live = liveReply, let i = messages.firstIndex(where: { $0.id == live.id }) else { return }
        let b = live.builder
        messages[i].text = b.text
        messages[i].toolChips = b.toolChips
        if let m = b.model { messages[i].model = m }
        if let note = b.retryNote {
            statusNote = note
        } else if let running = b.toolChips.last(where: { $0.state == .running }) {
            statusNote = running.title
        } else {
            statusNote = b.isThinking || b.text.isEmpty ? "Pensando…" : nil
        }
        scrollTick += 1
    }

    private func finishReply(_ replyID: UUID, failure incoming: ClaudeFailure?) {
        flushLive()
        stopThinkingPulse()
        runTask = nil
        isStreaming = false
        statusNote = nil
        OrbexBus.setActivity(source: "assistant", working: false, attention: false)
        let builder = liveReply?.builder ?? ClaudeReplyBuilder()
        liveReply = nil
        if let sid = builder.sessionID { sessionID = sid }

        var failure = incoming
        if failure == nil && builder.failed {
            failure = ClaudeErrorClassifier.classify(assistantError: builder.assistantError,
                                                     resultText: builder.result?.text,
                                                     errors: builder.result?.errors ?? [],
                                                     strayLines: builder.strayLines)
        }
        guard let i = messages.firstIndex(where: { $0.id == replyID }) else { return }
        messages[i].isStreaming = false

        if let f = failure {
            let partial = builder.text
            if f.kind == .cancelled {
                if partial.isEmpty { messages.remove(at: i) } else { messages[i].text = partial + "\n\n_(cortado)_" }
                setPet(.idle)
            } else {
                if partial.isEmpty { messages.remove(at: i) } else { messages[i].text = partial }
                var text = f.message
                if let d = f.detail, !d.isEmpty { text += "\n`\(d)`" }
                append(ChatMessage(role: .system, text: text, isError: true))
                lastError = f
                if f.kind == .notInstalled { cliStatus = .missing }
                if (f.detail ?? "").localizedCaseInsensitiveContains("no conversation found") { sessionID = nil }
                OrbexBus.play(.error)
                OrbexBus.react(.worry)
                setPet(.sad, reset: 4)
            }
        } else {
            let final = builder.finalText
            messages[i].text = final.isEmpty ? "_(Claude no devolvió texto)_" : final
            messages[i].toolChips = builder.toolChips
            messages[i].costUSD = builder.result?.costUSD
            messages[i].durationMs = builder.result?.durationMs
            if let m = builder.model { messages[i].model = m }
            OrbexBus.play(.assistantMessage)
            CharacterBrain.shared.show(.happy, for: 1.6)
            setPet(.happy, reset: 2.6)
            if !isPanelVisible { OrbexBus.toast("Claude respondió", symbol: "sparkles") }
        }
        scrollTick += 1
        save()
    }

    // MARK: - Mascota y ORBEX

    private func setPet(_ mood: ClawdMood, reset after: Double? = nil) {
        moodWork?.cancel()
        if petMood != mood { petMood = mood; petMoodSince = Date() }
        guard let after else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isStreaming else { return }
                self.petMood = .idle
                self.petMoodSince = Date()
            }
        }
        moodWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: work)
    }

    private func startThinkingPulse() {
        stopThinkingPulse()
        CharacterBrain.shared.show(.thinking, for: 2)
        thinkingTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { _ in
            MainActor.assumeIsolated { CharacterBrain.shared.show(.thinking, for: 2) }
        }
    }

    private func stopThinkingPulse() {
        thinkingTimer?.invalidate()
        thinkingTimer = nil
    }

    // MARK: - Historial

    private func append(_ m: ChatMessage) {
        messages.append(m)
        if messages.count > maxHistory * 2 { messages.removeFirst(messages.count - maxHistory) }
        scrollTick += 1
    }

    private func save() {
        guard rememberConversation, !isStreaming else { return }
        let t = ChatTranscript(sessionID: sessionID, messages: messages).trimmed(max: maxHistory)
        if let data = try? t.encoded() { try? data.write(to: Self.historyURL, options: .atomic) }
    }

    private func load() {
        guard rememberConversation, let data = try? Data(contentsOf: Self.historyURL),
              let t = try? ChatTranscript.decode(data) else { return }
        let trimmed = t.trimmed(max: maxHistory)
        messages = trimmed.messages
        sessionID = trimmed.sessionID
    }
}

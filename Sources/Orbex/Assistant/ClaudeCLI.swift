import Foundation
import OrbexCore

/// Habla con el Claude Code local (`claude`) como proceso hijo, con la suscripción del usuario.
/// Sin API HTTP ni claves: todo pasa por el CLI.
///
/// Se ejecuta a través de un shell de login (`/bin/zsh -l -c 'exec … "$@"'`) para heredar el PATH
/// del usuario (node, Homebrew, nvm). El texto del usuario nunca se mete en el script del shell:
/// los argumentos van como `$@` y el prompt por stdin.
final class ClaudeCLI: @unchecked Sendable {
    static let shared = ClaudeCLI()

    private let lock = NSLock()
    private var cachedPath: String?

    /// Lugares donde suele quedar instalado `claude` si el shell de login no lo encuentra.
    static var fallbackPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.volta/bin/claude",
        ]
    }

    private init() {
        // Si el hijo se cierra antes de leer stdin, escribir no debe tirar la app abajo.
        signal(SIGPIPE, SIG_IGN)
    }

    // MARK: - Detección

    /// Busca el CLI y pregunta su versión (`claude --version`).
    func detect() async -> (path: String?, version: String?) {
        guard let path = await resolveExecutable(force: true) else { return (nil, nil) }
        let out = await Self.capture(executable: path, arguments: ["--version"], timeout: 20)
        let version = out.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.first?.isNumber == true }
        return (path, version)
    }

    /// Ruta absoluta de `claude` (con caché). `force` vuelve a buscar.
    func resolveExecutable(force: Bool = false) async -> String? {
        if !force, let p = lock.withLock({ cachedPath }), FileManager.default.isExecutableFile(atPath: p) { return p }
        var found: String?
        // 1) Lo que ve el shell de login del usuario.
        let out = await Self.capture(executable: nil, script: "command -v claude", arguments: [], timeout: 15)
        if out.status == 0 {
            found = out.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
        }
        // 2) Instalaciones conocidas (también nvm).
        if found == nil {
            found = (Self.fallbackPaths + Self.nvmCandidates()).first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        lock.withLock { cachedPath = found }
        return found
    }

    private static func nvmCandidates() -> [String] {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node")
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: base.path) else { return [] }
        return versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { base.appendingPathComponent($0).appendingPathComponent("bin/claude").path }
    }

    // MARK: - Conversación

    /// Corre una consulta y devuelve los eventos del stream. Cancelar la iteración corta el proceso.
    /// Termina con error `ClaudeFailure` si el CLI falla (no instalado, sin sesión, límite, …).
    func stream(_ request: ClaudeRequest, workingDirectory: URL) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let run = ClaudeRun(continuation: continuation)
            continuation.onTermination = { @Sendable _ in run.cancel() }
            Task.detached(priority: .userInitiated) {
                let path = await self.resolveExecutable()
                run.start(executable: path,
                          arguments: ClaudeArguments.arguments(for: request),
                          input: ClaudeArguments.standardInput(for: request),
                          environment: Self.environment(extraDir: path.map { ($0 as NSString).deletingLastPathComponent }),
                          workingDirectory: workingDirectory)
            }
        }
    }

    // MARK: - Proceso

    /// Entorno heredado + PATH ampliado + `ORBEX_INTERNAL=1` (el relé de hooks ignora estas sesiones).
    static func environment(extraDir: String?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs: [String] = []
        if let extraDir { dirs.append(extraDir) }
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin",
                 "\(home)/.bun/bin", "\(home)/.volta/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let current = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = (current + dirs).filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        env["ORBEX_INTERNAL"] = "1"
        // Si ORBEX se lanzó desde una terminal de Claude Code, el CLI creería que está anidado.
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        env.removeValue(forKey: "CLAUDE_CODE_SSE_PORT")
        return env
    }

    /// Argumentos de `/bin/zsh` para ejecutar `claude` (o una ruta absoluta) con `argv` sin interpolar nada.
    static func shellArguments(executable: String?, arguments: [String]) -> [String] {
        if let executable {
            return ["-l", "-c", "exec \"$0\" \"$@\"", executable] + arguments
        }
        return ["-l", "-c", "exec claude \"$@\"", "orbex"] + arguments
    }

    struct Captured {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    /// Corre algo corto y junta su salida (con tope de tiempo).
    static func capture(executable: String?, script: String? = nil, arguments: [String], timeout: TimeInterval) async -> Captured {
        await withCheckedContinuation { (cont: CheckedContinuation<Captured, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                if let script {
                    p.arguments = ["-l", "-c", script, "orbex"] + arguments
                } else {
                    p.arguments = shellArguments(executable: executable, arguments: arguments)
                }
                p.environment = environment(extraDir: executable.map { ($0 as NSString).deletingLastPathComponent })
                p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = FileHandle.nullDevice
                do {
                    try p.run()
                } catch {
                    cont.resume(returning: Captured(status: 127, stdout: "", stderr: error.localizedDescription))
                    return
                }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                var errData = Data()
                let errDone = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    errDone.signal()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                _ = errDone.wait(timeout: .now() + timeout)
                p.waitUntilExit()
                killer.cancel()
                cont.resume(returning: Captured(status: p.terminationStatus,
                                                stdout: String(decoding: outData, as: UTF8.self),
                                                stderr: String(decoding: errData, as: UTF8.self)))
            }
        }
    }
}

/// Una ejecución de `claude -p …` en curso.
private final class ClaudeRun: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<ClaudeStreamEvent, Error>.Continuation
    private var process: Process?
    private var parser = ClaudeStreamParser()
    private var stderrData = Data()
    private var strayLines: [String] = []
    private var lastResult: ClaudeResult?
    private var assistantError: String?
    private var cancelled = false
    private var finished = false
    private var stdoutDone = false
    private var stderrDone = false
    private var terminated = false
    private var exitCode: Int32 = 0

    init(continuation: AsyncThrowingStream<ClaudeStreamEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    func start(executable: String?, arguments: [String], input: Data,
               environment: [String: String], workingDirectory: URL) {
        if lock.withLock({ cancelled }) {
            finish(throwing: ClaudeFailure.cancelled())
            return
        }
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ClaudeCLI.shellArguments(executable: executable, arguments: arguments)
        p.environment = environment
        p.currentDirectoryURL = workingDirectory
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.terminationHandler = { [self] proc in
            let code = proc.terminationStatus
            lock.withLock {
                terminated = true
                exitCode = code
            }
            tryFinish()
            // Si algún nieto dejó la salida abierta, no esperar para siempre.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) { [self] in forceFinish() }
        }

        do {
            try p.run()
        } catch {
            finish(throwing: ClaudeFailure(kind: .notInstalled,
                                           message: ClaudeFailure.notInstalledMessage,
                                           detail: error.localizedDescription))
            return
        }
        lock.withLock { process = p }

        // Prompt por stdin (en segundo plano: un prompt grande puede llenar el buffer del pipe).
        DispatchQueue.global(qos: .userInitiated).async {
            let h = inPipe.fileHandleForWriting
            do { try h.write(contentsOf: input) } catch {}
            try? h.close()
        }

        // stdout: línea a línea al parser.
        let outHandle = outPipe.fileHandleForReading
        Thread.detachNewThread { [self] in
            while true {
                let data = outHandle.availableData
                if data.isEmpty { break }
                let events = lock.withLock { parser.feed(data) }
                deliver(events)
            }
            let rest = lock.withLock { parser.finish() }
            deliver(rest)
            lock.withLock { stdoutDone = true }
            tryFinish()
        }

        // stderr: se junta para explicar errores (con tope).
        let errHandle = errPipe.fileHandleForReading
        Thread.detachNewThread { [self] in
            while true {
                let data = errHandle.availableData
                if data.isEmpty { break }
                lock.withLock {
                    if stderrData.count < 64 * 1024 { stderrData.append(data) }
                }
            }
            lock.withLock { stderrDone = true }
            tryFinish()
        }
    }

    /// Corta la respuesta: primero SIGINT (Claude Code cierra el turno prolijo), después SIGTERM y SIGKILL.
    func cancel() {
        let p: Process? = lock.withLock {
            guard !finished else { return nil }
            cancelled = true
            return process
        }
        guard let p, p.isRunning else { return }
        p.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if p.isRunning { p.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }

    // MARK: - Internos

    private func deliver(_ events: [ClaudeStreamEvent]) {
        guard !events.isEmpty else { return }
        let stop: Bool = lock.withLock {
            for e in events {
                switch e {
                case .result(let r): lastResult = r
                case .assistant(let m): if let err = m.error { assistantError = err }
                case .nonJSON(let line):
                    strayLines.append(line)
                    if strayLines.count > 30 { strayLines.removeFirst() }
                default: break
                }
            }
            return finished
        }
        guard !stop else { return }
        for e in events { continuation.yield(e) }
    }

    private func tryFinish() {
        let ready: Bool = lock.withLock {
            guard !finished, terminated else { return false }
            let sawResult = lastResult != nil
            return (stdoutDone || sawResult) && (stderrDone || sawResult)
        }
        if ready { finishFromState() }
    }

    private func forceFinish() {
        let pending = lock.withLock { !finished }
        if pending { finishFromState() }
    }

    private func finishFromState() {
        let snapshot: (cancelled: Bool, result: ClaudeResult?, assistantError: String?, stderr: String, stray: [String], code: Int32) =
            lock.withLock {
                (cancelled, lastResult, assistantError, String(decoding: stderrData, as: UTF8.self), strayLines, exitCode)
            }
        if snapshot.cancelled {
            finish(throwing: ClaudeFailure.cancelled())
            return
        }
        if let r = snapshot.result, r.succeeded, snapshot.assistantError == nil {
            finish(throwing: nil)
            return
        }
        let failedResult = snapshot.result.map { !$0.succeeded } ?? false
        if failedResult || snapshot.assistantError != nil || snapshot.code != 0 {
            let failure = ClaudeErrorClassifier.classify(assistantError: snapshot.assistantError,
                                                         resultText: snapshot.result?.text,
                                                         errors: snapshot.result?.errors ?? [],
                                                         stderr: snapshot.stderr,
                                                         strayLines: snapshot.stray,
                                                         exitCode: snapshot.code)
            finish(throwing: failure)
            return
        }
        finish(throwing: nil)
    }

    private func finish(throwing error: Error?) {
        let first: Bool = lock.withLock {
            guard !finished else { return false }
            finished = true
            process = nil
            return true
        }
        guard first else { return }
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

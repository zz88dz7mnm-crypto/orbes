import Foundation

/// Habla con el helper de Kokoro (`scripts/orbex-tts.py`) que queda vivo leyendo pedidos JSON por
/// stdin y devolviendo la ruta de un WAV por stdout. Todo corre en una cola propia: nunca en el hilo
/// principal. Si el helper se cae o no contesta, lo reinicia una vez; si vuelve a fallar, tira error
/// (y `OrbiVoice` pasa al motor siguiente).
///
/// Protocolo y manejo de pipelines inspirados en OpenJarvis (`speech/kokoro_tts.py`, Apache-2.0).
final class KokoroEngine: @unchecked Sendable {
    static let shared = KokoroEngine()

    enum Failure: LocalizedError {
        case notInstalled
        case helperDied(String)
        case timeout
        case synthesis(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Kokoro no está instalado (scripts/instalar-voz.sh)."
            case .helperDied(let why): return "El helper de voz se cerró: \(why)"
            case .timeout: return "El helper de voz no contestó a tiempo."
            case .synthesis(let why): return "Kokoro no pudo generar el audio: \(why)"
            }
        }
    }

    private let queue = DispatchQueue(label: "orbex.voice.kokoro", qos: .userInitiated)
    // Estado del proceso: solo se toca desde `queue`.
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var buffer = Data()
    private var idleTimer: DispatchWorkItem?

    /// Sin pedidos durante este tiempo, el helper se cierra (libera ~400 MB de RAM).
    private let idleShutdown: TimeInterval = 15 * 60

    private init() {}

    /// Genera el audio (WAV) de `text`. Lanza el helper si hace falta.
    func synthesize(_ text: String, voice: String, speed: Double) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            queue.async {
                do {
                    cont.resume(returning: try self.synthesizeWithRetry(text, voice: voice, speed: speed))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Arranca el helper de antemano (carga el modelo) para que la primera respuesta sea rápida.
    func prewarm(voice: String) {
        queue.async {
            guard OrbiVoicePaths.kokoroInstalled else { return }
            _ = try? self.ensureRunning(voice: voice)
            self.scheduleIdleShutdown()
        }
    }

    /// Cierra el helper (al salir de la app o si se desinstala).
    func shutdown() {
        queue.async { self.kill() }
    }

    /// Versión síncrona para `applicationWillTerminate`.
    func shutdownNow() {
        queue.sync { self.kill() }
    }

    // MARK: - En la cola

    private func synthesizeWithRetry(_ text: String, voice: String, speed: Double) throws -> Data {
        guard OrbiVoicePaths.kokoroInstalled else { throw Failure.notInstalled }
        defer { scheduleIdleShutdown() }
        do {
            return try request(text, voice: voice, speed: speed)
        } catch Failure.synthesis(let why) {
            throw Failure.synthesis(why) // error de Kokoro con este texto: reiniciar no sirve
        } catch {
            NSLog("ORBEX voz: el helper falló (\(error.localizedDescription)); reintento una vez")
            kill()
            return try request(text, voice: voice, speed: speed)
        }
    }

    private func request(_ text: String, voice: String, speed: Double) throws -> Data {
        try ensureRunning(voice: voice)
        let payload: [String: Any] = ["text": text, "voice": voice, "speed": speed]
        var line = try JSONSerialization.data(withJSONObject: payload)
        line.append(0x0A)
        do {
            try stdin?.write(contentsOf: line)
        } catch {
            throw Failure.helperDied("no se pudo escribir (\(error.localizedDescription))")
        }
        // Frases largas en CPU pueden tardar; más de 30 s es que algo se trabó.
        let reply = try readReply(timeout: 30)
        guard reply["ok"] as? Bool == true, let path = reply["path"] as? String else {
            throw Failure.synthesis(reply["error"] as? String ?? "respuesta inválida")
        }
        let url = URL(fileURLWithPath: path)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            throw Failure.synthesis("no se encontró el audio")
        }
        return data
    }

    private func ensureRunning(voice: String) throws {
        if let process, process.isRunning { return }
        kill()
        guard let helper = OrbiVoicePaths.helper else { throw Failure.notInstalled }

        let fm = FileManager.default
        try? fm.createDirectory(at: OrbiVoicePaths.tempAudio, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = OrbiVoicePaths.python
        p.arguments = [helper.path, "--outdir", OrbiVoicePaths.tempAudio.path, "--voice", voice]
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        env["TOKENIZERS_PARALLELISM"] = "false"
        p.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        // Lo que imprima Kokoro/torch va a un log (así el pipe nunca se llena).
        fm.createFile(atPath: OrbiVoicePaths.log.path, contents: nil)
        p.standardError = (try? FileHandle(forWritingTo: OrbiVoicePaths.log)) ?? FileHandle.nullDevice

        do {
            try p.run()
        } catch {
            throw Failure.helperDied("no arrancó (\(error.localizedDescription))")
        }
        process = p
        stdin = inPipe.fileHandleForWriting
        stdout = outPipe.fileHandleForReading
        buffer = Data()

        // Cargar el modelo puede tardar la primera vez.
        let hello = try readReply(timeout: 90)
        guard hello["ready"] as? Bool == true else {
            let why = hello["error"] as? String ?? "no quedó listo"
            kill()
            throw Failure.helperDied(why)
        }
    }

    /// Lee una línea JSON del helper. Si pasa `timeout`, mata el proceso (y así se corta la lectura).
    private func readReply(timeout: TimeInterval) throws -> [String: Any] {
        guard let stdout, let process else { throw Failure.helperDied("sin proceso") }
        var timedOut = false
        let lock = NSLock()
        let watchdog = DispatchWorkItem {
            lock.lock(); timedOut = true; lock.unlock()
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer { watchdog.cancel() }

        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                guard !lineData.isEmpty else { continue }
                if let obj = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any] {
                    return obj
                }
                continue // basura en stdout: se ignora
            }
            let chunk = stdout.availableData
            if chunk.isEmpty {
                lock.lock(); let late = timedOut; lock.unlock()
                kill()
                throw late ? Failure.timeout : Failure.helperDied("se cerró (ver \(OrbiVoicePaths.log.path))")
            }
            buffer.append(chunk)
        }
    }

    private func kill() {
        idleTimer?.cancel()
        idleTimer = nil
        try? stdin?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil
        stdin = nil
        stdout = nil
        buffer = Data()
    }

    private func scheduleIdleShutdown() {
        idleTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.kill() }
        idleTimer = item
        queue.asyncAfter(deadline: .now() + idleShutdown, execute: item)
    }
}

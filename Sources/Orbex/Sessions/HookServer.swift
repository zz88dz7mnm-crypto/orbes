import Foundation
import Darwin
import OrbexCore

/// Servidor del socket Unix donde el relé `orbex-hook` manda los eventos de
/// Claude Code / Codex (una línea JSON por evento).
///
/// - La E/S del socket corre en hilos de fondo; los callbacks se llaman SIEMPRE en el hilo principal.
/// - `PermissionRequest`: la conexión queda abierta hasta que la app responde
///   (`respond(true/false, mensaje)`) o hasta 105 s (`respond(nil, _)` automático = sin decisión,
///   Claude Code pregunta en la terminal). Se responde una sola vez; las demás llamadas se ignoran.
/// - Los `PermissionRequest` van SOLO a `onPermissionRequest` (si no hay nadie escuchando,
///   van a `onEvent` y se cierran sin respuesta). El resto de los eventos van a `onEvent`.
final class HookServer: @unchecked Sendable {
    static let shared = HookServer()

    /// Cada evento recibido (hilo principal).
    var onEvent: ((HookEvent) -> Void)?
    /// Pedido de permiso (hilo principal). Llamar `respond` una vez: `true` permite,
    /// `false` deniega (con mensaje opcional), `nil` cierra sin decidir.
    var onPermissionRequest: ((HookEvent, @escaping (Bool?, String?) -> Void) -> Void)?

    /// Tiempo máximo que se retiene un pedido de permiso (el relé espera 110 s).
    static let permissionTimeout: TimeInterval = 105
    private static let maxLineBytes = 16 * 1024 * 1024

    private let lock = NSLock()
    private var started = false

    private init() {}

    func start() {
        lock.lock()
        if started { lock.unlock(); return }
        started = true
        lock.unlock()

        signal(SIGPIPE, SIG_IGN)
        installRelay()
        let path = AppPaths.socketPath
        let thread = Thread { [weak self] in self?.serve(path: path) }
        thread.name = "ORBEX.HookServer"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    // MARK: - Relé

    /// Copia el relé que viene en la app a una ruta estable (la que figura en `settings.json`).
    private func installRelay() {
        guard let bundled = AppPaths.bundledHookBinary else { return }
        let fm = FileManager.default
        let dest = AppPaths.hookBinaryPath
        if fm.fileExists(atPath: dest), fm.contentsEqual(atPath: bundled.path, andPath: dest) {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest)
            return
        }
        let temp = dest + ".nuevo"
        try? fm.removeItem(atPath: temp)
        do {
            try fm.copyItem(atPath: bundled.path, toPath: temp)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp)
            // rename() es atómico: un hook que esté corriendo sigue con el binario viejo.
            if rename(temp, dest) != 0 {
                try? fm.removeItem(atPath: dest)
                try fm.moveItem(atPath: temp, toPath: dest)
            }
        } catch {
            try? fm.removeItem(atPath: temp)
            NSLog("ORBEX: no se pudo copiar orbex-hook: \(error.localizedDescription)")
        }
    }

    // MARK: - Socket

    private func serve(path: String) {
        unlink(path)   // socket viejo de una ejecución anterior
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { NSLog("ORBEX: socket() falló (\(errno))"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            NSLog("ORBEX: ruta del socket demasiado larga: \(path)")
            close(fd)
            return
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, length) }
        }
        guard bound == 0 else { NSLog("ORBEX: bind() falló (\(errno))"); close(fd); return }
        chmod(path, 0o600)   // solo el usuario actual
        guard Darwin.listen(fd, 32) == 0 else { NSLog("ORBEX: listen() falló (\(errno))"); close(fd); return }

        while true {
            let client = Darwin.accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == ECONNABORTED { continue }
                usleep(200_000)
                continue
            }
            var one: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            Self.setTimeout(client, SO_RCVTIMEO, seconds: 5)
            Self.setTimeout(client, SO_SNDTIMEO, seconds: 2)
            let worker = Thread { [weak self] in self?.handle(client) }
            worker.name = "ORBEX.HookClient"
            worker.start()
        }
    }

    /// Lee líneas JSON del cliente hasta que cierre. Un PermissionRequest deja la conexión en espera.
    private func handle(_ fd: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            // Procesar las líneas completas que haya.
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer = Data(buffer[buffer.index(after: nl)...])
                guard !line.isEmpty, let event = HookEvent.parse(Data(line)) else { continue }
                if event.kind == .permissionRequest {
                    waitForDecision(fd, event: event)   // se encarga de cerrar
                    return
                }
                deliver(event)
            }
            let n = read(fd, &chunk, chunk.count)
            if n > 0 {
                buffer.append(contentsOf: chunk[0..<n])
                if buffer.count > Self.maxLineBytes { break }
                continue
            }
            if n < 0 && errno == EINTR { continue }
            // Fin (o tiempo vencido): una última línea sin salto también vale.
            if !buffer.isEmpty, let event = HookEvent.parse(buffer) {
                if event.kind == .permissionRequest {
                    waitForDecision(fd, event: event)
                    return
                }
                deliver(event)
            }
            break
        }
        close(fd)
    }

    private func deliver(_ event: HookEvent) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onEvent?(event) }
        }
    }

    private func waitForDecision(_ fd: Int32, event: HookEvent) {
        let pending = PendingDecision()

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let handler = self.onPermissionRequest else {
                    self?.onEvent?(event)
                    pending.finish(nil, nil)
                    return
                }
                handler(event) { allow, message in pending.finish(allow, message) }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.permissionTimeout) {
            pending.finish(nil, nil)
        }

        // Este hilo es el único que toca el fd: escribe la decisión cuando llega y lo cierra.
        // Si el relé se va antes (se respondió en la terminal o Claude Code lo cortó),
        // el pedido se da por cerrado sin respuesta.
        while true {
            if let decision = pending.decision {
                if let allow = decision.allow {
                    Self.writeAll(fd, PermissionReply.json(allow: allow, message: decision.message) + "\n")
                }
                break
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let r = poll(&pfd, 1, 100)
            if r > 0 {
                var byte: UInt8 = 0
                let n = recv(fd, &byte, 1, 0)
                if n == 0 || (n < 0 && errno != EINTR && errno != EAGAIN) {
                    pending.finish(nil, nil)
                }
            } else if r < 0 && errno != EINTR {
                pending.finish(nil, nil)
            }
        }
        close(fd)
    }

    private static func writeAll(_ fd: Int32, _ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let n = write(fd, base + sent, raw.count - sent)
                if n > 0 { sent += n; continue }
                if n < 0 && errno == EINTR { continue }
                return
            }
        }
    }

    fileprivate static func setTimeout(_ fd: Int32, _ option: Int32, seconds: Double) {
        let whole = Int(seconds)
        var tv = timeval(tv_sec: whole, tv_usec: Int32((seconds - Double(whole)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, option, &tv, socklen_t(MemoryLayout<timeval>.size))
    }
}

/// Decisión de un pedido de permiso: se fija una sola vez (la primera gana).
/// La escribe y cierra el hilo que vigila la conexión, así nadie más toca el fd.
private final class PendingDecision: @unchecked Sendable {
    struct Decision { let allow: Bool?; let message: String? }

    private let lock = NSLock()
    private var value: Decision?

    var decision: Decision? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func finish(_ allow: Bool?, _ message: String?) {
        lock.lock(); defer { lock.unlock() }
        if value == nil { value = Decision(allow: allow, message: message) }
    }
}

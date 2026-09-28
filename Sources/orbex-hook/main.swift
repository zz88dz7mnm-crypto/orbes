// orbex-hook — relé de hooks de Claude Code / Codex hacia ORBEX.
//
// Claude Code corre este programa en cada hook con el evento en JSON por stdin.
// Lo reenviamos a ORBEX por el socket Unix ~/Library/Application Support/ORBEX/orbex.sock
// (una línea JSON). Para `PermissionRequest` esperamos la decisión del usuario y la
// imprimimos en stdout tal cual la espera Claude Code:
//   {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
//
// REGLA DE ORO: nunca bloquear ni romper a Claude Code. Si ORBEX no está abierto, falta el
// socket, algo falla o se vence el tiempo: no imprimimos nada y salimos con 0 (Claude Code
// sigue normal y pregunta en la terminal). Nunca denegamos por defecto.
//
// Las sesiones del asistente de ORBEX (ORBEX_INTERNAL=1) se ignoran.
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

let env = ProcessInfo.processInfo.environment
if env["ORBEX_INTERNAL"] == "1" { exit(0) }

let isCodex = CommandLine.arguments.contains("--codex")

// MARK: - Leer el evento

let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty,
      var payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else {
    exit(0)
}

// MARK: - Contexto de la terminal (para "saltar a la terminal")

/// Sube por los procesos padres hasta encontrar una terminal real (p. ej. ttys003).
func findTTY() -> String? {
    var pid = getppid()
    for _ in 0..<8 {
        guard pid > 1 else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "ppid=,tty=", "-p", String(pid)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        guard parts.count >= 2 else { return nil }
        let tty = parts[1]
        if tty != "??" && tty != "?" && !tty.isEmpty {
            return tty.hasPrefix("/dev/") ? tty : "/dev/" + tty
        }
        guard let parent = Int32(parts[0]) else { return nil }
        pid = parent
    }
    return nil
}

let extras: [(String, String?)] = [
    ("term_program", env["TERM_PROGRAM"]),
    ("iterm_session_id", env["ITERM_SESSION_ID"]),
    ("term_session_id", env["TERM_SESSION_ID"]),
    ("bundle_id", env["__CFBundleIdentifier"]),
    ("tty", findTTY()),
    ("cwd", FileManager.default.currentDirectoryPath),
]
for (key, value) in extras {
    if let value, !value.isEmpty, payload[key] == nil { payload[key] = value }
}
payload["source"] = isCodex ? "codex" : "claude"
payload["ppid"] = Int(getppid())

let eventName = (payload["hook_event_name"] as? String) ?? ""
let waitsForDecision = eventName == "PermissionRequest"

guard var line = try? JSONSerialization.data(withJSONObject: payload) else { exit(0) }
line.append(0x0A)

// MARK: - Socket Unix

let socketPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ORBEX/orbex.sock").path

func connectSocket(path socketPath: String, timeout seconds: Int) -> Int32? {
    #if canImport(Darwin)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    #else
    let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
    #endif
    guard fd >= 0 else { return nil }

    var tv = timeval(tv_sec: seconds, tv_usec: seconds == 0 ? 300_000 : 0)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    #if canImport(Darwin)
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    #endif

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(socketPath.utf8)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard pathBytes.count < capacity else { close(fd); return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        for (i, b) in pathBytes.enumerated() { raw[i] = b }
        raw[pathBytes.count] = 0
    }
    let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else { close(fd); return nil }
    return fd
}

func sendAll(_ fd: Int32, _ data: Data) -> Bool {
    var sent = 0
    let total = data.count
    return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
        guard let base = raw.baseAddress else { return false }
        while sent < total {
            let n = send(fd, base + sent, total - sent, 0)
            if n <= 0 { return false }
            sent += n
        }
        return true
    }
}

/// Lee una línea (hasta "\n" o cierre). `nil` si se venció el tiempo o no llegó nada.
func readLine(_ fd: Int32) -> String? {
    var buffer = [UInt8](repeating: 0, count: 4096)
    var collected = Data()
    while true {
        let n = recv(fd, &buffer, buffer.count, 0)
        if n <= 0 { break }
        collected.append(contentsOf: buffer[0..<n])
        if buffer[0..<n].contains(0x0A) { break }
        if collected.count > 1_000_000 { break }
    }
    guard !collected.isEmpty,
          let text = String(data: collected, encoding: .utf8)?
            .split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init),
          !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    return text
}

// Permisos: hasta 110 s (el instalador le da 120 s de timeout al hook). Resto: 0,3 s.
guard let fd = connectSocket(path: socketPath, timeout: waitsForDecision ? 110 : 0) else { exit(0) }

if sendAll(fd, line), waitsForDecision, let reply = readLine(fd), reply.contains("hookSpecificOutput") {
    FileHandle.standardOutput.write(Data((reply + "\n").utf8))
}
close(fd)
exit(0)

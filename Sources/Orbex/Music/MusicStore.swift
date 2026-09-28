import AppKit
import OrbexCore

/// Canción que está sonando (Spotify o Música). No se guarda historial.
struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var position: Double   // segundos
    var duration: Double   // segundos
    var source: String     // "Spotify" | "Música"
}

/// Lee "ahora suena" de la app de escritorio de Spotify (o de Música) por AppleScript.
/// Sólo consulta cada 2 s mientras alguna de las dos está abierta; nunca las abre.
@MainActor
final class MusicStore: ObservableObject {
    static let shared = MusicStore()

    static let spotifyID = "com.spotify.client"
    static let musicID = "com.apple.Music"

    @Published private(set) var track: NowPlaying?
    @Published private(set) var isPlaying = false
    @Published private(set) var spotifyRunning = false
    @Published private(set) var musicRunning = false
    /// Momento de la última lectura (para interpolar la barra de progreso).
    private(set) var fetchedAt = Date()

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var polledOnce = false
    private var tintOn = false
    private let queue = DispatchQueue(label: "orbex.music.applescript", qos: .utility)

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshRunning() } }
            })
        }
        refreshRunning()
    }

    /// Posición estimada ahora (interpola entre lecturas mientras suena).
    func livePosition(at date: Date = Date()) -> Double {
        guard let t = track else { return 0 }
        let p = t.position + (isPlaying ? date.timeIntervalSince(fetchedAt) : 0)
        return min(max(p, 0), max(t.duration, 0))
    }

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    // MARK: - Apps abiertas

    private func refreshRunning() {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        spotifyRunning = ids.contains(Self.spotifyID)
        musicRunning = ids.contains(Self.musicID)
        if spotifyRunning || musicRunning {
            if timer == nil {
                let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.poll() } }
                }
                t.tolerance = 0.4
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
            poll()
        } else {
            timer?.invalidate(); timer = nil
            apply(nil, playing: false)
        }
    }

    // MARK: - Lectura

    private func poll() {
        let sp = spotifyRunning, mu = musicRunning
        queue.async { [weak self] in
            var best: (NowPlaying, Bool)?
            if sp, let r = Self.read(Self.spotifyScript, source: "Spotify", msDuration: true) { best = r }
            if mu, best?.1 != true, let r = Self.read(Self.musicScript, source: "Música", msDuration: false),
               r.1 || best == nil { best = r }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(best?.0, playing: best?.1 ?? false) }
            }
        }
    }

    private func apply(_ new: NowPlaying?, playing: Bool) {
        let changed = new.map { "\($0.title)|\($0.artist)" } != track.map { "\($0.title)|\($0.artist)" }
        if changed, new != nil, playing, polledOnce { OrbexBus.play(.newSong) }
        polledOnce = true
        fetchedAt = Date()
        if track != new { track = new }
        if isPlaying != playing { isPlaying = playing }
        if AppModel.shared.isPlayingMusic != playing { AppModel.shared.isPlayingMusic = playing }
        let wantTint = playing && new?.source == "Spotify"
        if wantTint != tintOn {
            tintOn = wantTint
            OrbexBus.requestTint(wantTint ? .green : nil, source: "spotify")
        }
    }

    // MARK: - Controles

    private func command(_ verb: String) {
        let id: String?
        if let s = track?.source { id = s == "Spotify" ? Self.spotifyID : Self.musicID }
        else { id = spotifyRunning ? Self.spotifyID : (musicRunning ? Self.musicID : nil) }
        guard let id else { return }
        let src = "if application id \"\(id)\" is running then\ntell application id \"\(id)\" to \(verb)\nend if"
        queue.async { [weak self] in
            _ = Self.run(src)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                MainActor.assumeIsolated { self?.poll() }
            }
        }
    }

    // MARK: - AppleScript (cola de fondo)

    private nonisolated static let spotifyScript = """
    if application id "com.spotify.client" is running then
      tell application id "com.spotify.client"
        try
          if player state is stopped then return "stopped"
          if player state is playing then
            set s to "playing"
          else
            set s to "paused"
          end if
          set t to current track
          return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (artwork url of t) & linefeed & (player position as string) & linefeed & ((duration of t) as string)
        on error
          return "stopped"
        end try
      end tell
    end if
    return "stopped"
    """

    private nonisolated static let musicScript = """
    if application id "com.apple.Music" is running then
      tell application id "com.apple.Music"
        try
          if player state is stopped then return "stopped"
          if player state is playing then
            set s to "playing"
          else
            set s to "paused"
          end if
          set t to current track
          return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & "" & linefeed & (player position as string) & linefeed & ((duration of t) as string)
        on error
          return "stopped"
        end try
      end tell
    end if
    return "stopped"
    """

    private nonisolated static func run(_ source: String) -> String? {
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let out = script.executeAndReturnError(&err)
        return err == nil ? out.stringValue : nil
    }

    private nonisolated static func read(_ source: String, source name: String, msDuration: Bool) -> (NowPlaying, Bool)? {
        guard let out = run(source), out != "stopped" else { return nil }
        let f = out.components(separatedBy: "\n")
        guard f.count >= 7, !f[1].isEmpty else { return nil }
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0 }
        let dur = num(f[6]) / (msDuration ? 1000 : 1)
        let np = NowPlaying(title: f[1], artist: f[2], album: f[3],
                            artworkURL: f[4].isEmpty ? nil : URL(string: f[4]),
                            position: num(f[5]), duration: dur, source: name)
        return (np, f[0] == "playing")
    }
}

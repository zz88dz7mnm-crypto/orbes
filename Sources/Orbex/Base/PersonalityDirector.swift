import AppKit
import Combine
import CoreGraphics
import OrbexCore

extension Notification.Name {
    /// ORBEX echa un vistazo hacia algún lado.
    ///
    /// `userInfo`:
    /// - `"dx"` (`CGFloat`): −1 izquierda … 1 derecha.
    /// - `"dy"` (`CGFloat`): −1 arriba … 1 abajo (coordenadas de pantalla, y hacia abajo).
    /// - `"duration"` (`Double`): segundos que sostiene la mirada; `0` = sostener hasta el próximo
    ///   vistazo (así se usa para "mirar el teclado" mientras tipeás, y `dx = dy = 0` para soltarla).
    ///
    /// Al vencer un vistazo con duración, el motor debería volver a la última mirada sostenida.
    /// La postea `PersonalityDirector`; el motor (`BotEngine`/`BotCanvasView`) la va a escuchar en
    /// otra fase (hoy nadie la consume: es inocua).
    static let personalityGlance = Notification.Name("orbex.personality.glance")
}

/// Director de la personalidad: observa el sistema (input reciente, teclas, cambio de app) y aplica
/// lo que decide `PersonalityBrain` (OrbexCore): texto del encabezado, parpadeos, emotes y miradas.
///
/// Sin permisos: `CGEventSource.secondsSinceLastEventType` solo dice *cuándo* hubo input, no qué.
/// Bajo consumo: un timer de un disparo que se re-arma cada 2 s (5 s con la isla oculta, 8 s en
/// modo de bajo consumo) con tolerancia amplia. Nada a 60 Hz.
@MainActor
final class PersonalityDirector: ObservableObject {
    static let shared = PersonalityDirector()

    /// Frase actual para el encabezado de la isla.
    @Published private(set) var headerLine: String = ""

    private static let stateKey = "orbex.personality.state"

    private var brain: PersonalityBrain
    private var lastSaved: PersonalityRecord
    private var timer: Timer?
    private var appObserver: NSObjectProtocol?
    private var running = false

    private init() {
        var record = PersonalityRecord()
        if let data = UserDefaults.standard.data(forKey: Self.stateKey),
           let saved = try? JSONDecoder().decode(PersonalityRecord.self, from: data) {
            record = saved
        }
        lastSaved = record
        brain = PersonalityBrain(record: record)
    }

    // MARK: - Ciclo de vida

    /// Arranca la observación. Idempotente.
    func start() {
        guard !running else { return }
        running = true
        brain.name = currentFirstName()
        apply(brain.start(now: Date()))
        persistIfNeeded()

        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.appDidActivate(app)
            }
        }
        scheduleNext()
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        if let o = appObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        appObserver = nil
        persistIfNeeded()
    }

    // MARK: - Muestreo

    private func scheduleNext() {
        guard running else { return }
        let model = AppModel.shared
        let interval: TimeInterval
        if model.settings.lowPowerMode || model.lowPower {
            interval = 8
        } else if model.islandState == .hidden {
            interval = 5
        } else {
            interval = 2
        }
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
                self?.scheduleNext()
            }
        }
        t.tolerance = interval * 0.4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        brain.name = currentFirstName()
        let anyInput = CGEventType(rawValue: UInt32.max)!   // kCGAnyInputEventType
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        apply(brain.tick(now: Date(), idleSeconds: idle, keyIdleSeconds: keyIdle))
        persistIfNeeded()
    }

    // MARK: - Cambio de app

    private func appDidActivate(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        apply(brain.appActivated(now: Date(), toward: gaze(towardWindowOf: app.processIdentifier)))
    }

    /// Dirección desde el notch (arriba al centro de la pantalla principal) hacia la ventana principal
    /// de la app. Solo usa los límites de la ventana (no hace falta permiso de grabación de pantalla).
    private func gaze(towardWindowOf pid: pid_t) -> GazeVector? {
        guard let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  rect.width > 40, rect.height > 40 else { continue }
            // Coordenadas globales de CG: origen arriba a la izquierda de la pantalla principal.
            return GazeVector.toward(originX: Double(primary.frame.width / 2), originY: 0,
                                     targetX: Double(rect.midX), targetY: Double(rect.midY),
                                     reach: Double(max(primary.frame.width / 2, 1)))
        }
        return nil
    }

    // MARK: - Aplicar

    private func apply(_ events: [PersonalityEvent]) {
        let nc = NotificationCenter.default
        let calm = AppModel.shared.effectiveReduceMotion
        for event in events {
            switch event {
            case .header(let line):
                headerLine = line
            case .emote(let e):
                if let emote = BotEmote(rawValue: e.rawValue) {
                    nc.post(name: .triggerEmote, object: emote)
                }
            case .blink:
                nc.post(name: .botBlink, object: nil)
            case .eyeScale(let s):
                // Con "reducir movimiento" no cambiamos la escala de ojos (siempre se puede volver a 1).
                if !calm || s == 1 { nc.post(name: .botSetTgEs, object: CGFloat(s)) }
            case .glance(let g, let duration):
                if calm && !(g == .ahead) { continue }
                nc.post(name: .personalityGlance, object: nil,
                        userInfo: ["dx": CGFloat(g.dx), "dy": CGFloat(g.dy), "duration": duration])
            }
        }
    }

    // MARK: - Utilidades

    private func currentFirstName() -> String {
        let configured = AppModel.shared.settings.userName
        let full = configured.trimmingCharacters(in: .whitespaces).isEmpty ? NSFullUserName() : configured
        return PersonalityPhrases.firstName(from: full)
    }

    private func persistIfNeeded() {
        guard brain.record != lastSaved,
              let data = try? JSONEncoder().encode(brain.record) else { return }
        UserDefaults.standard.set(data, forKey: Self.stateKey)
        lastSaved = brain.record
    }
}

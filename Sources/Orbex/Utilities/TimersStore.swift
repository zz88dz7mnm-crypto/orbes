import Foundation
import UserNotifications
import OrbexCore

/// Timers, pomodoro y cronómetro de la app. Guarda el motor en `timers.json` (sobrevive a reinicios).
@MainActor
final class TimersStore: ObservableObject {
    static let shared = TimersStore()

    @Published private(set) var engine = TimerEngine()
    /// Línea corta para la isla ("⏱ Pizza 12:30"). Vacía si no hay nada.
    @Published private(set) var statusLine: String = ""
    /// Hora del último tick (para refrescar las vistas).
    @Published private(set) var now = Date()

    static let defaultMinutesKey = "orbex.utilities.defaultTimerMinutes"
    static let soundOnFinishKey = "orbex.utilities.timerSound"
    static let notificationsKey = "orbex.utilities.timerNotifications"

    private let fileURL = AppPaths.dataFile("timers.json")
    private var ticker: Timer?
    private var askedNotifications = false

    private init() {
        UserDefaults.standard.register(defaults: [
            Self.defaultMinutesKey: 5,
            Self.soundOnFinishKey: true,
            Self.notificationsKey: true,
        ])
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(TimerEngine.self, from: data) {
            engine = saved
        }
        tick()
    }

    // MARK: - Ajustes

    var defaultMinutes: Int {
        max(1, UserDefaults.standard.integer(forKey: Self.defaultMinutesKey))
    }

    private var soundOnFinish: Bool { UserDefaults.standard.bool(forKey: Self.soundOnFinishKey) }
    private var notificationsOn: Bool { UserDefaults.standard.bool(forKey: Self.notificationsKey) }

    // MARK: - Consultas

    var timers: [OrbexTimer] { engine.timers }
    var stopwatch: Stopwatch { engine.stopwatch }
    var anyRunning: Bool { engine.anyRunning }
    var anyRinging: Bool { engine.anyRinging }

    // MARK: - Acciones

    /// Nuevo timer. `seconds <= 0` usa los minutos por defecto.
    @discardableResult
    func startTimer(seconds: TimeInterval, label: String? = nil) -> OrbexTimer {
        let secs = seconds > 0 ? seconds : TimeInterval(defaultMinutes * 60)
        let t = engine.add(duration: secs, label: label, now: Date())
        OrbexBus.play(.timerStart)
        scheduleNotification(for: t)
        changed()
        return t
    }

    @discardableResult
    func startPomodoro() -> OrbexTimer {
        let t = engine.startPomodoro(Pomodoro(), now: Date())
        OrbexBus.play(.timerStart)
        scheduleNotification(for: t)
        changed()
        return t
    }

    func togglePause(_ id: UUID) {
        engine.togglePause(id, now: Date())
        if let t = engine.timer(id) {
            if t.isRunning { scheduleNotification(for: t) } else { cancelNotification(id) }
        }
        OrbexBus.play(.tap)
        changed()
    }

    func addTime(_ id: UUID, seconds: TimeInterval) {
        engine.addTime(id, seconds: seconds, now: Date())
        if let t = engine.timer(id), t.isRunning { scheduleNotification(for: t) }
        changed()
    }

    func stop(_ id: UUID) {
        engine.remove(id)
        cancelNotification(id)
        OrbexBus.play(.close)
        changed()
    }

    func dismissFinished() {
        engine.dismissFinished()
        changed()
    }

    // Cronómetro

    func toggleStopwatch() {
        let wasRunning = engine.stopwatch.isRunning
        engine.stopwatch.toggle(at: Date())
        OrbexBus.play(wasRunning ? .tap : .timerStart)
        changed()
    }

    func lap() {
        guard engine.stopwatch.lap(at: Date()) != nil else { return }
        OrbexBus.play(.lap)
        changed()
    }

    func resetStopwatch() {
        engine.stopwatch.reset()
        changed()
    }

    // MARK: - Tick

    private func tick() {
        let date = Date()
        now = date
        let events = engine.tick(now: date)
        for event in events { handle(event, now: date) }
        if !events.isEmpty { save() }
        publish()
        updateTicker()
    }

    private func handle(_ event: TimerEvent, now: Date) {
        switch event {
        case .finished(let id, let label, let at):
            cancelNotification(id)
            // Si terminó hace mucho (app cerrada), no hacer ruido.
            guard now.timeIntervalSince(at) < 60 else { return }
            if soundOnFinish { OrbexBus.play(.timerDone) }
            OrbexBus.react(.celebrate)
            OrbexBus.toast("¡Terminó \(label)!", symbol: "timer")
        case .pomodoroPhase(let id, let phase, let at):
            if let t = engine.timer(id) { scheduleNotification(for: t) }
            guard now.timeIntervalSince(at) < 60 else { return }
            if soundOnFinish { OrbexBus.play(.timerDone) }
            OrbexBus.react(phase == .focus ? .greet : .celebrate)
            OrbexBus.toast(phase == .focus ? "¡A concentrarse!" : "¡A descansar!",
                           symbol: phase == .focus ? "brain.head.profile" : "cup.and.saucer")
        }
    }

    private func changed() {
        save()
        tick()
    }

    private func publish() {
        let line = engine.statusLine(at: now)
        if statusLine != line { statusLine = line }
        let running = engine.anyRunning
        let ringing = engine.anyRinging
        OrbexBus.setActivity(source: "timers", working: running, attention: ringing)
        if AppModel.shared.hasTimerRunning != running { AppModel.shared.hasTimerRunning = running }
    }

    /// El tick de 0,5 s corre solo mientras hay algo contando o sonando.
    private func updateTicker() {
        let needed = engine.anyRunning || engine.anyRinging
        if needed && ticker == nil {
            let t = Timer(timeInterval: 0.5, repeats: true) { _ in
                MainActor.assumeIsolated { TimersStore.shared.tick() }
            }
            t.tolerance = 0.1
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        } else if !needed, let t = ticker {
            t.invalidate()
            ticker = nil
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(engine)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("ORBEX: no pude guardar los timers: \(error.localizedDescription)")
        }
    }

    // MARK: - Notificaciones

    private func scheduleNotification(for timer: OrbexTimer) {
        guard notificationsOn, let end = timer.endDate else { return }
        let center = UNUserNotificationCenter.current()
        if !askedNotifications {
            askedNotifications = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = "ORBEX"
        if let p = timer.pomodoro {
            content.body = "Terminó: \(p.phase.title)"
        } else {
            content.body = "¡Terminó \(timer.displayName)!"
        }
        content.sound = .default
        let interval = max(1, end.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: "orbex.timer.\(timer.id.uuidString)",
                                            content: content, trigger: trigger)
        center.add(request) { _ in }
    }

    private func cancelNotification(_ id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["orbex.timer.\(id.uuidString)"])
    }
}

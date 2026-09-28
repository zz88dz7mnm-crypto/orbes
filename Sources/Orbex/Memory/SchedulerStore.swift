import AppKit
import Foundation
import OrbexCore
import UserNotifications

/// Recordatorios y acciones programadas (informe §9.6). Mira cada 30 s y al despertar la Mac.
@MainActor
final class SchedulerStore: ObservableObject {
    static let shared = SchedulerStore()

    static let missedPolicyKey = "orbex.scheduler.missedPolicy"

    @Published private(set) var actions: [ScheduledAction] = []

    private var engine = SchedulerEngine()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var attentionSources: Set<String> = []
    private var askedNotifications = false
    private let file = AppPaths.dataFile("scheduler.json")

    private init() { load() }

    var missedPolicy: MissedPolicy {
        MissedPolicy(rawValue: UserDefaults.standard.string(forKey: Self.missedPolicyKey) ?? "") ?? .runOnWake
    }

    // MARK: - API

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { SchedulerStore.shared.check() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SchedulerStore.shared.check(afterWake: true) }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: .orbexIslandStateChanged, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if AppModel.shared.islandState.isExpanded { SchedulerStore.shared.clearAttention() }
                }
            })
        // Lo que venció con la app cerrada cuenta como "perdido mientras dormía".
        check(afterWake: true)
    }

    func add(_ action: ScheduledAction) {
        engine.add(action)
        save()
        scheduleNotification(for: action)
    }

    @discardableResult
    func addReminder(at date: Date, text: String) -> ScheduledAction {
        let a = ScheduledAction(date: date, kind: .reminder(text: text))
        add(a)
        return a
    }

    @discardableResult
    func addAction(at date: Date, name: String) -> ScheduledAction {
        let a = ScheduledAction(date: date, kind: .action(name: name))
        add(a)
        return a
    }

    func remove(id: UUID) {
        engine.remove(id: id)
        save()
        UNCenter.remove("orbex.scheduler.\(id.uuidString)")
    }

    // MARK: - Revisión

    func check(afterWake: Bool = false) {
        let now = Date()
        let due = engine.due(now: now)
        // Vencidos hace más de 2 min: se perdieron mientras dormía (o con la app cerrada).
        let missed = afterWake ? Set(due.filter { now.timeIntervalSince($0.date) > 120 }.map(\.id)) : []
        guard !due.isEmpty else { return }
        for item in due {
            engine.markDone(id: item.id)
            if missed.contains(item.id) && missedPolicy == .notifyOnly {
                announce("Te perdiste: \(item.title) (\(Self.time(item.date)))", source: item.id)
            } else {
                fire(item, late: missed.contains(item.id))
            }
        }
        engine.purgeDone(before: now.addingTimeInterval(-7 * 86_400))
        save()
    }

    private func fire(_ item: ScheduledAction, late: Bool) {
        let suffix = late ? " (era a las \(Self.time(item.date)))" : ""
        switch item.kind {
        case .reminder(let text):
            OrbexBus.play(.alarm)
            announce(text + suffix, source: item.id)
        case .action(let name):
            if let action = UtilitiesKeys.loadAllowlist().action(named: name) {
                AppLauncher.run(action)
                OrbexBus.toast("Hice lo programado: \(action.name)\(suffix)", symbol: "clock.badge.checkmark")
            } else {
                OrbexBus.play(.needsYou)
                announce("Tenías programado \"\(name)\"\(suffix). No está en tu lista: pedímelo y lo confirmo.", source: item.id)
            }
        }
    }

    /// Toast + atención en la isla hasta que la abras (o 60 s).
    private func announce(_ text: String, source id: UUID) {
        OrbexBus.toast(text, symbol: "bell.fill")
        let source = "reminder:\(id.uuidString)"
        attentionSources.insert(source)
        OrbexBus.setActivity(source: source, working: false, attention: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            MainActor.assumeIsolated { SchedulerStore.shared.clearAttention(source) }
        }
    }

    private func clearAttention(_ only: String? = nil) {
        let sources = only.map { attentionSources.contains($0) ? [$0] : [] } ?? Array(attentionSources)
        for s in sources {
            attentionSources.remove(s)
            OrbexBus.setActivity(source: s, working: false, attention: false)
        }
    }

    // MARK: - Notificaciones del sistema

    private func scheduleNotification(for item: ScheduledAction) {
        guard Bundle.main.bundleIdentifier != nil, item.date > Date() else { return }
        let center = UNUserNotificationCenter.current()
        if !askedNotifications {
            askedNotifications = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = "ORBEX"
        switch item.kind {
        case .reminder(let text): content.body = text
        case .action(let name): content.body = "Acción programada: \(name)"
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.date.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: "orbex.scheduler.\(item.id.uuidString)",
                                         content: content, trigger: trigger)) { _ in }
    }

    private enum UNCenter {
        static func remove(_ id: String) {
            guard Bundle.main.bundleIdentifier != nil else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
    }

    // MARK: - Disco

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "d/M HH:mm"
        return f.string(from: date)
    }

    private func load() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode(SchedulerEngine.self, from: data) {
            engine = saved
        }
        actions = engine.actions
    }

    private func save() {
        actions = engine.actions
        if let data = try? JSONEncoder().encode(engine) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

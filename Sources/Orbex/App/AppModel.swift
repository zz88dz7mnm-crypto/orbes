import AppKit
import SwiftUI
import CoreGraphics
import OrbexCore

/// Estado central de ORBEX: ajustes, tema, personaje, actividad de los módulos y bus.
/// La isla en sí (ventana, estados, vistas) vive en la base de Coucou (`AppState` + `IslandWindowController`);
/// `OrbexBridge` traduce entre los dos mundos y mantiene `islandState` como espejo para los módulos.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // MARK: - Ajustes

    @Published var settings: OrbexSettings {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.save(settings)
            applySettings(old: oldValue)
        }
    }

    // MARK: - Isla

    /// Espejo del estado de la isla (lo actualiza `OrbexBridge` al cambiar el modo o la vista).
    @Published private(set) var islandState: IslandState = .hidden
    @Published private(set) var notch = NotchMetrics(width: 185, height: 32, isHardware: false)
    @Published private(set) var screenSize = CGSize(width: 1440, height: 900)
    /// Línea corta que se muestra debajo del notch en "trabajando" / "te necesita".
    @Published var statusLine: String = ""
    /// Fuentes que piden atención (para el texto de "te necesita").
    @Published private(set) var attentionSources: [String] = []

    // MARK: - Sistema

    @Published private(set) var systemReduceMotion = false
    @Published private(set) var systemReduceTransparency = false
    @Published private(set) var lowPower = false
    @Published var isPlayingMusic = false {
        didSet { if isPlayingMusic != oldValue { updateMood() } }
    }
    @Published var hasTimerRunning = false {
        didSet { if hasTimerRunning != oldValue { updateMood() } }
    }

    let brain = CharacterBrain.shared

    private var activity: [String: (working: Bool, attention: Bool)] = [:]
    private var tintRequests: [String: OrbexTint] = [:]
    private var tintOrder: [String] = []
    private(set) var isSleepy = false
    private var islandMode: IslandMode = .hidden
    private var islandView: IslandView = .overview
    private var observers: [NSObjectProtocol] = []
    private var sleepTimer: Timer?

    private init() {
        let loaded = SettingsStore.load()
        settings = loaded
        systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        systemReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        brain.tint = loaded.tint
        brain.lifeLevel = loaded.lifeLevel
        brain.reduceMotion = loaded.reduceMotion || systemReduceMotion
        observeSystem()
        observeBus()
        startSleepWatch()
    }

    // MARK: - Derivados

    var themeStyle: ThemeStyle {
        ThemeStyle(id: settings.theme,
                   useGlass: settings.useGlass,
                   glassTint: settings.glassTint,
                   reduceTransparency: systemReduceTransparency,
                   reduceMotion: effectiveReduceMotion)
    }

    var effectiveReduceMotion: Bool { settings.reduceMotion || systemReduceMotion }

    /// Cuadros por segundo del personaje (baja en ahorro de energía).
    var characterFPS: Double {
        if settings.lowPowerMode || lowPower { return 24 }
        return Double(min(120, max(15, settings.maxFPS)))
    }

    var geometryOptions: IslandGeometryOptions {
        IslandGeometryOptions(wingScale: settings.wingScale)
    }

    func size(for state: IslandState) -> IslandSize {
        IslandGeometry.size(for: state, notch: notch,
                            screenWidth: Double(screenSize.width), screenHeight: Double(screenSize.height),
                            options: geometryOptions)
    }

    var islandSize: IslandSize { size(for: islandState) }

    var maxIslandSize: CGSize {
        let m = IslandGeometry.maxSize(notch: notch, screenWidth: Double(screenSize.width),
                                       screenHeight: Double(screenSize.height), options: geometryOptions)
        return CGSize(width: m.width, height: m.height)
    }

    // MARK: - Entradas

    func updatePlacement(notch: NotchMetrics, screenSize: CGSize) {
        if self.notch != notch { self.notch = notch }
        if self.screenSize != screenSize { self.screenSize = screenSize }
    }

    /// Asoma la isla unos segundos (para mostrar dónde vive ORBEX o avisar algo chiquito).
    func flash() {
        OrbexBridge.shared.reveal()
    }

    /// Abre la isla en una página de ORBEX.
    func show(page: IslandPage) {
        OrbexBridge.shared.show(page: page)
    }

    // MARK: - Cambios de estado

    /// Lo llama `OrbexBridge` cada vez que la isla cambia de modo o de vista.
    func islandDidChange(mode: IslandMode, view: IslandView) {
        islandMode = mode
        islandView = view
        refreshIslandState()
    }

    private func refreshIslandState() {
        let working = activity.values.contains { $0.working }
        let attention = activity.values.contains { $0.attention }
        let new: IslandState
        switch islandMode {
        case .expanded:
            new = islandView == .prompt ? .assistant : .open
        case .compact:
            new = attention ? .needsYou : (working ? .active : .peek)
        case .hidden:
            if ClockController.shared.isVisible { new = .clock }
            else if isSleepy { new = .sleeping }
            else if attention { new = .needsYou }
            else if working { new = .active }
            else { new = .hidden }
        }
        guard new != islandState else { return }
        islandState = new
        updateMood()
        NotificationCenter.default.post(name: .orbexIslandStateChanged, object: nil)
    }

    private func updateMood() {
        let mood = CharacterDirector.mood(for: islandState, isPlayingMusic: isPlayingMusic,
                                          hasTimerRunning: hasTimerRunning)
        if brain.mood != mood { brain.mood = mood }
    }

    private func recomputeContext() {
        let working = activity.values.contains { $0.working }
        let attention = activity.values.contains { $0.attention }
        let hadAttention = !attentionSources.isEmpty
        attentionSources = activity.filter { $0.value.attention }.map { $0.key }.sorted()
        OrbexBridge.shared.setAmbient(working: working, attention: attention, sleepy: isSleepy)
        if attention && !hadAttention {
            OrbexBus.play(.needsYou)
            OrbexBridge.shared.reveal()
        }
        refreshIslandState()
    }

    private func applySettings(old: OrbexSettings) {
        brain.lifeLevel = settings.lifeLevel
        brain.reduceMotion = effectiveReduceMotion
        refreshTint()
        if settings.launchAtLogin != old.launchAtLogin {
            LaunchAtLogin.set(settings.launchAtLogin)
        }
        if settings.desktopShortcut != old.desktopShortcut {
            if settings.desktopShortcut { DesktopShortcut.create() } else { DesktopShortcut.remove() }
        }
        if settings.screen != old.screen || settings.notchAdjustWidth != old.notchAdjustWidth
            || settings.notchAdjustHeight != old.notchAdjustHeight || settings.wingScale != old.wingScale {
            NotificationCenter.default.post(name: .orbexPlacementNeedsUpdate, object: nil)
        }
        if settings.sleep != old.sleep { checkSleep() }
        // Cambio de tema en vivo: saludo con el pack de sonido nuevo.
        if settings.theme != old.theme {
            SoundEngine.shared.preview(.greet, theme: settings.theme)
            brain.greet()
        }
    }

    private func refreshTint() {
        // La última integración que pidió color gana; si no hay, el color elegido por el usuario.
        let requested = tintOrder.last.flatMap { tintRequests[$0] }
        brain.tint = requested ?? settings.tint
    }

    // MARK: - Sueño

    private func startSleepWatch() {
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSleep() }
        }
        sleepTimer?.tolerance = 3
    }

    func checkSleep() {
        let hour = Calendar.current.component(.hour, from: Date())
        let idle = Self.secondsSinceLastInput()
        let sleepy = settings.sleep.shouldSleep(hour: hour, idleSeconds: idle) && idle > 60
        setSleepy(sleepy)
    }

    /// Dormir / despertar (también lo usa "Probar estados" del menú).
    func setSleepy(_ sleepy: Bool) {
        guard sleepy != isSleepy else { return }
        isSleepy = sleepy
        OrbexBus.play(sleepy ? .sleep : .wake)
        recomputeContext()
    }

    static func secondsSinceLastInput() -> Double {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    // MARK: - Observadores

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self.systemReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                self.brain.reduceMotion = self.effectiveReduceMotion
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSleep() }
        })
    }

    private func observeBus() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: OrbexBus.sound, object: nil, queue: .main) { note in
            guard let raw = note.object as? String, let s = OrbexSound(rawValue: raw) else { return }
            MainActor.assumeIsolated { SoundEngine.shared.play(s) }
        })
        observers.append(nc.addObserver(forName: OrbexBus.reaction, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.object as? String, let r = OrbexReaction(rawValue: raw) else { return }
            MainActor.assumeIsolated { self?.react(r) }
        })
        observers.append(nc.addObserver(forName: OrbexBus.activity, object: nil, queue: .main) { [weak self] note in
            guard let u = note.object as? OrbexBus.ActivityUpdate else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                if !u.working && !u.attention {
                    self.activity.removeValue(forKey: u.source)
                } else {
                    self.activity[u.source] = (u.working, u.attention)
                }
                self.recomputeContext()
            }
        })
        observers.append(nc.addObserver(forName: OrbexBus.showPage, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.object as? String, let p = IslandPage(rawValue: raw) else { return }
            MainActor.assumeIsolated { self?.show(page: p) }
        })
        observers.append(nc.addObserver(forName: OrbexBus.command, object: nil, queue: .main) { [weak self] note in
            guard let action = note.object as? String else { return }
            MainActor.assumeIsolated { self?.perform(action) }
        })
        observers.append(nc.addObserver(forName: OrbexBus.tint, object: nil, queue: .main) { [weak self] note in
            guard let req = note.object as? OrbexBus.TintRequest else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tintOrder.removeAll { $0 == req.source }
                if let t = req.tint {
                    self.tintRequests[req.source] = t
                    self.tintOrder.append(req.source)
                } else {
                    self.tintRequests.removeValue(forKey: req.source)
                }
                self.refreshTint()
            }
        })
        observers.append(nc.addObserver(forName: OrbexBus.toast, object: nil, queue: .main) { note in
            guard let t = note.object as? OrbexBus.Toast else { return }
            MainActor.assumeIsolated { OrbexBridge.shared.showNote(t.text, symbol: t.symbol) }
        })
    }

    func react(_ r: OrbexReaction) {
        OrbexBridge.shared.react(r)
        switch r {
        case .celebrate: brain.celebrate()
        case .worry: brain.worry()
        case .greet: brain.greet()
        case .love: brain.show(.love, for: 2)
        case .surprised: brain.show(.surprised, for: 1.5)
        case .thinking: brain.show(.thinking, for: 3)
        }
    }

    /// Acciones globales (menú, atajos, bus).
    func perform(_ action: String) {
        switch action {
        case "assistant": OrbexBridge.shared.toggleAssistant()
        case "clock": OrbexBridge.shared.toggleClock()
        case "open": OrbexBridge.shared.openIsland()
        case "close": OrbexBridge.shared.close()
        case "settings": NotificationCenter.default.post(name: .orbexOpenSettings, object: nil)
        default: break
        }
    }
}

extension Notification.Name {
    static let orbexIslandStateChanged = Notification.Name("orbex.islandStateChanged")
    static let orbexPlacementNeedsUpdate = Notification.Name("orbex.placementNeedsUpdate")
    static let orbexOpenSettings = Notification.Name("orbex.openSettings")
}

/// Guarda los ajustes como JSON en `UserDefaults`.
enum SettingsStore {
    private static let key = "orbex.settings.v1"

    static func load() -> OrbexSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? OrbexSettings.importJSON(data) else { return OrbexSettings() }
        return s
    }

    static func save(_ s: OrbexSettings) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

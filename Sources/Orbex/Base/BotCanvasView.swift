// Basado en Coucou (https://github.com/louis-cfm/coucou) © 2026 Louis Raillé — licencia MIT.
// Modificado para ORBEX (solo el código; ningún asset de Coucou). Ver THIRD_PARTY_NOTICES.md.

import SwiftUI
import QuartzCore

/// ORBEX de la isla: un `TimelineView` le da cuadros a un `Canvas` que dibuja `BotEngine`.
/// Cada vista tiene su propio motor (el de la isla, el fantasma al arrastrar, el puntito al subir).
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0
    /// `true` en el fantasma que se arrastra: ORBEX es un globo que patalea.
    var carried: Bool = false

    @StateObject private var engine = BotEngine()
    /// Mirada que pide `PersonalityDirector` (vistazos y mirada sostenida).
    @State private var glance = GlanceHold()

    var body: some View {
        // Oculta, o tapada por el lienzo del saludo o de subir archivo (dibujan su propio ORBEX): en pausa.
        let paused = state.mode == .hidden || isCovered
        TimelineView(.animation(minimumInterval: 1.0 / AppModel.shared.characterFPS, paused: paused)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // redibuja en cada cuadro de la línea de tiempo
                // Un solo reloj para todo el motor (tweens, dt, partículas): CACurrentMediaTime.
                let now = CACurrentMediaTime()
                let dt = min(0.05, max(0, now - engine.lastTime))
                engine.lookX = lookX(state: state, size: size)
                engine.lookY = lookY(state: state, size: size)
                // Si el mouse se mueve, la mirada sostenida se suelta y vuelve a seguir al cursor.
                glance.releaseIfMouseMoved(state.mousePosition, engine: engine)
                engine.particleOverhang = particleOverhang
                engine.carried = carried
                // Cuerpo entero (brazos, piernitas y pies) solo en la vista abierta.
                engine.fullBody = state.mode == .expanded && state.view != .uploading
                // Archivo encima del portal: se entreabre. El motor decide la apertura final y no
                // deja que esto pise un trago en curso.
                engine.portalHover = (engine.morph > 0.3 && state.fileDragOver) ? 0.20 : 0
                // Las pastillas de integraciones tienen color de marca → tiñe el vidrio.
                // Las tareas de Claude Code usan el color del estado (trabajando = azul, pensando = violeta…).
                engine.bodyColor = (state.focusTask?.isIntegration == true)
                    ? cgColorFromHex(state.focusTask!.color)
                    : nil
                engine.update(dt: dt)
                engine.drawHandsBehind(context: context, size: size)
                engine.draw(context: context, size: size)
                engine.drawHandsAndExtras(context: context, size: size)
            }
        }
        .onChange(of: state.effectiveState) { _, newState in
            engine.setState(newState)
        }
        .onChange(of: state.view) { _, newView in
            // Portal de vidrio mientras está la vista de subir archivo
            if state.mode == .expanded && newView == .upload {
                engine.anim("morph", keys: [TweenKey(target: 1, duration: 550, ease: Ease.inOut)])
            } else if newView != .upload && newView != .uploading && engine.morph > 0.01 {
                // Cualquier otra vista (que no esté tragando): vuelve a ser ORBEX
                engine.anim("morph", keys: [TweenKey(target: 0, duration: 550, ease: Ease.inOut)])
            }
        }
        .onChange(of: state.mode) { _, newMode in
            // Si la isla se cierra, el portal se deshace de una
            if newMode != .expanded {
                engine.tweens.removeValue(forKey: "morph")
                engine.locks.remove("morph")
                engine.morph = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { notif in
            if let emote = notif.object as? BotEmote {
                engine.audible = canSpeak
                engine.triggerEmote(emote)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in
            // Clic sobre ORBEX: cosquillas (tres rápidos = mareo).
            guard !carried else { return }
            engine.audible = canSpeak
            engine.tickle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botPet)) { notif in
            // Caricia: mouse quieto encima de ORBEX en la vista abierta.
            guard !carried else { return }
            engine.setPetting((notif.object as? Bool) ?? false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .personalityGlance)) { notif in
            guard !carried, let info = notif.userInfo else { return }
            let dx = (info["dx"] as? CGFloat) ?? 0
            let dy = (info["dy"] as? CGFloat) ?? 0
            let duration = (info["duration"] as? Double) ?? 0
            glance.apply(dx: dx, dy: dy, duration: duration, mouse: state.mousePosition, engine: engine)
        }
        .onReceive(NotificationCenter.default.publisher(for: .botBlink)) { _ in
            engine.blink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botSetTgEs)) { notif in
            if let v = notif.object as? CGFloat {
                engine.tgEs = v
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGulp)) { _ in
            engine.audible = canSpeak
            engine.gulp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botMorphTo)) { notif in
            if let target = notif.object as? CGFloat {
                let dur: CGFloat = target > 0.5 ? 550 : 650
                engine.anim("morph", keys: [TweenKey(target: target, duration: dur, ease: Ease.inOut)])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            engine.audible = canSpeak
            engine.greet()
        }
        .onAppear {
            engine.setState(state.effectiveState, force: true)
        }
    }

    /// Otro lienzo (saludo o subir archivo) dibuja su propio ORBEX encima de este.
    private var isCovered: Bool {
        guard state.mode == .expanded else { return false }
        if state.view == .greeting { return true }
        return UploadSequenceEngine.shared.isActive
            && (state.view == .upload || state.view == .uploading || state.view == .choose)
    }

    /// Las reacciones propias (emotes, saludo, trago) suenan solo si este ORBEX se ve.
    private var canSpeak: Bool { state.mode != .hidden && !isCovered }

    private func lookX(state: AppState, size: CGSize) -> CGFloat {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let (botCx, _, _, _) = botPosition(mode: state.mode, view: state.view,
                                            islandW: islandW, islandH: islandH,
                                            uploadProgress: state.uploadProgress)
        // La isla está centrada en la pantalla; el bot está en botCx dentro de la isla
        let botScreenX = screen.frame.midX - islandW / 2 + botCx
        return tanh((state.mousePosition.x - botScreenX) / 260)
    }

    private func lookY(state: AppState, size: CGSize) -> CGFloat {
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let actualH: CGFloat = (state.mode == .expanded && state.view == .prompt)
            ? min(300, 240 + CGFloat(state.chatMessageCount) * 40)
            : islandH
        let (_, botCy, _, _) = botPosition(mode: state.mode, view: state.view,
                                             islandW: islandW, islandH: actualH,
                                             uploadProgress: state.uploadProgress)
        // Arriba de la isla = arriba de la pantalla → Y del bot en pantalla = botCy
        return -tanh((state.mousePosition.y - botCy) / 200)
    }
}

/// Mirada pedida por la personalidad, sumada a la del cursor (`engine.glanceX/glanceY`).
/// `duration == 0` → se sostiene; con duración → vistazo que vuelve a la mirada sostenida.
/// Si el mouse se mueve (más de 40 pt) la mirada sostenida se suelta: manda el cursor.
@MainActor
final class GlanceHold {
    private var heldX: CGFloat = 0
    private var heldY: CGFloat = 0
    private var holding = false
    private var mouseAtHold: CGPoint = .zero

    func apply(dx: CGFloat, dy: CGFloat, duration: Double, mouse: CGPoint, engine: BotEngine) {
        let x = max(-1, min(1, dx))
        let y = max(-1, min(1, dy))
        mouseAtHold = mouse
        if duration <= 0 {
            heldX = x
            heldY = y
            holding = x != 0 || y != 0
            engine.anim("glanceX", keys: [TweenKey(target: x, duration: 320, ease: Ease.out)])
            engine.anim("glanceY", keys: [TweenKey(target: y, duration: 320, ease: Ease.out)])
        } else {
            let hold = CGFloat(max(0, duration * 1000 - 560))
            let backX = holding ? heldX : 0
            let backY = holding ? heldY : 0
            engine.anim("glanceX", keys: [
                TweenKey(target: x, duration: 260, ease: Ease.out),
                TweenKey(target: x, duration: hold, ease: Ease.lin),
                TweenKey(target: backX, duration: 300, ease: Ease.inOut),
            ])
            engine.anim("glanceY", keys: [
                TweenKey(target: y, duration: 260, ease: Ease.out),
                TweenKey(target: y, duration: hold, ease: Ease.lin),
                TweenKey(target: backY, duration: 300, ease: Ease.inOut),
            ])
        }
    }

    func releaseIfMouseMoved(_ mouse: CGPoint, engine: BotEngine) {
        guard holding, hypot(mouse.x - mouseAtHold.x, mouse.y - mouseAtHold.y) > 40 else { return }
        holding = false
        heldX = 0
        heldY = 0
        engine.anim("glanceX", keys: [TweenKey(target: 0, duration: 350, ease: Ease.inOut)])
        engine.anim("glanceY", keys: [TweenKey(target: 0, duration: 350, ease: Ease.inOut)])
    }
}

/// Mini-ORBEX (pastillas y grilla compacta): esfera + ojos + color de marca, sin extremidades.
struct MiniBotCanvasView: View {
    let task: AgentTask
    @StateObject private var engine: BotEngine

    init(task: AgentTask) {
        self.task = task
        _engine = StateObject(wrappedValue: {
            let e = BotEngine()
            e.isMini = true
            e.bodyColor = cgColorFromHex(task.color)
            return e
        }())
    }

    var body: some View {
        // A este tamaño alcanza con 30 cuadros por segundo (menos aún en ahorro de energía).
        TimelineView(.animation(minimumInterval: 1.0 / min(30, AppModel.shared.characterFPS))) { timeline in
            Canvas { context, size in
                _ = timeline.date
                let now = CACurrentMediaTime()
                let dt = min(0.05, max(0, now - engine.lastTime))
                engine.update(dt: dt)
                engine.draw(context: context, size: size)
            }
        }
        .onChange(of: task.state) { _, newState in
            engine.setState(newState)
        }
        .onChange(of: task.color) { _, hex in
            engine.bodyColor = cgColorFromHex(hex)
        }
        .onAppear {
            engine.setState(task.state, force: true)
            if let emote = task.emote {
                engine.setPermanentEmote(emote)
            }
            // Una forma de ojos fija tiene prioridad (p. ej. .wide para Research)
            if let eye = task.miniEye {
                engine.permanentEye = eye
                engine.eyeOverride = eye
                engine.eyeOverrideUntil = .greatestFiniteMagnitude
            }
        }
    }
}

// MARK: - CGColor desde hex

func cgColorFromHex(_ hex: String) -> CGColor? {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard let val = UInt64(h, radix: 16) else { return nil }
    let r = CGFloat((val >> 16) & 0xFF) / 255
    let g = CGFloat((val >> 8)  & 0xFF) / 255
    let b = CGFloat( val        & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}

extension CGColor {
    static func from(_ hex: String) -> CGColor {
        cgColorFromHex(hex) ?? CGColor(gray: 0.5, alpha: 1)
    }
}

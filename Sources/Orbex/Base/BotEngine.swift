// Basado en Coucou (https://github.com/louis-cfm/coucou) © 2026 Louis Raillé — licencia MIT.
// Modificado para ORBEX (solo el código; ningún asset de Coucou). Ver THIRD_PARTY_NOTICES.md.
//
// Motor del personaje de la isla. Del original queda la lógica genérica: tweens y easing, partículas,
// estados y emotes, proyección de los ojos sobre la esfera (yaw/pitch/roll), squash & stretch, rebote,
// insignias, morph y apertura con resorte. Todo lo que se ve es ORBEX (`OrbexPainter`): esfera de vidrio
// teñida por el estado, ojos ovalados, brazos-gota, piernitas, halo, insignias de vidrio y portal de vidrio.

import Foundation
import CoreGraphics
import QuartzCore
import SwiftUI
import OrbexCore

// MARK: - Easing (E.out, E.inOut, E.back, E.lin)

enum Ease {
    static func out(_ t: CGFloat) -> CGFloat   { 1 - pow(1 - t, 3) }
    static func inOut(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4*t*t*t : 1 - pow(-2*t+2, 3)/2 }
    static func back(_ t: CGFloat) -> CGFloat  { let c1: CGFloat = 1.7; let c3 = c1+1; return 1+c3*pow(t-1,3)+c1*pow(t-1,2) }
    static func lin(_ t: CGFloat) -> CGFloat   { t }
}

// MARK: - Tween: [destino, duración en ms, easing]

struct TweenKey {
    let target: CGFloat
    let duration: CGFloat    // milisegundos
    let ease: (CGFloat) -> CGFloat
}

struct Tween {
    let property: String
    var keys: [TweenKey]
    var keyIndex: Int = 0
    var from: CGFloat
    var startTime: Double    // CACurrentMediaTime() * 1000
    var onComplete: (() -> Void)? = nil
}

// MARK: - Partículas

struct Particle {
    /// Corazón, estrellita dorada, chispita de vidrio, gotita de sudor, "z" de dormir, burbujita,
    /// confeti de vidrio (cae con gravedad) y signo de pregunta flotante.
    enum ParticleType { case heart, star, spark, sweat, z, bubble, confetti, question }
    var type: ParticleType
    var x, y, vx, vy: CGFloat   // en unidades de 1,3 R desde el centro del cuerpo
    var age: Double             // segundos
    var life: Double
    var rot: CGFloat
    var size: CGFloat
}

// MARK: - Configuración de cada estado

struct BotStateCfg {
    let color: CGColor
    let tint: CGFloat
    let eye: BotEyeShape
    let badge: BadgeType?
    let badgeColor: CGColor
    let glow: CGColor
    let glowOpacity: CGFloat
    let bounces: Bool
    let scans: Bool
    let breathes: Bool
    let zz: Bool
    let sweat: Bool
    let look: CGPoint?     // mirada fija
    let tilt: CGFloat
    let sound: String?
}

enum BotEyeShape: String {
    case pill, wide, dot, line, flat, happy, closed, spiral, heart, star, tired, wink, cup
}

enum BadgeType {
    case dots(CGColor)
    case bang(CGColor)
    case question(CGColor)
    case dot(CGColor)
}

// MARK: - Constantes de ORBEX (fracciones del radio R de la esfera; ver design/character/README.md)

enum BotConst {
    /// Ojos: óvalos verticales de 0,075 D × 0,20 D (D = 2 R).
    static let eyeW: CGFloat  = 0.15
    static let eyeH: CGFloat  = 0.40
    /// Posición de cada ojo sobre la esfera: yaw (±0,14 D del eje) y pitch (un poco arriba del centro).
    static let eyeSp: CGFloat = 0.29
    static let eyeP: CGFloat  = 0.12
    /// Vidrio por defecto (transparente azulado, #D6E4F0) y su sombra.
    static let baseTop    = CGColor(red: 0.84, green: 0.89, blue: 0.94, alpha: 1)
    static let baseBottom = CGColor(red: 0.60, green: 0.68, blue: 0.78, alpha: 1)
    /// Tinta de los ojos (casi negro).
    static let ink        = CGColor(red: 0.03, green: 0.035, blue: 0.05, alpha: 1)
    static let miniInk    = CGColor(red: 0.02, green: 0.025, blue: 0.04, alpha: 1)
    /// Radio mínimo (pt) para dibujar piernitas y pies.
    static let limbsMinR: CGFloat = 14
    /// Escuchando un pedido por voz: magenta #E040FB (ningún otro estado lo usa).
    static let listen = CGColor(red: 0.878, green: 0.251, blue: 0.984, alpha: 1)
    static let listenRGB: (r: Double, g: Double, b: Double) = (0.878, 0.251, 0.984)
    /// Costado de la mano que va a la "oreja" al escuchar (+1 = derecha).
    static let earSide: Double = 1
    /// Hablando (voz de salida): celeste cálido, el color de Orbi (el magenta queda para escuchar).
    static let speakRGB: (r: Double, g: Double, b: Double) = (0.52, 0.82, 0.97)
}

// MARK: - Estados

let BotStates: [BotState: BotStateCfg] = [
    .idle: BotStateCfg(
        color: CGColor(red:0.902,green:0.914,blue:0.933,alpha:1), tint:0,
        eye:.pill, badge:nil,
        badgeColor: .white, glow: CGColor(red:1,green:1,blue:1,alpha:0.35), glowOpacity:0.25,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:nil),
    .working: BotStateCfg(
        color: CGColor(red:0.231,green:0.620,blue:1,alpha:1), tint:0.72,
        eye:.pill, badge:.dots(CGColor(red:0.231,green:0.620,blue:1,alpha:1)),
        badgeColor: CGColor(red:0.231,green:0.620,blue:1,alpha:1),
        glow: CGColor(red:0.231,green:0.620,blue:1,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"work"),
    .thinking: BotStateCfg(
        color: CGColor(red:0.545,green:0.361,blue:0.965,alpha:1), tint:0.72,
        eye:.pill, badge:.dots(CGColor(red:0.545,green:0.361,blue:0.965,alpha:1)),
        badgeColor: CGColor(red:0.545,green:0.361,blue:0.965,alpha:1),
        glow: CGColor(red:0.545,green:0.361,blue:0.965,alpha:1), glowOpacity:0.5,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look: CGPoint(x:0.55, y:0.55), tilt:0, sound:"think"),
    .searching: BotStateCfg(
        color: CGColor(red:0.388,green:0.396,blue:0.949,alpha:1), tint:0.72,
        eye:.pill, badge:.dots(CGColor(red:0.388,green:0.396,blue:0.949,alpha:1)),
        badgeColor: CGColor(red:0.388,green:0.396,blue:0.949,alpha:1),
        glow: CGColor(red:0.388,green:0.396,blue:0.949,alpha:1), glowOpacity:0.55,
        bounces:false, scans:true, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"search"),
    .approval: BotStateCfg(
        color: CGColor(red:0.961,green:0.647,blue:0.141,alpha:1), tint:0.78,
        eye:.wide, badge:.bang(CGColor(red:0.961,green:0.647,blue:0.141,alpha:1)),
        badgeColor: CGColor(red:0.961,green:0.647,blue:0.141,alpha:1),
        glow: CGColor(red:0.961,green:0.647,blue:0.141,alpha:1), glowOpacity:0.6,
        bounces:true, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"approval"),
    .question: BotStateCfg(
        color: CGColor(red:0.133,green:0.827,blue:0.933,alpha:1), tint:0.75,
        eye:.pill, badge:.question(CGColor(red:0.133,green:0.827,blue:0.933,alpha:1)),
        badgeColor: CGColor(red:0.133,green:0.827,blue:0.933,alpha:1),
        glow: CGColor(red:0.133,green:0.827,blue:0.933,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0.17, sound:"question"),
    .error: BotStateCfg(
        color: CGColor(red:0.957,green:0.314,blue:0.369,alpha:1), tint:0.78,
        eye:.flat, badge:.bang(CGColor(red:0.957,green:0.314,blue:0.369,alpha:1)),
        badgeColor: CGColor(red:0.957,green:0.314,blue:0.369,alpha:1),
        glow: CGColor(red:0.957,green:0.314,blue:0.369,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"error"),
    .finished: BotStateCfg(
        color: CGColor(red:0.204,green:0.831,blue:0.600,alpha:1), tint:0.35,
        eye:.happy, badge:.dot(CGColor(red:0.204,green:0.831,blue:0.600,alpha:1)),
        badgeColor: CGColor(red:0.204,green:0.831,blue:0.600,alpha:1),
        glow: CGColor(red:0.204,green:0.831,blue:0.600,alpha:1), glowOpacity:0.5,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"finish"),
    .ratelimit: BotStateCfg(
        color: CGColor(red:0.984,green:0.573,blue:0.235,alpha:1), tint:0.72,
        eye:.tired, badge:.dot(CGColor(red:0.984,green:0.573,blue:0.235,alpha:1)),
        badgeColor: CGColor(red:0.984,green:0.573,blue:0.235,alpha:1),
        glow: CGColor(red:0.984,green:0.573,blue:0.235,alpha:1), glowOpacity:0.45,
        bounces:false, scans:false, breathes:false, zz:false, sweat:true,
        look:nil, tilt:0, sound:"rate"),
    .sleeping: BotStateCfg(
        color: CGColor(red:0.580,green:0.635,blue:0.722,alpha:1), tint:0.32,
        eye:.closed, badge:nil,
        badgeColor: .white,
        glow: CGColor(red:0.580,green:0.635,blue:0.722,alpha:1), glowOpacity:0.2,
        bounces:false, scans:false, breathes:true, zz:true, sweat:false,
        look:nil, tilt:0, sound:"sleep"),
    .dizzy: BotStateCfg(
        color: CGColor(red:0.957,green:0.447,blue:0.714,alpha:1), tint:0.7,
        eye:.spiral, badge:nil,
        badgeColor: .white,
        glow: CGColor(red:0.957,green:0.447,blue:0.714,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"dizzy"),
    // Escuchando "Orbex, …": magenta propio, ojos bien abiertos mirando al frente, sin insignia (las
    // ondas son el ícono), respira suave. Sin sonido: el de activación lo toca la voz.
    .listening: BotStateCfg(
        color: BotConst.listen, tint:0.78,
        eye:.wide, badge:nil,
        badgeColor: BotConst.listen,
        glow: BotConst.listen, glowOpacity:0.62,
        bounces:false, scans:false, breathes:true, zz:false, sweat:false,
        look: CGPoint(x:0, y:-0.12), tilt:0, sound:nil),
]

// MARK: - Motor

@MainActor
final class BotEngine: ObservableObject {
    var isMini: Bool = false
    /// Color de marca (pastillas de integraciones): tiñe el vidrio en lugar del tinte del usuario.
    var bodyColor: CGColor? = nil

    // MARK: Entradas del lienzo (se ponen en cada cuadro)

    /// Vista abierta: brazos siempre a la vista y, si la esfera es grande, piernitas con pies.
    var fullBody: Bool = false
    /// Apertura que pide el lienzo cuando hay un archivo encima del portal (fracción de R).
    var portalHover: CGFloat = 0
    /// `false` si otro lienzo (saludo, subir archivo) tapa a este ORBEX: sus reacciones no suenan.
    var audible: Bool = true

    // MARK: Animación

    var yaw:    CGFloat = 0
    var pitch:  CGFloat = 0
    var roll:   CGFloat = 0
    var tilt:   CGFloat = 0
    var open:   CGFloat = 1          // párpado (1 = abierto)
    var sx:     CGFloat = 1          // escala X
    var sy:     CGFloat = 1          // escala Y
    var oy:     CGFloat = 0          // salto (fracción de R)
    var ox:     CGFloat = 0          // sacudida (fracción de R)
    var tint:   CGFloat = 0          // cuánto tiñe el color del estado
    var morph:  CGFloat = 0          // 0 = ORBEX, 1 = portal de vidrio (subir archivo)
    var hands:  CGFloat = 0          // saludo: 0 = brazo en reposo, 1 = brazo derecho arriba
    var blush:  CGFloat = 0          // el vidrio se entibia (cariño, orgullo)
    var es:     CGFloat = 1          // escala de los ojos
    var badgeS: CGFloat = 0          // escala de la insignia
    var armsUp: CGFloat = 0          // los dos brazos arriba (festejo, estirarse)
    var glanceX: CGFloat = 0         // mirada extra de los microgestos
    var glanceY: CGFloat = 0

    // Objetivos
    var tgYaw:    CGFloat = 0
    var tgPitch:  CGFloat = 0
    var tgTilt:   CGFloat = 0
    var tgSy:     CGFloat = 1
    var tgSx:     CGFloat = 1
    var tgEs:     CGFloat = 1   // escala de ojos (mouse encima con cariño: 1,08)
    var tgTint:   CGFloat = 0

    /// Lienzo extra arriba para que las partículas suban sin cortarse (BotPlacement lo compensa).
    var particleOverhang: CGFloat = 0

    // MARK: Portal (subir archivo)

    /// Apertura del portal con resorte (fracción de R: 0 cerrado, 0,20 entreabierto, 0,42 abierto, 0,50 máximo).
    var slotH: CGFloat = 0
    var slotHTarget: CGFloat = 0
    var slotHVel: CGFloat = 0
    /// ~0,8 s después de tragar: el remolino gira rapidísimo ("mastica").
    var isChewing: Bool = false
    /// Giro del remolino (radianes) y su velocidad (rad/s).
    var swirl: CGFloat = 0
    var swirlSpeed: CGFloat = 1.4
    private var gulpOpenUntil: Double = 0
    private var gulpToken: Int = 0
    private var rippleStart: Double = -10

    // Color del estado (animado)
    var col:  (CGFloat, CGFloat, CGFloat) = (0.902, 0.914, 0.933)
    var colT: (CGFloat, CGFloat, CGFloat) = (0.902, 0.914, 0.933)

    // Estado
    var state: BotState = .idle
    var cfg: BotStateCfg = BotStates[.idle]!

    // Ojos: expresión pasajera (emote) y permanente
    var eyeOverride: BotEyeShape? = nil
    var eyeOverrideUntil: Double = 0        // CACurrentMediaTime()
    var permanentEye: BotEyeShape? = nil    // vuelve cuando vence un emote o parpadeo
    var permanentEmote: BotEmote? = nil     // para el comportamiento periódico de los mini
    var miniNextBehavior: Double = 0

    // Insignia
    var badge: BadgeType? = nil
    var badgeKey: String = "none"
    var badgeToken: Int = 0

    // Tweens (por nombre de propiedad)
    var tweens: [String: Tween] = [:]
    var locks:  Set<String> = []

    var particles: [Particle] = []

    // Mirada (−1…1; la pone el lienzo según el cursor)
    var lookX: CGFloat = 0
    var lookY: CGFloat = 0

    // Tiempo: todo el motor usa un solo reloj, CACurrentMediaTime()
    var lastTime: Double = CACurrentMediaTime()
    var t0: Double = CACurrentMediaTime() - Double.random(in: 0...5)
    var waveUntil: Double = 0
    var waveStart: Double = 0     // cuándo empieza a mover el brazo
    var greetToken: Int = 0       // invalida los pasos pendientes de un saludo viejo
    var lastAmbient: Double = 0

    // Toques (3 seguidos = mareo)
    var slapTimes: [Double] = []

    // Mini: mirada que pasea al azar
    var miniLookTarget: CGPoint = .zero
    var miniLookNextTime: Double = 0

    // MARK: Vida (respiración, parpadeo, microgestos)

    private var life = LifeScheduler(level: .normal, now: CACurrentMediaTime(),
                                     seed: UInt64.random(in: 1...UInt64.max))
    private var gesture: (kind: Microgesture, start: Double)? = nil
    private var limbs: CGFloat = 0        // 0…1 cuerpo entero (vista abierta), suave
    private var crouch: CGFloat = 0       // 0…1 agachado (dormido)
    private var floatY: CGFloat = 0       // flotación leve (fracción de R)
    private var lastLookInput: Double = 0
    private var prevLook: CGPoint = .zero

    // MARK: Relación con el usuario (caricia, cosquillas, timidez, globo) y extras por estado

    /// Lo pone el lienzo: este motor es el fantasma que se arrastra (globo que patalea).
    var carried: Bool = false
    /// Caricia en curso (mouse quieto encima de ORBEX, vista abierta). Ver `setPetting(_:)`.
    private(set) var petting: Bool = false
    private var petK: CGFloat = 0            // 0…1 intensidad de la caricia, suave
    private var purrX: CGFloat = 0           // vibración del ronroneo (fracción de R)
    private var nextPetHeart: Double = 0
    private var nearSince: Double = 0        // desde cuándo el cursor está cerca (timidez)
    private var shyCooldown: Double = 0
    private var fog: CGFloat = 0             // vidrio empañado (error), suave
    private var deflate: CGFloat = 0         // desinflado (límite de uso), suave
    /// Idle raro en curso que se dibuja cuadro a cuadro (burbuja con la que juega).
    private var bubblePlayStart: Double = 0
    private static let bubblePlayDur: Double = 2.6
    private var lifeTuned = false

    // MARK: Escucha por voz ("Orbex, …")

    /// 0…1: cuánto está escuchando (suave). Lleva la mano a la oreja, los anillos y el acercamiento.
    private(set) var listenK: CGFloat = 0
    /// Nivel de la voz del usuario (0…1), suavizado: sube rápido y baja despacio.
    private(set) var voiceLevel: CGFloat = 0
    private var voiceTarget: CGFloat = 0
    private var voiceLevelAt: Double = 0
    /// Fase de los anillos (avanza más rápido cuanto más fuerte habla).
    private var ringPhase: Double = 0
    /// Rebote de los ojos con el volumen (resorte poco amortiguado).
    private var eyeBounce: CGFloat = 0
    private var eyeBounceVel: CGFloat = 0
    /// Destello al oír su nombre; enfriamiento de la entrada y del "entendido".
    private var listenFlashAt: Double = -10
    private var lastHearAt: Double = -10
    private var lastAckAt: Double = -10

    // MARK: Habla (voz de salida): se superpone a cualquier estado

    private var speakOn = false
    /// 0…1: cuánto está hablando (entrada y salida suaves).
    private(set) var speakK: CGFloat = 0
    /// Nivel de la voz de Orbi (0…1), suavizado.
    private(set) var speakLevel: CGFloat = 0
    private var speakTarget: CGFloat = 0
    private var speakPrevTarget: CGFloat = 0
    private var speakLevelAt: Double = 0
    /// Escala que late con los picos (resorte).
    private var speakPulse: CGFloat = 0
    private var speakPulseVel: CGFloat = 0
    /// Anillos que salen con las sílabas fuertes (como mucho dos vivos).
    private var speakRings: [(start: Double, strength: Double)] = []
    private var lastSpeakRingAt: Double = -10
    private static let speakRingLife: Double = 0.75
    /// Brazo-gota que gesticula de a ratos (vista grande).
    private var speakArmStart: Double = -10
    private var speakArmSide: Double = -1
    private var speakArmNext: Double = 0
    private static let speakArmDur: Double = 1.3

    // MARK: Ambiente (tema, tinte, reducir movimiento): se relee dos veces por segundo

    private(set) var reduceMotion: Bool = false
    private(set) var material: OrbexMaterial = .glass
    private var userTint: (r: Double, g: Double, b: Double) = OrbexTint.clear.rgb
    private var frameTint: (r: Double, g: Double, b: Double) = OrbexTint.clear.rgb
    private var nextEnvCheck: Double = 0

    // MARK: - API pública

    func setState(_ newState: BotState, force: Bool = false) {
        guard state != newState || force else { return }
        let prev = state
        state = newState
        cfg = BotStates[newState]!
        colT = cgColorToTuple(cfg.color)
        setTarget(key: "tint", value: cfg.tint)
        setTarget(key: "tilt", value: cfg.tilt)
        setBadge(cfg.badge)

        // Sonido del estado: solo en cambios de verdad (no al aparecer la vista) y nunca en los mini.
        if !force && prev != newState && !isMini, let name = cfg.sound {
            BotSoundGate.play(name, gap: Self.stateSoundGap(name))
        }

        let m: CGFloat = reduceMotion ? 0.3 : 1
        // Se despierta: sobresalto y estirada (antes de la reacción del estado nuevo).
        let wakes = prev == .sleeping && newState != .sleeping && !force && !isMini
        if wakes { wakeUp() }
        // Terminó de escuchar: asiente ("entendido") y sigue con el estado nuevo.
        let heard = prev == .listening && newState != .listening && !force && !isMini
        if heard { acknowledgeListening() }
        switch newState {
        case .finished:
            // Voltereta con saltito y confeti de vidrio.
            if !reduceMotion { doRoll(duration: 950, turns: 1) }
            anim("oy", keys: [
                TweenKey(target: -0.28 * m, duration: 220, ease: Ease.out),
                TweenKey(target: -0.28 * m, duration: 420, ease: Ease.lin),
                TweenKey(target: 0,         duration: 380, ease: Ease.back),
            ])
            anim("armsUp", keys: [
                TweenKey(target: 1, duration: 220, ease: Ease.out),
                TweenKey(target: 1, duration: 700, ease: Ease.lin),
                TweenKey(target: 0, duration: 320, ease: Ease.inOut),
            ])
            after(0.5) { e in
                e.emit(.spark, count: 5)
                e.emit(.confetti, count: e.reduceMotion ? 6 : 14)
            }
        case .error:
            anim("ox", keys: [
                TweenKey(target: 0.08 * m,  duration: 50, ease: Ease.out),
                TweenKey(target: -0.08 * m, duration: 70, ease: Ease.inOut),
                TweenKey(target: 0.05 * m,  duration: 70, ease: Ease.inOut),
                TweenKey(target: 0,         duration: 90, ease: Ease.out),
            ])
        case .approval:
            anim("oy", keys: [
                TweenKey(target: -0.2 * m, duration: 150, ease: Ease.out),
                TweenKey(target: 0,        duration: 300, ease: Ease.back),
            ])
        case .dizzy:
            if !reduceMotion { doRoll(duration: 1300, turns: 2) }
        case .question:
            blink()
        case .ratelimit:
            emit(.sweat, count: 1)
        case .listening:
            // Oyó su nombre: saltito + destello (si se estaba despertando, solo el destello).
            if !isMini { hearName(hop: !wakes) }
        default:
            if !wakes && !heard && (prev != .idle || newState != .idle) { blink() }
        }
    }

    // MARK: - Escucha por voz

    /// La voz empezó (`true`) o terminó (`false`) de escuchar un pedido (`orbex.voice.listening`).
    /// El color y el gesto los da el estado `.listening`; esto adelanta la entrada o el "entendido"
    /// si la notificación llega antes que el cambio de estado (cada uno corre una sola vez).
    func voiceListening(_ on: Bool) {
        guard !isMini else { return }
        if on {
            hearName(hop: true)
        } else {
            voiceTarget = 0
            if state == .listening || listenK > 0.3 { acknowledgeListening() }
        }
    }

    /// Nivel de la voz del usuario, 0…1 (`orbex.voice.level`, ~20 Hz).
    func setVoiceLevel(_ level: CGFloat) {
        guard level.isFinite else { return }
        voiceTarget = max(0, min(1, level))
        voiceLevelAt = CACurrentMediaTime()
    }

    // MARK: - Habla (voz de salida)

    /// Orbi empezó (`true`) o terminó (`false`) de hablar (`orbex.voice.speaking`).
    /// Se superpone al estado actual; entra y sale suave.
    func voiceSpeaking(_ on: Bool) {
        guard on != speakOn else { return }
        speakOn = on
        if on {
            speakArmNext = CACurrentMediaTime() + Double.random(in: 0.6...1.4)
        } else {
            speakTarget = 0
        }
    }

    /// Nivel de la voz de Orbi, 0…1 (`orbex.voice.outLevel`, ~20 Hz).
    func setVoiceOutLevel(_ level: CGFloat) {
        guard level.isFinite else { return }
        speakTarget = max(0, min(1, level))
        speakLevelAt = CACurrentMediaTime()
    }

    /// Cuánto se ve el habla: la escucha tiene prioridad visual.
    private var speakVis: CGFloat { speakK * (1 - listenK) }

    /// Una vez por cuadro: presencia del habla, nivel, latido, anillos y gesto del brazo.
    private func updateSpeaking(now: Double, dt: Double) {
        guard speakOn || speakK > 0.001 || speakLevel > 0.001 || !speakRings.isEmpty
                || abs(speakPulse) > 0.0005 || abs(speakPulseVel) > 0.005 else {
            speakK = 0; speakLevel = 0; speakPulse = 0; speakPulseVel = 0
            return
        }
        speakK += ((speakOn ? 1 : 0) - speakK) * CGFloat(1 - exp(-dt * (speakOn ? 6 : 3.5)))
        if !speakOn { speakTarget = 0 } else if now - speakLevelAt > 0.3 { speakTarget *= CGFloat(exp(-dt * 6)) }
        let rate: Double = speakTarget > speakLevel ? 24 : 9
        speakLevel += (speakTarget - speakLevel) * CGFloat(1 - exp(-dt * rate))

        let vis = speakVis
        let lively = !reduceMotion && !isMini && fullBody
        // Sílaba fuerte: el nivel sube de golpe → anillo (vista grande, sin "reducir movimiento").
        let jump = speakTarget - speakPrevTarget
        speakPrevTarget = speakTarget
        if lively && vis > 0.3 && speakTarget > 0.45 && jump > 0.12 && now - lastSpeakRingAt > 0.3 {
            lastSpeakRingAt = now
            speakRings.append((start: now, strength: Double(min(1, speakTarget))))
            if speakRings.count > 2 { speakRings.removeFirst(speakRings.count - 2) }
        }
        speakRings.removeAll { now - $0.start >= Self.speakRingLife }

        if lively {
            let w: CGFloat = 2 * .pi * 3.6, z: CGFloat = 0.35, d = CGFloat(dt)
            speakPulseVel += (w * w * (speakLevel * vis - speakPulse) - 2 * z * w * speakPulseVel) * d
            speakPulse += speakPulseVel * d
            // Gesto del brazo de a ratos (alterna de lado; nunca pisa la mano de la oreja).
            if speakOn && vis > 0.5 && now >= speakArmNext && now - speakArmStart > Self.speakArmDur {
                speakArmStart = now
                speakArmSide = speakArmSide > 0 ? -1 : 1
                speakArmNext = now + Self.speakArmDur + Double.random(in: 1.8...4.2)
            }
        } else {
            speakPulse = 0
            speakPulseVel = 0
        }
    }

    /// Envolvente 0…1 del gesto del brazo al hablar.
    private func speakArmEnv(_ now: Double) -> Double {
        let p = (now - speakArmStart) / Self.speakArmDur
        guard p >= 0 && p < 1 else { return 0 }
        return sin(.pi * p)
    }

    /// Oyó "Orbex": saltito con squash, ojos que se abren grandes y destello magenta.
    private func hearName(hop: Bool) {
        let now = CACurrentMediaTime()
        guard now - lastHearAt > 1.0 else { return }
        lastHearAt = now
        interruptGreet()
        listenFlashAt = now
        guard !reduceMotion else { return }   // sin rebotes: alcanza con el destello
        let lite = !fullBody
        anim("es", keys: [
            TweenKey(target: 1.22, duration: 110, ease: Ease.out),
            TweenKey(target: 1,    duration: 420, ease: Ease.inOut),
        ])
        guard hop else { return }
        let m: CGFloat = lite ? 0.6 : 1
        anim("oy", keys: [
            TweenKey(target: -0.24 * m, duration: 130, ease: Ease.out),
            TweenKey(target: 0,         duration: 330, ease: Ease.back),
        ])
        anim("sy", keys: [
            TweenKey(target: 1.1,  duration: 110, ease: Ease.out),
            TweenKey(target: 0.9,  duration: 150, ease: Ease.inOut),
            TweenKey(target: 1,    duration: 220, ease: Ease.back),
        ])
        anim("sx", keys: [
            TweenKey(target: 0.94, duration: 110, ease: Ease.out),
            TweenKey(target: 1.08, duration: 150, ease: Ease.inOut),
            TweenKey(target: 1,    duration: 220, ease: Ease.back),
        ])
        if !lite { emit(.spark, count: 3) }
    }

    /// "Entendido": asiente dos veces (squash vertical doble + cabeceo) con ojos felices un instante.
    private func acknowledgeListening() {
        let now = CACurrentMediaTime()
        guard now - lastAckAt > 1.0 else { return }
        lastAckAt = now
        voiceTarget = 0
        eyeOverride = .happy
        eyeOverrideUntil = now + 0.75
        guard !reduceMotion else { return }   // sin rebotes: solo los ojos felices
        anim("sy", keys: [
            TweenKey(target: 0.87, duration: 90,  ease: Ease.out),
            TweenKey(target: 1.03, duration: 120, ease: Ease.inOut),
            TweenKey(target: 0.9,  duration: 100, ease: Ease.out),
            TweenKey(target: 1,    duration: 220, ease: Ease.back),
        ])
        anim("sx", keys: [
            TweenKey(target: 1.08, duration: 90,  ease: Ease.out),
            TweenKey(target: 0.98, duration: 120, ease: Ease.inOut),
            TweenKey(target: 1.06, duration: 100, ease: Ease.out),
            TweenKey(target: 1,    duration: 220, ease: Ease.back),
        ])
        anim("pitch", keys: [
            TweenKey(target: -0.24, duration: 90,  ease: Ease.out),
            TweenKey(target: 0.02,  duration: 120, ease: Ease.inOut),
            TweenKey(target: -0.18, duration: 100, ease: Ease.out),
            TweenKey(target: 0,     duration: 220, ease: Ease.inOut),
        ])
    }

    /// Una vez por cuadro: presencia de la escucha, nivel de la voz, fase de los anillos y rebote de ojos.
    private func updateListening(now: Double, dt: Double) {
        let on = state == .listening
        guard on || listenK > 0.001 || voiceLevel > 0.001 || voiceTarget > 0.001
                || abs(eyeBounce) > 0.0005 || abs(eyeBounceVel) > 0.005 else {
            listenK = 0; voiceLevel = 0; eyeBounce = 0; eyeBounceVel = 0
            return
        }
        listenK += ((on ? 1 : 0) - listenK) * CGFloat(1 - exp(-dt * 7))
        // Sin datos nuevos (o fuera de la escucha) el nivel se apaga solo.
        if !on { voiceTarget = 0 } else if now - voiceLevelAt > 0.3 { voiceTarget *= CGFloat(exp(-dt * 5)) }
        let rate: Double = voiceTarget > voiceLevel ? 22 : 7
        voiceLevel += (voiceTarget - voiceLevel) * CGFloat(1 - exp(-dt * rate))
        ringPhase += dt * (0.5 + 0.7 * Double(voiceLevel))
        if ringPhase > 1000 { ringPhase -= 1000 }
        if reduceMotion || isMini || !fullBody {
            eyeBounce = 0
            eyeBounceVel = 0
        } else {
            let w: CGFloat = 2 * .pi * 3.2, z: CGFloat = 0.3, d = CGFloat(dt)
            eyeBounceVel += (w * w * (voiceLevel * listenK - eyeBounce) - 2 * z * w * eyeBounceVel) * d
            eyeBounce += eyeBounceVel * d
        }
    }

    func setBadge(_ b: BadgeType?) {
        let key = badgeString(b)
        guard key != badgeKey else { return }
        badgeKey = key
        let tok = badgeToken + 1
        badgeToken = tok
        anim("badgeS", keys: [TweenKey(target: 0, duration: 90, ease: Ease.inOut)])
        after(0.1) { e in
            guard tok == e.badgeToken else { return }
            e.badge = b
            if b != nil {
                e.anim("badgeS", keys: [TweenKey(target: 1, duration: 280, ease: Ease.back)])
            }
        }
    }

    func blink() {
        guard !locks.contains("open") else { return }
        anim("open", keys: [
            TweenKey(target: 0.06, duration: 70,  ease: Ease.inOut),
            TweenKey(target: 1,    duration: 130, ease: Ease.out),
        ])
    }

    func squash() {
        anim("sy", keys: [
            TweenKey(target: 0.78, duration: 70,  ease: Ease.out),
            TweenKey(target: 1.1,  duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 170, ease: Ease.inOut),
        ])
        anim("sx", keys: [
            TweenKey(target: 1.16, duration: 70,  ease: Ease.out),
            TweenKey(target: 0.95, duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 170, ease: Ease.inOut),
        ])
    }

    // MARK: - Tragar por el portal

    /// El portal se abre grande, se cierra tragando (contracción + ondita) y "mastica" (remolino rápido).
    /// Toda la apertura vive en el motor: el lienzo ya no la pisa en cada cuadro.
    func gulp() {
        gulpToken += 1
        let tok = gulpToken
        gulpOpenUntil = CACurrentMediaTime() + 0.46
        isChewing = false
        slotHTarget = 0.42
        anim("sy", keys: [
            TweenKey(target: 1.06, duration: 120, ease: Ease.out),
            TweenKey(target: 1.0,  duration: 340, ease: Ease.inOut),
        ])
        blink()
        after(0.46) { e in
            guard e.gulpToken == tok else { return }
            e.gulpOpenUntil = 0
            e.isChewing = true
            e.rippleStart = CACurrentMediaTime()
            e.anim("sx", keys: [
                TweenKey(target: 0.84, duration: 90,  ease: Ease.out),
                TweenKey(target: 1.08, duration: 150, ease: Ease.out),
                TweenKey(target: 1,    duration: 240, ease: Ease.back),
            ])
            e.anim("sy", keys: [
                TweenKey(target: 0.84, duration: 90,  ease: Ease.out),
                TweenKey(target: 1.08, duration: 150, ease: Ease.out),
                TweenKey(target: 1,    duration: 240, ease: Ease.back),
            ])
            e.emit(.bubble, count: 3)
            e.sound("gulp", gap: 0.5)
            e.after(0.8) { e2 in
                guard e2.gulpToken == tok else { return }
                e2.isChewing = false
                e2.sound("attach", gap: 0.5)
            }
        }
    }

    // MARK: - Cosquillas (tres clics rápidos = mareo)

    /// API heredada: el clic sobre ORBEX ya no es una cachetada sino cosquillas.
    func slap() { tickle() }

    /// Clic sobre ORBEX: se ríe (ojos felices, se sacude, chispitas). Tres clics en menos de 1,2 s
    /// lo marean: avisa con `.botDizzy` (la isla pasa a `.dizzy` y muestra la vista `confused`).
    func tickle() {
        interruptGreet()
        guard state != .dizzy else { return }
        let now = CACurrentMediaTime()
        slapTimes = slapTimes.filter { now - $0 < 1.2 }
        slapTimes.append(now)
        sound("blip", gap: 0.08)
        squash()
        if slapTimes.count >= 3 {
            slapTimes = []
            emit(.star, count: 3)
            NotificationCenter.default.post(name: .botDizzy, object: nil)
            return
        }
        let m: CGFloat = reduceMotion ? 0.3 : 1
        eyeOverride = .happy
        eyeOverrideUntil = now + 0.9
        // Risita: se sacude de lado a lado con saltitos cortos.
        anim("tilt", keys: [
            TweenKey(target:  0.12 * m, duration: 60,  ease: Ease.out),
            TweenKey(target: -0.12 * m, duration: 90,  ease: Ease.inOut),
            TweenKey(target:  0.09 * m, duration: 90,  ease: Ease.inOut),
            TweenKey(target: -0.06 * m, duration: 90,  ease: Ease.inOut),
            TweenKey(target:  0,        duration: 140, ease: Ease.out),
        ])
        anim("oy", keys: [
            TweenKey(target: -0.07 * m, duration: 80,  ease: Ease.out),
            TweenKey(target:  0,        duration: 90,  ease: Ease.inOut),
            TweenKey(target: -0.05 * m, duration: 80,  ease: Ease.out),
            TweenKey(target:  0,        duration: 150, ease: Ease.back),
        ])
        anim("blush", keys: [
            TweenKey(target: 0.6, duration: 120, ease: Ease.out),
            TweenKey(target: 0,   duration: 700, ease: Ease.inOut),
        ])
        emit(.spark, count: 3)
    }

    // MARK: - Caricia (mouse quieto encima)

    /// Caricia: con el mouse quieto encima, ORBEX se ruboriza, cierra los ojos feliz, suelta
    /// corazoncitos y "ronronea" (vibración suave). La prende y apaga la ventana de la isla.
    func setPetting(_ on: Bool) {
        guard !isMini, on != petting else { return }
        petting = on
        let now = CACurrentMediaTime()
        if on {
            nextPetHeart = now + 0.25
            nearSince = 0
        } else if eyeOverride == .happy && eyeOverrideUntil < now + 0.5 {
            // Abre los ojos con un parpadeo.
            eyeOverrideUntil = now
            after(0.02) { $0.blink() }
        }
    }

    // MARK: - Despertarse, timidez e idles raros

    /// Al despertar: se sobresalta (ojos grandes, saltito) y después se estira bostezando.
    func wakeUp() {
        let now = CACurrentMediaTime()
        let m: CGFloat = reduceMotion ? 0.3 : 1
        eyeOverride = .wide
        eyeOverrideUntil = now + 0.55
        anim("oy", keys: [
            TweenKey(target: -0.32 * m, duration: 130, ease: Ease.out),
            TweenKey(target: 0,         duration: 380, ease: Ease.back),
        ])
        anim("es", keys: [
            TweenKey(target: 1.3, duration: 110, ease: Ease.out),
            TweenKey(target: 1,   duration: 450, ease: Ease.inOut),
        ])
        emit(.spark, count: 2)
        sound("pop", gap: 0.6)
        after(0.7) { e in
            e.anim("armsUp", keys: [
                TweenKey(target: 0.9, duration: 420, ease: Ease.out),
                TweenKey(target: 0.9, duration: 380, ease: Ease.lin),
                TweenKey(target: 0,   duration: 450, ease: Ease.inOut),
            ])
            e.anim("sy", keys: [
                TweenKey(target: 1 + 0.08 * m, duration: 420, ease: Ease.inOut),
                TweenKey(target: 1 + 0.08 * m, duration: 380, ease: Ease.lin),
                TweenKey(target: 1,            duration: 450, ease: Ease.inOut),
            ])
            e.anim("sx", keys: [
                TweenKey(target: 1 - 0.05 * m, duration: 420, ease: Ease.inOut),
                TweenKey(target: 1 - 0.05 * m, duration: 380, ease: Ease.lin),
                TweenKey(target: 1,            duration: 450, ease: Ease.inOut),
            ])
            e.eyeOverride = .tired
            e.eyeOverrideUntil = CACurrentMediaTime() + 1.0
            e.sound("yawn", gap: 2)
        }
    }

    /// Tímido: el cursor se quedó mucho cerca mirándolo → mira para el otro lado y se ruboriza.
    private func beShy(now: Double) {
        shyCooldown = now + 30
        nearSince = 0
        let away: CGFloat = lookX >= 0 ? -1 : 1
        let m: CGFloat = reduceMotion ? 0.35 : 1
        anim("glanceX", keys: [
            TweenKey(target: away * 1.0, duration: 260, ease: Ease.out),
            TweenKey(target: away * 1.0, duration: 1400, ease: Ease.lin),
            TweenKey(target: 0,          duration: 450, ease: Ease.inOut),
        ])
        anim("glanceY", keys: [
            TweenKey(target: -0.35, duration: 260, ease: Ease.out),
            TweenKey(target: -0.35, duration: 1400, ease: Ease.lin),
            TweenKey(target: 0,     duration: 450, ease: Ease.inOut),
        ])
        anim("tilt", keys: [
            TweenKey(target: away * 0.1 * m, duration: 300, ease: Ease.out),
            TweenKey(target: away * 0.1 * m, duration: 1300, ease: Ease.lin),
            TweenKey(target: 0,              duration: 450, ease: Ease.inOut),
        ])
        anim("blush", keys: [
            TweenKey(target: 0.95, duration: 350, ease: Ease.out),
            TweenKey(target: 0.95, duration: 1300, ease: Ease.lin),
            TweenKey(target: 0,    duration: 600, ease: Ease.inOut),
        ])
        after(0.35) { $0.blink() }
        after(1.5) { $0.blink() }
    }

    /// Idles raros (aburrido): juega con una burbuja, estornudo, guiño, orgulloso, vuelta u ojos de corazón.
    private func startRareIdle(now: Double) {
        switch Int.random(in: 0..<6) {
        case 0:
            // Juega con una burbuja que le rebota en la cabeza; al final la pincha.
            bubblePlayStart = now
            let d = Self.bubblePlayDur
            for k in [1.0 / 3.0, 2.0 / 3.0] {
                after(d * k) { e in
                    guard e.bubblePlayStart == now else { return }
                    e.anim("sy", keys: [
                        TweenKey(target: 0.93, duration: 70,  ease: Ease.out),
                        TweenKey(target: 1,    duration: 200, ease: Ease.back),
                    ])
                }
            }
            after(d) { e in
                guard e.bubblePlayStart == now else { return }
                e.bubblePlayStart = 0
                e.emit(.spark, count: 3)
                e.sound("pop", gap: 1)
                e.eyeOverride = .happy
                e.eyeOverrideUntil = CACurrentMediaTime() + 0.6
                e.anim("glanceY", keys: [TweenKey(target: 0, duration: 350, ease: Ease.inOut)])
            }
        case 1:
            sneeze()
        case 2:
            triggerEmote(.wink, duration: 1.0)
        case 3:
            triggerEmote(.proud, duration: 1.6)
        case 4:
            doRoll(duration: 1100, turns: 1)
            emit(.spark, count: 3)
        default:
            triggerEmote(.love, duration: 1.4, silent: true)
        }
    }

    /// Estornudo: toma aire (se estira entrecerrando los ojos) y ¡achís! (se aplasta, cabecea y suelta burbujitas).
    private func sneeze() {
        let now = CACurrentMediaTime()
        eyeOverride = .tired
        eyeOverrideUntil = now + 0.6
        anim("sy", keys: [
            TweenKey(target: 1.08, duration: 550, ease: Ease.inOut),
            TweenKey(target: 0.82, duration: 70,  ease: Ease.out),
            TweenKey(target: 1.05, duration: 150, ease: Ease.out),
            TweenKey(target: 1,    duration: 220, ease: Ease.back),
        ])
        anim("sx", keys: [
            TweenKey(target: 0.95, duration: 550, ease: Ease.inOut),
            TweenKey(target: 1.13, duration: 70,  ease: Ease.out),
            TweenKey(target: 0.97, duration: 150, ease: Ease.out),
            TweenKey(target: 1,    duration: 220, ease: Ease.back),
        ])
        anim("glanceY", keys: [
            TweenKey(target: 0.5,  duration: 550, ease: Ease.inOut),
            TweenKey(target: -0.4, duration: 80,  ease: Ease.out),
            TweenKey(target: 0,    duration: 400, ease: Ease.inOut),
        ])
        after(0.56) { e in
            e.eyeOverride = .closed
            e.eyeOverrideUntil = CACurrentMediaTime() + 0.3
            e.anim("ox", keys: [
                TweenKey(target: -0.06, duration: 60,  ease: Ease.out),
                TweenKey(target:  0.03, duration: 120, ease: Ease.inOut),
                TweenKey(target:  0,    duration: 160, ease: Ease.out),
            ])
            e.emit(.bubble, count: 4)
            e.sound("pop", gap: 1)
        }
        after(0.95) { e in
            e.eyeOverride = .dot
            e.eyeOverrideUntil = CACurrentMediaTime() + 0.5
        }
    }

    // MARK: - Comportamiento periódico de los mini

    func doMiniBehaviorLoop() {
        switch permanentEmote {

        case .happy:
            // Saltito con squash
            guard !locks.contains("oy") else {
                miniNextBehavior = CACurrentMediaTime() + 0.4
                return
            }
            anim("oy", keys: [
                TweenKey(target: -0.30, duration: 120, ease: Ease.out),
                TweenKey(target:  0.03, duration: 200, ease: Ease.inOut),
                TweenKey(target:  0,    duration: 160, ease: Ease.back),
            ])
            anim("sy", keys: [
                TweenKey(target: 0.82, duration: 80,  ease: Ease.out),
                TweenKey(target: 1.18, duration: 130, ease: Ease.out),
                TweenKey(target: 0.88, duration: 160, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 200, ease: Ease.back),
            ])
            anim("sx", keys: [
                TweenKey(target: 1.15, duration: 80,  ease: Ease.out),
                TweenKey(target: 0.88, duration: 130, ease: Ease.out),
                TweenKey(target: 1.06, duration: 160, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 200, ease: Ease.back),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.2 + Double.random(in: 0...1.2)

        case .annoyed:
            // Sacude la cabeza
            guard !locks.contains("yaw") else {
                miniNextBehavior = CACurrentMediaTime() + 0.5
                return
            }
            anim("yaw", keys: [
                TweenKey(target: -0.65, duration: 50,  ease: Ease.out),
                TweenKey(target:  0.65, duration: 90,  ease: Ease.inOut),
                TweenKey(target: -0.5,  duration: 80,  ease: Ease.inOut),
                TweenKey(target:  0.4,  duration: 75,  ease: Ease.inOut),
                TweenKey(target: -0.2,  duration: 70,  ease: Ease.inOut),
                TweenKey(target:  0,    duration: 140, ease: Ease.out),
            ])
            miniNextBehavior = CACurrentMediaTime() + 3.0 + Double.random(in: 0...2.5)

        case .wink:
            // Guiño con la cabeza un poco inclinada
            eyeOverride = .wink
            eyeOverrideUntil = CACurrentMediaTime() + 0.55
            anim("tilt", keys: [
                TweenKey(target:  0.13, duration: 100, ease: Ease.out),
                TweenKey(target:  0.13, duration: 320, ease: Ease.lin),
                TweenKey(target:  0,    duration: 200, ease: Ease.inOut),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.2 + Double.random(in: 0...2.0)

        case .love:
            // Se hamaca suave
            emit(.heart, count: 2)
            anim("tilt", keys: [
                TweenKey(target: -0.1, duration: 180, ease: Ease.out),
                TweenKey(target:  0.1, duration: 340, ease: Ease.inOut),
                TweenKey(target:  0,   duration: 220, ease: Ease.inOut),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.6 + Double.random(in: 0...1.5)

        default:
            miniNextBehavior = CACurrentMediaTime() + 3.0 + Double.random(in: 0...2.0)
        }
    }

    func doRoll(duration: CGFloat, turns: CGFloat) {
        roll = 0
        anim("roll", keys: [TweenKey(target: .pi * 2 * turns, duration: duration, ease: Ease.inOut)]) { [weak self] in
            self?.roll = 0
        }
    }

    // MARK: - Saludo (brazo derecho arriba + ojos felices + sonido)

    func greet() {
        let now = CACurrentMediaTime()
        greetToken += 1
        let tok = greetToken
        waveStart = now + 0.45   // el brazo empieza a moverse
        waveUntil = now + 1.55   // y termina
        let m: CGFloat = reduceMotion ? 0.35 : 1

        // 0 s: ojos felices todo el saludo y saltito
        eyeOverride = .happy
        eyeOverrideUntil = now + 2.0
        anim("oy", keys: [
            TweenKey(target: -0.06 * m, duration: 220, ease: Ease.out),
            TweenKey(target:  0.0,      duration: 220, ease: Ease.back),
        ])

        // 0,25 s: sube el brazo, se aplasta un poquito y suena el saludo
        after(0.25) { e in
            guard e.greetToken == tok else { return }
            e.anim("hands", keys: [TweenKey(target: 1, duration: 280, ease: Ease.out)])
            e.anim("sy", keys: [
                TweenKey(target: 0.95, duration: 100, ease: Ease.out),
                TweenKey(target: 1.0,  duration: 260, ease: Ease.back),
            ])
            e.anim("sx", keys: [
                TweenKey(target: 1.04, duration: 100, ease: Ease.out),
                TweenKey(target: 1.0,  duration: 260, ease: Ease.back),
            ])
            e.sound("greet", gap: 1.0)
        }
        // 0,55 s y 1,5 s: parpadeos
        after(0.55) { e in
            guard e.greetToken == tok else { return }
            e.blink()
        }
        after(1.50) { e in
            guard e.greetToken == tok else { return }
            e.blink()
        }
        // 1,55 s: baja el brazo
        after(1.55) { e in
            guard e.greetToken == tok else { return }
            e.waveUntil = 0
            e.anim("hands", keys: [TweenKey(target: 0, duration: 200, ease: Ease.inOut)])
        }
        // 1,75 s: un toquecito más de ojos felices y vuelve a lo normal
        after(1.75) { e in
            guard e.greetToken == tok else { return }
            e.eyeOverride = .happy
            e.eyeOverrideUntil = CACurrentMediaTime() + 0.30
        }
    }

    /// Corta un saludo en curso (el brazo baja en 150 ms).
    func interruptGreet() {
        guard hands > 0.01 || CACurrentMediaTime() < waveUntil else { return }
        greetToken += 1   // invalida los pasos pendientes
        waveUntil = 0
        waveStart = 0
        anim("hands", keys: [TweenKey(target: 0, duration: 150, ease: Ease.inOut)])
    }

    /// Expresión permanente que sobrevive a parpadeos y emotes pasajeros.
    func setPermanentEmote(_ emote: BotEmote?) {
        permanentEmote = emote
        // .wink es periódico: entre guiño y guiño el ojo queda normal
        if emote == .wink {
            miniNextBehavior = CACurrentMediaTime() + Double.random(in: 0.8...2.5)
            return
        }
        permanentEye = emote.map { emoteEyeShape($0) }
        if let eye = permanentEye {
            eyeOverride = eye
            eyeOverrideUntil = .greatestFiniteMagnitude
        } else {
            if eyeOverrideUntil == .greatestFiniteMagnitude {
                eyeOverride = nil
                eyeOverrideUntil = 0
            }
        }
        // Escalonar el primer comportamiento para que los mini no se muevan todos juntos
        miniNextBehavior = CACurrentMediaTime() + Double.random(in: 0.8...2.5)
    }

    func triggerEmote(_ emote: BotEmote, duration: Double = 1.8, silent: Bool = false) {
        let now = CACurrentMediaTime()
        eyeOverride = emoteEyeShape(emote)
        eyeOverrideUntil = now + duration
        let m: CGFloat = reduceMotion ? 0.35 : 1

        switch emote {
        case .love:
            anim("blush", keys: [
                TweenKey(target: 1, duration: 300, ease: Ease.out),
                TweenKey(target: 1, duration: holdMs(duration, 0.6), ease: Ease.lin),
                TweenKey(target: 0, duration: 300, ease: Ease.inOut),
            ])
            emit(.heart, count: 4)
            anim("oy", keys: [
                TweenKey(target: -0.1 * m, duration: 160, ease: Ease.out),
                TweenKey(target: 0,        duration: 300, ease: Ease.back),
            ])
        case .surprised:
            anim("oy", keys: [
                TweenKey(target: -0.3 * m, duration: 140, ease: Ease.out),
                TweenKey(target: 0,        duration: 380, ease: Ease.back),
            ])
            anim("es", keys: [
                TweenKey(target: 1.25, duration: 120, ease: Ease.out),
                TweenKey(target: 1,    duration: 500, ease: Ease.inOut),
            ])
        case .proud:
            emit(.star, count: 5)
            anim("tilt", keys: [
                TweenKey(target: -0.14 * m, duration: 220, ease: Ease.out),
                TweenKey(target: -0.14 * m, duration: holdMs(duration, 0.5), ease: Ease.lin),
                TweenKey(target: 0,         duration: 280, ease: Ease.inOut),
            ])
            anim("blush", keys: [
                TweenKey(target: 0.7, duration: 250, ease: Ease.out),
                TweenKey(target: 0.7, duration: holdMs(duration, 0.5), ease: Ease.lin),
                TweenKey(target: 0,   duration: 300, ease: Ease.inOut),
            ])
            anim("armsUp", keys: [
                TweenKey(target: 0.8, duration: 220, ease: Ease.out),
                TweenKey(target: 0.8, duration: holdMs(duration, 0.5), ease: Ease.lin),
                TweenKey(target: 0,   duration: 300, ease: Ease.inOut),
            ])
        case .wink:
            anim("tilt", keys: [
                TweenKey(target: 0.12 * m, duration: 160, ease: Ease.out),
                TweenKey(target: 0.12 * m, duration: holdMs(duration, 0.4), ease: Ease.lin),
                TweenKey(target: 0,        duration: 240, ease: Ease.inOut),
            ])
        case .yawn:
            anim("sy", keys: [
                TweenKey(target: 1 + 0.12 * m, duration: 500, ease: Ease.inOut),
                TweenKey(target: 1,            duration: 500, ease: Ease.inOut),
            ])
            anim("sx", keys: [
                TweenKey(target: 1 - 0.06 * m, duration: 500, ease: Ease.inOut),
                TweenKey(target: 1,            duration: 500, ease: Ease.inOut),
            ])
            after(0.7) { e in
                guard e.eyeOverride == .tired else { return }
                e.eyeOverride = .closed
                e.emit(.z, count: 2)
            }
        case .happy:
            anim("blush", keys: [
                TweenKey(target: 0.6, duration: 200, ease: Ease.out),
                TweenKey(target: 0,   duration: 600, ease: Ease.inOut),
            ])
        case .annoyed:
            eyeOverride = .line
            eyeOverrideUntil = now + 0.8
        }

        guard !silent else { return }
        if emote == .annoyed {
            after(0.06) { $0.sound("annoyed", gap: 0.3) }
        } else if let name = emoteSoundName(emote) {
            // En el próximo ciclo: si el evento que lo disparó ya sonó por el bus, ORBEX no suma otro sonido.
            after(0) { e in
                guard !BotSoundGate.busSounded(within: 0.3) else { return }
                e.sound(name, gap: 0.9)
            }
        }
    }

    func emit(_ type: Particle.ParticleType, count: Int) {
        guard !isMini, count > 0 else { return }   // los mini no dibujan partículas
        for i in 0..<count {
            var p = Particle(
                type: type,
                x: CGFloat.random(in: -0.45...0.45),
                y: -0.7 - CGFloat.random(in: 0...0.2),
                vx: CGFloat.random(in: -0.5...0.5) * 0.35,
                vy: -(0.45 + CGFloat.random(in: 0...0.35)),
                age: -Double(i) * 0.14,
                life: 1.3 + Double.random(in: 0...0.5),
                rot: CGFloat.random(in: 0...(.pi * 2)),
                size: 0.15 + CGFloat.random(in: 0...0.08)
            )
            switch type {
            case .z:
                // Suben de costado, arriba a la derecha
                p.x = 0.55 + CGFloat.random(in: -0.1...0.1)
                p.vx = 0.18 + CGFloat.random(in: -0.5...0.5) * 0.2
            case .sweat:
                // Gotita que resbala por el costado
                p.x = 0.62 + CGFloat.random(in: -0.05...0.05)
                p.y = -0.5
                p.vx = 0.04
                p.vy = 0.3
                p.life = 1.1
            case .spark:
                // Chispitas de vidrio que saltan alrededor de la cabeza
                let a = CGFloat.random(in: -CGFloat.pi...0)
                p.x = cos(a) * 0.85
                p.y = sin(a) * 0.75 - 0.05
                p.vx = cos(a) * 0.25
                p.vy = sin(a) * 0.25 - 0.1
                p.size = 0.1 + CGFloat.random(in: 0...0.06)
            case .bubble:
                // Burbujitas: desde el portal si está armado; si no, desde arriba de la cabeza
                p.x = CGFloat.random(in: -0.3...0.3)
                p.y = morph > 0.3 ? CGFloat.random(in: -0.15...0.1) : -0.62
                p.vx = CGFloat.random(in: -0.06...0.06)
                p.vy = -(0.35 + CGFloat.random(in: 0...0.25))
                p.size = 0.07 + CGFloat.random(in: 0...0.06)
                p.life = 1.1 + Double.random(in: 0...0.5)
            case .confetti:
                // Esquirlas de vidrio de colores: salen para arriba y caen (la gravedad va al dibujar).
                p.x = CGFloat.random(in: -0.3...0.3)
                p.y = -0.6
                p.vx = CGFloat.random(in: -0.9...0.9)
                p.vy = -(0.9 + CGFloat.random(in: 0...0.6))
                p.age = -Double(i) * 0.02
                p.life = 1.5 + Double.random(in: 0...0.5)
                p.size = 0.07 + CGFloat.random(in: 0...0.05)
            case .question:
                // Signo de pregunta que sube despacio al costado de la cabeza.
                p.x = 0.62 + CGFloat.random(in: -0.08...0.08)
                p.y = -0.55
                p.vx = 0.05
                p.vy = -0.32
                p.age = 0
                p.life = 1.6
                p.size = 0.18
            default:
                break
            }
            particles.append(p)
        }
    }

    // MARK: - Cuadro (lo llama el TimelineView)

    func update(dt: Double) {
        let now = CACurrentMediaTime()
        refreshEnvironment(now)

        // Tweens
        for key in tweens.keys {
            guard var tw = tweens[key] else { continue }
            let k = tw.keys[tw.keyIndex]
            let elapsed = now * 1000 - tw.startTime
            let p = min(1, max(0, CGFloat(elapsed) / max(1, k.duration)))
            let val = tw.from + (k.target - tw.from) * k.ease(p)
            setProperty(key, value: val)

            if p >= 1 {
                tw.from = k.target
                tw.keyIndex += 1
                tw.startTime = now * 1000
                if tw.keyIndex >= tw.keys.count {
                    tweens.removeValue(forKey: key)
                    locks.remove(key)
                    tw.onComplete?()
                } else {
                    tweens[key] = tw
                }
            } else {
                tweens[key] = tw
            }
        }

        // Vida: parpadeos y microgestos (LifeScheduler de OrbexCore)
        runLife(now)
        // Escucha por voz: nivel, anillos, mano a la oreja y rebote de ojos.
        updateListening(now: now, dt: dt)
        // Habla: latido del brillo, ojos que gesticulan, anillos y brazo.
        updateSpeaking(now: now, dt: dt)

        // Mirada
        let t = CGFloat(now - t0)
        let motion: CGFloat = reduceMotion ? 0.35 : 1
        var ty: CGFloat = lookX * 0.62
        var tp: CGFloat = lookY * 0.5

        if !isMini {
            // Si el cursor no se mueve hace un rato, la mirada pasea sola (nunca queda clavada).
            if abs(lookX - prevLook.x) > 0.004 || abs(lookY - prevLook.y) > 0.004 { lastLookInput = now }
            prevLook = CGPoint(x: lookX, y: lookY)
            let still = now - lastLookInput
            if still > 5 {
                let k = CGFloat(min(1, (still - 5) / 1.5))
                let lazyX = sin(t * 0.37) * 0.32 + sin(t * 0.13) * 0.14
                let lazyY = cos(t * 0.23) * 0.12
                ty += (lazyX * motion - ty) * k
                tp += (lazyY * motion - tp) * k
            }
            // Juega con una burbuja: los ojos la siguen.
            if let b = bubblePlayPos(now) {
                if !locks.contains("glanceX") { glanceX = b.x * 0.8 }
                if !locks.contains("glanceY") { glanceY = 0.55 + b.hop * 0.35 }
            }
            ty += glanceX * 0.6
            tp += glanceY * 0.45
            if let g = gesture, g.kind == .followDot {
                let p = min(1, max(0, (now - g.start) / g.kind.duration))
                let a = CGFloat(p * 4 * .pi)
                let env = CGFloat(sin(.pi * p))
                ty += (cos(a) * 0.6 - ty) * env
                tp += (0.35 - sin(a) * 0.3 - tp) * env
            }
        }

        if let fixedLook = cfg.look {
            ty = ty * 0.35 + fixedLook.x * 0.55
            tp = tp * 0.3  + fixedLook.y * 0.5
        }
        if cfg.scans {
            ty = sin(t * 2.6) * 0.6 * motion
            tp = -0.06
        }
        if state == .sleeping { ty = 0; tp = -0.14 }
        if state == .dizzy    { ty = sin(t * 9) * 0.25 * motion }

        // Mini: mirada que pasea al azar (no sigue al mouse)
        if isMini && cfg.look == nil && !cfg.scans && state != .sleeping && state != .dizzy {
            if now > miniLookNextTime {
                miniLookTarget = CGPoint(
                    x: CGFloat.random(in: -0.88...0.88),
                    y: CGFloat.random(in: -0.55...0.45)
                )
                miniLookNextTime = now + Double.random(in: 0.5...2.0)
            }
            ty = miniLookTarget.x * 0.62
            tp = miniLookTarget.y * 0.5
        }

        tgYaw   = ty
        tgPitch = tp
        tgTilt  = cfg.tilt
        if state == .dizzy { tgTilt += sin(t * 5) * 0.09 * motion }

        if !isMini {
            updateRelation(now: now, t: t, dt: dt, motion: motion)
        }

        // Balanceo del cuerpo mientras saluda
        if now > waveStart && now < waveUntil {
            let wt = CGFloat(now - waveStart)
            tgTilt = (-0.06 + sin(2 * .pi * 1.2 * wt) * 0.07) * motion
        }

        // Rebote (pide permiso) y trotecito en el lugar (trabajando, de cuerpo entero)
        var bounce: CGFloat = cfg.bounces ? -abs(sin(t * 5.2)) * (0.07 + 0.07 * limbs) * motion : 0
        if state == .working && !reduceMotion { bounce -= abs(sin(t * 8)) * 0.018 * limbs }
        if carried { bounce = sin(t * 3) * 0.05 * motion }   // globo: sube y baja
        bounce += deflate * 0.08                              // desinflado: se hunde un poco
        if !locks.contains("oy") { oy += (bounce - oy) * CGFloat(1 - pow(0.0008, dt)) }

        // Respiración (siempre; más honda dormido; casi nada con "reducir movimiento") y flotación
        if cfg.breathes {
            // Escuchando respira suave (atento); dormido, hondo.
            let soft = state == .listening
            let amp: CGFloat = isMini ? (soft ? 0.035 : 0.07)
                : (reduceMotion ? (soft ? 0.006 : 0.012) : (soft ? 0.022 : 0.035))
            tgSy = 1 + sin(t * 1.8) * amp
            tgSx = 1 - sin(t * 1.8) * amp * 0.57
        } else if isMini {
            // Pulso sutil (fase propia de cada motor por t0)
            tgSy = 1 + sin(t * 2.2) * 0.04 * motion
            tgSx = 1 - sin(t * 2.2) * 0.02 * motion
        } else {
            let b = CGFloat(LifeScheduler.breathScale(at: Double(t), amplitude: reduceMotion ? 0.006 : 0.02) - 1)
            tgSy = 1 + b
            tgSx = 1 - b * 0.6
        }
        floatY = (isMini || reduceMotion) ? 0 : CGFloat(LifeScheduler.floatOffset(at: Double(t))) * 2
        if !isMini {
            // Desinflado (límite de uso): más bajito y más ancho.
            if deflate > 0.001 {
                tgSy *= 1 - 0.14 * deflate
                tgSx *= 1 + 0.08 * deflate
            }
            // Globo: estirado hacia arriba.
            if carried {
                tgSy *= 1.05
                tgSx *= 0.97
            }
            // Escuchando (vista abierta): se acerca un poquito, como inclinándose hacia vos.
            if listenK > 0.001 && fullBody {
                let k = 1 + 0.045 * listenK * motion
                tgSy *= k
                tgSx *= k
            }
            // Hablando: leve rebote de escala con los picos de la voz.
            if abs(speakPulse) > 0.0005 {
                tgSy *= 1 + 0.04 * speakPulse
                tgSx *= 1 + 0.025 * speakPulse
            }
        }

        // Mini: comportamientos periódicos
        if isMini && now > miniNextBehavior {
            doMiniBehaviorLoop()
        }

        // Suavizado
        let kLook = CGFloat(1 - pow(0.0025, dt))
        let kGen  = CGFloat(1 - pow(0.0008, dt))
        let kCol  = CGFloat(1 - pow(0.002, dt))

        if !locks.contains("yaw")   { yaw   += (tgYaw   - yaw)   * kLook }
        if !locks.contains("pitch") { pitch += (tgPitch - pitch) * kLook }
        if !locks.contains("tilt")  { tilt  += (tgTilt  - tilt)  * kGen  }
        if !locks.contains("sy")    { sy    += (tgSy    - sy)    * kGen  }
        if !locks.contains("sx")    { sx    += (tgSx    - sx)    * kGen  }
        if !locks.contains("es")    { es    += (tgEs    - es)    * kGen  }
        if !locks.contains("tint")  { tint  += (tgTint  - tint)  * kCol  }
        col = mix3(col, colT, kCol)

        // Emote vencido: vuelve la expresión permanente (si hay)
        if eyeOverride != nil && now > eyeOverrideUntil {
            eyeOverride = permanentEye
            if permanentEye != nil { eyeOverrideUntil = .greatestFiniteMagnitude }
        }

        // Partículas de ambiente
        if now - lastAmbient > 1.3 {
            lastAmbient = now
            if cfg.zz { emit(.z, count: 1) }
            if cfg.sweat && Double.random(in: 0...1) < 0.5 { emit(.sweat, count: 1) }
            if state == .thinking && Double.random(in: 0...1) < 0.35 { emit(.bubble, count: 1) }
            if state == .error && Double.random(in: 0...1) < 0.45 { emit(.sweat, count: 1) }
            if state == .question && Double.random(in: 0...1) < 0.5 { emit(.question, count: 1) }
        }
        for i in particles.indices { particles[i].age += dt }
        particles.removeAll { $0.age >= $0.life }

        // Cuerpo entero (vista abierta) y agachada (dormido), con transición suave
        let wantLimbs: CGFloat = ((fullBody || carried) && !isMini) ? 1 : 0
        limbs += (wantLimbs - limbs) * CGFloat(1 - exp(-dt * 9))
        let wantCrouch: CGFloat = state == .sleeping ? 1 : 0
        crouch += (wantCrouch - crouch) * CGFloat(1 - exp(-dt * 3))

        updatePortal(now: now, dt: dt)
        frameTint = computeTint()
        lastTime = now
    }

    // MARK: - Dibujo

    /// Cuerpo (esfera de vidrio o mini), portal y ojos.
    func draw(context: GraphicsContext, size: CGSize) {
        let g = geo(size)
        let R = g.R
        let D = 2 * R
        let now = CACurrentMediaTime()

        var ctx = bodyContext(context, g: g)

        if isMini {
            // Mini escuchando: solo el halo que late y un anillo (detrás de la cuenta).
            if listenK > 0.01 {
                var aura = context
                let center = CGPoint(x: g.cx, y: g.cy)
                let beat = sin(now * (reduceMotion ? 1.8 : 3.6))
                OrbexPainter.drawHalo(&aura, center: center, radius: R * 1.6, color: BotConst.listenRGB,
                                      alpha: Double(listenK) * (0.26 + 0.1 * beat))
                OrbexPainter.drawListenRings(aura, center: center, R: R, phase: ringPhase,
                                             level: Double(voiceLevel), count: 1, still: reduceMotion,
                                             color: BotConst.listenRGB, alpha: Double(listenK), earSide: 0)
            }
            // Mini: cuenta de vidrio del color de marca, con el borde del color del estado
            let idle = state == .idle
            let rim: (r: Double, g: Double, b: Double) = idle ? (r: 1, g: 1, b: 1) : rgbTuple(cfg.color)
            OrbexPainter.drawMiniBody(&ctx, D: D, tint: frameTint, rim: rim, rimAlpha: idle ? 0.35 : 0.95)
            if speakVis > 0.01 {
                OrbexPainter.drawInnerLight(&ctx, D: D, tint: speakTint,
                                            alpha: Double(speakVis) * (0.1 + 0.4 * Double(speakLevel)))
            }
        } else {
            OrbexPainter.drawBody(&ctx, D: D, tint: frameTint, material: material)
            if material == .glass {
                OrbexPainter.drawInnerLight(&ctx, D: D, tint: frameTint, alpha: 0.26)
            }
            // Destello al oír su nombre: el vidrio se enciende de magenta claro un instante.
            let fa = now - listenFlashAt
            if fa >= 0 && fa < 0.4 {
                OrbexPainter.drawInnerLight(&ctx, D: D, tint: BotConst.listenRGB, alpha: 0.6 * (1 - fa / 0.4))
            }
            // Hablando: la luz interior del vidrio late con la voz (también en compacto).
            if speakVis > 0.01 {
                OrbexPainter.drawInnerLight(&ctx, D: D, tint: speakTint,
                                            alpha: Double(speakVis) * (0.12 + 0.5 * Double(speakLevel)))
            }
            if blush > 0.01 {
                OrbexPainter.drawWarmth(&ctx, D: D, amount: Double(blush))
            }
            // Extras del estado dentro del vidrio (se apagan mientras es portal).
            let inside = Double(max(0, 1 - morph * 2))
            if inside > 0.01 {
                let lt = now - t0
                if state == .working {
                    OrbexPainter.drawInnerBubbles(&ctx, D: D, t: lt * (reduceMotion ? 0.35 : 1),
                                                  tint: frameTint, alpha: inside)
                } else if state == .searching {
                    OrbexPainter.drawSweep(&ctx, D: D, k: (lt * (reduceMotion ? 0.25 : 0.55))
                        .truncatingRemainder(dividingBy: 1), alpha: inside)
                }
                if fog > 0.01 {
                    OrbexPainter.drawFog(&ctx, D: D, amount: Double(fog) * inside)
                }
            }
            // Portal de vidrio (subir archivo)
            if morph > 0.02 {
                OrbexPainter.drawPortal(&ctx, D: D, hole: portalHole(R), swirl: Double(swirl),
                                        tint: frameTint, strength: Double(min(1, morph * 1.4)))
            }
            // Ondita del trago
            let ra = now - rippleStart
            if ra >= 0 && ra < 0.6 {
                OrbexPainter.drawRipple(&ctx, from: max(portalHole(R), R * 0.2), to: R * 1.3,
                                        k: ra / 0.6, tint: frameTint, D: D)
            }
        }

        drawEyes(ctx, R: R, now: now)
    }

    /// Detrás del cuerpo: halo del estado y, de cuerpo entero, reflejo en el piso y piernitas.
    func drawHandsBehind(context: GraphicsContext, size: CGSize) {
        guard !isMini else { return }
        let g = geo(size)
        let R = g.R
        let D = 2 * R
        let now = CACurrentMediaTime()
        var ctx = context

        // Halo suave del color del estado (late si pide atención; con un archivo encima se enciende)
        var glowRGB = rgbTuple(cfg.glow)
        if morph > 0.01 { glowRGB = mixRGB(glowRGB, frameTint, Double(min(1, morph))) }
        var a = Double(cfg.glowOpacity) * 0.5
        var haloR = R * 1.55
        if (state == .approval || state == .question) && !reduceMotion { a *= 0.75 + 0.25 * sin(now * 4) }
        if state == .listening {
            // Escuchando: el halo magenta late (más lento con "reducir movimiento") y se enciende con tu voz.
            a *= 0.72 + 0.28 * sin(now * (reduceMotion ? 1.8 : 3.6))
            a += 0.2 * Double(voiceLevel)
            if !reduceMotion { haloR *= 1 + 0.08 * voiceLevel }
        }
        if portalHover > 0.01 { a = max(a, 0.4) }
        let center = CGPoint(x: g.cx, y: g.cy)
        if a > 0.01 {
            OrbexPainter.drawHalo(&ctx, center: center, radius: haloR, color: glowRGB, alpha: a)
        }

        // Escuchando: anillos magenta según tu voz (compacto: uno solo) y destello al oír su nombre.
        let full = g.arms > 0.5 && R >= BotConst.limbsMinR
        if listenK > 0.01 {
            OrbexPainter.drawListenRings(ctx, center: center, R: R, phase: ringPhase, level: Double(voiceLevel),
                                         count: full ? 3 : 1, still: reduceMotion, color: BotConst.listenRGB,
                                         alpha: Double(listenK) * Double(max(0, 1 - morph)),
                                         earSide: full ? BotConst.earSide : 0)
        }
        // Hablando: halo celeste que respira con la voz y anillos que salen con las sílabas fuertes.
        let sv = Double(speakVis) * Double(max(0, 1 - morph))
        if sv > 0.01 {
            OrbexPainter.drawHalo(&ctx, center: center, radius: R * (1.45 + 0.1 * speakLevel),
                                  color: speakTint, alpha: sv * (0.08 + 0.22 * Double(speakLevel)))
            if full && !speakRings.isEmpty {
                OrbexPainter.drawSpeakRings(ctx, center: center, R: R,
                                            rings: speakRings.map { (k: (now - $0.start) / Self.speakRingLife,
                                                                     strength: $0.strength) },
                                            color: speakTint, alpha: sv)
            }
        }
        let fa = now - listenFlashAt
        if fa >= 0 && fa < 0.5 {
            let k = fa / 0.5
            OrbexPainter.drawHalo(&ctx, center: center, radius: R * CGFloat(1.4 + 0.4 * k),
                                  color: mixRGB(BotConst.listenRGB, (r: 1, g: 1, b: 1), 0.3), alpha: 0.5 * (1 - k))
            var ring = ctx
            ring.translateBy(x: g.cx, y: g.cy)
            OrbexPainter.drawRipple(&ring, from: R * 1.0, to: R * 1.6, k: k, tint: BotConst.listenRGB, D: D)
        }

        // Piernitas y pies: solo de cuerpo entero (vista abierta y esfera grande)
        guard g.legs > 0.02 else { return }
        var legs = ctx
        legs.opacity = Double(min(1, g.legs * 1.5))
        let hop = max(0, -(oy + floatY)) * R
        let shrink = max(0.4, 1 - hop / D * 2)
        if !carried {
            OrbexPainter.drawFloorGlow(&legs, center: CGPoint(x: g.cx, y: g.restY + 1.4 * R),
                                       width: 1.8 * R * shrink, height: 0.16 * R * shrink,
                                       alpha: 0.10 * Double(shrink))
        }
        let walking = state == .working && !reduceMotion
        let step = walking ? sin((now - t0) * 8) : 0
        for sd in [-1.0, 1.0] {
            var lift = CGFloat(max(0, sd < 0 ? step : -step) * 0.05) * D
            if carried {
                // Globo: las piernitas patalean en el aire, alternadas.
                let kick = sin((now - t0) * (reduceMotion ? 5 : 14) + (sd < 0 ? 0 : .pi))
                lift = CGFloat(0.02 + kick * 0.06) * D
            }
            let footY = g.hopY + (0.68 + 0.62 * g.legs) * R - lift
            OrbexPainter.drawLeg(&legs, side: sd, bodyCenter: CGPoint(x: g.cx, y: g.cy), footY: footY,
                                 D: D, tint: frameTint, crouch: Double(crouch), material: material)
        }
    }

    /// Delante del cuerpo: brazos-gota, puntito imaginario, insignia y partículas.
    func drawHandsAndExtras(context: GraphicsContext, size: CGSize) {
        let g = geo(size)
        let now = CACurrentMediaTime()

        if !isMini {
            drawArms(context, g: g, now: now)
            if let gs = gesture, gs.kind == .followDot {
                drawImaginaryDot(context, g: g, progress: (now - gs.start) / gs.kind.duration)
            }
            let center = CGPoint(x: g.cx, y: g.cy)
            let lt = now - t0
            if state == .thinking && morph < 0.25 {
                OrbexPainter.drawOrbitDots(context, center: center, R: g.R, t: lt * (reduceMotion ? 0.35 : 1),
                                           color: rgbTuple(cfg.color))
            }
            if state == .dizzy {
                OrbexPainter.drawDizzyStars(context, center: center, R: g.R, t: lt * (reduceMotion ? 0.35 : 1))
            }
            if let b = bubblePlayPos(now) {
                var c = context
                c.translateBy(x: g.cx + b.x * g.R, y: g.cy + b.y * g.R)
                c.opacity = Double(b.alpha)
                OrbexPainter.drawBubble(&c, radius: g.R * 0.2, tint: frameTint)
            }
        }

        // Insignia (se esconde mientras es portal)
        if let badge = badge, badgeS > 0.01, morph < 0.25 {
            drawBadge(context, badge: badge, g: g, now: now)
        }

        drawParticles(context, g: g)
    }

    // MARK: - Partes (privado)

    /// Medidas del cuadro. R = radio de la esfera.
    private struct Geo {
        let R: CGFloat
        let cx: CGFloat
        let cy: CGFloat      // centro del cuerpo (saltos, flotación y agachada incluidos)
        let hopY: CGFloat    // centro del cuerpo sin la agachada (los pies siguen al salto)
        let restY: CGFloat   // centro del cuerpo quieto (el piso queda en restY + 1,4 R)
        let legs: CGFloat    // 0…1 piernitas visibles
        let arms: CGFloat    // 0…1 brazos visibles (vista abierta)
    }

    private func geo(_ size: CGSize) -> Geo {
        let R = size.width * 0.3
        let big = !isMini && R >= BotConst.limbsMinR
        let legs = big ? limbs * (1 - morph) : 0
        let arms = isMini ? 0 : limbs * (1 - morph)
        // particleOverhang baja el cuerpo en el lienzo para que las partículas suban sin cortarse.
        // Con piernitas, el cuerpo sube un poco para que todo el personaje quede centrado.
        let restY = size.height / 2 + particleOverhang / 2 + R * 0.06 - R * 0.2 * legs
        let hopY = restY + (oy + floatY) * R
        let cy = hopY + crouch * 0.26 * R * legs
        return Geo(R: R, cx: size.width / 2 + (ox + purrX) * R, cy: cy, hopY: hopY, restY: restY, legs: legs, arms: arms)
    }

    /// Contexto del cuerpo: centro, inclinación y squash & stretch (parado se aplasta desde los pies).
    private func bodyContext(_ context: GraphicsContext, g: Geo) -> GraphicsContext {
        var ctx = context
        ctx.translateBy(x: g.cx, y: g.cy)
        if tilt != 0 { ctx.rotate(by: .radians(tilt)) }
        let anchor = g.R * g.legs
        ctx.translateBy(x: 0, y: anchor)
        ctx.scaleBy(x: sx, y: sy)
        ctx.translateBy(x: 0, y: -anchor)
        return ctx
    }

    private func portalHole(_ R: CGFloat) -> CGFloat {
        min(0.62 * R, R * morph * (0.1 + slotH))
    }

    private func drawEyes(_ base: GraphicsContext, R: CGFloat, now: Double) {
        var shape = eyeOverride ?? cfg.eye
        // Portal: ojos con ganas si hay un archivo encima, felices mientras "mastica"
        if morph > 0.5 {
            if isChewing { shape = .happy }
            else if slotHTarget > 0.05 || slotH > 0.10 { shape = .cup }
        }
        var ctx = base
        ctx.clip(to: Path(ellipseIn: CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R)))

        // En tamaño chico (compacto, mini) los ojos crecen y se redondean para que se lean.
        let small = min(1, max(0, (22 - R) / 14))
        let growW: CGFloat = 1 + small * (isMini ? 0.8 : 0.6)
        let growH: CGFloat = 1 + small * 0.35
        let shrink = 1 - 0.28 * morph
        // Escuchando: los ojos rebotan un poquito con el volumen de tu voz (crecen y suben).
        let bounce = 1 + 0.14 * eyeBounce
        // Hablando: los ojos se achinan con las sílabas y se abren entre ellas (gesticula).
        var talkH: CGFloat = 1, talkW: CGFloat = 1
        if speakVis > 0.01 && fullBody && !reduceMotion && !isMini {
            let v = speakVis
            talkH = 1 - v * (0.2 * speakLevel - 0.05)
            talkW = 1 + v * 0.06 * speakLevel
        }
        let w = max(1.4, R * BotConst.eyeW * es * growW * shrink * bounce * talkW)
        let h = max(2.2, R * BotConst.eyeH * es * growH * shrink * bounce * talkH)
        let spread = BotConst.eyeSp * (isMini ? 1.12 : 1)
        let ink = Color(cgColor: isMini ? BotConst.miniInk : BotConst.ink)
        // A través del vidrio se ven apenas los ojos cuando pasan por atrás (vueltas, mareo)
        let seeThrough = material == .glass && !isMini

        for sd in [-1.0, 1.0] {
            let side = CGFloat(sd)
            let eyeYaw = side * spread + yaw
            var eyePitch = BotConst.eyeP + pitch + roll + morph * 0.7 + eyeBounce * 0.06
            eyePitch = ((eyePitch + .pi).truncatingRemainder(dividingBy: .pi * 2) + .pi * 2)
                .truncatingRemainder(dividingBy: .pi * 2) - .pi
            let cYaw = cos(eyeYaw)
            let cPitch = cos(eyePitch)
            let front = cYaw * cPitch > 0.04
            guard front || seeThrough else { continue }

            var e = ctx
            e.translateBy(x: sin(eyeYaw) * cPitch * R, y: -sin(eyePitch) * R)
            e.scaleBy(x: max(0.18, abs(cYaw)), y: max(0.18, abs(cPitch)))
            if !front { e.opacity = 0.16 }
            OrbexPainter.drawEye(&e, shape: shape, w: w, h: h, open: open, side: side,
                                 t: now, detail: front && w >= 2.2, ink: ink)
        }
    }

    /// Brazos-gota: en la vista abierta siempre; en compacto solo aparece el que saluda.
    private func drawArms(_ context: GraphicsContext, g: Geo, now: Double) {
        let rightVis = max(g.arms, hands * (1 - morph))
        let leftVis = g.arms
        guard rightVis > 0.01 || leftVis > 0.01 else { return }
        let D = 2 * g.R
        let t = now - t0
        let ctx = bodyContext(context, g: g)

        let waving = waveStart > 0 && now >= waveStart && now < waveUntil
        let wt = now - waveStart
        let swing = reduceMotion ? 0.35 : 1.0
        for sd in [-1.0, 1.0] {
            let vis = sd > 0 ? rightVis : leftVis
            guard vis > 0.01 else { continue }
            var raise = restRaise(side: sd, t: t)
            raise += (2.5 - raise) * Double(armsUp)
            if sd > 0 && hands > 0.001 {
                // Saludo: brazo derecho arriba, moviéndose
                let osc = waving ? sin(13 * wt) * 0.38 * swing : 0
                raise += (2.35 + osc - raise) * Double(hands)
            } else if sd < 0 && waving {
                raise += sin(6 * wt) * 0.08 * swing
            }
            // Hablando: un brazo-gota gesticula de a ratos (sube, se mece y vuelve).
            let env = speakArmEnv(now) * Double(speakVis)
            if env > 0.001 && sd == speakArmSide && !reduceMotion {
                let beat = sin((now - speakArmStart) * 9) * (0.12 + 0.18 * Double(speakLevel))
                raise += (1.05 + beat - raise) * env
            }
            var length: CGFloat = 1
            if listenK > 0.001 && sd == BotConst.earSide {
                // Escuchando: lleva la mano-gota a la "oreja" (costado de la cabeza), un poco más corta
                // para que el bulbo apoye en el vidrio; con tu voz da toquecitos.
                let ear = Double(listenK)
                let tap = reduceMotion ? 0 : sin(t * 11) * 0.05 * Double(voiceLevel)
                raise += (2.97 + tap - raise) * ear
                length = 1 - 0.12 * listenK
            }
            var arm = ctx
            if vis < 0.99 {
                // Aparece creciendo desde el hombro
                let px = CGFloat(sd) * 0.45 * D
                arm.translateBy(x: px, y: 0)
                arm.scaleBy(x: vis, y: vis)
                arm.translateBy(x: -px, y: 0)
            }
            OrbexPainter.drawArm(&arm, side: sd, raise: raise, D: D, tint: frameTint, material: material,
                                 length: length)
        }
    }

    /// Color del habla: celeste cálido con un toque del tinte del vidrio.
    private var speakTint: (r: Double, g: Double, b: Double) { mixRGB(BotConst.speakRGB, frameTint, 0.2) }

    /// Ángulo de reposo de cada brazo según el estado (0 = colgando; positivo = hacia afuera).
    private func restRaise(side: Double, t: Double) -> Double {
        let calm = reduceMotion
        let phase: Double = side > 0 ? 1 : 0
        switch state {
        case .working:
            return 0.16 + (calm ? 0 : sin(t * 8 + phase * .pi) * 0.2 * Double(limbs))
        case .approval:
            // Levanta la mano (derecha) como pidiendo la palabra; la otra acompaña el salto.
            if side > 0 { return 2.3 + (calm ? 0 : sin(t * 7) * 0.16) }
            return 0.42 + (calm ? 0 : abs(sin(t * 5.2)) * 0.16)
        case .question:
            // Mano "pensativa" a medio subir.
            if side < 0 { return 0.9 + (calm ? 0 : sin(t * 1.3) * 0.08) }
            return 0.3
        case .error:
            return 0.3
        case .sleeping:
            return 0.45
        case .ratelimit:
            return 0.05
        case .dizzy:
            return 0.5 + (calm ? 0 : sin(t * 9 + side) * 0.35)
        case .listening:
            // La mano de la oreja la pone `drawArms`; la otra, un poco afuera, atenta.
            return 0.26 + (calm ? 0 : sin(t * 1.6 + phase) * 0.04)
        default:
            return 0.08 + (calm ? 0 : sin(t * 1.3 + phase) * 0.04)
        }
    }

    /// Microgesto "seguir el puntito": el puntito que miran los ojos.
    private func drawImaginaryDot(_ context: GraphicsContext, g: Geo, progress: Double) {
        let p = min(1, max(0, progress))
        let a = p * 4 * .pi
        let x = g.cx + CGFloat(cos(a) * 0.9) * g.R
        let y = g.cy + CGFloat((sin(a) * 0.3 - 0.35) * 1.8) * g.R
        let s = max(1.5, 0.09 * g.R)
        var c = context
        c.opacity = sin(.pi * p)
        c.fill(Path(ellipseIn: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)),
               with: .color(Color.white.opacity(0.9)))
    }

    private func drawBadge(_ context: GraphicsContext, badge: BadgeType, g: Geo, now: Double) {
        let R = g.R
        var ctx = context
        ctx.translateBy(x: g.cx - R * 0.74 * sx, y: g.cy - R * 0.74 * sy)
        var s = badgeS
        let glyph: OrbexPainter.BadgeGlyph
        let color: CGColor
        switch badge {
        case .dots(let c):
            glyph = .dots
            color = c
        case .bang(let c):
            glyph = .bang
            color = c
            if !reduceMotion { s *= 1 + 0.07 * CGFloat(sin(now * 6)) }
        case .question(let c):
            glyph = .question
            color = c
            if !reduceMotion { ctx.rotate(by: .radians(sin(now * 3) * 0.12)) }
        case .dot(let c):
            color = c
            glyph = state == .finished ? .check : (state == .ratelimit ? .clock : .plain)
        }
        ctx.scaleBy(x: s, y: s)
        OrbexPainter.drawBadge(&ctx, glyph: glyph, color: rgbTuple(color), size: R * 0.3, t: now)
    }

    private func drawParticles(_ context: GraphicsContext, g: Geo) {
        guard !particles.isEmpty else { return }
        let R = g.R
        for p in particles {
            guard p.age > 0 else { continue }
            let k = CGFloat(p.age / p.life)
            let a = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8
            let age = CGFloat(p.age)
            var px = g.cx + (p.x + p.vx * age) * R * 1.3
            var py = g.cy + (p.y + p.vy * age) * R * 1.3
            if p.type == .confetti { py += 1.1 * age * age * R * 1.3 }   // gravedad
            if p.type == .bubble { px += sin(age * 6 + p.rot) * R * 0.06 }
            let sz = R * p.size * (1 + k * 0.4)

            var c = context
            c.translateBy(x: px, y: py)
            c.opacity = Double(min(max(a, 0), 1))

            switch p.type {
            case .heart:
                c.rotate(by: .radians(sin(age * 6) * 0.3))
                let s = sz * 2
                c.fill(OrbexPainter.heart(size: s), with: .color(Color(red: 1, green: 0.36, blue: 0.52)))
                c.fill(Path(ellipseIn: CGRect(x: -s * 0.34, y: -s * 0.24, width: s * 0.16, height: s * 0.12)),
                       with: .color(Color.white.opacity(0.7)))
            case .star:
                c.rotate(by: .radians(p.rot + age * 2))
                c.fill(OrbexPainter.sparkle(size: sz * 2.4), with: .color(Color(red: 1, green: 0.86, blue: 0.4)))
            case .spark:
                c.rotate(by: .radians(p.rot + age * 3))
                c.fill(OrbexPainter.sparkle(size: sz * 1.7), with: .color(Color(red: 0.9, green: 0.97, blue: 1)))
            case .sweat:
                let s = sz * 1.5
                c.fill(OrbexPainter.teardrop(size: s), with: .color(Color(red: 0.55, green: 0.8, blue: 1).opacity(0.9)))
                c.fill(Path(ellipseIn: CGRect(x: -s * 0.2, y: -s * 0.05, width: s * 0.16, height: s * 0.22)),
                       with: .color(Color.white.opacity(0.7)))
            case .z:
                c.rotate(by: .radians(-0.15))
                c.stroke(OrbexPainter.zGlyph(size: sz * 1.5), with: .color(Color(red: 0.8, green: 0.86, blue: 0.95)),
                         style: StrokeStyle(lineWidth: max(1, sz * 0.26), lineCap: .round, lineJoin: .round))
            case .bubble:
                OrbexPainter.drawBubble(&c, radius: max(1.2, sz * 0.7), tint: frameTint)
            case .confetti:
                c.rotate(by: .radians(p.rot + age * 7))
                c.scaleBy(x: 1, y: max(0.2, abs(cos(age * 9 + p.rot))))   // da vueltas en el aire
                OrbexPainter.drawConfetti(&c, size: max(1.5, sz * 1.6), hue: Int(p.rot * 10))
            case .question:
                c.rotate(by: .radians(sin(age * 3) * 0.2))
                c.stroke(OrbexPainter.questionGlyph(size: max(4, sz * 2.2)),
                         with: .color(Color(red: 0.6, green: 0.95, blue: 1)),
                         style: StrokeStyle(lineWidth: max(1, sz * 0.3), lineCap: .round, lineJoin: .round))
            }
        }
    }

    // MARK: - Portal, vida y ambiente (privado)

    private func updatePortal(now: Double, dt: Double) {
        let dtCG = CGFloat(dt)
        // El trago manda sobre lo que pida el lienzo (antes el lienzo lo pisaba en cada cuadro).
        if now < gulpOpenUntil {
            slotHTarget = 0.42
        } else if isChewing {
            slotHTarget = 0.06 + 0.05 * CGFloat(sin(now * 17))
        } else {
            slotHTarget = portalHover
        }
        // Sin portal ni trago en curso, la apertura queda en cero.
        if morph < 0.05 && !isChewing && now >= gulpOpenUntil && portalHover < 0.01 {
            slotH = 0
            slotHVel = 0
        }
        // Resorte de la apertura: ω₀ ≈ 25 rad/s, ζ = 0,6 (un poquito de rebote)
        let omega: CGFloat = 2 * .pi / 0.25
        let zeta: CGFloat = 0.6
        let acc = omega * omega * (slotHTarget - slotH) - 2 * zeta * omega * slotHVel
        slotHVel += acc * dtCG
        slotH = max(0, slotH + slotHVel * dtCG)

        // Remolino: lento en reposo, más rápido con un archivo encima, rapidísimo al "masticar"
        let target: CGFloat = isChewing ? 9 : (now < gulpOpenUntil ? 5 : (slotHTarget > 0.1 ? 3.5 : 1.4))
        swirlSpeed += (target - swirlSpeed) * CGFloat(1 - exp(-dt * 6))
        swirl += swirlSpeed * dtCG * (reduceMotion ? 0.4 : 1)
        if swirl > 1000 { swirl -= 300 * .pi }
    }

    private func runLife(_ now: Double) {
        if let g = gesture, now - g.start > g.kind.duration { gesture = nil }
        let calm = state == .idle && eyeOverride == nil && morph < 0.02 && now > waveUntil
        let allowGestures = !isMini && !reduceMotion && calm && gesture == nil
            && bubblePlayStart == 0 && !petting && !carried
        for event in life.update(now: now, allowGestures: allowGestures) {
            switch event {
            case .blink(let double):
                guard state != .sleeping, state != .dizzy else { continue }
                blink()
                if double { after(0.24) { $0.blink() } }
            case .microgesture(let g):
                startGesture(g, now: now)
            case .surprise:
                // Idles raros (burbuja, estornudo, guiño, orgulloso…): el motor elige cuál.
                startRareIdle(now: now)
            }
        }
    }

    /// Microgestos suaves (capa L1): se estira, mira alrededor, bosteza, se rasca, sigue un puntito,
    /// se sacude, da un saltito o saluda chiquito.
    private func startGesture(_ g: Microgesture, now: Double) {
        gesture = (g, now)
        switch g {
        case .stretch:
            anim("sy", keys: [
                TweenKey(target: 1.07, duration: 450, ease: Ease.inOut),
                TweenKey(target: 1.07, duration: 250, ease: Ease.lin),
                TweenKey(target: 1,    duration: 450, ease: Ease.inOut),
            ])
            anim("sx", keys: [
                TweenKey(target: 0.96, duration: 450, ease: Ease.inOut),
                TweenKey(target: 0.96, duration: 250, ease: Ease.lin),
                TweenKey(target: 1,    duration: 450, ease: Ease.inOut),
            ])
            anim("armsUp", keys: [
                TweenKey(target: 0.85, duration: 450, ease: Ease.out),
                TweenKey(target: 0.85, duration: 250, ease: Ease.lin),
                TweenKey(target: 0,    duration: 500, ease: Ease.inOut),
            ])
            eyeOverride = .happy
            eyeOverrideUntil = now + 1.0
        case .lookAround:
            anim("glanceX", keys: [
                TweenKey(target: -0.7, duration: 500, ease: Ease.inOut),
                TweenKey(target: -0.7, duration: 300, ease: Ease.lin),
                TweenKey(target:  0.7, duration: 700, ease: Ease.inOut),
                TweenKey(target:  0.7, duration: 300, ease: Ease.lin),
                TweenKey(target:  0,   duration: 400, ease: Ease.inOut),
            ])
        case .yawn:
            triggerEmote(.yawn, duration: 1.6, silent: true)
        case .scratch:
            anim("tilt", keys: [
                TweenKey(target: 0.1,  duration: 250, ease: Ease.out),
                TweenKey(target: 0.06, duration: 300, ease: Ease.inOut),
                TweenKey(target: 0.1,  duration: 300, ease: Ease.inOut),
                TweenKey(target: 0,    duration: 400, ease: Ease.inOut),
            ])
            anim("glanceY", keys: [
                TweenKey(target: 0.6, duration: 300, ease: Ease.out),
                TweenKey(target: 0.6, duration: 700, ease: Ease.lin),
                TweenKey(target: 0,   duration: 400, ease: Ease.inOut),
            ])
        case .followDot:
            break   // la mirada y el puntito se calculan en cada cuadro
        case .wiggle:
            anim("tilt", keys: [
                TweenKey(target:  0.09, duration: 90,  ease: Ease.out),
                TweenKey(target: -0.09, duration: 140, ease: Ease.inOut),
                TweenKey(target:  0.06, duration: 130, ease: Ease.inOut),
                TweenKey(target: -0.04, duration: 120, ease: Ease.inOut),
                TweenKey(target:  0,    duration: 150, ease: Ease.out),
            ])
        case .hop:
            anim("oy", keys: [
                TweenKey(target: -0.16, duration: 160, ease: Ease.out),
                TweenKey(target:  0,    duration: 260, ease: Ease.back),
            ])
            anim("sy", keys: [
                TweenKey(target: 0.9,  duration: 80,  ease: Ease.out),
                TweenKey(target: 1.08, duration: 140, ease: Ease.out),
                TweenKey(target: 1,    duration: 220, ease: Ease.back),
            ])
            anim("sx", keys: [
                TweenKey(target: 1.07, duration: 80,  ease: Ease.out),
                TweenKey(target: 0.95, duration: 140, ease: Ease.out),
                TweenKey(target: 1,    duration: 220, ease: Ease.back),
            ])
        case .waveSmall:
            greetToken += 1
            let tok = greetToken
            waveStart = now + 0.2
            waveUntil = now + 1.2
            anim("hands", keys: [TweenKey(target: 0.7, duration: 250, ease: Ease.out)])
            eyeOverride = .happy
            eyeOverrideUntil = now + 1.3
            after(1.2) { e in
                guard e.greetToken == tok else { return }
                e.waveUntil = 0
                e.anim("hands", keys: [TweenKey(target: 0, duration: 220, ease: Ease.inOut)])
            }
        }
    }

    /// Tema, tinte del usuario, "reducir movimiento" y nivel de vida (dos veces por segundo, no en cada cuadro).
    private func refreshEnvironment(_ now: Double) {
        guard now >= nextEnvCheck else { return }
        nextEnvCheck = now + 0.5
        BotSoundGate.start()
        let model = AppModel.shared
        reduceMotion = model.effectiveReduceMotion
        let theme = model.themeStyle
        material = (theme.glassAllowed || theme.id != .liquidGlass) ? OrbexMaterial(theme: theme.id) : .solid
        userTint = model.brain.tint.rgb
        let level = model.settings.lifeLevel
        if life.level != level { life.level = level }
        if !lifeTuned {
            // ~1 de cada 8 microgestos es un idle raro (con el aburrimiento aparecen solos).
            life.surpriseChance = 0.12
            lifeTuned = true
        }
    }

    /// Caricia, cosquillas, timidez, globo y extras suaves por estado (una vez por cuadro, sin nada pesado).
    private func updateRelation(now: Double, t: CGFloat, dt: Double, motion: CGFloat) {
        let k = CGFloat(1 - exp(-dt * 4))
        fog += ((state == .error ? 1 : 0) - fog) * CGFloat(1 - exp(-dt * 1.5))
        deflate += ((state == .ratelimit ? 1 : 0) - deflate) * CGFloat(1 - exp(-dt * 1.2))
        if state != .idle { bubblePlayStart = 0 }

        // Pregunta: cabeza ladeada que se hamaca despacio.
        if state == .question { tgTilt += sin(t * 1.3) * 0.05 * motion }

        // Escuchando (vista abierta): ladea la cabeza hacia la mano de la oreja.
        if listenK > 0.001 && fullBody {
            tgTilt += CGFloat(BotConst.earSide) * 0.09 * listenK * motion
        }

        // Se inclina hacia el cursor (más de cuerpo entero).
        if !carried && state != .sleeping && state != .dizzy && morph < 0.3 {
            tgTilt += lookX * (0.035 + 0.05 * limbs) * motion
        }

        // Caricia: ojos felices, rubor, corazoncitos, ronroneo y hamaca.
        petK += ((petting ? 1 : 0) - petK) * k
        if petting || petK > 0.001 {
            if petting && petK > 0.3 && (eyeOverride == nil || eyeOverride == .happy) {
                eyeOverride = .happy
                eyeOverrideUntil = now + 0.2
            }
            if !locks.contains("blush") { blush += (petK * 0.9 - blush) * k }
            if petting && now >= nextPetHeart {
                emit(.heart, count: 1)
                nextPetHeart = now + Double.random(in: 0.7...1.2)
            }
            tgTilt += sin(t * 1.4) * 0.05 * petK * motion
        }
        purrX = reduceMotion ? 0 : CGFloat(sin(now * 44)) * 0.008 * petK

        // Globo (fantasma que se arrastra): se hamaca con los brazos arriba y ojos felices.
        if carried {
            tgTilt = sin(t * 2.6) * 0.12 * motion
            if !locks.contains("armsUp") { armsUp += (1 - armsUp) * k }
            if eyeOverride == nil {
                eyeOverride = .happy
                eyeOverrideUntil = now + 0.2
            }
        }

        // Timidez: el cursor se queda cerca mirándolo más de 4 s.
        let near = abs(lookX) < 0.5 && abs(lookY) < 0.6
        let calmIdle = state == .idle && !petting && !carried && morph < 0.1 && limbs > 0.5 && eyeOverride == nil
        if near && calmIdle {
            if nearSince == 0 {
                nearSince = now
            } else if now - nearSince > 4 && now > shyCooldown {
                beShy(now: now)
            }
        } else if !near || petting {
            nearSince = 0
        }
    }

    /// Burbuja con la que juega (idle raro): posición en unidades de R desde el centro del cuerpo.
    private func bubblePlayPos(_ now: Double) -> (x: CGFloat, y: CGFloat, hop: CGFloat, alpha: CGFloat)? {
        guard bubblePlayStart > 0 else { return nil }
        let p = (now - bubblePlayStart) / Self.bubblePlayDur
        guard p >= 0, p < 1 else { return nil }
        let hop = CGFloat(abs(sin(p * 3 * .pi)))
        let x = CGFloat(sin(p * 2 * .pi)) * 0.18
        let y = -1.14 - hop * 0.85
        return (x, y, hop, CGFloat(min(1, p / 0.08)))
    }

    /// Tinte del vidrio: color de marca o el que eligió el usuario, teñido por el color del estado.
    private func computeTint() -> (r: Double, g: Double, b: Double) {
        let base = bodyColor.map { rgbTuple($0) } ?? userTint
        let k: Double = isMini ? 0 : Double(tint * (1 - morph * 0.4))
        var c = mixRGB(base, (r: Double(col.0), g: Double(col.1), b: Double(col.2)), k)
        if blush > 0.01 { c = mixRGB(c, (r: 1, g: 0.5, b: 0.64), Double(blush) * 0.3) }
        return c
    }

    /// Sonido de una reacción del personaje (nunca en los mini ni si otro lienzo lo tapa).
    private func sound(_ name: String, gap: Double) {
        guard !isMini, audible else { return }
        BotSoundGate.play(name, gap: gap)
    }

    /// Estados que cambian seguido (trabajando/pensando/buscando) suenan como mucho cada 8 s.
    private static func stateSoundGap(_ name: String) -> Double {
        switch name {
        case "work", "think", "search": return 8
        default: return 1.2
        }
    }

    /// Corre `body` en el hilo principal dentro de `delay` segundos (si el motor sigue vivo).
    private func after(_ delay: Double, _ body: @escaping @MainActor (BotEngine) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                body(self)
            }
        }
    }

    // MARK: - Tweens

    func anim(_ key: String, keys: [TweenKey], onComplete: (() -> Void)? = nil) {
        let current = getProperty(key)
        tweens[key] = Tween(property: key, keys: keys, keyIndex: 0,
                            from: current, startTime: CACurrentMediaTime() * 1000,
                            onComplete: onComplete)
        locks.insert(key)
    }

    private func setTarget(key: String, value: CGFloat) {
        guard !locks.contains(key) else { return }
        switch key {
        case "tint":  tgTint = value   // se suaviza en update
        case "tilt":  tgTilt = value
        default: break
        }
    }

    private func setProperty(_ key: String, value: CGFloat) {
        switch key {
        case "yaw":     yaw     = value
        case "pitch":   pitch   = value
        case "roll":    roll    = value
        case "tilt":    tilt    = value
        case "open":    open    = value
        case "sx":      sx      = value
        case "sy":      sy      = value
        case "oy":      oy      = value
        case "ox":      ox      = value
        case "tint":    tint    = value
        case "morph":   morph   = value
        case "hands":   hands   = value
        case "blush":   blush   = value
        case "es":      es      = value
        case "badgeS":  badgeS  = value
        case "armsUp":  armsUp  = value
        case "glanceX": glanceX = value
        case "glanceY": glanceY = value
        default: break
        }
    }

    private func getProperty(_ key: String) -> CGFloat {
        switch key {
        case "yaw":     return yaw
        case "pitch":   return pitch
        case "roll":    return roll
        case "tilt":    return tilt
        case "open":    return open
        case "sx":      return sx
        case "sy":      return sy
        case "oy":      return oy
        case "ox":      return ox
        case "tint":    return tint
        case "morph":   return morph
        case "hands":   return hands
        case "blush":   return blush
        case "es":      return es
        case "badgeS":  return badgeS
        case "armsUp":  return armsUp
        case "glanceX": return glanceX
        case "glanceY": return glanceY
        default:        return 0
        }
    }
}

// MARK: - Sonidos del personaje

/// Evita ráfagas: el mismo sonido no se repite dentro de `gap` segundos aunque lo pidan varias instancias
/// del motor (isla, fantasma al arrastrar, puntito al subir) o aunque ya haya sonado por el bus de ORBEX.
@MainActor
enum BotSoundGate {
    private static var lastPlayed: [String: Double] = [:]
    private static var lastBusSound: Double = -10
    private static var observer: NSObjectProtocol?

    /// Empieza a escuchar los sonidos del bus (una sola vez).
    static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: OrbexBus.sound, object: nil, queue: .main) { note in
            let raw = note.object as? String
            MainActor.assumeIsolated {
                let now = CACurrentMediaTime()
                BotSoundGate.lastBusSound = now
                if let raw { BotSoundGate.lastPlayed[raw] = now }
            }
        }
    }

    /// ¿Sonó algo por el bus hace menos de `seconds`? (el evento que disparó la reacción ya tiene su sonido)
    static func busSounded(within seconds: Double) -> Bool {
        CACurrentMediaTime() - lastBusSound < seconds
    }

    /// Reproduce un evento de la isla por nombre ("greet", "gulp"…), salvo que el mismo sonido haya
    /// sonado hace menos de `gap` segundos.
    static func play(_ name: String, gap: Double) {
        start()
        let key = SoundEngine.eventSounds[name]?.rawValue ?? name
        let now = CACurrentMediaTime()
        if let last = lastPlayed[key], now - last < gap { return }
        lastPlayed[key] = now
        SoundEngine.shared.play(name)
    }
}

// MARK: - Ayudas

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b-a) * t }

private func cgColorToTuple(_ c: CGColor) -> (CGFloat, CGFloat, CGFloat) {
    guard let comps = c.components, comps.count >= 3 else { return (1,1,1) }
    return (comps[0], comps[1], comps[2])
}

private func rgbTuple(_ c: CGColor) -> (r: Double, g: Double, b: Double) {
    let t = cgColorToTuple(c)
    return (r: Double(t.0), g: Double(t.1), b: Double(t.2))
}

private func mix3(_ a: (CGFloat,CGFloat,CGFloat), _ b: (CGFloat,CGFloat,CGFloat), _ t: CGFloat) -> (CGFloat,CGFloat,CGFloat) {
    (lerp(a.0,b.0,t), lerp(a.1,b.1,t), lerp(a.2,b.2,t))
}

private func mixRGB(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double),
                    _ k: Double) -> (r: Double, g: Double, b: Double) {
    (r: a.r + (b.r - a.r) * k, g: a.g + (b.g - a.g) * k, b: a.b + (b.b - a.b) * k)
}

/// Duración (ms) del tramo quieto de un emote; nunca negativa aunque el emote dure poco.
private func holdMs(_ duration: Double, _ lead: Double) -> CGFloat {
    CGFloat(max(0, (duration - lead) * 1000))
}

private func badgeString(_ b: BadgeType?) -> String {
    guard let b else { return "none" }
    func hex(_ c: CGColor) -> String {
        guard let k = c.components, k.count >= 3 else { return "?" }
        return "\(Int(k[0]*255)).\(Int(k[1]*255)).\(Int(k[2]*255))"
    }
    switch b {
    case .dots(let c):     return "dots-\(hex(c))"
    case .bang(let c):     return "bang-\(hex(c))"
    case .question(let c): return "q-\(hex(c))"
    case .dot(let c):      return "dot-\(hex(c))"
    }
}

/// Emote → forma de ojos de ORBEX.
private func emoteEyeShape(_ e: BotEmote) -> BotEyeShape {
    switch e {
    case .love:      return .heart
    case .surprised: return .wide     // sorprendido: óvalos más altos
    case .proud:     return .star
    case .wink:      return .wink
    case .yawn:      return .tired
    case .happy:     return .happy
    case .annoyed:   return .line
    }
}

/// Emote → sonido (nombre de evento de la isla).
private func emoteSoundName(_ e: BotEmote) -> String? {
    switch e {
    case .love:      return "love"
    case .surprised: return "pop"
    case .proud:     return "proud"
    case .wink:      return "wink"
    case .yawn:      return "yawn"
    case .annoyed:   return "annoyed"
    case .happy:     return nil   // se usa como confirmación, junto con el sonido de quien la pide
    }
}

// Equatable para BadgeType (compara solo el tipo)
extension BadgeType: Equatable {
    static func == (lhs: BadgeType, rhs: BadgeType) -> Bool {
        switch (lhs, rhs) {
        case (.dots, .dots): return true
        case (.bang, .bang): return true
        case (.question, .question): return true
        case (.dot, .dot): return true
        default: return false
        }
    }
}

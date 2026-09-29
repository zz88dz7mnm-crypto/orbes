// Basado en Coucou (https://github.com/louis-cfm/coucou) © 2026 Louis Raillé — licencia MIT.
// Modificado para ORBEX (solo el código; ningún asset de Coucou). Ver THIRD_PARTY_NOTICES.md.

import Foundation
import CoreGraphics

// Motor de la secuencia "tragar archivo" de ORBEX (vistas upload / uploading / choose, lienzo 640×176).
//
//   Arrastre  ORBEX sigue al cursor por la tarjeta y abre en la panza un portal de vidrio con remolino.
//             La apertura, el giro y el brillo del borde reaccionan a qué tan cerca viene el archivo;
//             cuando lo "engancha" abre los brazos para recibirlo ("attach").
//   Soltar    El ícono cae en espiral dentro del portal ("gulp"), el portal se cierra con un destello
//             y suben burbujitas de vidrio dentro de la esfera.
//   Subida    Se achica a un mini-ORBEX (esfera + ojos) que viaja a saltitos por la barra de progreso
//             dejando una estela de brillitos.
//   Listo     Salta contento al final de la barra y crece ("pop") hasta su lugar en la vista "choose".
//
// Los tiempos van en "t_ref" (el drop es a los 1,95 s). `FileDropView` usa `T_PROG_START - T_DROP`
// (1,30 s) para sincronizar los "tic" del progreso: no cambiar esa diferencia.

// ============================================================
// CONSTANTES (coordenadas del lienzo de la isla: 640 × 176)
// ============================================================

enum USC {
    static let W:     Double = 640
    static let ISL_H: Double = 176
    static let CARD_X: Double = 10;  static let CARD_Y: Double = 42
    static let CARD_W: Double = 620; static let CARD_H: Double = 124; static let CARD_R: Double = 20
    // ORBEX sobre la zona de soltar: centro de la esfera y diámetro (como la vista `.upload`).
    static let REST_X: Double = 140; static let REST_Y: Double = 104
    static let D_BOX:  Double = 62
    static let FOLLOW_MIN: Double = 60    // CARD_X + 50
    static let FOLLOW_MAX: Double = 580   // CARD_X + CARD_W - 50
    static let TEXT_X: Double = 196;  static let TEXT_Y: Double = 94
    static let BAR_X0: Double = 46;   static let BAR_X1: Double = 520;  static let BAR_Y: Double = 118
    // Lugar final (como la vista `.choose`: x 60, y 101, diámetro 52).
    static let CHOOSE_X: Double = 60; static let CHOOSE_Y: Double = 101; static let CHOOSE_D: Double = 52
    // Mini-ORBEX que viaja apoyado sobre la barra (la barra mide 6 pt de alto).
    static let MINI_D: Double = 16
    static let MINI_Y: Double = BAR_Y - 11
    static let LOCK_IN:  Double = 60
    static let LOCK_OUT: Double = 90
    // Apertura del portal (fracción del radio de la esfera) y su centro (fracción de D, bajo los ojos).
    static let PORTAL_AJAR: Double = 0.18
    static let PORTAL_OPEN: Double = 0.36
    static let PORTAL_MAX:  Double = 0.44
    static let PORTAL_Y:    Double = 0.20
    // Tiempos (t_ref; drop = 1,95)
    static let T_DROP:         Double = 1.95
    static let T_SUCK_START:   Double = 2.02   // empieza a caer en espiral
    static let T_SUCK_END:     Double = 2.50   // desaparece en el portal ("gulp")
    static let T_CLOSE_END:    Double = 2.62   // el portal terminó de cerrarse
    static let T_BUBBLES:      Double = 2.50   // burbujitas dentro de la esfera
    static let T_SHRINK_START: Double = 2.90   // se vuelve mini-ORBEX
    static let T_SHRINK_END:   Double = 3.23
    static let T_BAR_IN:       Double = 3.00
    static let T_PROG_START:   Double = 3.25
    static let DT: Double = 1.0 / 240.0
    // Al entrar se arranca 0,40 s antes del drop (tiempo de seguimiento de referencia).
    static let ENTRY_T_REF: Double = T_DROP - 0.40  // = 1,55
}

// ============================================================
// CURVAS
// ============================================================

func usEOut(_ t: Double) -> Double   { 1 - pow(1 - t, 3) }
func usEIn(_ t: Double)  -> Double   { t * t * t }
func usEInOut(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func usEBack(_ t: Double) -> Double  { let c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2) }

func usSeg(_ t: Double, _ a: Double, _ b: Double) -> Double { max(0, min(1, (t - a) / (b - a))) }
func usLerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

// Squeeze del "trago" (T_SUCK_END → +0,30 s): se aplasta, se estira y se asienta.
func usGulpSqueezeY(_ t: Double) -> Double {
    let t0 = USC.T_SUCK_END, t1 = t0 + 0.07, t2 = t0 + 0.18, t3 = t0 + 0.30
    if t <= t0 { return 1.06 }
    if t <= t1 { return usLerp(1.06, 0.84, usEOut(usSeg(t, t0, t1))) }
    if t <= t2 { return usLerp(0.84, 1.08, usEOut(usSeg(t, t1, t2))) }
    if t <= t3 { return usLerp(1.08, 1.00, usEInOut(usSeg(t, t2, t3))) }
    return 1.0
}
func usGulpSqueezeX(_ t: Double) -> Double {
    let t0 = USC.T_SUCK_END, t1 = t0 + 0.07, t2 = t0 + 0.18, t3 = t0 + 0.30
    if t <= t0 { return 0.97 }
    if t <= t1 { return usLerp(0.97, 1.12, usEOut(usSeg(t, t0, t1))) }
    if t <= t2 { return usLerp(1.12, 0.96, usEOut(usSeg(t, t1, t2))) }
    if t <= t3 { return usLerp(0.96, 1.00, usEInOut(usSeg(t, t2, t3))) }
    return 1.0
}

func usProgressCurve(_ u: Double) -> Double {
    if u < 0.40 { return 0.60 * usEOut(u / 0.40) }
    if u < 0.85 { return 0.60 + 0.32 * usEInOut((u - 0.40) / 0.45) }
    return 0.92 + 0.08 * usEIn((u - 0.85) / 0.15)
}
func usProgressAt(_ t: Double, progStart: Double, progEnd: Double) -> Double {
    t < progStart ? 0 : usProgressCurve(usSeg(t, progStart, progEnd))
}

// ============================================================
// RESORTE
// ============================================================

struct USSpring {
    var v:   Double
    var vel: Double = 0
    mutating func step(target: Double, response: Double, damping: Double, dt: Double) {
        let k = pow(2 * .pi / response, 2)
        let c = 2 * damping * sqrt(k)
        let a = k * (target - v) - c * vel
        vel += a * dt; v += vel * dt
    }
}

// ============================================================
// ESTADO DE LA SIMULACIÓN
// ============================================================

struct USSimState {
    var t:         Double = 0
    var bx:        USSpring = USSpring(v: USC.REST_X)
    var by:        USSpring = USSpring(v: USC.REST_Y)
    var tilt:      Double = 0
    var portal:    USSpring = USSpring(v: 0)   // apertura del portal (fracción del radio)
    var swirl:     Double = 0                  // ángulo del remolino (rad)
    var proximity: Double = 0                  // 0…1 qué tan cerca viene el archivo (suavizado)
    var locked:    Bool = false
    var lockAt:    Double = -9
    var entered:   Double = -9                 // t_ref de entrada a la zona; -9 = no entró
}

// ============================================================
// CUADRO — lo que lee UploadCanvasView
// ============================================================

enum USEyeShape { case neutral, eager, happy }

struct USFrame {
    var t: Double = 0
    var calm: Bool = false                     // "reducir movimiento"
    var cursorX: Double = 600; var cursorY: Double = 280
    // ORBEX (centro de la esfera, diámetro, squash & stretch)
    var x: Double = USC.REST_X; var y: Double = USC.REST_Y; var d: Double = USC.D_BOX
    var sx: Double = 1; var sy: Double = 1; var tilt: Double = 0; var hop: Double = 0
    var limbs: Double = 1                      // 0…1 brazos y piernas (el mini no tiene)
    var arms: Double = 0.08                    // cuánto levanta los brazos
    var eye: USEyeShape = .neutral
    var eyeOpen: Double = 1
    var lookX: Double = 0; var lookY: Double = 0
    // Portal de vidrio en la panza
    var portalRing: Double = 0                 // 0…1 aparición del portal
    var portal: Double = 0                     // apertura (fracción del radio)
    var swirl: Double = 0
    var proximity: Double = 0
    var portalX: Double = 0; var portalY: Double = 0   // centro en el lienzo (para tragar el archivo)
    var cursorAngle: Double = 0                // hacia dónde brilla el borde del portal
    var gulpFlash: Double = 0                  // 1 → 0 destello al tragar
    var bubbleAge: Double = -1                 // s desde que suben las burbujitas (-1 = nada)
    var digest: Double = 0                     // brillo interno mientras "digiere"
    var trail: Bool = false                    // el mini deja brillitos en la barra
    var sparkleBurst: Double = -1              // s desde que llegó a "choose" (-1 = nada)
    // Archivo
    var fileVisible: Bool = true; var suck: Double = 0
    // Tarjeta, barra y "choose"
    var zoneOver:    Bool   = false
    var zoneAlpha:   Double = 1
    var textAlpha:   Double = 1
    var barReveal:   Double = 0
    var barAlpha:    Double = 0
    var progress:    Double = 0
    var flash:       Double = 0
    var check:       Double = 0
    var greenWash:   Double = 0
    var chooseAlpha: Double = 0
    var uploadDuration: Double = 2.4
    var progEnd:    Double = USC.T_PROG_START + 2.4
    var growStart:  Double = USC.T_PROG_START + 2.4 + 0.25
    var growEnd:    Double = USC.T_PROG_START + 2.4 + 0.70
}

// ============================================================
// MOTOR
// ============================================================

@MainActor
final class UploadSequenceEngine {
    static let shared = UploadSequenceEngine()

    var uploadDuration: Double = 2.4
    var progEnd:   Double { USC.T_PROG_START + uploadDuration }
    var growStart: Double { progEnd + 0.25 }
    var growEnd:   Double { progEnd + 0.70 }

    private(set) var isActive: Bool = false
    private var entryWallTime: Double = 0   // Date().timeIntervalSinceReferenceDate al entrar
    private var dropWallTime:  Double? = nil

    private var sim = USSimState()
    /// "Reducir movimiento" (se lee en cada cuadro).
    private var calm = false
    /// El archivo está sobre la isla (entre `enterZone`/`updateCursor` y `exitZone`).
    private var inZone = false
    /// Último t_ref con los sonidos revisados (suenan al cruzar cada instante, una sola vez).
    private var cueT: Double = 0
    private var attachPlayed = false
    /// Último cuadro: se sigue mostrando mientras la vista se desvanece después de `deactivate()`.
    private var lastFrame = USFrame()

    // Cursor real en coordenadas de la isla
    var cursorX: Double = 600
    var cursorY: Double = 280
    private var prevCursorX:  Double = 600
    private var prevCursorY:  Double = 280
    private var prevCursorTime: Double = 0
    private var cursorSpeed: Double = 0

    // MARK: - Ciclo de vida

    func enterZone(x: CGFloat, y: CGFloat) {
        let now = Date().timeIntervalSinceReferenceDate
        // Si salió y volvió a entrar en el mismo arrastre, ORBEX sigue desde donde estaba.
        let resume = isActive && dropWallTime == nil
        let old = sim
        cursorX = Double(x); cursorY = Double(y)
        prevCursorX = cursorX; prevCursorY = cursorY; prevCursorTime = now
        cursorSpeed = 0
        sim = USSimState()
        sim.t = USC.ENTRY_T_REF
        sim.entered = USC.ENTRY_T_REF
        if resume {
            sim.bx = old.bx; sim.by = old.by
            sim.portal = old.portal; sim.swirl = old.swirl; sim.proximity = old.proximity
            sim.entered = USC.ENTRY_T_REF - 1   // el portal ya estaba abierto: no vuelve a "aparecer"
        } else {
            attachPlayed = false
        }
        entryWallTime = now
        dropWallTime  = nil
        cueT = USC.ENTRY_T_REF
        inZone = true
        isActive = true
    }

    func updateCursor(x: CGFloat, y: CGFloat) {
        let now = Date().timeIntervalSinceReferenceDate
        let dt = now - prevCursorTime
        if dt > 0.001 {
            let dx = Double(x) - prevCursorX, dy = Double(y) - prevCursorY
            cursorSpeed = hypot(dx, dy) / dt
        }
        prevCursorX = Double(x); prevCursorY = Double(y); prevCursorTime = now
        cursorX = Double(x); cursorY = Double(y)
        inZone = true
    }

    func exitZone() {
        // La isla queda abierta (así lo pide el diseño); el portal se calma hasta que vuelva el archivo.
        inZone = false
    }

    func performDrop(uploadDuration ud: Double) {
        if !isActive { enterZone(x: CGFloat(cursorX), y: CGFloat(cursorY)) }
        uploadDuration = ud
        dropWallTime = Date().timeIntervalSinceReferenceDate
        // Después del drop la línea de tiempo arranca siempre en T_DROP, sin importar cuánto duró el
        // arrastre. Los resortes (posición, velocidad, portal) se conservan.
        sim.t = USC.T_DROP
        cueT = USC.T_DROP
        inZone = true
    }

    func deactivate() {
        isActive = false
        dropWallTime = nil
    }

    // MARK: - t_ref según el reloj

    func tRef(at date: Date) -> Double {
        guard isActive else { return 0 }
        let now = date.timeIntervalSinceReferenceDate
        if let dw = dropWallTime {
            return USC.T_DROP + max(0, now - dw)
        }
        // Sin tope: el resorte sigue mientras el archivo esté encima.
        // computeFrame fija las fases en "antes del drop".
        return USC.ENTRY_T_REF + max(0, now - entryWallTime)
    }

    // MARK: - Entrada pública

    func frame(at date: Date) -> USFrame {
        guard isActive else { return lastFrame }
        calm = AppModel.shared.effectiveReduceMotion
        let t = tRef(at: date)
        simulateTo(t)
        let f = computeFrame(t: t)
        playCues(upTo: t)
        lastFrame = f
        return f
    }

    // MARK: - Simulación

    private func simulateTo(_ tTarget: Double) {
        while sim.t < tTarget - 1e-10 {
            let dt = min(USC.DT, tTarget - sim.t)
            stepOnce(dt: dt)
            sim.t += dt
        }
    }

    private func stepOnce(dt: Double) {
        let isDragging = (dropWallTime == nil)
        let t = sim.t

        // Sigue al cursor por la tarjeta (solo mientras arrastra) y "engancha" el archivo cuando está
        // cerca y lento.
        var dist = 1e9
        if isDragging && sim.entered >= 0 {
            dist = hypot(cursorX - sim.bx.v, (cursorY + 14) - sim.by.v)
            if !sim.locked && inZone && dist < USC.LOCK_IN && cursorSpeed < 180 {
                sim.locked = true; sim.lockAt = t
                if !attachPlayed { attachPlayed = true; SoundEngine.shared.play("attach") }
            }
            if sim.locked && (dist > USC.LOCK_OUT || !inZone) { sim.locked = false }
            let tx = max(USC.FOLLOW_MIN, min(USC.FOLLOW_MAX, cursorX))
            let response = sim.locked ? 0.18 : 0.35
            let damping = sim.locked ? 0.75 : 0.70
            sim.bx.step(target: tx, response: response, damping: damping, dt: dt)
            sim.by.step(target: USC.REST_Y, response: response, damping: damping, dt: dt)
        }

        // Cercanía del archivo (suavizada): abre el portal y acelera el remolino.
        var proxTarget = 1.0                    // después del drop: al máximo
        if isDragging { proxTarget = inZone ? max(0, min(1, 1 - (dist - 40) / 160)) : 0 }
        sim.proximity = usLerp(sim.proximity, proxTarget, 1 - pow(0.002, dt))

        // Inclinación según la velocidad horizontal (solo mientras arrastra).
        let tiltTarget = (isDragging && !calm) ? max(-0.18, min(0.18, sim.bx.vel * 0.0015)) : 0.0
        sim.tilt = usLerp(sim.tilt, tiltTarget, 1 - pow(0.0005, dt))

        // Apertura del portal. Después de tragar se cierra solo.
        if !isDragging && t >= USC.T_SUCK_END {
            sim.portal.v = max(0, usLerp(USC.PORTAL_MAX, 0, usEIn(usSeg(t, USC.T_SUCK_END, USC.T_CLOSE_END))))
            sim.portal.vel = 0
        } else {
            var target = 0.0
            if sim.entered >= 0 {
                if !isDragging {
                    target = USC.PORTAL_MAX
                } else if sim.locked {
                    target = USC.PORTAL_OPEN
                } else if inZone {
                    target = USC.PORTAL_AJAR + (USC.PORTAL_OPEN - USC.PORTAL_AJAR) * 0.6 * sim.proximity
                } else {
                    target = USC.PORTAL_AJAR * 0.6
                }
            }
            sim.portal.step(target: target, response: 0.25, damping: calm ? 1.0 : 0.60, dt: dt)
            if sim.portal.v < 0 { sim.portal.v = 0 }
        }

        // Remolino: gira más rápido cuanto más cerca viene el archivo y mientras lo traga.
        let swallowing = !isDragging && t >= USC.T_SUCK_START && t < USC.T_SUCK_END
        let speed = calm
            ? 0.8 + 1.2 * sim.proximity + (swallowing ? 2.0 : 0)
            : 1.6 + 5.5 * sim.proximity + (swallowing ? 9.0 : 0)
        sim.swirl += speed * dt
    }

    /// Sonidos atados a la línea de tiempo del drop ("attach" suena en `stepOnce` al enganchar).
    private func playCues(upTo t: Double) {
        defer { cueT = max(cueT, t) }
        guard dropWallTime != nil, t > cueT else { return }
        let from = cueT
        func crossed(_ c: Double) -> Bool { from < c && t >= c }
        if crossed(USC.T_SUCK_END) { SoundEngine.shared.play("gulp") }
        if crossed(growStart + 0.06) { SoundEngine.shared.play("pop") }
    }

    /// Parpadeo cada 3,1 s (ORBEX siempre tiene algo vivo, también de mini).
    private func blink(_ t: Double) -> Double {
        let k = usSeg(t.truncatingRemainder(dividingBy: 3.1), 2.92, 3.06)
        return (k > 0 && k < 1) ? 1 - sin(.pi * k) * 0.93 : 1
    }

    // MARK: - Cuadro

    private func computeFrame(t: Double) -> USFrame {
        var f = USFrame()
        f.t = t
        f.calm = calm
        f.cursorX = cursorX; f.cursorY = cursorY
        f.uploadDuration = uploadDuration
        f.progEnd   = progEnd
        f.growStart = growStart
        f.growEnd   = growEnd

        let entered    = sim.entered >= 0 ? sim.entered : 1e9
        let isDragging = (dropWallTime == nil)
        // Mientras arrastra, las fases se calculan con t apenas antes del drop: un arrastre largo no
        // dispara lo que viene después de soltar.
        let pt = isDragging ? min(t, USC.T_DROP - USC.DT) : t
        let amp = calm ? 0.35 : 1.0             // amplitud del squash & stretch

        // ── Posición (centro de la esfera) y diámetro ──
        var x = sim.bx.v, y = sim.by.v, d = USC.D_BOX
        if pt >= USC.T_SHRINK_START && pt < USC.T_PROG_START {
            // Se achica a mini-ORBEX y salta al comienzo de la barra.
            let k = usEInOut(usSeg(pt, USC.T_SHRINK_START, USC.T_SHRINK_END))
            x = usLerp(sim.bx.v, USC.BAR_X0, k)
            y = usLerp(sim.by.v, USC.MINI_Y, k) - (calm ? 0 : 16 * sin(.pi * k))
            d = usLerp(USC.D_BOX, USC.MINI_D, k)
        }
        if pt >= USC.T_PROG_START {
            // Viaja por la barra a saltitos (20 saltos de punta a punta).
            let p = usProgressAt(pt, progStart: USC.T_PROG_START, progEnd: progEnd)
            x = usLerp(USC.BAR_X0, USC.BAR_X1, p)
            y = USC.MINI_Y - (calm ? 0 : 2.2 * abs(sin(.pi * 20 * p)))
            d = USC.MINI_D
        }
        if pt >= progEnd {
            // Salto contento al llegar.
            x = USC.BAR_X1
            y = USC.MINI_Y - (calm ? 3 : 9) * sin(.pi * usSeg(pt, progEnd, progEnd + 0.22))
        }
        if pt >= growStart {
            // Crece hasta su lugar en "choose".
            let k = usSeg(pt, growStart, growEnd)
            x = usLerp(USC.BAR_X1, USC.CHOOSE_X, usEInOut(k))
            y = usLerp(USC.MINI_Y, USC.CHOOSE_Y, usEInOut(k)) - (calm ? 0 : 12 * sin(.pi * k))
            d = usLerp(USC.MINI_D, USC.CHOOSE_D, calm ? usEOut(k) : usEBack(k))
        }
        f.x = x; f.y = y; f.d = d

        // ── Squash & stretch ──
        var sx = 1.0, sy = 1.0, lean = 0.0
        if pt >= USC.T_DROP && pt < USC.T_SUCK_START {
            // Anticipación: se agacha un poco para recibir.
            let k = usEOut(usSeg(pt, USC.T_DROP, USC.T_SUCK_START))
            sy = 1 - 0.08 * amp * k; sx = 1 + 0.06 * amp * k
        }
        if pt >= USC.T_SUCK_START && pt < USC.T_SUCK_END {
            // Inhala mientras traga.
            let k = usEInOut(usSeg(pt, USC.T_SUCK_START, USC.T_SUCK_END))
            sy = 1 + amp * (-0.08 + 0.13 * k); sx = 1 + amp * (0.06 - 0.08 * k)
        }
        if pt >= USC.T_SUCK_END && pt < USC.T_SUCK_END + 0.30 {
            sy = 1 + (usGulpSqueezeY(pt) - 1) * amp
            sx = 1 + (usGulpSqueezeX(pt) - 1) * amp
        }
        if pt >= USC.T_SHRINK_START && pt < USC.T_SHRINK_END {
            let k = sin(.pi * usSeg(pt, USC.T_SHRINK_START, USC.T_SHRINK_END))
            sy = 1 + 0.12 * amp * k; sx = 1 - 0.06 * amp * k
        }
        if pt >= USC.T_PROG_START && pt < progEnd {
            // Se estira con la velocidad y se inclina hacia adelante.
            let v = (usProgressAt(pt + 0.01, progStart: USC.T_PROG_START, progEnd: progEnd)
                   - usProgressAt(pt,        progStart: USC.T_PROG_START, progEnd: progEnd)) / 0.01
            let st = max(0, min(1, v * 0.18)) * amp
            sx = 1 + 0.25 * st; sy = 1 - 0.15 * st
            lean = calm ? 0 : 0.35 * st
        }
        if pt >= growStart && pt < growEnd {
            sy = 1 + 0.06 * amp * sin(.pi * usSeg(pt, growStart, growEnd))
        }
        f.sx = sx; f.sy = sy
        f.tilt = sim.tilt + lean
        f.hop = (sim.lockAt > 0 && isDragging && !calm)
            ? -5 * sin(.pi * usSeg(pt, sim.lockAt, sim.lockAt + 0.15)) : 0

        // ── Brazos y piernas ──
        var limbs = 1.0
        if pt >= USC.T_SHRINK_START { limbs = 1 - usSeg(pt, USC.T_SHRINK_START, USC.T_SHRINK_START + 0.18) }
        if pt >= growStart { limbs = usSeg(pt, growStart + 0.18, growEnd) }
        f.limbs = limbs
        // Abre los brazos a medida que se abre el portal; al volver a "choose", festejo.
        var arms = 0.08 + 1.1 * min(1, sim.portal.v / USC.PORTAL_MAX)
        if pt >= growStart { arms = 0.08 + 1.7 * sin(.pi * usSeg(pt, growEnd - 0.12, growEnd + 0.45)) }
        f.arms = arms

        // ── Ojos y mirada ──
        var eye: USEyeShape = .neutral
        if (sim.locked || !isDragging) && pt < USC.T_SUCK_END { eye = .eager }
        if pt >= USC.T_SUCK_END && pt < USC.T_SHRINK_START + 0.10 { eye = .happy }
        if pt >= progEnd && pt < growEnd + 0.30 { eye = .happy }
        f.eye = eye
        f.eyeOpen = blink(t)
        let lkx = pt < USC.T_SUCK_END ? cursorX - x : (pt < USC.T_PROG_START ? 0.0 : 40.0)
        let lky = pt < USC.T_SUCK_END ? (cursorY + 10) - y : 0.0
        f.lookX = max(-1, min(1, lkx / 200)); f.lookY = max(-1, min(1, lky / 150))

        // ── Portal ──
        f.portalRing = max(0, min(1.1, usEBack(usSeg(pt, entered, entered + 0.38))))
        f.portal = sim.portal.v
        f.swirl = sim.swirl
        f.proximity = sim.proximity
        // Centro del portal en el lienzo: mismo transform que el cuerpo (squash anclado abajo + giro).
        let ly = 0.5 * d + (USC.PORTAL_Y * d - 0.5 * d) * sy
        f.portalX = x - ly * sin(f.tilt)
        f.portalY = y + f.hop + ly * cos(f.tilt)
        f.cursorAngle = atan2((cursorY + 14) - f.portalY, cursorX - f.portalX)
        f.gulpFlash = pt >= USC.T_SUCK_END ? 1 - usSeg(pt, USC.T_SUCK_END, USC.T_SUCK_END + 0.25) : 0
        f.bubbleAge = pt >= USC.T_BUBBLES ? pt - USC.T_BUBBLES : -1
        f.digest = sin(.pi * usSeg(pt, USC.T_SUCK_END, USC.T_SHRINK_START + 0.15))
        f.trail = pt >= USC.T_PROG_START && pt < growStart + 0.30
        f.sparkleBurst = pt >= growEnd - 0.12 ? pt - (growEnd - 0.12) : -1

        // ── Archivo ──
        f.fileVisible = pt < USC.T_SUCK_END
        f.suck = usSeg(pt, USC.T_SUCK_START, USC.T_SUCK_END)

        // ── Tarjeta, barra y "choose" ──
        f.zoneOver   = sim.entered >= 0 && pt < USC.T_SHRINK_START
        f.zoneAlpha  = 1 - usSeg(pt, USC.T_SHRINK_START, USC.T_SHRINK_START + 0.20)
        f.textAlpha  = f.zoneAlpha * ((x > USC.TEXT_X - 40 && isDragging) ? 0.25 : 1.0)
        f.barReveal  = usEOut(usSeg(pt, USC.T_BAR_IN, USC.T_BAR_IN + 0.25))
                     * (1 - usSeg(pt, growStart, growStart + 0.20))
        f.barAlpha   = usSeg(pt, USC.T_BAR_IN + 0.05, USC.T_BAR_IN + 0.25)
                     * (1 - usSeg(pt, growStart, growStart + 0.20))
        f.progress   = usProgressAt(pt, progStart: USC.T_PROG_START, progEnd: progEnd)
        f.flash      = pt >= progEnd ? sin(.pi * usSeg(pt, progEnd, progEnd + 0.30)) : 0
        f.check      = pt >= progEnd ? usEBack(usSeg(pt, progEnd, progEnd + 0.25)) : 0
        let hoverGreen = f.zoneOver ? 0.22 : 0.0
        var uploadGreen = 0.0
        if pt >= USC.T_PROG_START {
            // Crece con el progreso, destello al terminar y se apaga cuando ORBEX vuelve a "choose".
            let baseGreen = f.progress * 0.50
            let flashExtra = pt >= progEnd ? 0.20 * sin(.pi * usSeg(pt, progEnd, progEnd + 0.40)) : 0
            let fadeOut = 1.0 - usSeg(pt, growEnd, growEnd + 0.60)
            uploadGreen = (baseGreen + flashExtra) * fadeOut
        }
        f.greenWash = max(hoverGreen, uploadGreen)
        f.chooseAlpha = usSeg(pt, growStart + 0.15, growEnd)
        return f
    }
}

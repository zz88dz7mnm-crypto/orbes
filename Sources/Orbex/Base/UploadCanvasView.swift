// Basado en Coucou (https://github.com/louis-cfm/coucou) © 2026 Louis Raillé — licencia MIT.
// Modificado para ORBEX (solo el código; ningún asset de Coucou). Ver THIRD_PARTY_NOTICES.md.

import SwiftUI
import AppKit
import OrbexCore

// Lienzo de 640×176 de la secuencia de subir archivo: reemplaza encabezado y contenido mientras el
// motor está activo. Dibuja la tarjeta, la zona de soltar, la barra de progreso, la vista "choose" y a
// ORBEX con su portal de vidrio. La coreografía y los tiempos están en `UploadSequenceEngine`.

struct UploadCanvasView: View {
    @ObservedObject var state: AppState
    @State private var fileIcon: NSImage? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / max(24, AppModel.shared.characterFPS))) { tl in
            let f = UploadSequenceEngine.shared.frame(at: tl.date)
            let scene = UploadScene(f: f,
                                    wall: tl.date.timeIntervalSinceReferenceDate,
                                    fileName: usShortName(state.droppedFile?.name ?? "archivo"),
                                    icon: fileIcon,
                                    look: currentLook())
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    scene.draw(&ctx)
                }
                .frame(width: 640, height: 176)

                // Botones de "choose" (zonas invisibles sobre lo que dibuja el lienzo)
                if f.chooseAlpha > 0 {
                    chooseOverlay(f: f)
                        .frame(width: 640, height: 176)
                }
            }
        }
        .onChange(of: state.droppedFile?.url) { _, url in
            if let url { loadIcon(url: url) }
        }
        .onAppear {
            if let url = state.droppedFile?.url { loadIcon(url: url) }
        }
        .frame(width: 640, height: 176)
    }

    // MARK: - Datos del momento

    /// Color y material de ORBEX según el tema (igual que `OrbexView`).
    @MainActor private func currentLook() -> UploadLook {
        let theme = AppModel.shared.themeStyle
        let material: OrbexMaterial = (theme.glassAllowed || theme.id != .liquidGlass)
            ? OrbexMaterial(theme: theme.id) : .solid
        return UploadLook(tint: CharacterBrain.shared.tint.rgb, material: material)
    }

    @MainActor private func loadIcon(url: URL) {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 64, height: 64)
        fileIcon = img
    }

    // MARK: - Botones de "choose"

    @MainActor @ViewBuilder
    private func chooseOverlay(f: USFrame) -> some View {
        // Mismas posiciones que dibuja el lienzo: botón 1 x=114 w=168, botón 2 x=290 w=120, y=113 h=26.
        ZStack(alignment: .topLeading) {
            Button {
                choose(.prompt)
            } label: {
                Color.clear
                    .frame(width: 168, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preguntar sobre esto")
            .frame(width: 168, height: 26)
            .position(x: 114 + 84, y: 113 + 13)

            Button {
                choose(.mail)
            } label: {
                Color.clear
                    .frame(width: 120, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mandar por mail")
            .frame(width: 120, height: 26)
            .position(x: 290 + 60, y: 113 + 13)
        }
        .opacity(f.chooseAlpha)
        .allowsHitTesting(f.chooseAlpha > 0.5)
    }

    @MainActor private func choose(_ view: IslandView) {
        withAnimation(.easeInOut(duration: 0.22)) { state.view = view }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            MainActor.assumeIsolated { UploadSequenceEngine.shared.deactivate() }
        }
    }
}

// MARK: - Ayudantes

private typealias USRGB = (r: Double, g: Double, b: Double)

private let usWhite: USRGB = (1, 1, 1)
private let usDeep: USRGB = (0.12, 0.2, 0.32)
/// Celeste del portal (se mezcla con el color de ORBEX).
private let usPortalBlue: USRGB = (0.45, 0.78, 1.0)

private func usMix(_ a: USRGB, _ b: USRGB, _ k: Double) -> USRGB {
    (a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k)
}

private func usColor(_ c: USRGB, _ a: Double) -> Color {
    Color(red: c.r, green: c.g, blue: c.b).opacity(a)
}

/// Número pseudoaleatorio estable en [0, 1) a partir de un valor (brillitos sin guardar estado).
private func usHash(_ x: Double) -> Double {
    let s = sin(x * 12.9898 + 78.233) * 43758.5453
    return s - floor(s)
}

/// Acorta nombres largos con "…" en el medio para que entren en la tarjeta.
private func usShortName(_ s: String, max n: Int = 36) -> String {
    guard s.count > n else { return s }
    return "\(s.prefix(n - n / 3 - 1))…\(s.suffix(n / 3))"
}

/// Posición horizontal de cada burbujita (fracción de ±0,2 D).
private let usBubbleX: [Double] = [-0.2, 0.55, -0.7, 0.15, 0.8, -0.45, 0.35]

private struct UploadLook {
    var tint: USRGB
    var material: OrbexMaterial
}

// MARK: - Escena

/// Todo lo que se dibuja en un cuadro (valores, sin estado: se puede dibujar desde el `Canvas`).
private struct UploadScene {
    let f: USFrame
    let wall: Double
    let fileName: String
    let icon: NSImage?
    let look: UploadLook

    private var portalColor: USRGB { usMix(look.tint, usPortalBlue, 0.5) }

    private var expression: FaceExpression {
        switch f.eye {
        case .neutral: return .neutral
        case .eager:   return .surprised
        case .happy:   return .happy
        }
    }

    func draw(_ ctx: inout GraphicsContext) {
        // Fondo de la isla
        ctx.fill(Path(CGRect(x: 0, y: 0, width: USC.W, height: USC.ISL_H)), with: .color(Color.black))
        drawCard(&ctx)
        if f.zoneAlpha > 0 { drawDashedBorder(&ctx) }
        if f.zoneAlpha > 0 && f.textAlpha > 0 { drawDropText(&ctx) }
        if f.barAlpha > 0 || f.barReveal > 0 { drawProgressBar(&ctx) }
        if f.trail { drawTrail(&ctx) }
        if f.chooseAlpha > 0 { drawChooseView(&ctx) }
        drawOrbex(&ctx)
        if f.sparkleBurst >= 0 && f.sparkleBurst < 0.7 { drawArrivalSparkles(&ctx) }
        if f.fileVisible { drawFile(&ctx) }
    }

    // MARK: Tarjeta

    private func drawCard(_ ctx: inout GraphicsContext) {
        let rect = CGRect(x: USC.CARD_X, y: USC.CARD_Y, width: USC.CARD_W, height: USC.CARD_H)
        var c = ctx
        c.clip(to: roundedRect(rect, r: USC.CARD_R))
        c.fill(Path(rect), with: .color(Color(red: 0.051, green: 0.055, blue: 0.063)))
        // Brillo verde desde abajo: aparece con el archivo encima y crece con la subida.
        if f.greenWash > 0 {
            let green = Color(red: 0.157, green: 0.831, blue: 0.510)
            let g = Gradient(stops: [
                .init(color: green.opacity(f.greenWash * 0.90), location: 0),
                .init(color: green.opacity(f.greenWash * 0.30), location: 0.55),
                .init(color: green.opacity(0), location: 1),
            ])
            c.fill(Path(rect), with: .radialGradient(g, center: CGPoint(x: rect.midX, y: rect.maxY),
                                                     startRadius: 0, endRadius: rect.height * 1.5))
        }
    }

    private func drawDashedBorder(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.opacity = f.zoneAlpha
        let color = f.zoneOver
            ? Color(red: 0.204, green: 0.831, blue: 0.600).opacity(0.55)
            : Color.white.opacity(0.14)
        let inset = CGRect(x: USC.CARD_X + 0.75, y: USC.CARD_Y + 0.75,
                           width: USC.CARD_W - 1.5, height: USC.CARD_H - 1.5)
        // El trazo "camina" a ~20 pt/s (fase en módulo del patrón 6 + 5 para no perder precisión).
        let phase = CGFloat((wall * 20).truncatingRemainder(dividingBy: 11))
        c.stroke(roundedRect(inset, r: USC.CARD_R - 0.5), with: .color(color),
                 style: StrokeStyle(lineWidth: 1.5, dash: [6, 5], dashPhase: phase))
    }

    private func drawDropText(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.opacity = f.textAlpha
        let label = Text("Soltá tus archivos acá")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Color(hex: "#D5D7DB"))
        c.draw(label, at: CGPoint(x: USC.TEXT_X, y: USC.TEXT_Y - 4), anchor: .leading)
        var x = USC.TEXT_X
        for chip in ["PDF", "Imágenes", "Código", "Docs"] {
            let w = Double(chip.count) * 6.5 + 16
            c.fill(roundedRect(CGRect(x: x, y: USC.TEXT_Y + 9, width: w, height: 18), r: 9),
                   with: .color(Color.white.opacity(0.07)))
            let text = Text(chip)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#B9BDC4"))
            c.draw(text, at: CGPoint(x: x + 8, y: USC.TEXT_Y + 18), anchor: .leading)
            x += w + 6
        }
    }

    // MARK: Barra de progreso

    private func drawProgressBar(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.opacity = max(f.barAlpha, 0.001)
        let x0 = USC.BAR_X0, x1 = USC.BAR_X1, by = USC.BAR_Y
        let gray = Color(hex: "#A9ADB5")

        let label = Text("Subiendo \(fileName)")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(gray)
        c.draw(label, at: CGPoint(x: x0, y: by - 30), anchor: .leading)

        // Tilde al terminar; si no, el porcentaje.
        if f.check > 0 {
            var ck = c
            ck.translateBy(x: CGFloat(x1 - 8), y: CGFloat(by - 30))
            ck.scaleBy(x: CGFloat(f.check), y: CGFloat(f.check))
            ck.fill(Path(ellipseIn: CGRect(x: -8, y: -8, width: 16, height: 16)), with: .color(Color(hex: "#34D399")))
            var mark = Path()
            mark.move(to: CGPoint(x: -3.6, y: 0.2))
            mark.addLine(to: CGPoint(x: -1, y: 2.8))
            mark.addLine(to: CGPoint(x: 3.8, y: -2.6))
            ck.stroke(mark, with: .color(Color(red: 0.027, green: 0.075, blue: 0.055)),
                      style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        } else {
            let pct = Text("\(Int(f.progress * 100)) %")
                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                .foregroundColor(gray)
            c.draw(pct, at: CGPoint(x: x1, y: by - 30), anchor: .trailing)
        }

        // Riel
        let railLen = (x1 - x0) * f.barReveal
        if railLen > 0 {
            c.fill(roundedRect(CGRect(x: x0, y: by - 3, width: railLen, height: 6), r: 3),
                   with: .color(Color.white.opacity(0.08)))
        }

        // Relleno (destella al terminar)
        let fx = usLerp(x0, x1, f.progress)
        if fx > x0 + 1 {
            let flashGreen = Color(red: usLerp(0.204, 0.431, f.flash),
                                   green: usLerp(0.827, 0.906, f.flash),
                                   blue: usLerp(0.600, 0.718, f.flash))
            let g = Gradient(stops: [
                .init(color: Color(hex: "#1FA87A"), location: 0),
                .init(color: flashGreen, location: 1),
            ])
            c.fill(roundedRect(CGRect(x: x0, y: by - 3, width: fx - x0, height: 6), r: 3),
                   with: .linearGradient(g, startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: fx, y: 0)))
        }

        // Estela luminosa en la punta del relleno (más larga cuanto más rápido avanza)
        if f.progress > 0.01 && f.progress < 1 {
            let v = (usProgressAt(f.t + 0.01, progStart: USC.T_PROG_START, progEnd: f.progEnd)
                   - usProgressAt(f.t,        progStart: USC.T_PROG_START, progEnd: f.progEnd)) / 0.01
            let tl = max(8, min(34, 8 + v * 40))
            let g = Gradient(stops: [
                .init(color: Color(red: 0.204, green: 0.831, blue: 0.600, opacity: 0), location: 0),
                .init(color: Color(red: 0.431, green: 0.906, blue: 0.718, opacity: 0.6), location: 1),
            ])
            var glow = c
            glow.addFilter(.blur(radius: 3))
            glow.fill(roundedRect(CGRect(x: fx - tl, y: by - 4, width: tl, height: 8), r: 4),
                      with: .linearGradient(g, startPoint: CGPoint(x: fx - tl, y: 0), endPoint: CGPoint(x: fx, y: 0)))
        }
    }

    /// Estela de brillitos del mini-ORBEX: se "siembra" uno cada 0,06 s donde estaba el mini;
    /// cada brillito queda en su lugar, titila y se apaga en 0,6 s (sin guardar estado).
    private func drawTrail(_ ctx: inout GraphicsContext) {
        let step = f.calm ? 0.12 : 0.06
        let life = 0.6
        let color = usMix(look.tint, usWhite, 0.55)
        var ts = floor(min(f.t, f.progEnd) / step) * step
        while ts > f.t - life && ts >= USC.T_PROG_START {
            let k = (f.t - ts) / life
            if k >= 0 && k < 1 {
                let p = usProgressAt(ts, progStart: USC.T_PROG_START, progEnd: f.progEnd)
                let h = usHash(ts)
                let x = usLerp(USC.BAR_X0, USC.BAR_X1, p) - USC.MINI_D * 0.45 + (h - 0.5) * 4
                let rise = f.calm ? 0 : k * 4
                let y = USC.MINI_Y + 2 - h * 9 - rise
                let size = CGFloat(3 + 3 * usHash(ts + 0.37)) * CGFloat(1 - 0.5 * k)
                let twinkle = f.calm ? 0.8 : 0.6 + 0.4 * abs(sin(k * 9 + h * 6))
                var s = ctx
                s.opacity = (1 - k) * twinkle
                s.translateBy(x: CGFloat(x), y: CGFloat(y))
                if !f.calm { s.rotate(by: .radians(k * 1.2)) }
                s.fill(OrbexPainter.sparkle(size: size), with: .color(usColor(color, 1)))
            }
            ts -= step
        }
    }

    // MARK: Vista "choose"

    private func drawChooseView(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.opacity = f.chooseAlpha
        c.translateBy(x: 0, y: CGFloat((1 - f.chooseAlpha) * 4))   // sube un poquito al aparecer

        let title = Text("¡Listo! Ya tengo \(fileName).")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color(hex: "#F5F6F8"))
        c.draw(title, at: CGPoint(x: 114, y: 80), anchor: .leading)

        let subtitle = Text("¿Qué querés hacer con el archivo?")
            .font(.system(size: 12.5))
            .foregroundColor(Color(hex: "#9398A1"))
        c.draw(subtitle, at: CGPoint(x: 114, y: 100), anchor: .leading)

        // Botón principal (blanco)
        c.fill(roundedRect(CGRect(x: 114, y: 113, width: 168, height: 26), r: 13),
               with: .color(Color(hex: "#F5F6F8")))
        let ask = Text("Preguntar sobre esto")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(Color(red: 0.043, green: 0.047, blue: 0.055))
        c.draw(ask, at: CGPoint(x: 198, y: 126), anchor: .center)

        // Botón secundario (tenue)
        c.fill(roundedRect(CGRect(x: 290, y: 113, width: 120, height: 26), r: 13),
               with: .color(Color.white.opacity(0.09)))
        let mail = Text("Mandar por mail")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(Color(hex: "#F1F2F4"))
        c.draw(mail, at: CGPoint(x: 350, y: 126), anchor: .center)
    }

    // MARK: ORBEX

    /// ORBEX con las partes de `OrbexPainter`: piernas, cuerpo (squash & stretch anclado abajo),
    /// brillo de "digestión", portal, burbujitas, ojos y brazos. El mini no tiene brazos ni piernas.
    private func drawOrbex(_ ctx: inout GraphicsContext) {
        let D = CGFloat(f.d)
        guard D > 0.5 else { return }
        let tint = look.tint
        let cx = CGFloat(f.x), cy = CGFloat(f.y + f.hop)

        if f.limbs > 0.01 {
            var legs = ctx
            legs.opacity = f.limbs
            OrbexPainter.drawContactGlow(&legs, x: cx, floorY: CGFloat(f.y) + 0.7 * D, D: D, lift: CGFloat(-f.hop))
            for side in [-1.0, 1.0] {
                OrbexPainter.drawLeg(&legs, side: side, bodyCenter: CGPoint(x: cx, y: cy), footY: cy + 0.65 * D,
                                     D: D, tint: tint, crouch: 0, material: look.material)
            }
        }

        var body = ctx
        body.translateBy(x: cx, y: cy)
        body.rotate(by: .radians(f.tilt))
        body.translateBy(x: 0, y: 0.5 * D)
        body.scaleBy(x: CGFloat(f.sx), y: CGFloat(f.sy))
        body.translateBy(x: 0, y: -0.5 * D)
        OrbexPainter.drawBody(&body, D: D, tint: tint, material: look.material)
        if f.digest > 0.01 { drawDigestGlow(&body, D: D) }
        if f.portal * f.portalRing > 0.004 || (f.gulpFlash > 0 && f.gulpFlash < 1) { drawPortal(&body, D: D) }
        if f.bubbleAge >= 0 && f.bubbleAge < 0.95 { drawBubbles(&body, D: D) }

        // Con el portal abierto los ojos suben un poco para dejarle lugar.
        var face = CharacterFrame()
        face.eye = EyeShape.forExpression(expression)
        face.eyeOpenness = f.eyeOpen
        let open = min(1, f.portal / USC.PORTAL_OPEN) * min(1, f.portalRing)
        face.look = (f.lookX * 0.07, f.lookY * 0.05 - 0.05 * open)
        OrbexPainter.drawEyes(&body, f: face, D: D)

        if f.limbs > 0.01 {
            var arms = body
            arms.opacity = f.limbs
            OrbexPainter.drawArm(&arms, side: -1, raise: f.arms, D: D, tint: tint, material: look.material)
            OrbexPainter.drawArm(&arms, side: 1, raise: f.arms, D: D, tint: tint, material: look.material)
        }
    }

    /// Brillo interno del color del portal mientras "digiere" el archivo (coordenadas del cuerpo).
    private func drawDigestGlow(_ ctx: inout GraphicsContext, D: CGFloat) {
        let R = D / 2
        ctx.fill(Path(ellipseIn: CGRect(x: -R, y: -R, width: D, height: D)),
                 with: .radialGradient(Gradient(colors: [usColor(portalColor, 0.32 * f.digest), usColor(portalColor, 0)]),
                                       center: CGPoint(x: 0, y: 0.1 * D), startRadius: 0, endRadius: R))
    }

    /// Portal de vidrio con remolino en la panza (coordenadas del cuerpo, recortado a la esfera).
    private func drawPortal(_ ctx: inout GraphicsContext, D: CGFloat) {
        let R = D / 2
        let ring = CGFloat(max(0, min(1.1, f.portalRing)))
        let r = CGFloat(f.portal) * R * ring
        let c = CGPoint(x: 0, y: CGFloat(USC.PORTAL_Y) * D)
        let col = portalColor
        var p = ctx
        p.clip(to: Path(ellipseIn: CGRect(x: -R, y: -R, width: D, height: D)))

        if r > 0.4 {
            let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))

            // Halo alrededor de la boca (más fuerte cuanto más cerca viene el archivo)
            let hr = r * 1.7
            p.fill(Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: 2 * hr, height: 2 * hr)),
                   with: .radialGradient(Gradient(colors: [usColor(col, 0.35 * (0.4 + 0.6 * f.proximity)), usColor(col, 0)]),
                                         center: c, startRadius: r * 0.7, endRadius: hr))

            // Profundidad: centro hondo, borde claro
            p.fill(disc, with: .radialGradient(Gradient(stops: [
                .init(color: usColor(usMix(col, usDeep, 0.85), 0.95), location: 0),
                .init(color: usColor(usMix(col, usDeep, 0.55), 0.80), location: 0.55),
                .init(color: usColor(col, 0.60), location: 0.88),
                .init(color: usColor(usMix(col, usWhite, 0.6), 0.85), location: 1),
            ]), center: c, startRadius: 0, endRadius: r))

            // Remolino: tres brazos en espiral que giran hacia adentro
            var swirl = p
            swirl.clip(to: disc)
            let armColor = usColor(usMix(col, usWhite, 0.75), 0.55)
            let lineW = max(0.7, r * 0.16)
            for arm in 0..<3 {
                var path = Path()
                for s in 0...14 {
                    let k = Double(s) / 14
                    let ang = f.swirl + Double(arm) * 2 * .pi / 3 - k * 2.6
                    let rr = r * CGFloat(0.1 + 0.9 * k)
                    let pt = CGPoint(x: c.x + rr * CGFloat(cos(ang)), y: c.y + rr * CGFloat(sin(ang)))
                    if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                swirl.stroke(path, with: .color(armColor),
                             style: StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round))
            }

            // Luz del otro lado del portal
            let cr = r * 0.22
            p.fill(Path(ellipseIn: CGRect(x: c.x - cr, y: c.y - cr, width: 2 * cr, height: 2 * cr)),
                   with: .color(Color.white.opacity(0.35 + 0.3 * f.proximity)))

            // Borde de vidrio y brillo del lado de donde viene el archivo
            p.stroke(disc, with: .color(Color.white.opacity(0.7)), lineWidth: max(0.8, 0.024 * D))
            let facing = f.cursorAngle - f.tilt
            var rim = Path()
            rim.addArc(center: c, radius: r, startAngle: .radians(facing - 0.55),
                       endAngle: .radians(facing + 0.55), clockwise: false)
            p.stroke(rim, with: .color(Color.white.opacity(0.35 + 0.55 * f.proximity)),
                     style: StrokeStyle(lineWidth: max(1.1, 0.045 * D), lineCap: .round))
        }

        // Destello al tragar: un aro que se abre y se apaga
        if f.gulpFlash > 0 && f.gulpFlash < 1 {
            let k = 1 - f.gulpFlash
            let fr = CGFloat(USC.PORTAL_MAX) * R * CGFloat(0.6 + 1.2 * k)
            p.stroke(Path(ellipseIn: CGRect(x: c.x - fr, y: c.y - fr, width: 2 * fr, height: 2 * fr)),
                     with: .color(Color.white.opacity(0.8 * f.gulpFlash)), lineWidth: max(1, 0.03 * D))
        }
    }

    /// Burbujitas de vidrio que suben dentro de la esfera y revientan arriba (coordenadas del cuerpo).
    private func drawBubbles(_ ctx: inout GraphicsContext, D: CGFloat) {
        let R = D / 2
        var b = ctx
        b.clip(to: Path(ellipseIn: CGRect(x: -R, y: -R, width: D, height: D)))
        let count = f.calm ? 3 : usBubbleX.count
        for i in 0..<count {
            let t0 = Double(i) * (f.calm ? 0.12 : 0.055)
            let life = (f.calm ? 0.7 : 0.46) + Double(i % 3) * 0.05
            let k = (f.bubbleAge - t0) / life
            guard k > 0 && k < 1 else { continue }
            let wob = f.calm ? 0 : sin(k * 9 + Double(i)) * 0.03
            let x = CGFloat(usBubbleX[i] * 0.2 + wob) * D
            let y = CGFloat(usLerp(USC.PORTAL_Y + 0.04, -0.34, usEOut(k))) * D
            let pop = k > 0.85 ? (k - 0.85) / 0.15 : 0
            let r = D * CGFloat((0.028 + 0.018 * Double(i % 3)) * (1 + 0.25 * k) * (1 + 0.5 * pop))
            let a = k > 0.85 ? 1 - pop : min(1, k * 6)
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            b.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.12 * a)))
            b.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.7 * a)), lineWidth: max(0.5, 0.012 * D))
            let hs = r * 0.35
            b.fill(Path(ellipseIn: CGRect(x: x - r * 0.45, y: y - r * 0.55, width: hs, height: hs)),
                   with: .color(Color.white.opacity(0.85 * a)))
        }
    }

    /// Chispitas al llegar a "choose".
    private func drawArrivalSparkles(_ ctx: inout GraphicsContext) {
        let k = f.sparkleBurst / 0.7
        guard k > 0 && k < 1 else { return }
        let n = f.calm ? 4 : 7
        let D = CGFloat(f.d)
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi - .pi / 2 + 0.3
            let dist = D * CGFloat(0.55 + 0.45 * usEOut(k))
            var s = ctx
            s.opacity = sin(.pi * k)
            s.translateBy(x: CGFloat(f.x) + CGFloat(cos(a)) * dist, y: CGFloat(f.y) + CGFloat(sin(a)) * dist * 0.85)
            if !f.calm { s.rotate(by: .radians(k)) }
            s.fill(OrbexPainter.sparkle(size: D * 0.16), with: .color(Color.white))
        }
    }

    // MARK: Archivo

    private func drawFile(_ ctx: inout GraphicsContext) {
        let sx0 = f.cursorX, sy0 = f.cursorY + 14
        if f.suck <= 0 {
            // Mientras se arrastra: sigue al cursor y, con el portal cerca, tiembla hacia él.
            let pull = f.proximity * min(1, f.portalRing)
            let dx = f.portalX - sx0, dy = f.portalY - sy0
            let len = max(1, hypot(dx, dy))
            var c = ctx
            c.opacity = 0.92
            c.translateBy(x: CGFloat(sx0 + dx / len * 3 * pull), y: CGFloat(sy0 + dy / len * 3 * pull))
            if !f.calm { c.rotate(by: .radians(sin(f.t * 18) * 0.05 * pull)) }
            drawDoc(&c, scale: 1)
            if pull > 0.2 && !f.calm { drawSuctionMotes(&ctx, fromX: sx0, fromY: sy0, pull: pull) }
            return
        }

        // Tragado en espiral: gira alrededor del portal cerrando el radio y achicándose,
        // con copias tenues detrás marcando el camino.
        let px = f.portalX, py = f.portalY
        let r0 = hypot(sx0 - px, sy0 - py)
        let a0 = atan2(sy0 - py, sx0 - px)
        let turns = f.calm ? 0.25 : 1.35
        let alpha = 1 - usSeg(f.suck, 0.8, 1)
        let ghosts = f.calm ? 0 : 3
        for j in stride(from: ghosts, through: 0, by: -1) {
            let k = max(0, min(1, f.suck - Double(j) * 0.05))
            let ang = a0 + turns * 2 * .pi * pow(k, 1.6)
            let rad = r0 * pow(1 - k, 1.25)
            let scale = 0.12 + 0.88 * pow(1 - k, 1.1)
            var c = ctx
            c.opacity = j == 0 ? alpha : alpha * 0.22 / Double(j)
            c.translateBy(x: CGFloat(px + cos(ang) * rad), y: CGFloat(py + sin(ang) * rad))
            c.rotate(by: .radians((ang - a0) * 0.8))
            drawDoc(&c, scale: scale)
        }
    }

    /// Motitas de vidrio que van del archivo al portal cuando está cerca.
    private func drawSuctionMotes(_ ctx: inout GraphicsContext, fromX: Double, fromY: Double, pull: Double) {
        let dx = f.portalX - fromX, dy = f.portalY - fromY
        let len = max(1, hypot(dx, dy))
        let nx = -dy / len, ny = dx / len
        for i in 0..<4 {
            let k = (wall * 1.4 + Double(i) / 4).truncatingRemainder(dividingBy: 1)
            let e = usEIn(k)
            let side: Double = i % 2 == 0 ? 1 : -1
            let bow = sin(.pi * k) * 12 * side
            let x = fromX + dx * e + nx * bow
            let y = fromY + dy * e + ny * bow
            let r = 1.8 * (1 - 0.5 * k)
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                     with: .color(Color.white.opacity(0.75 * sin(.pi * k) * pull)))
        }
    }

    /// El archivo centrado en el origen: ícono real si ya se conoce; si no, una hoja genérica.
    private func drawDoc(_ ctx: inout GraphicsContext, scale s: Double) {
        let sc = CGFloat(s)
        var c = ctx
        c.addFilter(.shadow(color: Color.black.opacity(0.45), radius: 8 * sc, x: 0, y: 3 * sc))
        if let icon {
            let side = 42 * sc
            c.draw(Image(nsImage: icon), in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
            return
        }
        let w = 34 * sc, h = 42 * sc
        let x = -w / 2, y = -h / 2
        let fold = 8 * sc, e = 2 * sc
        var sheet = Path()
        sheet.move(to: CGPoint(x: x + e, y: y))
        sheet.addLine(to: CGPoint(x: x + w - fold, y: y))
        sheet.addLine(to: CGPoint(x: x + w, y: y + fold))
        sheet.addLine(to: CGPoint(x: x + w, y: y + h - e))
        sheet.addQuadCurve(to: CGPoint(x: x + w - e, y: y + h), control: CGPoint(x: x + w, y: y + h))
        sheet.addLine(to: CGPoint(x: x + e, y: y + h))
        sheet.addQuadCurve(to: CGPoint(x: x, y: y + h - e), control: CGPoint(x: x, y: y + h))
        sheet.addLine(to: CGPoint(x: x, y: y + e))
        sheet.addQuadCurve(to: CGPoint(x: x + e, y: y), control: CGPoint(x: x, y: y))
        sheet.closeSubpath()
        c.fill(sheet, with: .color(Color(red: 0.957, green: 0.957, blue: 0.965)))

        var corner = Path()
        corner.move(to: CGPoint(x: x + w - fold, y: y))
        corner.addLine(to: CGPoint(x: x + w - fold, y: y + fold))
        corner.addLine(to: CGPoint(x: x + w, y: y + fold))
        ctx.fill(corner, with: .color(Color(red: 0.835, green: 0.839, blue: 0.859)))
        ctx.fill(roundedRect(CGRect(x: x + w * 0.18, y: y + h * 0.58, width: w * 0.64, height: h * 0.16), r: 2 * s),
                 with: .color(Color(red: 0.231, green: 0.510, blue: 0.961)))
    }
}

// MARK: - Rectángulo redondeado (lo usan también otras partes del lienzo)

func roundedRect(_ rect: CGRect, r rr: Double) -> Path {
    let r = max(0, min(rr, Double(rect.width) / 2, Double(rect.height) / 2))
    var p = Path()
    p.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
    return p
}

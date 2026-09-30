// Basado en Coucou (https://github.com/louis-cfm/coucou) © 2026 Louis Raillé — licencia MIT.
// Modificado para ORBEX (solo el código; ningún asset de Coucou). Ver THIRD_PARTY_NOTICES.md.

import SwiftUI

/// Top-level SwiftUI view rendered inside the 720×320 transparent panel.
/// The island is drawn at the top-center; everything else is transparent and click-through.
/// Note: drag-drop is handled at the AppKit level in IslandWindowController (FileDropNSView),
/// not in SwiftUI, to avoid interfering with SwiftUI hit-testing.
struct IslandRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            IslandContainer(state: state)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Island container
//
// Una sola fuente de verdad para la forma: el tamaño y las esquinas salen del estado (`mode`, `view`,
// largo del chat y medida en vivo del notch) vía `IslandGeometry`, y un solo resorte los anima
// (`.animation(_:value:)` sobre la geometría). No hay `@State` de tamaño que pueda quedar a mitad de
// camino: si el modo cambia rápido de ida y vuelta, el resorte se redirige y siempre termina en el
// tamaño que corresponde al estado final.

/// Tamaño y esquinas de la isla para el estado actual.
struct IslandGeometry: Equatable {
    var width: CGFloat
    var height: CGFloat
    var corner: CGFloat

    @MainActor init(state: AppState) {
        let (w, h) = islandSize(mode: state.mode, view: state.view,
                                nw: state.notchWidth, nh: state.notchHeight,
                                chatMessages: state.chatMessageCount)
        width = w
        height = h
        corner = state.mode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
    }

    var shape: IslandShape {
        IslandShape(width: width, height: height, cornerRadius: corner, topRadius: 0)
    }
}

/// Qué dibuja el interior de la isla (cada caso entra y sale con su fundido).
private enum IslandContentBranch: Equatable {
    case empty, greeting, upload, views
}

struct IslandContainer: View {
    @ObservedObject var state: AppState

    /// Abrir, cambiar de vista o crecer el chat: resorte con un poquito de rebote.
    static let openSpring = Animation.spring(response: 0.5, dampingFraction: 0.72)
    /// Achicar (a compacta u oculta) o asomarse: resorte sin rebote, así la forma nunca queda más chica
    /// que el notch ni "late" al llegar.
    static let settleSpring = Animation.spring(response: 0.34, dampingFraction: 1)

    /// El contenido entra con un fundido apenas demorado, cuando la isla ya va abriendo (y siempre
    /// recortado por la forma: nada queda afuera ni salta durante el morph); se va rápido al cerrar.
    private static func contentTransition(removal: Double = 0.12) -> AnyTransition {
        .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.14)),
                    removal: .opacity.animation(.easeIn(duration: removal)))
    }

    var body: some View {
        let geo = IslandGeometry(state: state)

        // Canvas active during drag-over (.upload), post-drop animation (.uploading),
        // AND choose overlay (.choose) — canvas handles the full sequence through user action.
        // Engine deactivates when user clicks a canvas choose button or navigates away.
        let uploadActive = state.mode == .expanded
            && UploadSequenceEngine.shared.isActive
            && (state.view == .upload || state.view == .uploading || state.view == .choose)
        let greetingActive = state.mode == .expanded && state.view == .greeting
        let branch: IslandContentBranch = state.mode != .expanded ? .empty
            : greetingActive ? .greeting
            : uploadActive ? .upload
            : .views

        let calm = AppModel.shared.effectiveReduceMotion
        let morph: Animation = calm ? .easeInOut(duration: 0.2)
            : (state.mode == .expanded ? Self.openSpring : Self.settleSpring)

        return ZStack(alignment: .topLeading) {
            // Forma negra
            geo.shape.fill(Color.black)

            // Contenido: siempre recortado por la MISMA forma animada. El contenedor existe en todos los
            // modos (así su recorte se interpola) y el contenido entra/sale adentro con un fundido.
            ZStack(alignment: .topLeading) {
                switch branch {
                case .greeting:
                    // Lienzo del saludo: 640 de ancho, x = 320 en el centro de la isla.
                    GreetingCanvasView(state: state)
                        .frame(width: IslandConst.expandedWidth, height: geo.height)
                        .transition(Self.contentTransition(removal: 0.3))
                case .upload:
                    ZStack(alignment: .topLeading) {
                        UploadCanvasView(state: state)
                            .frame(width: geo.width, height: geo.height)
                        // Header overlaid: canvas CARD_Y=42 aligns exactly with header bottom,
                        // matching normal view proportions (8pt top + 34pt header + card + 10pt bottom).
                        IslandHeader(state: state)
                            .frame(width: geo.width, height: 34)
                            .offset(y: 8)
                    }
                    .transition(Self.contentTransition())
                case .views:
                    IslandContentView(state: state)
                        .frame(width: geo.width, height: geo.height)
                        .transition(Self.contentTransition())
                case .empty:
                    EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.22), value: branch)
            .frame(width: geo.width, height: geo.height, alignment: .topLeading)
            .clipShape(geo.shape)

            // Single BotPlacement — always alive in the view tree so spring animations
            // fire from the current position (e.g. choose at 60,101) when canvas deactivates.
            // Hidden during upload canvas or greeting (both draw their own ORBEX).
            BotPlacement(state: state, islandW: geo.width, islandH: geo.height)
                .opacity(uploadActive || greetingActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)

            CountdownBar(state: state, islandW: geo.width)
            // Isla compacta: solo ORBEX a la izquierda; a la derecha del notch no se dibuja nada.
        }
        .frame(width: geo.width, height: geo.height, alignment: .topLeading)
        // Un solo resorte para la forma (tamaño + esquinas), venga el cambio de donde venga.
        .animation(morph, value: geo)
        .onChange(of: state.view) { _, newView in
            // Salir del flujo de subir archivo apaga su motor.
            guard state.mode == .expanded else { return }
            let uploadViews: Set<IslandView> = [.upload, .uploading, .choose]
            if UploadSequenceEngine.shared.isActive && !uploadViews.contains(newView) {
                UploadSequenceEngine.shared.deactivate()
            }
        }
    }
}

// MARK: - Island shape
//
// topRadius > 0  → convex rounded top corners (expanded mode)
// topRadius < 0  → concave ear cutouts, |topRadius| = ear radius (compact/notch mode)
// topRadius = 0  → sharp top corners, flush with the top of the screen (what the island uses now)

struct IslandShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat   // bottom corners
    var topRadius: CGFloat      // see above

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>, CGFloat> {
        get { .init(.init(.init(width, height), cornerRadius), topRadius) }
        set {
            width        = newValue.first.first.first
            height       = newValue.first.first.second
            cornerRadius = newValue.first.second
            topRadius    = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Radios acotados al tamaño: con un notch bajo o a mitad del morph los arcos nunca se cruzan.
        let cr = max(0, min(cornerRadius, width / 2, height / 2))
        var p  = Path()

        if topRadius >= 0 {
            // ── Convex rounded top corners (expanded) ──────────────────────────
            let tr = min(topRadius, min(width / 2, height / 2))
            p.move(to: CGPoint(x: tr, y: 0))
            p.addLine(to: CGPoint(x: width - tr, y: 0))
            // Top-right convex corner
            p.addArc(center: CGPoint(x: width - tr, y: tr), radius: tr,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge
            p.addLine(to: CGPoint(x: 0, y: tr))
            // Top-left convex corner
            p.addArc(center: CGPoint(x: tr, y: tr), radius: tr,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // ── Concave ear cutouts (compact / notch) ─────────────────────────
            let er = min(-topRadius, width / 2, height)   // positive ear radius
            p.move(to: CGPoint(x: 0, y: 0))
            // Top-left ear
            p.addArc(center: CGPoint(x: 0, y: er), radius: er,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Top edge
            p.addLine(to: CGPoint(x: width - er, y: er))
            // Top-right ear
            p.addArc(center: CGPoint(x: width, y: er), radius: er,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge back to top-left corner
            p.addLine(to: CGPoint(x: 0, y: 0))
        }

        p.closeSubpath()
        return p
    }
}

// MARK: - Bot placement helper

struct BotPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let (cx, cy, diameter, opacity) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: state.uploadProgress)
        let canvasSize = diameter / 0.6
        let overhang: CGFloat = 40
        let isUploading = state.view == .uploading

        Group {
            // No glow in uploading mode — the tiny dot doesn't need it
            if state.mode == .expanded && !isUploading {
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: botGlowColor(state.effectiveState), location: 0),
                            .init(color: .clear, location: 0.62)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 1.1
                    ))
                    .frame(width: diameter * 2.2, height: diameter * 2.2)
                    .blur(radius: 6)
                    .opacity(botGlowOpacity(state.effectiveState))
                    .position(x: cx, y: cy)
                    .animation(.easeInOut(duration: 0.4), value: state.effectiveState)
            }

            // Uploading: no particle overhang (no hearts during upload), positioned directly at cy.
            // BotEngine cy = H/2 + 0 + oy*R + R*0.06 ≈ H/2 (body centered in canvas).
            // With .position(x:y:) placing the frame center at (uploadCx, cy), bot is at cy ✓.
            //
            // Normal: extra 40pt canvas at top for heart particles; position offset up by 20pt;
            // BotEngine compensates with cy = H/2 + particleOverhang/2 + oy*R + R*0.06.
            if isUploading {
                TimelineView(.animation) { tl in
                    let elapsed: Double = {
                        guard let start = state.uploadStartTime else { return 0 }
                        return tl.date.timeIntervalSince(start)
                    }()
                    let t = min(1.0, max(0, elapsed / state.uploadDuration))
                    // cx = 36 + 526*t: bot center at fill right edge (bar left=36, width=526)
                    let uploadCx = 36 + CGFloat(t * (2 - t)) * 526
                    BotCanvasView(state: state, particleOverhang: 0)
                        .frame(width: canvasSize, height: canvasSize)
                        .opacity(state.isDraggingBot ? 0 : opacity)
                        .position(x: uploadCx, y: cy)
                }
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            } else {
                BotCanvasView(state: state, particleOverhang: overhang)
                    .frame(width: canvasSize, height: canvasSize + overhang)
                    .opacity(state.isDraggingBot ? 0 : opacity)
                    .position(x: cx, y: cy - overhang / 2)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cx)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cy)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: canvasSize)
                    .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            }
        }
        // Branch switch (uploading ↔ normal) animates with a fast spring: uploading dot
        // scales out at bar-end while normal bot scales in at choose position.
        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: isUploading)
        // Slap, drag, and hover are handled by the AppKit NSEvent monitor in
        // IslandWindowController — not SwiftUI gestures — so this is safe.
        .allowsHitTesting(false)
    }

    private func botGlowColor(_ s: BotState) -> Color {
        switch s {
        case .working:   return Color(hex: "#3B9EFF")
        case .thinking:  return Color(hex: "#A78BFA")
        case .searching: return Color(hex: "#6366F1")
        case .approval:  return Color(hex: "#F5A524")
        case .error:     return Color(hex: "#F4505E")
        case .finished:  return Color(hex: "#34D399")
        case .ratelimit: return Color(hex: "#F59E0B")
        case .listening: return Color(hex: "#E040FB")
        default:         return Color.white
        }
    }

    private func botGlowOpacity(_ s: BotState) -> Double {
        switch s {
        case .idle, .sleeping: return 0.15
        case .dizzy:           return 0.0
        default:               return 0.65
        }
    }
}

func botPosition(mode: IslandMode, view: IslandView, islandW: CGFloat, islandH: CGFloat, uploadProgress: Double) -> (CGFloat, CGFloat, CGFloat, Double) {
    switch mode {
    case .hidden:   return (46, 16, 6, 0)
    case .compact:  return (40, 16, 20, 1)
    case .expanded:
        let layout = IslandConst.viewLayouts[view]!
        let diameter = layout.botDiameter
        // Uploading: ORBEX dot rides the leading edge of the progress fill.
        // Bar in island coords: left=36, width=526. cx = 36 + progress*526 (dot center at fill right edge).
        // cy comes from ViewLayout.botY (bar center in island coords).
        if view == .uploading {
            let cx = 36 + CGFloat(uploadProgress) * 526
            return (cx, layout.botY ?? 103, diameter, 1)
        }
        let cx = layout.botX
        let cy: CGFloat
        if let fixedY = layout.botY {
            cy = fixedY
        } else {
            // Center of the fixed 84pt card (VStack top=8, header=34 → content starts at y=42)
            let headerBottom: CGFloat = 42
            let cardH: CGFloat = 84
            cy = headerBottom + (islandH - headerBottom - cardH) / 2 + cardH / 2
        }
        return (cx, cy, diameter, 1)
    }
}

// MARK: - Countdown bar

struct CountdownBar: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    @State private var barWidth: CGFloat = 0
    @State private var timer: Timer? = nil

    var body: some View {
        GeometryReader { _ in
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: barWidth, height: 2)
                .cornerRadius(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { updateBar() }
        }
    }

    private func updateBar() {
        guard state.mode == .expanded && !state.isPinned else {
            barWidth = 0
            return
        }
        let autoClose = state.autoCloseInterval
        let window = min(10.0, autoClose * 0.6)
        let elapsed = Date.now.timeIntervalSince(state.lastActivity)
        let remaining = autoClose - elapsed
        if remaining < window {
            barWidth = max(0, CGFloat(remaining / window) * 160)
        } else {
            barWidth = 0
        }
    }
}

// MARK: - Island content (header + views, only in expanded mode)

struct IslandContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            IslandHeader(state: state)
                .frame(height: 34)
                .opacity(state.view == .confused ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: state.view == .confused)

            ZStack {
                ForEach(IslandView.allCases, id: \.self) { v in
                    let active = state.view == v
                    // Views that fill available height instead of the fixed 98pt content frame:
                    // chat (prompt) is always flexible; utilities only when active so they don't
                    // push the ZStack taller when inactive.
                    let isUtility = Self.utilityViews.contains(v)
                    let isTall = v == .prompt || (isUtility && active)
                    let anim: Animation = active
                        ? .spring(response: 0.4, dampingFraction: 0.8).delay(0.16)
                        : .easeIn(duration: 0.16)
                    content(for: v, active: active)
                        .frame(maxWidth: .infinity)
                        .frame(height: isTall ? nil : 98)
                        .frame(maxHeight: isTall ? .infinity : nil)
                        .opacity(active ? 1 : 0)
                        .scaleEffect(active ? 1 : 0.97)
                        .allowsHitTesting(active)
                        .animation(anim, value: state.view)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .foregroundColor(Color(hex: "#F5F6F8"))
    }

    /// Vistas de utilidades de ORBEX (timers, notas, música): se dibujan acá y solo mientras están
    /// activas, así no refrescan (ni gastan CPU) escondidas detrás de las demás.
    static let utilityViews: Set<IslandView> = [.timers, .notes, .music]

    @ViewBuilder
    private func content(for v: IslandView, active: Bool) -> some View {
        switch v {
        case .timers:
            if active { TimersIslandView(state: state) } else { Color.clear }
        case .notes:
            if active { NotesIslandView(state: state) } else { Color.clear }
        case .music:
            if active { MusicIslandView(state: state) } else { Color.clear }
        default:
            IslandViewContent(view: v, state: state)
        }
    }
}

// MARK: - Island header (tabs + icons)
//
// La franja del notch (su ancho medido en vivo + un margen a cada lado) queda SIEMPRE vacía: ahí están
// la cámara y el borde del notch, así que cualquier texto o ícono se vería cortado. Las pestañas van a
// la izquierda y los íconos a la derecha, cada grupo dentro de su costado; si el notch es ancho, las
// pestañas se angostan antes de meterse debajo.

struct IslandHeader: View {
    @ObservedObject var state: AppState

    /// Margen libre a cada lado del notch.
    static let notchMargin: CGFloat = 12

    private static let tabCount: CGFloat = 6
    private static let tabSpacing: CGFloat = 5
    private static let leading: CGFloat = 14
    private static let trailing: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let side = max(0, (geo.size.width - state.notchWidth) / 2 - Self.notchMargin)
            let fit = (side - Self.leading - Self.tabSpacing * (Self.tabCount - 1)) / Self.tabCount
            let tabWidth = min(30, max(20, fit))
            HStack(spacing: 0) {
                tabs(width: tabWidth)
                    .padding(.leading, Self.leading)
                    .frame(width: side, alignment: .leading)
                // Franja del notch: vacía a propósito.
                Spacer(minLength: 0)
                icons
                    .padding(.trailing, Self.trailing)
                    .frame(width: side, alignment: .trailing)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // Left: tab capsules
    private func tabs(width: CGFloat) -> some View {
        HStack(spacing: Self.tabSpacing) {
            TabButton(icon: "house.fill", view: .overview, state: state, width: width)
            TabButton(icon: "bubble.left.fill", view: .prompt, state: state, width: width, preAction: {
                #if !APPSTORE
                if state.promptContext == nil {
                    state.promptContext = WindowContextCapture.captureActive(from: state.lastExternalApp)
                }
                #endif
            })
            TabButton(icon: "plus", view: .upload, state: state, width: width)
            TabButton(icon: "timer", view: .timers, state: state, width: width)
            TabButton(icon: "note.text", view: .notes, state: state, width: width)
            TabButton(icon: "music.note", view: .music, state: state, width: width)
        }
        .fixedSize()
    }

    // Right: action icons
    private var icons: some View {
        HStack(spacing: 14) {
            Button(action: { OrbexBus.perform("clock") }) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            .help("Pasar a reloj")

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    state.view = .settings
                }
            }) {
                Image(systemName: state.view == .settings ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(state.view == .settings ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            .help("Ajustes rápidos")

            Button(action: { state.soundEnabled.toggle() }) {
                Image(systemName: state.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            .help(state.soundEnabled ? "Silenciar" : "Activar el sonido")
        }
        .fixedSize()
    }
}

struct TabButton: View {
    let icon: String
    let view: IslandView
    @ObservedObject var state: AppState
    var width: CGFloat = 30
    var preAction: (() -> Void)? = nil
    @State private var isHovered = false

    private var isOn: Bool {
        if view == .overview { return state.view == .overview || state.view == .empty }
        return state.view == view
    }

    var body: some View {
        Button(action: {
            preAction?()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.view = view
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isOn ? Color(hex: "#F5F6F8") : (isHovered ? Color(hex: "#B0B5BE") : Color(hex: "#8E939C")))
                .frame(width: width, height: 22)
                .background(
                    isOn ? Color(hex: "#1D1F23") :
                    isHovered ? Color.white.opacity(0.07) : Color.clear
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8)  & 0xFF) / 255
        let b = Double( val        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

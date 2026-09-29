import AppKit
import SwiftUI

/// Piezas compartidas por las vistas de utilidades de la isla (timers, notas, música).
enum IslandPalette {
    static let text = Color(hex: "#F5F6F8")
    static let secondary = Color(hex: "#8E939C")
    static let tertiary = Color(hex: "#6B7079")
    static let chip = Color.white.opacity(0.07)
    static let chipHover = Color.white.opacity(0.12)
    /// Lugar que se deja a la izquierda de la tarjeta para el personaje (botX 56, diámetro 46).
    static let botGutter: CGFloat = 90
}

/// Botón-cápsula chiquito de la isla ("+5 min", "Vuelta", …).
struct IslandChipButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = IslandPalette.text
    var height: CGFloat = 24
    var expand = false
    var help: String? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                }
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundColor(tint)
            .padding(.horizontal, 9)
            .frame(maxWidth: expand ? .infinity : nil)
            .frame(height: height)
            .background(Capsule().fill(hovered ? IslandPalette.chipHover : IslandPalette.chip))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help ?? title)
    }
}

/// Botón redondo con ícono (pausa, sumar, cerrar…).
struct IslandIconButton: View {
    let symbol: String
    var size: CGFloat = 20
    var font: CGFloat = 9.5
    var tint: Color = IslandPalette.secondary
    var help: String = ""
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: font, weight: .bold))
                .foregroundColor(hovered ? IslandPalette.text : tint)
                .frame(width: size, height: size)
                .background(Circle().fill(hovered ? IslandPalette.chipHover : IslandPalette.chip))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

/// El panel de la isla no se vuelve "key" solo (es no-activante). Un campo de texto lo necesita:
/// esto lo hace key cuando la vista aparece en la ventana.
struct IslandKeyWindowGrabber: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { GrabberView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class GrabberView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if window.canBecomeKey && !window.isKeyWindow { window.makeKey() }
                }
            }
        }
    }
}

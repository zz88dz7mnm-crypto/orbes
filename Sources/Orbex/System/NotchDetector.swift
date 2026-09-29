import AppKit
import OrbexCore

/// Mide el notch en vivo con `NSScreen` (informe §3.2) y elige la pantalla donde vive la isla.
@MainActor
enum NotchDetector {

    struct Placement {
        let screen: NSScreen
        let notch: NotchMetrics
        /// Centro horizontal del notch en coordenadas de pantalla.
        let notchCenterX: CGFloat
        /// Borde superior de la pantalla.
        let topY: CGFloat
    }

    static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0 && screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
    }

    static func chooseScreen(_ choice: ScreenChoice) -> NSScreen? {
        let screens = NSScreen.screens
        switch choice {
        case .automatic:
            return screens.first(where: hasNotch) ?? NSScreen.main ?? screens.first
        case .main:
            return NSScreen.main ?? screens.first
        case .display(let id):
            return screens.first(where: { displayID(of: $0) == id }) ?? screens.first(where: hasNotch) ?? NSScreen.main
        }
    }

    static func placement(for choice: ScreenChoice, adjustW: Double, adjustH: Double) -> Placement? {
        guard let screen = chooseScreen(choice) else { return nil }
        let frame = screen.frame
        let measured = NotchMetrics.measure(
            screenWidth: Double(frame.width),
            safeAreaTop: Double(screen.safeAreaInsets.top),
            auxLeftWidth: screen.auxiliaryTopLeftArea.map { Double($0.width) },
            auxRightWidth: screen.auxiliaryTopRightArea.map { Double($0.width) })

        let notch: NotchMetrics
        let centerX: CGFloat
        if let m = measured {
            notch = m.adjusted(dw: adjustW, dh: adjustH)
            // El notch empieza donde termina el área auxiliar izquierda.
            let leftW = screen.auxiliaryTopLeftArea?.width ?? (frame.width - CGFloat(m.width)) / 2
            centerX = frame.minX + leftW + CGFloat(m.width) / 2
        } else {
            // Sin notch (monitor externo o modo "debajo del notch"): se simula centrado arriba.
            let menuBar = max(24, frame.maxY - screen.visibleFrame.maxY)
            notch = NotchMetrics.simulated(screenWidth: Double(frame.width), menuBarHeight: Double(menuBar))
                .adjusted(dw: adjustW, dh: adjustH)
            centerX = frame.midX
        }
        return Placement(screen: screen, notch: notch, notchCenterX: centerX, topY: frame.maxY)
    }
}

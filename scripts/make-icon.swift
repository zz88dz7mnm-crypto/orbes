// make-icon.swift — dibuja el ícono de ORBEX y lo guarda como .iconset (todos los tamaños).
//
// Uso:
//     swift scripts/make-icon.swift <salida.iconset>
//     iconutil -c icns <salida.iconset> -o AppIcon.icns
//
// Lo llama scripts/build-app.sh. Solo usa Foundation + CoreGraphics + ImageIO
// (sin AppKit), así corre como script suelto con las Command Line Tools.
//
// Diseño (todo en un lienzo de 1024 × 1024 que se escala a cada tamaño):
// - Cuadrado redondeado con la grilla de íconos de macOS: 824 px centrado
//   (margen ≈ 10 %), radio ≈ 22,5 %, degradado azul marino profundo → pizarra.
// - ORBEX: esfera de vidrio translúcida (degradado radial), borde de luz,
//   reflejo en media luna arriba a la izquierda, punto especular, luz rebotada
//   abajo a la derecha, sombra interna abajo, y dos ojos ovalados negros
//   un poco por encima del centro. Resplandor suave debajo.
// Proporciones del personaje: design/character/README.md.

import CoreGraphics
import Foundation
import ImageIO

enum IconArt {
    /// Tamaño del lienzo de diseño (se escala a cada tamaño de salida).
    static let canvas: CGFloat = 1024

    static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func gradient(_ space: CGColorSpace, _ stops: [(CGFloat, CGColor)]) -> CGGradient? {
        let colors = stops.map { $0.1 } as CFArray
        let locations: [CGFloat] = stops.map { $0.0 }
        return CGGradient(colorsSpace: space, colors: colors, locations: locations)
    }

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// Recorta a la zona que está dentro de `outer` pero fuera de `cutter` (media luna).
    static func clipCrescent(_ ctx: CGContext, outer: CGRect, cutter: CGRect) {
        ctx.addEllipse(in: outer)
        ctx.clip()
        ctx.addRect(CGRect(x: -canvas, y: -canvas, width: canvas * 3, height: canvas * 3))
        ctx.addEllipse(in: cutter)
        ctx.clip(using: .evenOdd)
    }

    /// Dibuja el ícono en un bitmap de `pixels` × `pixels`.
    static func render(pixels: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: pixels,
                  height: pixels,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        ctx.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))

        let scale = CGFloat(pixels) / canvas
        ctx.scaleBy(x: scale, y: scale)
        draw(in: ctx, space: space, scale: scale, small: pixels <= 32)
        return ctx.makeImage()
    }

    // Coordenadas de CoreGraphics: origen abajo a la izquierda, y hacia arriba.
    static func draw(in ctx: CGContext, space: CGColorSpace, scale: CGFloat, small: Bool) {
        // ---------------------------------------------------------------
        // Placa: cuadrado redondeado (grilla de macOS)
        // ---------------------------------------------------------------
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let corner: CGFloat = tile.width * 0.225
        let tilePath = CGPath(roundedRect: tile, cornerWidth: corner, cornerHeight: corner, transform: nil)

        // Sombra de la placa. (El desplazamiento y el desenfoque de las sombras
        // no se escalan con la transformación: van en píxeles reales.)
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -10 * scale),
            blur: 24 * scale,
            color: rgba(0, 0, 0, 0.45)
        )
        ctx.addPath(tilePath)
        ctx.setFillColor(rgba(0.07, 0.10, 0.20))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(tilePath)
        ctx.clip()

        // Fondo: azul marino profundo (arriba) → pizarra (abajo).
        if let bg = gradient(space, [
            (0.00, rgba(0.055, 0.090, 0.200)),
            (0.55, rgba(0.100, 0.145, 0.265)),
            (1.00, rgba(0.225, 0.280, 0.355)),
        ]) {
            ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
        }

        // Brillo suave arriba de la placa.
        if let sheen = gradient(space, [
            (0.00, rgba(1, 1, 1, 0.10)),
            (1.00, rgba(1, 1, 1, 0.00)),
        ]) {
            ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.maxY - 300), options: [])
        }

        // ---------------------------------------------------------------
        // Esfera
        // ---------------------------------------------------------------
        let center = CGPoint(x: 512, y: 548)
        let radius: CGFloat = 248
        let diameter = radius * 2
        let sphere = circle(center, radius)

        // Halo azulado detrás de la esfera.
        if let halo = gradient(space, [
            (0.00, rgba(0.45, 0.70, 1.00, 0.26)),
            (1.00, rgba(0.45, 0.70, 1.00, 0.00)),
        ]) {
            ctx.drawRadialGradient(halo, startCenter: center, startRadius: radius * 0.85,
                                   endCenter: center, endRadius: radius * 1.45, options: [])
        }

        // Resplandor suave debajo (elipse achatada).
        if let glow = gradient(space, [
            (0.00, rgba(0.60, 0.82, 1.00, 0.55)),
            (0.45, rgba(0.50, 0.74, 1.00, 0.22)),
            (1.00, rgba(0.45, 0.70, 1.00, 0.00)),
        ]) {
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y - radius - 26)
            ctx.scaleBy(x: 1, y: 0.18)
            ctx.drawRadialGradient(glow, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: diameter * 0.50, options: [])
            ctx.restoreGState()
        }

        // Cuerpo de vidrio (todo lo que sigue va recortado al círculo).
        ctx.saveGState()
        ctx.addEllipse(in: sphere)
        ctx.clip()

        // Relleno: centro celeste muy transparente → borde gris azulado más denso (Fresnel).
        if let body = gradient(space, [
            (0.00, rgba(0.93, 0.97, 1.00, 0.34)),
            (0.50, rgba(0.72, 0.82, 0.94, 0.20)),
            (0.82, rgba(0.58, 0.70, 0.86, 0.32)),
            (1.00, rgba(0.80, 0.89, 0.99, 0.62)),
        ]) {
            ctx.drawRadialGradient(body,
                                   startCenter: CGPoint(x: center.x - radius * 0.28, y: center.y + radius * 0.32),
                                   startRadius: 0,
                                   endCenter: center, endRadius: radius,
                                   options: [.drawsAfterEndLocation])
        }

        // Sombra interna abajo (refracción simulada).
        if let inner = gradient(space, [
            (0.00, rgba(0.02, 0.05, 0.14, 0.45)),
            (1.00, rgba(0.02, 0.05, 0.14, 0.00)),
        ]) {
            ctx.drawLinearGradient(inner, start: CGPoint(x: center.x, y: center.y - radius),
                                   end: CGPoint(x: center.x, y: center.y - radius * 0.15), options: [])
        }

        // Luz rebotada abajo a la derecha (media luna tenue).
        if !small, let bounce = gradient(space, [
            (0.00, rgba(0.85, 0.93, 1.00, 0.30)),
            (1.00, rgba(0.85, 0.93, 1.00, 0.00)),
        ]) {
            ctx.saveGState()
            clipCrescent(ctx,
                         outer: circle(center, radius * 0.94),
                         cutter: circle(CGPoint(x: center.x - radius * 0.10, y: center.y + radius * 0.10), radius * 0.96))
            ctx.drawLinearGradient(bounce,
                                   start: CGPoint(x: center.x + radius * 0.66, y: center.y - radius * 0.66),
                                   end: CGPoint(x: center.x + radius * 0.20, y: center.y - radius * 0.20),
                                   options: [])
            ctx.restoreGState()
        }

        // Reflejo en media luna arriba a la izquierda (la "ventana").
        if let window = gradient(space, [
            (0.00, rgba(1, 1, 1, 0.85)),
            (0.45, rgba(1, 1, 1, 0.35)),
            (1.00, rgba(1, 1, 1, 0.00)),
        ]) {
            ctx.saveGState()
            clipCrescent(ctx,
                         outer: circle(center, radius * 0.95),
                         cutter: circle(CGPoint(x: center.x + radius * 0.10, y: center.y - radius * 0.12), radius * 0.97))
            ctx.drawLinearGradient(window,
                                   start: CGPoint(x: center.x - radius * 0.62, y: center.y + radius * 0.74),
                                   end: CGPoint(x: center.x - radius * 0.05, y: center.y + radius * 0.06),
                                   options: [])
            ctx.restoreGState()
        }

        // Punto especular (con un halo suave).
        let spec = CGPoint(x: center.x - radius * 0.40, y: center.y + radius * 0.50)
        if !small, let specHalo = gradient(space, [
            (0.00, rgba(1, 1, 1, 0.55)),
            (1.00, rgba(1, 1, 1, 0.00)),
        ]) {
            ctx.drawRadialGradient(specHalo, startCenter: spec, startRadius: 0,
                                   endCenter: spec, endRadius: radius * 0.17, options: [])
        }
        ctx.setFillColor(rgba(1, 1, 1, 0.95))
        ctx.fillEllipse(in: circle(spec, radius * (small ? 0.09 : 0.055)))

        ctx.restoreGState() // fin del recorte a la esfera

        // Borde de luz (rim light): más brillante arriba a la izquierda.
        let rimWidth: CGFloat = small ? 18 : 7
        if let rim = gradient(space, [
            (0.00, rgba(1, 1, 1, 0.95)),
            (0.50, rgba(0.85, 0.93, 1.00, 0.40)),
            (1.00, rgba(0.85, 0.93, 1.00, 0.22)),
        ]) {
            ctx.saveGState()
            ctx.addEllipse(in: sphere.insetBy(dx: rimWidth / 2, dy: rimWidth / 2))
            ctx.setLineWidth(rimWidth)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ctx.drawLinearGradient(rim,
                                   start: CGPoint(x: center.x - radius * 0.75, y: center.y + radius * 0.75),
                                   end: CGPoint(x: center.x + radius * 0.75, y: center.y - radius * 0.75),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }

        // ---------------------------------------------------------------
        // Ojos: dos óvalos verticales negros, un poco por encima del centro.
        // En tamaños chicos, más grandes para que se lean.
        // ---------------------------------------------------------------
        let eyeWidth = diameter * (small ? 0.12 : 0.085)
        let eyeHeight = diameter * (small ? 0.26 : 0.215)
        let eyeOffsetX = diameter * (small ? 0.16 : 0.14)
        let eyeY = center.y + diameter * 0.06
        for side in [-1.0, 1.0] as [CGFloat] {
            let eyeCenter = CGPoint(x: center.x + side * eyeOffsetX, y: eyeY)
            let eye = CGRect(x: eyeCenter.x - eyeWidth / 2, y: eyeCenter.y - eyeHeight / 2,
                             width: eyeWidth, height: eyeHeight)
            ctx.setFillColor(rgba(0.020, 0.025, 0.040))
            ctx.fillEllipse(in: eye)

            // Brillito chico arriba del ojo.
            if !small {
                let glint = eyeWidth * 0.36
                ctx.setFillColor(rgba(1, 1, 1, 0.80))
                ctx.fillEllipse(in: CGRect(x: eyeCenter.x - eyeWidth * 0.22 - glint / 2,
                                           y: eyeCenter.y + eyeHeight * 0.26 - glint / 2,
                                           width: glint, height: glint))
            }
        }

        ctx.restoreGState() // fin del recorte a la placa

        // Filete interno claro de la placa (terminación).
        if !small {
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5),
                               cornerWidth: corner - 1.5, cornerHeight: corner - 1.5, transform: nil))
            ctx.setStrokeColor(rgba(1, 1, 1, 0.10))
            ctx.setLineWidth(3)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("make-icon: " + message + "\n").utf8))
        exit(1)
    }
}

// ---------------------------------------------------------------------------
// Programa principal
// ---------------------------------------------------------------------------
let arguments = CommandLine.arguments
guard arguments.count >= 2, !arguments[1].isEmpty else {
    FileHandle.standardError.write(Data("Uso: swift scripts/make-icon.swift <salida.iconset>\n".utf8))
    exit(2)
}

let outputDir = URL(fileURLWithPath: arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
} catch {
    IconArt.fail("no pude crear la carpeta \(outputDir.path): \(error.localizedDescription)")
}

// Nombres que espera `iconutil` dentro de un .iconset.
let outputs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for output in outputs {
    let url = outputDir.appendingPathComponent(output.name)
    guard let image = IconArt.render(pixels: output.pixels) else {
        IconArt.fail("no pude dibujar \(output.name)")
    }
    guard IconArt.writePNG(image, to: url) else {
        IconArt.fail("no pude guardar \(url.path)")
    }
}
print("    Ícono dibujado en \(outputDir.path) (\(outputs.count) imágenes).")

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Orbex",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Orbex", targets: ["Orbex"]),
        .executable(name: "orbex-hook", targets: ["orbex-hook"]),
        .library(name: "OrbexCore", targets: ["OrbexCore"]),
    ],
    targets: [
        // Lógica pura (Foundation). Sin AppKit/SwiftUI: se prueba en cualquier plataforma.
        .target(name: "OrbexCore"),
        // La app (AppKit + SwiftUI).
        .executableTarget(
            name: "Orbex",
            dependencies: ["OrbexCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Security"),
            ]
        ),
        // Relé mínimo de hooks (Claude Code / Codex) → socket Unix de la app.
        .executableTarget(name: "orbex-hook"),
        .testTarget(name: "OrbexCoreTests", dependencies: ["OrbexCore"]),
    ]
)

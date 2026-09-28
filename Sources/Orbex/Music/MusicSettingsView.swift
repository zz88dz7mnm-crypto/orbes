import SwiftUI
import CoreGraphics

/// Configuración › Música: detección de Spotify/Música, baile al ritmo y privacidad.
struct MusicSettingsView: View {
    @ObservedObject private var store = MusicStore.shared
    @ObservedObject private var beat = BeatDetector.shared
    @AppStorage("orbex.music.beatDetection") private var beatDetection = false
    @State private var permissionMissing = false

    var body: some View {
        Form {
            Section("Estado") {
                row("Spotify", on: store.spotifyRunning)
                row("Música", on: store.musicRunning)
                if let t = store.track {
                    LabeledContent("Ahora suena", value: "\(t.title) — \(t.artist)")
                }
            }

            Section {
                Toggle("Bailar al ritmo (analiza el audio del sistema)", isOn: $beatDetection)
                    .onChange(of: beatDetection) { _, on in apply(on) }
                if beatDetection {
                    LabeledContent("Análisis", value: beat.isRunning ? "Escuchando" : "Detenido")
                }
                if permissionMissing || (beatDetection && !beat.isRunning) {
                    Text("Necesita el permiso de Grabación de pantalla y audio del sistema. ORBEX sólo mide la energía de los graves en tu Mac; no graba nada.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Abrir permiso de Grabación de pantalla") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Baile")
            }

            Section("Privacidad") {
                Text("ORBEX lee lo que suena en Spotify o Música sólo para mostrarlo. No se guarda historial de escucha.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            store.start()
            permissionMissing = beatDetection && !CGPreflightScreenCaptureAccess()
        }
    }

    private func row(_ name: String, on: Bool) -> some View {
        LabeledContent(name) {
            HStack(spacing: 5) {
                Circle().fill(on ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                Text(on ? "Detectado" : "No abierto").foregroundStyle(.secondary)
            }
        }
    }

    private func apply(_ on: Bool) {
        if on {
            Task { @MainActor in
                let ok = await BeatDetector.shared.start()
                permissionMissing = !ok
            }
        } else {
            BeatDetector.shared.stop()
            permissionMissing = false
        }
    }
}

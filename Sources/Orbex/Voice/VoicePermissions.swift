import AppKit
import AVFoundation
import Speech

/// Estado de un permiso de macOS que usa la voz.
enum VoicePermission: Equatable {
    case notAsked, granted, denied, restricted

    var label: String {
        switch self {
        case .notAsked: return "Sin pedir todavía"
        case .granted: return "Permitido"
        case .denied: return "Denegado"
        case .restricted: return "Bloqueado por el sistema"
        }
    }

    var symbol: String {
        switch self {
        case .notAsked: return "questionmark.circle"
        case .granted: return "checkmark.circle.fill"
        case .denied, .restricted: return "xmark.octagon.fill"
        }
    }
}

/// Micrófono + reconocimiento de voz. Se piden SOLO la primera vez que el usuario usa la voz
/// (activarla, probar el micrófono, el atajo), nunca al abrir la app (regla 9).
enum VoicePermissions {
    static var microphone: VoicePermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notAsked
        @unknown default: return .notAsked
        }
    }

    static var speech: VoicePermission {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notAsked
        @unknown default: return .notAsked
        }
    }

    /// Muestra el cartel de macOS (solo si nunca se pidió). Devuelve si quedó permitido.
    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Muestra el cartel de macOS (solo si nunca se pidió). La clausura se arma fuera del actor principal
    /// (Speech la llama en otra cola).
    static func requestSpeech() async -> VoicePermission {
        await withCheckedContinuation { (cont: CheckedContinuation<VoicePermission, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in
                cont.resume(returning: VoicePermissions.speech)
            }
        }
    }

    // MARK: - Ajustes del Sistema

    static let microphoneSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    static let speechSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    /// Teclado › Dictado: activar el dictado en español descarga el modelo de voz a la Mac.
    static let dictationSettings = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")

    static func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

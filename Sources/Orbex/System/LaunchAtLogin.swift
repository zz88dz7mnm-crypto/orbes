import Foundation
import ServiceManagement

/// "Iniciar ORBEX con la Mac" (informe §10, General; §13.5).
/// Usa `SMAppService.mainApp` (macOS 13+): la app queda en Ajustes del Sistema > General > Ítems de inicio.
/// Solo funciona con la app empaquetada (`ORBEX.app`); con `swift run` falla sin romper nada.
enum LaunchAtLogin {
    /// `true` si macOS tiene a ORBEX registrado para abrirse al iniciar sesión.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `true` si el usuario tiene que aprobarlo en Ajustes del Sistema (Ítems de inicio).
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Estado legible para mostrar en Configuración.
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "Activado"
        case .notRegistered: return "Desactivado"
        case .requiresApproval: return "Falta aprobarlo en Ajustes del Sistema"
        case .notFound: return "No disponible (abrí ORBEX desde la app instalada)"
        @unknown default: return "Desconocido"
        }
    }

    /// Activa o desactiva el inicio automático. Los errores se registran y no se propagan.
    static func set(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                guard service.status != .enabled else { return }
                try service.register()
                if service.status == .requiresApproval {
                    NSLog("ORBEX: iniciar con la Mac quedó pendiente de aprobación en Ajustes del Sistema.")
                }
            } else {
                guard service.status == .enabled || service.status == .requiresApproval else { return }
                try service.unregister()
            }
        } catch {
            NSLog("ORBEX: no se pudo %@ el inicio con la Mac: %@",
                  enabled ? "activar" : "desactivar", error.localizedDescription)
        }
    }

    /// Abre Ajustes del Sistema en Ítems de inicio (para aprobar a mano).
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

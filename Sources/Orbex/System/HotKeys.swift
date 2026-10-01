import AppKit
import Carbon

/// Firma de los atajos de ORBEX en Carbon ('ORBX').
private let orbexHotKeySignature: OSType = 0x4F52_4258

/// Atajos globales (funcionan aunque ORBEX no esté al frente) con `RegisterEventHotKey` de Carbon.
/// No necesita permisos de Accesibilidad.
///
///     HotKeyCenter.shared.register(id: "clock", keyCode: UInt32(kVK_ANSI_C),
///                                  modifiers: UInt32(controlKey | optionKey)) { ... }
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Entry {
        let ref: EventHotKeyRef
        let number: UInt32
        let action: () -> Void
    }

    private var entries: [String: Entry] = [:]
    private var nextNumber: UInt32 = 1
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Registra (o reemplaza) un atajo. `keyCode` = `kVK_…`; `modifiers` = `cmdKey | optionKey | controlKey | shiftKey`.
    /// Devuelve `false` si macOS no lo dejó (p. ej. otra app ya lo usa).
    @discardableResult
    func register(id: String, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        unregister(id: id)
        guard installHandlerIfNeeded() else { return false }

        let number = nextNumber
        nextNumber &+= 1
        let hotKeyID = EventHotKeyID(signature: orbexHotKeySignature, id: number)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("ORBEX: no se pudo registrar el atajo \"%@\" (error %ld).", id, Int(status))
            return false
        }
        entries[id] = Entry(ref: ref, number: number, action: action)
        return true
    }

    func unregister(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(entry.ref)
    }

    func unregisterAll() {
        for entry in entries.values {
            UnregisterEventHotKey(entry.ref)
        }
        entries.removeAll()
    }

    var registeredIDs: [String] { entries.keys.sorted() }

    /// Lo llama el manejador de Carbon (ya en el hilo principal).
    fileprivate func fire(number: UInt32) {
        guard let entry = entries.values.first(where: { $0.number == number }) else { return }
        entry.action()
    }

    private func installHandlerIfNeeded() -> Bool {
        if handlerRef != nil { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        // Clausura sin capturas: se convierte en puntero a función de C.
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hotKeyID)
            guard err == noErr, hotKeyID.signature == orbexHotKeySignature else {
                return OSStatus(eventNotHandledErr)
            }
            let number = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    HotKeyCenter.shared.fire(number: number)
                }
            }
            return noErr
        }, 1, &spec, nil, &ref)
        guard status == noErr, let ref else {
            NSLog("ORBEX: no se pudo instalar el manejador de atajos (error %ld).", Int(status))
            return false
        }
        handlerRef = ref
        return true
    }
}

/// Atajos por defecto de ORBEX (informe §5.7). Se evita ⌃⌥Espacio: macOS lo usa para cambiar la fuente de entrada.
enum OrbexHotKeys {
    private static let mods = UInt32(controlKey | optionKey)

    /// (atajo, qué hace) — para mostrar en Configuración > General y en la bienvenida.
    static let descriptions: [(String, String)] = [
        ("⌃⌥O", "Abrir la isla"),
        ("⌃⌥A", "Asistente"),
        ("⌃⌥C", "Modo reloj"),
        ("⌃⌥,", "Configuración"),
    ]

    @MainActor
    static func installDefaults() {
        let center = HotKeyCenter.shared
        center.register(id: "open", keyCode: UInt32(kVK_ANSI_O), modifiers: mods) {
            AppModel.shared.perform("open")
        }
        center.register(id: "assistant", keyCode: UInt32(kVK_ANSI_A), modifiers: mods) {
            AppModel.shared.perform("assistant")
        }
        center.register(id: "clock", keyCode: UInt32(kVK_ANSI_C), modifiers: mods) {
            AppModel.shared.perform("clock")
        }
        center.register(id: "settings", keyCode: UInt32(kVK_ANSI_Comma), modifiers: mods) {
            AppModel.shared.perform("settings")
        }
        // ⌃⌥I: modo inteligente (panel grande de Orbi), también sin usar la voz.
        center.register(id: "smart", keyCode: UInt32(kVK_ANSI_I), modifiers: mods) {
            MainActor.assumeIsolated { SmartModeController.shared.toggle() }
        }
    }

    @MainActor
    static func uninstall() {
        HotKeyCenter.shared.unregisterAll()
    }
}

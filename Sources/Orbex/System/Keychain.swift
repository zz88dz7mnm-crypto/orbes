import Foundation
import Security

/// Claves y tokens en el Keychain de macOS (nunca en disco ni en `UserDefaults`).
/// Uso: `Keychain.set("rk_...", for: "stripe-api-key")`, `Keychain.get("stripe-api-key")`.
/// Los ítems quedan solo en esta Mac (no se sincronizan con iCloud ni migran a otro equipo).
enum Keychain {
    static let service = "com.orbex.ORBEX"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Guarda el valor. `nil` o texto vacío lo borra.
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return true }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func has(_ account: String) -> Bool { get(account) != nil }

    // MARK: - Nombres que usa el código de la isla (base Coucou)

    static func save(key: String, value: String) { set(value, for: key) }
    static func load(key: String) -> String? { get(key) }
    static func delete(key: String) { set(nil, for: key) }
}

/// Caché de claves: lee cada una UNA vez al arrancar (en el hilo principal, desde `AppDelegate`) y después
/// todo se lee del diccionario, sin tocar el Keychain (así macOS no pregunta varias veces).
final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    /// Claves de las integraciones opcionales (Stripe, Cal.com, Notion). El asistente usa `claude`
    /// local: no hay clave de API.
    static let allKeys = [
        "stripe-api-key",
        "calcom-api-key",
        "notion-api-key",
        "cartesia-api-key",   // voz de Orbi en la nube (opcional)
    ]

    private init() {
        for key in Self.allKeys {
            if let v = Keychain.get(key) { cache[key] = v }
        }
    }

    /// Lectura segura desde cualquier hilo; nunca toca el Keychain.
    func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    /// Actualiza la caché y guarda en el Keychain. Texto vacío = borrar.
    func set(_ key: String, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        cache[key] = trimmed.isEmpty ? nil : trimmed
        lock.unlock()
        Keychain.set(trimmed, for: key)
    }

    /// Borra de la caché y del Keychain (solo si estaba guardada).
    func remove(_ key: String) {
        lock.lock()
        let had = cache.removeValue(forKey: key) != nil
        lock.unlock()
        if had { Keychain.set(nil, for: key) }
    }
}

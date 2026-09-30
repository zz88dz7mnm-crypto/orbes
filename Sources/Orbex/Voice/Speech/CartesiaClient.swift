import Foundation

/// Cartesia (nube, opcional). La clave vive en el Keychain (`cartesia-api-key`).
/// Pedido adaptado de OpenJarvis (`speech/cartesia_tts.py`, Apache-2.0): `POST /tts/bytes`, pero
/// pidiendo WAV PCM 16 bits (así lo reproduce `AVAudioPlayer` con medición de nivel) e idioma "es".
enum CartesiaClient {
    static let endpoint = URL(string: "https://api.cartesia.ai/tts/bytes")!
    static let apiVersion = "2024-06-10"
    static let model = "sonic-2"

    enum Failure: LocalizedError {
        case noKey
        case http(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case .noKey: return "Falta la clave de Cartesia."
            case .http(let code, let body): return "Cartesia respondió \(code): \(body)"
            case .empty: return "Cartesia no devolvió audio."
            }
        }
    }

    static var apiKey: String? { KeychainStore.shared.get(OrbiVoiceSettings.cartesiaKeyAccount) }
    static var isConfigured: Bool { apiKey != nil }

    /// Devuelve el audio WAV. Corre en `URLSession` (nunca bloquea el hilo principal).
    static func synthesize(_ text: String, voiceID: String, speed: Double) async throws -> Data {
        guard let key = apiKey else { throw Failure.noKey }
        var req = URLRequest(url: endpoint, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "X-API-Key")
        req.setValue(apiVersion, forHTTPHeaderField: "Cartesia-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model_id": model,
            "transcript": text,
            "voice": ["mode": "id", "id": voiceID],
            "output_format": ["container": "wav", "encoding": "pcm_s16le", "sample_rate": 24000],
            "language": "es",
        ]
        if abs(speed - 1.0) > 0.01 { body["speed"] = speed }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let text = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw Failure.http(code, text)
        }
        guard !data.isEmpty else { throw Failure.empty }
        return data
    }
}

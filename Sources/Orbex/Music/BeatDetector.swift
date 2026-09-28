import Foundation
import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Baile al compás (informe §9.10): escucha el audio del sistema con ScreenCaptureKit y mide la
/// energía de los graves. Apagado por defecto; necesita el permiso de Grabación de pantalla y audio.
/// Nada se graba ni se guarda: solo se calcula un nivel 0…1.
@MainActor
final class BeatDetector: ObservableObject {
    static let shared = BeatDetector()

    /// Energía de graves suavizada (0…1).
    @Published private(set) var level: Double = 0
    @Published private(set) var isRunning = false

    private var stream: SCStream?
    private var output: AudioTap?

    private init() {}

    /// Arranca la captura. Devuelve `false` si no hay permiso o algo falla (sin romper nada).
    func start() async -> Bool {
        if isRunning { return true }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return false }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 44_100
            config.channelCount = 1
            // Video mínimo: solo nos interesa el audio.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let tap = AudioTap { value in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { BeatDetector.shared.push(value) }
                }
            }
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(tap, type: .audio, sampleHandlerQueue: tap.queue)
            try await stream.startCapture()
            self.stream = stream
            self.output = tap
            isRunning = true
            return true
        } catch {
            NSLog("ORBEX: no se pudo escuchar el audio del sistema: %@", error.localizedDescription)
            isRunning = false
            return false
        }
    }

    func stop() {
        guard let stream else { return }
        Task { try? await stream.stopCapture() }
        self.stream = nil
        self.output = nil
        isRunning = false
        level = 0
        CharacterBrain.shared.beatLevel = 0
    }

    /// Suaviza: sube rápido (golpe), baja lento.
    private func push(_ raw: Double) {
        let v = min(1, max(0, raw))
        level = v > level ? level + (v - level) * 0.6 : level + (v - level) * 0.12
        CharacterBrain.shared.beatLevel = level
    }
}

/// Recibe los buffers de audio en un hilo propio y calcula la energía de graves.
private final class AudioTap: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "orbex.beat")
    private let onLevel: (Double) -> Void
    /// Estado del filtro pasa-bajos (graves ≈ < 150 Hz).
    private var lowpass: Float = 0
    /// Promedio lento para normalizar según el volumen de la canción.
    private var average: Float = 0.01

    init(onLevel: @escaping (Double) -> Void) {
        self.onLevel = onLevel
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferIsValid(sampleBuffer) else { return }
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return }

        var blockBuffer: CMBlockBuffer?
        var bufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard status == noErr, let data = bufferList.mBuffers.mData else { return }

        let count = Int(bufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return }
        let samples = data.bindMemory(to: Float.self, capacity: count)

        // Pasa-bajos de un polo + energía (RMS) de los graves.
        let sampleRate = Float(asbd.mSampleRate > 0 ? asbd.mSampleRate : 44_100)
        let alpha: Float = 1 - exp(-2 * Float.pi * 150 / sampleRate)
        var energy: Float = 0
        var lp = lowpass
        for i in 0..<count {
            lp += alpha * (samples[i] - lp)
            energy += lp * lp
        }
        lowpass = lp
        let rms = (energy / Float(count)).squareRoot()
        average = average * 0.97 + rms * 0.03
        let normalized = Double(rms / max(average * 2.2, 0.0005))
        onLevel(min(1, normalized))
    }
}

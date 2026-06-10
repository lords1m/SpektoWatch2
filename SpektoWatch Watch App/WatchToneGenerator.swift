import Foundation
import AVFoundation
import Combine
import os

/// Real-time sine tone synthesis for the watch Tongenerator face.
/// Mirrors the iOS `ToneGenerator` engine pattern (`AVAudioSourceNode` + unfair lock).
final class WatchToneGenerator: ObservableObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var srcNode: AVAudioSourceNode?

    @Published private(set) var isPlaying = false

    @Published var frequency: Float = 1000 {
        didSet { synthLock.withLock { $0.frequency = frequency } }
    }

    @Published var amplitude: Float = 0.5 {
        didSet { synthLock.withLock { $0.amplitude = amplitude } }
    }

    private var sampleRate: Double = 48_000

    private struct SynthState {
        var frequency: Float = 1000
        var amplitude: Float = 0.5
        var phase: Double = 0
    }

    private let synthLock = OSAllocatedUnfairLock<SynthState>(initialState: SynthState())

    func start() {
        guard !isPlaying else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            // Playback-only session routes to the watch speaker; avoid clobbering an
            // active `.record` session unless we need to take over for audible output.
            if session.category != .playback {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)

            let engine = AVAudioEngine()
            audioEngine = engine

            let outputFormat = engine.outputNode.outputFormat(forBus: 0)
            sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48_000

            let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            )!

            srcNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                guard let self else { return noErr }

                let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                guard let buffer = ablPointer.first?.mData?.assumingMemoryBound(to: Float.self) else {
                    return noErr
                }

                let state = self.synthLock.withLockUnchecked { $0 }
                let freq = Double(state.frequency)
                let amp = Double(state.amplitude)
                var currentPhase = state.phase
                let phaseIncrement = 2.0 * .pi * freq / self.sampleRate

                for frame in 0..<Int(frameCount) {
                    buffer[frame] = Float(sin(currentPhase) * amp)
                    currentPhase += phaseIncrement
                    if currentPhase >= 2.0 * .pi {
                        currentPhase -= 2.0 * .pi
                    }
                }

                self.synthLock.withLockUnchecked { $0.phase = currentPhase }
                return noErr
            }

            guard let sourceNode = srcNode else { return }

            engine.attach(sourceNode)
            engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
            try engine.start()
            isPlaying = true
        } catch {
            print("[WatchToneGenerator] Error starting: \(error)")
        }
    }

    func stop() {
        srcNode = nil
        audioEngine?.stop()
        audioEngine = nil
        synthLock.withLock { $0.phase = 0 }
        isPlaying = false
    }

    func toggle() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    deinit {
        srcNode = nil
        audioEngine?.stop()
        audioEngine = nil
    }
}

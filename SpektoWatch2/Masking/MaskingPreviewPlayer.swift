import Foundation
import AVFoundation
import Combine

// Manages the playback AVAudioEngine that plays the masker during preview.
//
// Graph: sourceNode/playerNode → eqNode → mixerNode → outputNode
//
// Lifecycle: MaskingEngine calls play() after stopping the main AudioEngine and
// switching the AVAudioSession to .playAndRecord. It calls stop() when the user
// leaves preview, after which MaskingEngine restores the session and restarts
// the main AudioEngine.
@MainActor
final class MaskingPreviewPlayer: ObservableObject {

    @Published private(set) var isPlaying: Bool = false
    @Published var volumeDB: Float = -20.0 {
        didSet { applyVolume() }
    }

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?    // synthetic noise
    private var playerNode: AVAudioPlayerNode?    // asset-based (rain)
    private var eqNode: AVAudioUnitEQ?
    private var mixerNode: AVAudioMixerNode?

    // MARK: – Play

    func play(maskerType: MaskerType, eqBands: [EQBand], volumeDB: Float) throws {
        stop()

        let newEngine   = AVAudioEngine()
        let newMixer    = AVAudioMixerNode()
        let newEQ       = AVAudioUnitEQ(numberOfBands: 3)

        newEngine.attach(newMixer)
        newEngine.attach(newEQ)

        configureEQ(newEQ, bands: eqBands)

        let outputFormat = newEngine.outputNode.inputFormat(forBus: 0)

        // UI-16: start silent and fade in — the mixer used to run at unity
        // gain until `volumeDB` was applied after `start()` (full-scale burst).
        newMixer.outputVolume = 0

        if maskerType.isAssetBased {
            // Asset-based masker (Rain): schedule looping file on a player node.
            guard let loop = NoiseGenerator.loopingAssetBuffer(named: "rain_loop", extension: "m4a") else {
                // Rain asset missing — fall back to pink noise
                return try play(maskerType: .pinkNoise, eqBands: eqBands, volumeDB: volumeDB)
            }
            let player = AVAudioPlayerNode()
            newEngine.attach(player)
            // UI-16: connect with the asset's own processing format.
            newEngine.connect(player,   to: newEQ,    format: loop.format)
            newEngine.connect(newEQ,    to: newMixer, format: loop.format)
            newEngine.connect(newMixer, to: newEngine.outputNode, format: outputFormat)
            player.scheduleBuffer(loop, at: nil, options: .loops)

            try newEngine.start()
            player.play()
            playerNode = player

        } else {
            // Synthetic noise: generate in real time via AVAudioSourceNode.
            guard let source = NoiseGenerator.makeNode(type: maskerType) else { return }
            newEngine.attach(source)
            // Keep mono format through source→eq→mixer; the mixer handles mono→stereo for output.
            let sourceFormat = source.outputFormat(forBus: 0)
            newEngine.connect(source,   to: newEQ,    format: sourceFormat)
            newEngine.connect(newEQ,    to: newMixer, format: sourceFormat)
            newEngine.connect(newMixer, to: newEngine.outputNode, format: outputFormat)

            try newEngine.start()
            sourceNode = source
        }

        engine    = newEngine
        eqNode    = newEQ
        mixerNode = newMixer
        isFadingIn = true
        self.volumeDB = volumeDB
        isPlaying = true
        fadeIn(mixer: newMixer)
    }

    private var isFadingIn = false
    private var fadeTimer: Timer?

    static func linearVolume(_ db: Float) -> Float {
        min(1.0, max(0.0, pow(10.0, db / 20.0)))
    }

    /// ~100 ms linear fade-in to the current `volumeDB`.
    private func fadeIn(mixer: AVAudioMixerNode) {
        fadeTimer?.invalidate()
        var step = 0
        let steps = 10
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self, weak mixer] timer in
            MainActor.assumeIsolated {
                step += 1
                guard let self, let mixer, self.mixerNode === mixer else { timer.invalidate(); return }
                mixer.outputVolume = Self.linearVolume(self.volumeDB) * Float(step) / Float(steps)
                if step >= steps {
                    timer.invalidate()
                    self.isFadingIn = false
                    self.fadeTimer = nil
                }
            }
        }
    }

    // MARK: – Stop

    func stop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        isFadingIn = false
        playerNode?.stop()
        engine?.stop()
        if let source = sourceNode { engine?.detach(source) }
        if let player = playerNode { engine?.detach(player) }
        engine    = nil
        sourceNode = nil
        playerNode = nil
        eqNode    = nil
        mixerNode = nil
        isPlaying = false
    }

    // MARK: – EQ update (while playing)

    func updateEQ(bands: [EQBand]) {
        guard let eq = eqNode else { return }
        configureEQ(eq, bands: bands)
    }

    // MARK: – Helpers

    private func applyVolume() {
        guard !isFadingIn else { return } // the fade reads `volumeDB` each step
        mixerNode?.outputVolume = Self.linearVolume(volumeDB)
    }

    private func configureEQ(_ eq: AVAudioUnitEQ, bands: [EQBand]) {
        let slots = min(3, eq.bands.count)
        for (i, band) in bands.prefix(slots).enumerated() {
            let eqBand         = eq.bands[i]
            eqBand.filterType  = avFilterType(for: band.type)
            eqBand.frequency   = band.frequency
            eqBand.gain        = band.gainDB
            eqBand.bandwidth   = Self.octaveBandwidth(forQ: band.q)
            eqBand.bypass      = false
        }
        // MC-10: `bands.count..<3` trapped for more than three bands.
        for i in min(bands.count, slots)..<slots {
            eq.bands[i].bypass = true
        }
    }

    /// MC-10: AVAudioUnitEQ takes bandwidth in octaves:
    /// `N = (2 / ln 2) · asinh(1 / (2Q))` (was `1/Q`).
    static func octaveBandwidth(forQ q: Float) -> Float {
        let safeQ = max(0.1, q.isFinite ? q : 1)
        let n = (2 / Float(log(2.0))) * asinh(1 / (2 * safeQ))
        return max(0.05, min(5.0, n))
    }

    private func avFilterType(for type: EQBand.BandType) -> AVAudioUnitEQFilterType {
        switch type {
        case .lowShelf:  return .lowShelf
        case .peak:      return .parametric
        case .highShelf: return .highShelf
        }
    }
}

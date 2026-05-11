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

        if maskerType.isAssetBased {
            // Asset-based masker (Rain): schedule looping file on a player node.
            let player = AVAudioPlayerNode()
            newEngine.attach(player)
            newEngine.connect(player,   to: newEQ,    format: outputFormat)
            newEngine.connect(newEQ,    to: newMixer, format: outputFormat)
            newEngine.connect(newMixer, to: newEngine.outputNode, format: outputFormat)

            let loaded = NoiseGenerator.scheduleLoopingAsset(
                named: "rain_loop", extension: "m4a",
                on: player, engine: newEngine
            )
            if !loaded {
                // Rain asset missing — fall back to pink noise
                return try play(maskerType: .pinkNoise, eqBands: eqBands, volumeDB: volumeDB)
            }

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
        self.volumeDB = volumeDB
        isPlaying = true
    }

    // MARK: – Stop

    func stop() {
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
        let linear = pow(10.0, volumeDB / 20.0)
        mixerNode?.outputVolume = min(1.0, max(0.0, linear))
    }

    private func configureEQ(_ eq: AVAudioUnitEQ, bands: [EQBand]) {
        for (i, band) in bands.prefix(3).enumerated() {
            let eqBand         = eq.bands[i]
            eqBand.filterType  = avFilterType(for: band.type)
            eqBand.frequency   = band.frequency
            eqBand.gain        = band.gainDB
            eqBand.bandwidth   = 1.0 / max(0.1, band.q)   // AVAudioUnitEQ uses octave-bandwidth
            eqBand.bypass      = false
        }
        for i in bands.count..<3 {
            eq.bands[i].bypass = true
        }
    }

    private func avFilterType(for type: EQBand.BandType) -> AVAudioUnitEQFilterType {
        switch type {
        case .lowShelf:  return .lowShelf
        case .peak:      return .parametric
        case .highShelf: return .highShelf
        }
    }
}

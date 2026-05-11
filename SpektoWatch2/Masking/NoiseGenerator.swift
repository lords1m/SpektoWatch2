import Foundation
import AVFoundation

// Real-time synthesis of Pink, Brown, and White noise via AVAudioSourceNode.
// Rain is played from a bundled asset (rain_loop.m4a) via AVAudioPlayerNode.
//
// Usage: attach the node returned by makeNode() to an AVAudioEngine, then call start().
// All synthesis state is maintained inside the closure captured by AVAudioSourceNode,
// so the generator is safe to use from the audio render thread.

enum NoiseGenerator {

    // MARK: – Noise source nodes

    // Creates an AVAudioSourceNode that renders Pink/Brown/White noise in real time.
    // The returned node must be connected to an AVAudioEngine before calling engine.start().
    static func makeNode(type: MaskerType, sampleRate: Double = 44100) -> AVAudioSourceNode? {
        guard !type.isAssetBased else { return nil }

        // Synthesis state — captured in the render closure (audio thread, no malloc).
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        var b3: Float = 0, b4: Float = 0, b5: Float = 0  // Pink noise IIR state (Kellet)
        var brownLast: Float = 0                           // Brown noise integrator state

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let channel = ablPointer.first,
                  let buffer  = channel.mData?.assumingMemoryBound(to: Float.self)
            else { return kAudioUnitErr_InvalidParameter }

            for i in 0..<Int(frameCount) {
                let white = Float.random(in: -1...1)
                let sample: Float

                switch type {
                case .whiteNoise:
                    sample = white * 0.5

                case .pinkNoise:
                    // Paul Kellet's 6-pole IIR approximation of 1/f spectrum.
                    b0 = 0.99886 * b0 + white * 0.0555179
                    b1 = 0.99332 * b1 + white * 0.0750759
                    b2 = 0.96900 * b2 + white * 0.1538520
                    b3 = 0.86650 * b3 + white * 0.3104856
                    b4 = 0.55000 * b4 + white * 0.5329522
                    b5 = -0.7616 * b5 - white * 0.0168980
                    sample = (b0 + b1 + b2 + b3 + b4 + b5 + white * 0.5362) * 0.11

                case .brownNoise:
                    // Leaky integrator: integrate white noise with slow decay.
                    brownLast = (brownLast + 0.02 * white) / 1.02
                    sample = brownLast * 3.5

                case .rain:
                    // Asset-based — never reaches this branch.
                    sample = 0
                }

                buffer[i] = max(-1.0, min(1.0, sample))
            }
            return noErr
        }
    }

    // MARK: – Asset player node (Rain)

    // Schedules a looping asset-based audio file on an existing player node.
    // Returns false if the file cannot be found in the main bundle.
    @discardableResult
    static func scheduleLoopingAsset(named name: String,
                                     extension ext: String = "m4a",
                                     on playerNode: AVAudioPlayerNode,
                                     engine: AVAudioEngine) -> Bool {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            return false
        }
        do {
            let file = try AVAudioFile(forReading: url)
            // Read entire file into a PCM buffer so we can loop it with .loops option.
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                               frameCapacity: AVAudioFrameCount(file.length)) else {
                return false
            }
            try file.read(into: buffer)
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            return true
        } catch {
            return false
        }
    }
}

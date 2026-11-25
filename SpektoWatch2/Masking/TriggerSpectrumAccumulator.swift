import Foundation

// Builds a TriggerSpectrum from live band data received on the main thread.
//
// Data flow:
//   AudioEngine → MaskingEngine.onBandsUpdated → accumulator.feed()
//   UI button press/release              → accumulator.beginMark() / endMark()
//
// The accumulator keeps a sliding window of recent band snapshots. A "mark" extracts
// the window around the moment the user tapped "Das war es", computes the mean spectrum
// for that slice, and adds it to the running average. The trigger doesn't need to be
// loud — the window is defined by user timing, not by amplitude threshold.
final class TriggerSpectrumAccumulator {

    // MARK: – Configuration

    private let windowCapacity: Int    // how many frames fit in the ring buffer
    private let preMarkSeconds: Double // frames captured before mark start
    private let postMarkSeconds: Double

    // MARK: – Ring buffer (all access on main thread)

    private struct Frame {
        let bands: [Float]
        let rmsDB: Float
    }

    private var ringBuffer: [Frame?]
    private var writeHead: Int = 0

    // MARK: – Mark state

    private var markStartHead: Int? = nil    // writeHead when beginMark() was called
    private var isMarking: Bool = false

    // MARK: – Accumulated captures

    private var capturedBandSets: [[Float]] = []   // one [Float](31) per confirmed capture
    private var capturedRMSValues: [Float] = []
    private var previousMeanSpectrum: [Float]?

    // MARK: – Public state

    private(set) var captureCount: Int = 0
    private(set) var convergenceScore: Float = 0.0

    // Ambient baseline: set by MaskingEngine after calibration step
    var ambientBands: [Float]?

    private let sampleRate: Double
    private let hopSize: Double

    // MARK: – Init

    init(sampleRate: Double = 44100, hopSize: Int = 512,
         historySeconds: Double = 8, preMarkSeconds: Double = 1.0, postMarkSeconds: Double = 0.5) {
        let safeSampleRate = max(1.0, sampleRate)
        let safeHopSize = max(1, hopSize)
        self.sampleRate = safeSampleRate
        self.hopSize = Double(safeHopSize)
        let fps = safeSampleRate / Double(safeHopSize)
        self.windowCapacity  = max(1, Int(fps * historySeconds))
        self.preMarkSeconds  = preMarkSeconds
        self.postMarkSeconds = postMarkSeconds
        self.ringBuffer = [Frame?](repeating: nil, count: windowCapacity)
    }

    // MARK: – Feed (called every audio frame from MaskingEngine)

    func feed(bands: [Float], rmsDB: Float) {
        ringBuffer[writeHead % windowCapacity] = Frame(bands: bands, rmsDB: rmsDB)
        writeHead += 1
    }

    // MARK: – Tap-to-mark interface

    // Called when the user presses "Das war es"
    func beginMark() {
        markStartHead = writeHead
        isMarking = true
    }

    // Called when the user releases "Das war es".
    // Extracts frames around the mark, computes their mean spectrum, adds it as a capture.
    // Returns true if the capture was valid (at least a few frames available).
    @discardableResult
    func endMark() -> Bool {
        guard isMarking, let startHead = markStartHead else { return false }
        isMarking = false
        markStartHead = nil

        let fps        = sampleRate / hopSize
        let preFames   = Int(preMarkSeconds * fps)
        let postFrames = Int(postMarkSeconds * fps)

        let captureStart = max(0, startHead - preFames)
        let captureEnd   = writeHead + postFrames     // may extend slightly into future
        let frameRange   = min(captureEnd - captureStart, windowCapacity)

        guard frameRange >= 3 else { return false }

        var bandAccum = [Float](repeating: 0, count: TriggerSpectrum.bandCount)
        var rmsAccum: Float = 0
        var validFrames = 0

        for offset in 0..<frameRange {
            let idx = (captureStart + offset) % windowCapacity
            guard let frame = ringBuffer[idx], frame.bands.count >= TriggerSpectrum.bandCount else { continue }
            for b in 0..<TriggerSpectrum.bandCount {
                bandAccum[b] += frame.bands[b]
            }
            rmsAccum += frame.rmsDB
            validFrames += 1
        }

        guard validFrames > 0 else { return false }

        let scale = 1.0 / Float(validFrames)
        let meanBands = bandAccum.map { $0 * scale }
        capturedBandSets.append(meanBands)
        capturedRMSValues.append(rmsAccum * scale)
        captureCount = capturedBandSets.count

        updateConvergence(newMean: computeGlobalMean())
        return true
    }

    // MARK: – Ambient calibration

    // Call after a dedicated "ambient only" recording window to set the baseline.
    // Averages all frames currently in the ring buffer (assumes no trigger present).
    func calibrateAmbient() {
        var accum = [Float](repeating: 0, count: TriggerSpectrum.bandCount)
        var count = 0
        for frame in ringBuffer {
            guard let f = frame, f.bands.count >= TriggerSpectrum.bandCount else { continue }
            for b in 0..<TriggerSpectrum.bandCount { accum[b] += f.bands[b] }
            count += 1
        }
        guard count > 0 else { return }
        ambientBands = accum.map { $0 / Float(count) }
    }

    // MARK: – Spectrum output

    func currentSpectrum() -> TriggerSpectrum? {
        guard !capturedBandSets.isEmpty else { return nil }
        let means  = computeGlobalMean()
        let stdDevs = computeStdDev(mean: means)
        let peakIdx = means.indices.max(by: { means[$0] < means[$1] }) ?? 0
        let avgRMS  = capturedRMSValues.reduce(0, +) / Float(capturedRMSValues.count)

        return TriggerSpectrum(
            bands: means,
            stdDev: stdDevs,
            peakBandIndex: peakIdx,
            totalRMSdB: avgRMS,
            acquisitionMode: .tapToMark,
            captureCount: captureCount,
            ambientBands: ambientBands
        )
    }

    func reset() {
        ringBuffer = [Frame?](repeating: nil, count: windowCapacity)
        writeHead = 0
        capturedBandSets.removeAll()
        capturedRMSValues.removeAll()
        previousMeanSpectrum = nil
        captureCount = 0
        convergenceScore = 0
        ambientBands = nil
        isMarking = false
        markStartHead = nil
    }

    // MARK: – Private helpers

    private func computeGlobalMean() -> [Float] {
        guard !capturedBandSets.isEmpty else { return [Float](repeating: TriggerSpectrum.noiseFloor, count: TriggerSpectrum.bandCount) }
        var accum = [Float](repeating: 0, count: TriggerSpectrum.bandCount)
        for set in capturedBandSets {
            for b in 0..<TriggerSpectrum.bandCount { accum[b] += set[b] }
        }
        let n = Float(capturedBandSets.count)
        return accum.map { $0 / n }
    }

    private func computeStdDev(mean: [Float]) -> [Float] {
        guard capturedBandSets.count > 1 else {
            return [Float](repeating: 0, count: TriggerSpectrum.bandCount)
        }
        var variance = [Float](repeating: 0, count: TriggerSpectrum.bandCount)
        for set in capturedBandSets {
            for b in 0..<TriggerSpectrum.bandCount {
                let diff = set[b] - mean[b]
                variance[b] += diff * diff
            }
        }
        let n = Float(capturedBandSets.count)
        return variance.map { sqrt($0 / max(1, n - 1)) }  // Bessel's correction
    }

    private func updateConvergence(newMean: [Float]) {
        if let prev = previousMeanSpectrum {
            convergenceScore = TriggerSpectrum.convergence(between: newMean, and: prev)
        }
        previousMeanSpectrum = newMean
    }
}

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
    private let preMarkSeconds: Double // seconds captured before mark start
    private let postMarkSeconds: Double
    private let historySeconds: Double

    // MARK: – Ring buffer (all access on main thread)

    /// MC-8: frames carry their arrival time. The live band feed arrives at
    /// the UI publish cadence (~60 Hz, or ~10 Hz from the Watch), not at the
    /// 86 frames/s the old `sampleRate / hopSize` math assumed, so capture
    /// windows are selected by time instead of by frame count.
    private struct Frame {
        let bands: [Float]
        let rmsDB: Float
        let time: TimeInterval
    }

    private var ringBuffer: [Frame?]
    private var writeHead: Int = 0

    // MARK: – Mark state

    private var markStartTime: TimeInterval? = nil
    private var isMarking: Bool = false
    /// Capture window waiting for its post-mark frames to arrive.
    private var pendingCapture: (start: TimeInterval, end: TimeInterval)?

    /// Called on the main thread when a deferred capture (one with a
    /// post-mark window) has been evaluated. `true` = capture added.
    var onCaptureFinalized: ((Bool) -> Void)?

    // MARK: – Accumulated captures

    private var capturedBandSets: [[Float]] = []   // one [Float](31) per confirmed capture
    private var capturedRMSValues: [Float] = []
    private var previousMeanSpectrum: [Float]?

    // MARK: – Public state

    private(set) var captureCount: Int = 0
    private(set) var convergenceScore: Float = 0.0

    // Ambient baseline: set by MaskingEngine after calibration step
    var ambientBands: [Float]?

    /// `true` while a capture waits for its post-mark frames.
    var isCapturePending: Bool { pendingCapture != nil }

    // MARK: – Init

    /// `sampleRate`/`hopSize` are kept for source compatibility; the ring is
    /// sized for `maxFrameRate` frames per second of history.
    init(sampleRate: Double = 44100, hopSize: Int = 512,
         historySeconds: Double = 8, preMarkSeconds: Double = 1.0, postMarkSeconds: Double = 0.5,
         maxFrameRate: Double = 120) {
        self.historySeconds = max(0, historySeconds)
        self.windowCapacity  = max(1, Int(max(1, maxFrameRate) * self.historySeconds))
        self.preMarkSeconds  = preMarkSeconds
        self.postMarkSeconds = max(0, postMarkSeconds)
        self.ringBuffer = [Frame?](repeating: nil, count: windowCapacity)
    }

    // MARK: – Feed (called every audio frame from MaskingEngine)

    func feed(bands: [Float], rmsDB: Float, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        ringBuffer[writeHead % windowCapacity] = Frame(bands: bands, rmsDB: rmsDB, time: time)
        writeHead += 1
        if let pending = pendingCapture, time >= pending.end {
            pendingCapture = nil
            let captured = finalizeCapture(start: pending.start, end: pending.end)
            onCaptureFinalized?(captured)
        }
    }

    // MARK: – Tap-to-mark interface

    // Called when the user presses "Das war es"
    func beginMark(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        markStartTime = time
        isMarking = true
    }

    /// Called when the user releases "Das war es".
    ///
    /// MC-8: the capture window is `[markStart − pre, release + post]`. When
    /// `post > 0` the capture completes once frames up to the window end have
    /// arrived (reported via `onCaptureFinalized`) — the old code read
    /// not-yet-written ring slots. Returns `true` if a capture was accepted
    /// (immediately evaluated or pending), `false` otherwise.
    @discardableResult
    func endMark(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard isMarking, let start = markStartTime else { return false }
        isMarking = false
        markStartTime = nil
        let window = (start: start - preMarkSeconds, end: time + postMarkSeconds)
        if postMarkSeconds > 0 {
            pendingCapture = window
            return true
        }
        return finalizeCapture(start: window.start, end: window.end)
    }

    /// Mean spectrum of all ring frames inside `[start, end]`.
    private func finalizeCapture(start: TimeInterval, end: TimeInterval) -> Bool {
        var bandAccum = [Float](repeating: 0, count: TriggerSpectrum.bandCount)
        var rmsAccum: Float = 0
        var validFrames = 0

        let count = min(writeHead, windowCapacity)
        for offset in 0..<count {
            let idx = (writeHead - 1 - offset) % windowCapacity
            guard let frame = ringBuffer[idx] else { continue }
            if frame.time < start { break }  // walking backwards in time
            guard frame.time <= end, frame.bands.count >= TriggerSpectrum.bandCount else { continue }
            for b in 0..<TriggerSpectrum.bandCount {
                bandAccum[b] += frame.bands[b]
            }
            rmsAccum += frame.rmsDB
            validFrames += 1
        }

        guard validFrames >= 3 else { return false }

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
        markStartTime = nil
        pendingCapture = nil
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

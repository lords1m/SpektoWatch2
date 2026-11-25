import Foundation

/// Sample-counter clock that gives every live FFT frame its own audio-position
/// timestamp.
///
/// A single tap callback usually yields several FFT frames (the tap may deliver
/// 4800+ samples while the hop is 400–1024). Stamping all of them with the
/// callback's arrival time made the frames of one burst share a timestamp, so
/// downstream renderers saw `dt = 0` followed by one large jump. This clock
/// instead anchors the end of the newest buffered sample to the buffer arrival
/// time and derives each frame's timestamp from how many samples still follow
/// the frame's window end, so frames inside a burst are spaced by exactly
/// `hop / sampleRate`.
///
/// The anchor is advanced by the sample count of every incoming buffer
/// (`predicted`) and only slewed gently toward the observed arrival time, which
/// removes callback-scheduling jitter while still tracking clock drift. A gap
/// (interruption, slower-than-real-time producer) or a large lead re-anchors
/// hard. Output timestamps are strictly monotonic.
///
/// Pure value type with no allocation: `AudioEngine` keeps it inside
/// `rtPerfLock` and drives it from the audio render thread.
struct SpectrogramFrameClock {
    /// Observed-minus-predicted lag above which the anchor jumps forward to
    /// the arrival time (samples were lost or arrive slower than real time).
    static let forwardResyncThreshold: TimeInterval = 0.25
    /// Lead above which the anchor jumps back to the arrival time (samples
    /// arrive much faster than real time, e.g. bulk external feeds).
    static let backwardResyncThreshold: TimeInterval = 1.0
    /// Fraction of the observed error folded into the anchor per buffer.
    static let slewFactor: Double = 0.02
    /// Minimum spacing enforced between emitted timestamps.
    static let minimumSpacing: TimeInterval = 1e-6

    /// Absolute time (seconds since reference date) of the newest buffered sample.
    private(set) var bufferEndTime: TimeInterval = 0
    private(set) var lastFrameTimestamp: TimeInterval = 0
    /// Audio duration of the most recent buffer; the UI pacing delay.
    private(set) var lastBufferDuration: TimeInterval = 0

    /// Advances the anchor for a freshly appended buffer and returns the new
    /// buffer-end time. Call once per incoming buffer, after the append.
    @discardableResult
    mutating func advance(arrivalTime: TimeInterval, appendedSamples: Int, sampleRate: Double) -> TimeInterval {
        guard sampleRate > 0 else {
            bufferEndTime = arrivalTime
            return bufferEndTime
        }
        lastBufferDuration = Double(max(0, appendedSamples)) / sampleRate
        guard bufferEndTime > 0 else {
            bufferEndTime = arrivalTime
            return bufferEndTime
        }
        let predicted = bufferEndTime + Double(max(0, appendedSamples)) / sampleRate
        let error = arrivalTime - predicted
        if error > Self.forwardResyncThreshold || error < -Self.backwardResyncThreshold {
            bufferEndTime = arrivalTime
        } else {
            bufferEndTime = predicted + error * Self.slewFactor
        }
        return bufferEndTime
    }

    /// Timestamp of the frame whose window end is followed by
    /// `samplesAfterFrameEnd` still-buffered samples.
    mutating func frameTimestamp(samplesAfterFrameEnd: Int, sampleRate: Double) -> TimeInterval {
        let offset = sampleRate > 0 ? Double(max(0, samplesAfterFrameEnd)) / sampleRate : 0
        var timestamp = bufferEndTime - offset
        if lastFrameTimestamp > 0, timestamp <= lastFrameTimestamp {
            timestamp = lastFrameTimestamp + Self.minimumSpacing
        }
        lastFrameTimestamp = timestamp
        return timestamp
    }

    /// Drops the anchor (e.g. on capture stop) so the next buffer re-anchors
    /// to its arrival time. The monotonic floor is kept.
    mutating func resetAnchor() {
        bufferEndTime = 0
    }
}

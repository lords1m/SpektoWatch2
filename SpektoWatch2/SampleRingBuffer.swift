import Foundation

/// Offset-based sample accumulator for the live FFT path. Incoming tap buffers
/// are appended; full FFT windows are extracted with an overlap hop. Uses an
/// index (`offset`) instead of `removeFirst` so the steady-state per-frame
/// advance is O(1); the backing storage is compacted only when the dead head
/// grows past a threshold.
///
/// This type owns **no lock**. It is not internally synchronised: `AudioEngine`
/// holds its `processingLock` around every call exactly as it did when these
/// three buffers lived inline, so the serialisation against reconfiguration
/// (`applyFFTConfiguration` / `setBlockSize` / `updateProcessingSampleRate`) is
/// unchanged. The frame-extraction scratch is reused across calls to avoid
/// per-frame allocation on the audio render thread.
///
/// Extracted from `AudioEngine.processSamples` in VERBESSERUNGSPLAN Phase 3
/// (post-3.5 shrink). All buffer math is verbatim.
final class SampleRingBuffer {
    private var buffer: [Float] = []
    private var offset: Int = 0
    /// Reusable copy target for the current FFT window. Resized only when the
    /// FFT size changes; never reallocated per frame in the steady state.
    private var frameScratch: [Float] = []

    /// Number of unconsumed samples (live samples ahead of the read offset).
    var bufferedCount: Int { max(0, buffer.count - offset) }

    /// Appends a freshly captured tap buffer.
    func append(_ samples: [Float]) {
        buffer.append(contentsOf: samples)
    }

    /// Advances the read offset to drop the oldest `count` queued samples
    /// (real-time backlog trim). No storage move; the dead head is reclaimed by
    /// `compactIfNeeded` / `nextFrame`.
    func dropOldest(_ count: Int) {
        offset += count
    }

    /// Reclaims the dead head when the offset has run past `threshold`, so the
    /// backing storage cannot grow unbounded if the backlog trimmer jumped the
    /// offset without the frame loop executing.
    func compactIfNeeded(threshold: Int) {
        if offset > threshold {
            buffer.removeFirst(offset)
            offset = 0
        }
    }

    /// Copies the next `frameSize` samples into the reusable scratch, advances
    /// the read offset by `hop`, and compacts when the offset passes
    /// `frameSize * 2`. Returns the scratch window, or `nil` when fewer than
    /// `frameSize` samples are buffered. The returned array is the shared
    /// scratch (copy-on-write): consume it before the next `nextFrame` call.
    func nextFrame(frameSize: Int, hop: Int) -> [Float]? {
        guard buffer.count - offset >= frameSize else { return nil }
        if frameScratch.count != frameSize {
            frameScratch = [Float](repeating: 0, count: frameSize)
        }
        buffer.withUnsafeBufferPointer { source in
            frameScratch.withUnsafeMutableBufferPointer { target in
                guard let sourceBase = source.baseAddress, let targetBase = target.baseAddress else { return }
                memcpy(
                    targetBase,
                    sourceBase.advanced(by: offset),
                    frameSize * MemoryLayout<Float>.stride
                )
            }
        }
        offset += hop
        if offset > frameSize * 2 {
            buffer.removeFirst(offset)
            offset = 0
        }
        return frameScratch
    }

    /// Clears all accumulated samples and the frame scratch. Called on
    /// reconfiguration and on capture stop.
    func reset() {
        buffer.removeAll()
        offset = 0
        frameScratch.removeAll()
    }
}

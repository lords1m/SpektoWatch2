import AVFoundation
import Foundation
import os

enum RealtimeAudioFileWriterError: Error {
    case bufferAllocationFailed
}

/// Copies capture buffers on the audio render thread into a preallocated
/// pool and writes them to disk on a dedicated worker thread.
///
/// M22 RT-5: the render-thread path takes only an `OSAllocatedUnfairLock`
/// (no `NSLock`), performs no block dispatch, allocation or logging. Drops are
/// counted atomically and logged from the worker thread.
final class RealtimeAudioFileWriter {
    let fileURL: URL

    private let audioFile: AVAudioFile
    private let lifecycleLock = OSAllocatedUnfairLock<Bool>(initialState: false) // isClosed
    private let buffers: [AVAudioPCMBuffer]
    private let frameCapacity: AVAudioFrameCount
    private var slotQueue: RealtimeSlotQueue!
    private let oversizeDrops = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    private var lastLoggedDrops: UInt64 = 0   // worker thread only

    init(
        fileURL: URL,
        format: AVAudioFormat,
        settings: [String: Any],
        frameCapacity: AVAudioFrameCount,
        maxPendingBuffers: Int = 24
    ) throws {
        self.fileURL = fileURL
        self.audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
        self.frameCapacity = frameCapacity

        let capacity = max(1, maxPendingBuffers)
        let allocatedBuffers = (0..<capacity).compactMap { _ in
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)
        }
        guard !allocatedBuffers.isEmpty else {
            throw RealtimeAudioFileWriterError.bufferAllocationFailed
        }
        self.buffers = allocatedBuffers

        let file = audioFile
        let pool = allocatedBuffers
        slotQueue = RealtimeSlotQueue(capacity: allocatedBuffers.count, name: "com.spektowatch.audio-file.writer") { [weak self] slot in
            do {
                try file.write(from: pool[slot])
            } catch {
                NSLog("[RealtimeAudioFileWriter] audio write failed: \(error.localizedDescription)")
            }
            self?.logDropsIfNeeded()
        }
    }

    deinit {
        close()
    }

    /// Render-thread safe.
    func write(_ source: AVAudioPCMBuffer) {
        lifecycleLock.withLockUnchecked { isClosed in
            guard !isClosed else { return }
            guard source.frameLength <= frameCapacity else {
                oversizeDrops.withLockUnchecked { $0 &+= 1 }
                return
            }
            guard let slot = slotQueue.acquireFreeSlot() else { return }
            guard copy(source, into: buffers[slot]) else {
                slotQueue.returnUnusedSlot(slot)
                return
            }
            slotQueue.enqueue(slot)
        }
    }

    /// Flushes pending buffers and stops the worker. Idempotent; call off the
    /// render thread.
    func close() {
        let alreadyClosed = lifecycleLock.withLock { isClosed -> Bool in
            let was = isClosed
            isClosed = true
            return was
        }
        guard !alreadyClosed else { return }
        slotQueue.drainAndStop()
        logDropsIfNeeded()
    }

    private func copy(_ source: AVAudioPCMBuffer, into destination: AVAudioPCMBuffer) -> Bool {
        guard let sourceChannels = source.floatChannelData,
              let destinationChannels = destination.floatChannelData else {
            return false
        }

        let frameLength = source.frameLength
        let frameCount = Int(frameLength)
        let channelCount = min(Int(source.format.channelCount), Int(destination.format.channelCount))
        for channel in 0..<channelCount {
            memcpy(
                destinationChannels[channel],
                sourceChannels[channel],
                frameCount * MemoryLayout<Float>.stride
            )
        }
        destination.frameLength = frameLength
        return true
    }

    /// Worker thread / close only.
    private func logDropsIfNeeded() {
        let dropped = slotQueue.droppedCount + oversizeDrops.withLock { $0 }
        if dropped >= lastLoggedDrops + 32 {
            lastLoggedDrops = dropped
            NSLog("[RealtimeAudioFileWriter] dropped %llu buffers", dropped)
        }
    }
}

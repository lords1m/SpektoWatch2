import AVFoundation
import Foundation

enum RealtimeAudioFileWriterError: Error {
    case bufferAllocationFailed
}

final class RealtimeAudioFileWriter {
    let fileURL: URL

    private let audioFile: AVAudioFile
    private let writeQueue = DispatchQueue(label: "com.spektowatch.audio-file.writer", qos: .utility)
    private let lifecycleLock = NSLock()
    private let bufferPoolLock = NSLock()
    private var isClosed = false
    private var droppedBufferCount: UInt64 = 0

    private let buffers: [AVAudioPCMBuffer]
    private var availableBufferIndices: [Int]
    private let frameCapacity: AVAudioFrameCount

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
        self.availableBufferIndices = Array(0..<allocatedBuffers.count)
    }

    func write(_ source: AVAudioPCMBuffer) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard !isClosed else { return }
        guard source.frameLength <= frameCapacity else {
            recordDroppedBuffer(reason: "input frameLength exceeds pooled capacity")
            return
        }
        guard let bufferIndex = acquireBufferIndex() else {
            recordDroppedBuffer(reason: "queue full")
            return
        }

        let destination = buffers[bufferIndex]
        guard copy(source, into: destination) else {
            releaseBufferIndex(bufferIndex)
            return
        }

        let file = audioFile
        writeQueue.async { [weak self] in
            do {
                try file.write(from: destination)
            } catch {
                NSLog("[RealtimeAudioFileWriter] audio write failed: \(error.localizedDescription)")
            }
            self?.releaseBufferIndex(bufferIndex)
        }
    }

    func close() {
        lifecycleLock.lock()
        guard !isClosed else {
            lifecycleLock.unlock()
            return
        }
        isClosed = true
        lifecycleLock.unlock()

        writeQueue.sync {}
    }

    private func copy(_ source: AVAudioPCMBuffer, into destination: AVAudioPCMBuffer) -> Bool {
        guard let sourceChannels = source.floatChannelData,
              let destinationChannels = destination.floatChannelData else {
            recordDroppedBuffer(reason: "non-float PCM buffer")
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

    private func acquireBufferIndex() -> Int? {
        bufferPoolLock.lock()
        defer { bufferPoolLock.unlock() }
        return availableBufferIndices.popLast()
    }

    private func releaseBufferIndex(_ index: Int) {
        bufferPoolLock.lock()
        availableBufferIndices.append(index)
        bufferPoolLock.unlock()
    }

    private func recordDroppedBuffer(reason: String) {
        bufferPoolLock.lock()
        droppedBufferCount += 1
        let dropped = droppedBufferCount
        bufferPoolLock.unlock()

        if dropped.isMultiple(of: 32) {
            NSLog("[RealtimeAudioFileWriter] dropped %llu buffers (\(reason))", dropped)
        }
    }
}

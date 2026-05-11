import Foundation

private final class MeasurementFrameBuffer {
    var values: [Float]

    init(floatCount: Int) {
        self.values = [Float](repeating: 0, count: floatCount)
    }
}

final class MeasurementDataWriter {
    let fileURL: URL
    let metricKeys: [String]
    let sampleRate: Double
    let fps: Float
    let fftBlockSize: Int
    let fftBinCount: Int

    private let fileHandle: FileHandle
    private let frameSize: Int
    private(set) var frameCount: UInt64 = 0
    private(set) var droppedFrameCount: UInt64 = 0
    private var isClosed = false

    // Async I/O: all frame writes are dispatched onto this serial queue to keep
    // the audio hot path free of blocking disk operations. The queue depth is
    // bounded — if the disk stalls and we exceed `maxPendingFrames`, we drop the
    // incoming frame and log it instead of letting memory grow unbounded.
    private let writeQueue = DispatchQueue(label: "com.spektowatch.measurement.writer", qos: .utility)
    private let lifecycleLock = NSLock()
    private let bufferPoolLock = NSLock()
    private var frameFloatBuffers: [MeasurementFrameBuffer]
    private var availableFrameBufferIndices: [Int]
    private let frameFloatCount: Int

    init(
        fileURL: URL,
        metricKeys: [String],
        sampleRate: Double,
        fps: Float,
        fftBlockSize: Int,
        fftBinCount: Int,
        maxPendingFrames: Int = 32
    ) throws {
        self.fileURL = fileURL
        self.metricKeys = metricKeys
        self.sampleRate = sampleRate
        self.fps = fps
        self.fftBlockSize = fftBlockSize
        self.fftBinCount = max(0, fftBinCount)
        let pendingFrameCapacity = max(0, maxPendingFrames)
        let fullFftCount = max(0, fftBinCount)
        let frameFloatCount = 1 + metricKeys.count + 1 + (MeasurementDataFormat.thirdOctaveBandCount * 3) + fullFftCount
        // Frame layout (floats): timestamp + metrics + broadband + 3×thirdOctave + fullFFT
        self.frameFloatCount = frameFloatCount
        self.frameSize = MemoryLayout<Float>.size * frameFloatCount
        self.frameFloatBuffers = (0..<pendingFrameCapacity).map { _ in MeasurementFrameBuffer(floatCount: frameFloatCount) }
        self.availableFrameBufferIndices = Array(0..<pendingFrameCapacity)

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
        try writeHeader(frameCount: 0)
    }

    deinit {
        try? close()
    }

    func writeFrame(
        timestamp: Float,
        metricValues: [Float],
        broadbandLevel: Float,
        thirdOctaveZ: [Float],
        thirdOctaveA: [Float],
        thirdOctaveC: [Float],
        fullFFT: [Float]
    ) throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard !isClosed else { return }
        guard metricValues.count == metricKeys.count else {
            throw MeasurementDataError.metricCountMismatch(expected: metricKeys.count, got: metricValues.count)
        }
        guard thirdOctaveZ.count == MeasurementDataFormat.thirdOctaveBandCount,
              thirdOctaveA.count == MeasurementDataFormat.thirdOctaveBandCount,
              thirdOctaveC.count == MeasurementDataFormat.thirdOctaveBandCount else {
            throw MeasurementDataError.invalidFrameIndex
        }
        if fftBinCount > 0, fullFFT.count != fftBinCount {
            throw MeasurementDataError.metricCountMismatch(expected: fftBinCount, got: fullFFT.count)
        }

        guard let bufferIndex = acquireFrameBufferIndex() else {
            let dropped = recordDroppedFrame()
            if dropped.isMultiple(of: 32) {
                NSLog("[MeasurementDataWriter] dropped %llu frames (queue full)", dropped)
            }
            return
        }

        // Fill a checked-out reusable buffer directly. The buffer will not be
        // returned to the pool until the writer queue has finished writing it.
        let frameBuffer = frameFloatBuffers[bufferIndex]
        var idx = 0
        frameBuffer.values[idx] = timestamp; idx += 1
        for v in metricValues { frameBuffer.values[idx] = v; idx += 1 }
        frameBuffer.values[idx] = broadbandLevel; idx += 1
        for v in thirdOctaveZ { frameBuffer.values[idx] = v; idx += 1 }
        for v in thirdOctaveA { frameBuffer.values[idx] = v; idx += 1 }
        for v in thirdOctaveC { frameBuffer.values[idx] = v; idx += 1 }
        if fftBinCount > 0 {
            for v in fullFFT { frameBuffer.values[idx] = v; idx += 1 }
        }

        let handle = fileHandle
        writeQueue.async {
            frameBuffer.values.withUnsafeBytes { ptr in
                handle.write(Data(ptr))
            }
            self.releaseFrameBufferIndex(bufferIndex)
        }
        frameCount += 1
    }

    func close() throws {
        lifecycleLock.lock()
        guard !isClosed else {
            lifecycleLock.unlock()
            return
        }
        isClosed = true
        lifecycleLock.unlock()

        // Drain all pending async writes before syncing the file
        writeQueue.sync {}
        try fileHandle.synchronize()
        try updateFrameCount()
        try fileHandle.close()
    }

    private func writeHeader(frameCount: UInt64) throws {
        var header = Data(capacity: MeasurementDataFormat.fixedHeaderSize + (metricKeys.count * 16))
        header.appendUInt32LE(MeasurementDataFormat.magic)
        header.appendUInt16LE(MeasurementDataFormat.version)
        header.appendUInt16LE(UInt16(min(fftBinCount, Int(UInt16.max))))
        header.appendUInt64LE(frameCount)
        header.appendDoubleLE(sampleRate)
        header.appendFloatLE(fps)
        header.appendUInt32LE(UInt32(max(1, fftBlockSize)))
        header.appendUInt16LE(UInt16(min(metricKeys.count, Int(UInt16.max))))
        let flags: UInt16 = fftBinCount > 0 ? MeasurementDataFormat.flagHasFullFFT : 0
        header.appendUInt16LE(flags)

        for key in metricKeys {
            let utf8 = key.data(using: .utf8) ?? Data()
            let length = UInt16(min(utf8.count, Int(UInt16.max)))
            header.appendUInt16LE(length)
            header.append(utf8.prefix(Int(length)))
        }

        fileHandle.write(header)
    }

    private func updateFrameCount() throws {
        try fileHandle.seek(toOffset: UInt64(MeasurementDataFormat.frameCountOffset))
        var countData = Data()
        countData.appendUInt64LE(frameCount)
        fileHandle.write(countData)
    }

    private func acquireFrameBufferIndex() -> Int? {
        bufferPoolLock.lock()
        defer { bufferPoolLock.unlock() }
        return availableFrameBufferIndices.popLast()
    }

    private func releaseFrameBufferIndex(_ index: Int) {
        bufferPoolLock.lock()
        availableFrameBufferIndices.append(index)
        bufferPoolLock.unlock()
    }

    private func recordDroppedFrame() -> UInt64 {
        bufferPoolLock.lock()
        droppedFrameCount += 1
        let count = droppedFrameCount
        bufferPoolLock.unlock()
        return count
    }
}

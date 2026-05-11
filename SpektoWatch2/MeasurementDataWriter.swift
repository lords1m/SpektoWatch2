import Foundation

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
    private let pendingFramesLock = NSLock()
    private var pendingFrames: Int = 0
    private static let maxPendingFrames: Int = 32   // ~370 ms backlog at 86 fps

    // Pre-allocated frame buffer — filled inline each call, then captured by value
    // for the async write (Swift COW defers the actual copy until next modification).
    private var frameFloatBuffer: [Float]
    private let frameFloatCount: Int

    init(
        fileURL: URL,
        metricKeys: [String],
        sampleRate: Double,
        fps: Float,
        fftBlockSize: Int,
        fftBinCount: Int
    ) throws {
        self.fileURL = fileURL
        self.metricKeys = metricKeys
        self.sampleRate = sampleRate
        self.fps = fps
        self.fftBlockSize = fftBlockSize
        self.fftBinCount = max(0, fftBinCount)
        let fullFftCount = self.fftBinCount
        // Frame layout (floats): timestamp + metrics + broadband + 3×thirdOctave + fullFFT
        self.frameFloatCount = 1 + metricKeys.count + 1 + (MeasurementDataFormat.thirdOctaveBandCount * 3) + fullFftCount
        self.frameSize = MemoryLayout<Float>.size * frameFloatCount
        self.frameFloatBuffer = [Float](repeating: 0, count: frameFloatCount)

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

        // Fill the pre-allocated buffer directly (replaces ~4000 individual Data.appendFloatLE calls)
        var idx = 0
        frameFloatBuffer[idx] = timestamp; idx += 1
        for v in metricValues { frameFloatBuffer[idx] = v; idx += 1 }
        frameFloatBuffer[idx] = broadbandLevel; idx += 1
        for v in thirdOctaveZ { frameFloatBuffer[idx] = v; idx += 1 }
        for v in thirdOctaveA { frameFloatBuffer[idx] = v; idx += 1 }
        for v in thirdOctaveC { frameFloatBuffer[idx] = v; idx += 1 }
        if fftBinCount > 0 {
            for v in fullFFT { frameFloatBuffer[idx] = v; idx += 1 }
        }

        // Bounded async write: cap the in-flight queue depth so a stalled disk
        // can't grow memory unbounded. On overflow, drop and log instead of
        // stalling the audio path or ballooning RAM.
        pendingFramesLock.lock()
        if pendingFrames >= Self.maxPendingFrames {
            pendingFramesLock.unlock()
            droppedFrameCount += 1
            // Log sparsely — every 32nd drop — to avoid log floods if the disk
            // stays slow for a long stretch.
            if droppedFrameCount.isMultiple(of: 32) {
                NSLog("[MeasurementDataWriter] dropped %llu frames (queue full)", droppedFrameCount)
            }
            return
        }
        pendingFrames += 1
        pendingFramesLock.unlock()

        // Snapshot by value (COW — copy will happen when the next frame mutates
        // `frameFloatBuffer`, which is fine because we've already returned to
        // the caller and the copy happens off the audio thread, on the writer
        // queue when it picks up the snapshot).
        let snapshot = frameFloatBuffer
        let handle = fileHandle
        writeQueue.async { [weak self] in
            snapshot.withUnsafeBytes { ptr in
                handle.write(Data(ptr))
            }
            if let self {
                self.pendingFramesLock.lock()
                self.pendingFrames -= 1
                self.pendingFramesLock.unlock()
            }
        }
        frameCount += 1
    }

    func close() throws {
        guard !isClosed else { return }
        isClosed = true
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
}

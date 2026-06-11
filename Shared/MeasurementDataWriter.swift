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
    let fileFormatVersion: UInt16

    private let fileHandle: FileHandle
    private let frameSize: Int
    private let headerByteCount: Int
    private let headerFlags: UInt16
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
        maxPendingFrames: Int = 32,
        fileFormatVersion: UInt16 = MeasurementDataFormat.preferredWriteVersion,
        calibration: MeasurementCalibrationMetadata? = nil
    ) throws {
        self.fileURL = fileURL
        self.metricKeys = metricKeys
        self.sampleRate = sampleRate
        self.fps = fps
        self.fftBlockSize = fftBlockSize
        self.fftBinCount = max(0, fftBinCount)
        self.fileFormatVersion = fileFormatVersion
        let pendingFrameCapacity = max(0, maxPendingFrames)
        let fullFftCount = max(0, fftBinCount)
        let frameFloatCount = 1 + metricKeys.count + 1 + (MeasurementDataFormat.thirdOctaveBandCount * 3) + fullFftCount
        self.frameFloatCount = frameFloatCount
        self.frameSize = MemoryLayout<Float>.size * frameFloatCount
        var flags: UInt16 = fftBinCount > 0 ? MeasurementDataFormat.flagHasFullFFT : 0
        if fileFormatVersion >= MeasurementDataFormat.version3 {
            // Seek index is patched on close; CRC is patched after the trailer.
            flags &= ~MeasurementDataFormat.flagHasSeekIndex
        }
        self.headerFlags = flags
        self.frameFloatBuffers = (0..<pendingFrameCapacity).map { _ in MeasurementFrameBuffer(floatCount: frameFloatCount) }
        self.availableFrameBufferIndices = Array(0..<pendingFrameCapacity)

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        // Updating (not write-only) so v3 close can re-read the header for CRC32.
        self.fileHandle = try FileHandle(forUpdating: fileURL)
        self.headerByteCount = try Self.writeHeader(
            to: fileHandle,
            metricKeys: metricKeys,
            sampleRate: sampleRate,
            fps: fps,
            fftBlockSize: fftBlockSize,
            fftBinCount: self.fftBinCount,
            flags: flags,
            frameCount: 0,
            fileFormatVersion: fileFormatVersion,
            calibration: calibration
        )
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
            let data = frameBuffer.values.withUnsafeBytes { Data($0) }
            do {
                try handle.write(contentsOf: data)
                self.frameCount += 1
            } catch {
                NSLog("MeasurementDataWriter: frame write failed: %@", String(describing: error))
                _ = self.recordDroppedFrame()
            }
            self.releaseFrameBufferIndex(bufferIndex)
        }
    }

    func close() throws {
        lifecycleLock.lock()
        guard !isClosed else {
            lifecycleLock.unlock()
            return
        }
        isClosed = true
        lifecycleLock.unlock()

        writeQueue.sync {}
        try fileHandle.synchronize()
        try updateFrameCount()
        if fileFormatVersion >= MeasurementDataFormat.version3 {
            try finalizeV3Trailer()
        }
        try fileHandle.synchronize()
        try fileHandle.close()
    }

    private func finalizeV3Trailer() throws {
        guard frameCount > 0 else { return }

        let indexOffset = UInt64(headerByteCount) + frameCount * UInt64(frameSize)
        let offsets = (0..<frameCount).map { index in
            UInt64(headerByteCount) + UInt64(index) * UInt64(frameSize)
        }
        try fileHandle.seek(toOffset: indexOffset)
        try fileHandle.write(contentsOf: MeasurementDataV3Support.encodeSeekIndex(frameOffsets: offsets))

        try fileHandle.seek(toOffset: UInt64(MeasurementDataFormat.v3SeekIndexOffsetField))
        var seekPatch = Data()
        seekPatch.appendUInt64LE(indexOffset)
        try fileHandle.write(contentsOf: seekPatch)

        var finalizedFlags = headerFlags | MeasurementDataFormat.flagHasSeekIndex
        try fileHandle.seek(toOffset: 34)
        var flagsPatch = Data()
        flagsPatch.appendUInt16LE(finalizedFlags)
        try fileHandle.write(contentsOf: flagsPatch)

        try fileHandle.seek(toOffset: 0)
        guard let headerBytes = try fileHandle.read(upToCount: headerByteCount),
              headerBytes.count == headerByteCount else {
            throw MeasurementDataError.ioFailure("Header konnte nicht für CRC gelesen werden.")
        }
        let crc = MeasurementDataV3Support.headerCRC32(for: headerBytes)
        try fileHandle.seek(toOffset: UInt64(MeasurementDataFormat.v3HeaderCRCOffset))
        var crcPatch = Data()
        crcPatch.appendUInt32LE(crc)
        try fileHandle.write(contentsOf: crcPatch)
    }

    private func updateFrameCount() throws {
        try fileHandle.seek(toOffset: UInt64(MeasurementDataFormat.frameCountOffset))
        var countData = Data()
        countData.appendUInt64LE(frameCount)
        try fileHandle.write(contentsOf: countData)
    }

    @discardableResult
    private static func writeHeader(
        to fileHandle: FileHandle,
        metricKeys: [String],
        sampleRate: Double,
        fps: Float,
        fftBlockSize: Int,
        fftBinCount: Int,
        flags: UInt16,
        frameCount: UInt64,
        fileFormatVersion: UInt16,
        calibration: MeasurementCalibrationMetadata?
    ) throws -> Int {
        let tlvData = calibration.map(MeasurementDataV3Support.encodeTLV) ?? Data()
        var header = Data(capacity: MeasurementDataFormat.v3FixedHeaderSize + (metricKeys.count * 16) + tlvData.count)
        header.appendUInt32LE(MeasurementDataFormat.magic)
        header.appendUInt16LE(fileFormatVersion)
        header.appendUInt16LE(UInt16(min(fftBinCount, Int(UInt16.max))))
        header.appendUInt64LE(frameCount)
        header.appendDoubleLE(sampleRate)
        header.appendFloatLE(fps)
        header.appendUInt32LE(UInt32(max(1, fftBlockSize)))
        header.appendUInt16LE(UInt16(min(metricKeys.count, Int(UInt16.max))))
        header.appendUInt16LE(flags)

        if fileFormatVersion >= MeasurementDataFormat.version3 {
            header.appendUInt32LE(0)
            header.appendUInt64LE(0)
            header.appendUInt32LE(UInt32(min(tlvData.count, Int(UInt32.max))))
        }

        for key in metricKeys {
            let utf8 = key.data(using: .utf8) ?? Data()
            let length = UInt16(min(utf8.count, Int(UInt16.max)))
            header.appendUInt16LE(length)
            header.append(utf8.prefix(Int(length)))
        }

        if !tlvData.isEmpty {
            header.append(tlvData)
        }

        try fileHandle.write(contentsOf: header)
        return header.count
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

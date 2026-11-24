import Foundation
import os

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
    private var _frameCount: UInt64 = 0
    private var _droppedFrameCount: UInt64 = 0
    private var isClosed = false
    /// DL-5: set once a frame write fails. Later frames are rejected so the
    /// file never contains misaligned data after a partial write.
    private var _writeFailed = false
    /// Byte offset just past the last fully written frame (write queue only).
    private var nextFrameOffset: UInt64 = 0
    /// DL-4: header `frameCount` is checkpointed every this many frames so a
    /// crash leaves a header the reader can trust (it additionally derives
    /// the count from the file size for unfinalized files).
    private let checkpointInterval: UInt64

    /// `true` once a frame write failed; the writer stopped appending.
    var writeFailed: Bool {
        counterLock.withLockUnchecked { _ in _writeFailed }
    }

    var frameCount: UInt64 {
        counterLock.withLockUnchecked { _ in _frameCount }
    }

    var droppedFrameCount: UInt64 {
        counterLock.withLockUnchecked { _ in _droppedFrameCount + (slotQueue?.droppedCount ?? 0) }
    }

    // Async I/O (M22 RT-5): frames are copied into preallocated slots on the
    // caller's (audio render) thread and written by a dedicated worker thread
    // via `RealtimeSlotQueue` — no `DispatchQueue.async`, `NSLock` or logging
    // on the render thread. Depth is bounded by `maxPendingFrames`; when the
    // disk stalls frames are dropped and counted.
    private var slotQueue: RealtimeSlotQueue?
    private let lifecycleLock = OSAllocatedUnfairLock()
    private let counterLock = OSAllocatedUnfairLock()
    private var frameFloatBuffers: [MeasurementFrameBuffer]
    private let frameFloatCount: Int
    private var lastLoggedDrops: UInt64 = 0

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
        self.frameFloatBuffers = (0..<max(1, pendingFrameCapacity)).map { _ in MeasurementFrameBuffer(floatCount: frameFloatCount) }
        // ~10 s of frames between header checkpoints (at least 16 frames).
        self.checkpointInterval = UInt64(max(16, Int((fps.isFinite ? fps : 10) * 10)))

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
        self.nextFrameOffset = UInt64(headerByteCount)
        let pool = frameFloatBuffers
        if pendingFrameCapacity > 0 {
            slotQueue = RealtimeSlotQueue(capacity: pool.count, name: "com.spektowatch.measurement.writer") { [weak self] slot in
                self?.performFrameWrite(pool[slot])
                self?.logDropsIfNeeded()
            }
        }
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

        guard !isClosed, let slotQueue else { return }
        if writeFailed {
            throw MeasurementDataError.ioFailure("Messdaten-Datei: vorheriger Schreibfehler, Aufzeichnung gestoppt.")
        }
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

        guard let bufferIndex = slotQueue.acquireFreeSlot() else {
            // Counted by the slot queue; logged from the worker thread.
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

        slotQueue.enqueue(bufferIndex)
    }

    func close() throws {
        lifecycleLock.lock()
        guard !isClosed else {
            lifecycleLock.unlock()
            return
        }
        isClosed = true
        lifecycleLock.unlock()

        // Flush queued frames. Safe if invoked from the worker thread itself
        // (deinit after the last frame): drainAndStop doesn't wait then.
        slotQueue?.drainAndStop()
        try fileHandle.synchronize()
        try updateFrameCount()
        if fileFormatVersion >= MeasurementDataFormat.version3 {
            try finalizeV3Trailer()
        }
        try fileHandle.synchronize()
        try fileHandle.close()
    }

    /// Runs on the writer worker thread. Writes one frame at the tracked offset; on
    /// failure truncates back to the last good frame and stops appending
    /// (DL-5). Checkpoints the header frame count periodically (DL-4).
    private func performFrameWrite(_ frameBuffer: MeasurementFrameBuffer) {
        if writeFailed { return }
        let goodOffset = nextFrameOffset
        let data = frameBuffer.values.withUnsafeBytes { Data($0) }
        do {
            try fileHandle.seek(toOffset: goodOffset)
            try fileHandle.write(contentsOf: data)
            nextFrameOffset = goodOffset + UInt64(data.count)
            let count = incrementFrameCount()
            if count % checkpointInterval == 0 {
                checkpointFrameCount(count)
            }
        } catch {
            NSLog("MeasurementDataWriter: frame write failed, truncating to last good frame: %@", String(describing: error))
            try? fileHandle.truncate(atOffset: goodOffset)
            counterLock.withLockUnchecked { _ in
                _writeFailed = true
                _droppedFrameCount += 1
            }
        }
    }

    /// Positional header patch that does not move the handle's offset.
    private func checkpointFrameCount(_ count: UInt64) {
        var le = count.littleEndian
        let fd = fileHandle.fileDescriptor
        let written = withUnsafeBytes(of: &le) { raw in
            pwrite(fd, raw.baseAddress, raw.count, off_t(MeasurementDataFormat.frameCountOffset))
        }
        if written != MemoryLayout<UInt64>.size {
            NSLog("MeasurementDataWriter: frame-count checkpoint failed")
        }
    }

    private func finalizeV3Trailer() throws {
        let count = frameCount
        guard count > 0 else { return }

        let indexOffset = UInt64(headerByteCount) + count * UInt64(frameSize)
        let offsets = (0..<count).map { index in
            UInt64(headerByteCount) + UInt64(index) * UInt64(frameSize)
        }
        try fileHandle.seek(toOffset: indexOffset)
        try fileHandle.write(contentsOf: MeasurementDataV3Support.encodeSeekIndex(frameOffsets: offsets))

        try fileHandle.seek(toOffset: UInt64(MeasurementDataFormat.v3SeekIndexOffsetField))
        var seekPatch = Data()
        seekPatch.appendUInt64LE(indexOffset)
        try fileHandle.write(contentsOf: seekPatch)

        let finalizedFlags = headerFlags | MeasurementDataFormat.flagHasSeekIndex
        try fileHandle.seek(toOffset: UInt64(MeasurementDataFormat.flagsOffset))
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

    @discardableResult
    private func incrementFrameCount() -> UInt64 {
        counterLock.withLockUnchecked { _ in
            _frameCount += 1
            return _frameCount
        }
    }

    /// Worker thread only.
    private func logDropsIfNeeded() {
        let dropped = droppedFrameCount
        if dropped >= lastLoggedDrops + 32 {
            lastLoggedDrops = dropped
            NSLog("[MeasurementDataWriter] dropped %llu frames (queue full)", dropped)
        }
    }
}

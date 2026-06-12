import Foundation

final class MeasurementDataReader {
    let fileURL: URL
    let header: MeasurementDataHeader
    let frameSize: Int
    let summaryFrameSize: Int

    private let fileHandle: FileHandle
    private let frameStartOffset: UInt64
    private let frameOffsets: [UInt64]?

    var frameCount: Int {
        Int(header.frameCount)
    }

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.fileHandle = try FileHandle(forReadingFrom: fileURL)

        let fixedHeader = try MeasurementDataReader.readExactly(
            MeasurementDataFormat.fixedHeaderSize, from: fileHandle)
        var cursor = MeasurementDataCursor(data: fixedHeader)

        let magic = try cursor.readUInt32()
        guard magic == MeasurementDataFormat.magic else {
            throw MeasurementDataError.invalidMagic
        }
        let version = try cursor.readUInt16()
        guard MeasurementDataFormat.isSupportedReadVersion(version) else {
            throw MeasurementDataError.unsupportedVersion(version)
        }

        let fftBinCountField = Int(try cursor.readUInt16())
        let frameCount = try cursor.readUInt64()
        let sampleRate = try cursor.readDouble()
        let fps = try cursor.readFloat()
        let fftBlockSize = Int(try cursor.readUInt32())
        let metricCount = Int(try cursor.readUInt16())
        let flags = try cursor.readUInt16()

        var headerCRC32: UInt32 = 0
        var seekIndexOffset: UInt64 = 0
        var tlvSectionLength = 0
        if version >= MeasurementDataFormat.version3 {
            let v3Extension = try MeasurementDataReader.readExactly(
                MeasurementDataFormat.v3FixedHeaderSize - MeasurementDataFormat.fixedHeaderSize,
                from: fileHandle
            )
            var v3Cursor = MeasurementDataCursor(data: v3Extension)
            headerCRC32 = try v3Cursor.readUInt32()
            seekIndexOffset = try v3Cursor.readUInt64()
            tlvSectionLength = Int(try v3Cursor.readUInt32())
        }

        let fftBinCount = version >= 2 ? fftBinCountField : 0
        let resolvedFlags: UInt16 = version >= 2 ? flags : 0

        var metricKeys: [String] = []
        metricKeys.reserveCapacity(metricCount)
        var bytesConsumed = version >= MeasurementDataFormat.version3
            ? MeasurementDataFormat.v3FixedHeaderSize
            : MeasurementDataFormat.fixedHeaderSize
        for _ in 0..<metricCount {
            let lengthData = try MeasurementDataReader.readExactly(2, from: fileHandle)
            var lengthCursor = MeasurementDataCursor(data: lengthData)
            let length = Int(try lengthCursor.readUInt16())
            let keyData = try MeasurementDataReader.readExactly(length, from: fileHandle)
            var keyCursor = MeasurementDataCursor(data: keyData)
            let key = try keyCursor.readUTF8String(length: length)
            metricKeys.append(key)
            bytesConsumed += 2 + length
        }

        var calibration: MeasurementCalibrationMetadata?
        if tlvSectionLength > 0 {
            let tlvData = try MeasurementDataReader.readExactly(tlvSectionLength, from: fileHandle)
            calibration = MeasurementDataV3Support.decodeTLV(tlvData)
            bytesConsumed += tlvSectionLength
        }

        if version >= MeasurementDataFormat.version3, headerCRC32 != 0 {
            try fileHandle.seek(toOffset: 0)
            let headerBytes = try MeasurementDataReader.readExactly(bytesConsumed, from: fileHandle)
            let expected = MeasurementDataV3Support.headerCRC32(for: headerBytes)
            guard expected == headerCRC32 else {
                throw MeasurementDataError.invalidChecksum
            }
        }

        self.header = MeasurementDataHeader(
            version: version,
            frameCount: frameCount,
            metricKeys: metricKeys,
            sampleRate: sampleRate,
            fps: fps,
            fftBlockSize: fftBlockSize,
            fftBinCount: fftBinCount,
            flags: resolvedFlags,
            headerSize: bytesConsumed,
            headerCRC32: headerCRC32,
            seekIndexOffset: seekIndexOffset,
            calibration: calibration
        )
        self.frameStartOffset = UInt64(bytesConsumed)
        let fullFftCount = header.hasFullFFT ? header.fftBinCount : 0
        self.summaryFrameSize = MemoryLayout<Float>.size
            * (1 + metricKeys.count + 1 + (MeasurementDataFormat.thirdOctaveBandCount * 3))
        self.frameSize = MemoryLayout<Float>.size
            * (1 + metricKeys.count + 1 + (MeasurementDataFormat.thirdOctaveBandCount * 3) + fullFftCount)

        if header.hasSeekIndex, seekIndexOffset > 0, frameCount > 0 {
            try fileHandle.seek(toOffset: seekIndexOffset)
            let indexByteCount = 12 + Int(frameCount) * MemoryLayout<UInt64>.size
            let indexData = try MeasurementDataReader.readExactly(indexByteCount, from: fileHandle)
            if let offsets = MeasurementDataV3Support.decodeSeekIndex(from: indexData),
               offsets.count == Int(frameCount) {
                self.frameOffsets = offsets
            } else {
                self.frameOffsets = nil
            }
        } else {
            self.frameOffsets = nil
        }
    }

    deinit {
        try? fileHandle.close()
    }

    func readFrame(at index: Int) throws -> MeasurementFrame {
        try readFrame(at: index, includingFullFFT: true)
    }

    func readFrameSummary(at index: Int) throws -> MeasurementFrame {
        try readFrame(at: index, includingFullFFT: false)
    }

    private func readFrame(at index: Int, includingFullFFT: Bool) throws -> MeasurementFrame {
        guard index >= 0, index < frameCount, frameSize >= 0 else {
            throw MeasurementDataError.invalidFrameIndex
        }

        let offset: UInt64
        if let frameOffsets, index < frameOffsets.count {
            offset = frameOffsets[index]
        } else {
            let (mul, mulOverflow) = UInt64(index).multipliedReportingOverflow(by: UInt64(frameSize))
            let (computed, addOverflow) = frameStartOffset.addingReportingOverflow(mul)
            guard !mulOverflow, !addOverflow else {
                throw MeasurementDataError.invalidFrameIndex
            }
            offset = computed
        }

        try fileHandle.seek(toOffset: offset)
        let bytesToRead = includingFullFFT ? frameSize : summaryFrameSize
        guard let frameData = try fileHandle.read(upToCount: bytesToRead), frameData.count == bytesToRead else {
            throw MeasurementDataError.ioFailure("Frame konnte nicht vollständig gelesen werden.")
        }
        return try decodeFrame(from: frameData, includingFullFFT: includingFullFFT)
    }

    func readFrames(in range: Range<Int>) throws -> [MeasurementFrame] {
        guard !range.isEmpty else { return [] }
        var frames: [MeasurementFrame] = []
        frames.reserveCapacity(range.count)
        for index in range {
            frames.append(try readFrame(at: index))
        }
        return frames
    }

    func forEachFrame(_ body: (Int, MeasurementFrame) throws -> Void) throws {
        for index in 0..<frameCount {
            let frame = try readFrame(at: index)
            try body(index, frame)
        }
    }

    /// Reads exactly `count` bytes from the file handle at its current offset.
    /// Throws `ioFailure` if the file ends before `count` bytes are available.
    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        guard count >= 0 else { return Data() }
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw MeasurementDataError.ioFailure("Header konnte nicht vollständig gelesen werden.")
        }
        return data
    }

    private func decodeFrame(from data: Data, includingFullFFT: Bool) throws -> MeasurementFrame {
        var cursor = MeasurementDataCursor(data: data)
        let timestamp = try cursor.readFloat()

        var metrics: [Float] = []
        metrics.reserveCapacity(header.metricKeys.count)
        for _ in 0..<header.metricKeys.count {
            metrics.append(try cursor.readFloat())
        }

        let broadbandLevel = try cursor.readFloat()

        var z = [Float](repeating: -120.0, count: MeasurementDataFormat.thirdOctaveBandCount)
        var a = [Float](repeating: -120.0, count: MeasurementDataFormat.thirdOctaveBandCount)
        var c = [Float](repeating: -120.0, count: MeasurementDataFormat.thirdOctaveBandCount)
        for i in 0..<MeasurementDataFormat.thirdOctaveBandCount { z[i] = try cursor.readFloat() }
        for i in 0..<MeasurementDataFormat.thirdOctaveBandCount { a[i] = try cursor.readFloat() }
        for i in 0..<MeasurementDataFormat.thirdOctaveBandCount { c[i] = try cursor.readFloat() }

        var fullFFT: [Float] = []
        if includingFullFFT && header.hasFullFFT && header.fftBinCount > 0 {
            fullFFT = [Float](repeating: -120.0, count: header.fftBinCount)
            for i in 0..<header.fftBinCount { fullFFT[i] = try cursor.readFloat() }
        }

        return MeasurementFrame(
            timestamp: timestamp,
            metrics: metrics,
            broadbandLevel: broadbandLevel,
            thirdOctaveZ: z,
            thirdOctaveA: a,
            thirdOctaveC: c,
            fullFFT: fullFFT
        )
    }
}

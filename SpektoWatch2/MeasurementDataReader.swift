import Foundation

final class MeasurementDataReader {
    let fileURL: URL
    let header: MeasurementDataHeader
    let frameSize: Int

    private let fileHandle: FileHandle
    private let frameStartOffset: UInt64

    var frameCount: Int {
        Int(header.frameCount)
    }

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.fileHandle = try FileHandle(forReadingFrom: fileURL)

        let fullData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        var cursor = MeasurementDataCursor(data: fullData)

        let magic = try cursor.readUInt32()
        guard magic == MeasurementDataFormat.magic else {
            throw MeasurementDataError.invalidMagic
        }
        let version = try cursor.readUInt16()
        guard version == 1 || version == MeasurementDataFormat.version else {
            throw MeasurementDataError.unsupportedVersion(version)
        }

        let fftBinCountField = Int(try cursor.readUInt16())
        let frameCount = try cursor.readUInt64()
        let sampleRate = try cursor.readDouble()
        let fps = try cursor.readFloat()
        let fftBlockSize = Int(try cursor.readUInt32())
        let metricCount = Int(try cursor.readUInt16())
        let flags = try cursor.readUInt16()
        let fftBinCount = version >= 2 ? fftBinCountField : 0
        let resolvedFlags: UInt16 = version >= 2 ? flags : 0

        var metricKeys: [String] = []
        metricKeys.reserveCapacity(metricCount)
        for _ in 0..<metricCount {
            let length = Int(try cursor.readUInt16())
            let key = try cursor.readUTF8String(length: length)
            metricKeys.append(key)
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
            headerSize: cursor.offset
        )
        self.frameStartOffset = UInt64(cursor.offset)
        let fullFftCount = header.hasFullFFT ? header.fftBinCount : 0
        self.frameSize = MemoryLayout<Float>.size
            * (1 + metricKeys.count + 1 + (MeasurementDataFormat.thirdOctaveBandCount * 3) + fullFftCount)
    }

    deinit {
        try? fileHandle.close()
    }

    func readFrame(at index: Int) throws -> MeasurementFrame {
        guard index >= 0, index < frameCount else {
            throw MeasurementDataError.invalidFrameIndex
        }
        let offset = frameStartOffset + UInt64(index * frameSize)
        try fileHandle.seek(toOffset: offset)
        guard let frameData = try fileHandle.read(upToCount: frameSize), frameData.count == frameSize else {
            throw MeasurementDataError.ioFailure("Frame konnte nicht vollständig gelesen werden.")
        }
        return try decodeFrame(from: frameData)
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

    private func decodeFrame(from data: Data) throws -> MeasurementFrame {
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
        if header.hasFullFFT && header.fftBinCount > 0 {
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

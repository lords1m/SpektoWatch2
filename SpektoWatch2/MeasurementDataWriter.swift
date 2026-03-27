import Foundation

final class MeasurementDataWriter {
    let fileURL: URL
    let metricKeys: [String]
    let sampleRate: Double
    let fps: Float
    let fftBlockSize: Int

    private let fileHandle: FileHandle
    private let frameSize: Int
    private(set) var frameCount: UInt64 = 0
    private var isClosed = false

    init(
        fileURL: URL,
        metricKeys: [String],
        sampleRate: Double,
        fps: Float,
        fftBlockSize: Int
    ) throws {
        self.fileURL = fileURL
        self.metricKeys = metricKeys
        self.sampleRate = sampleRate
        self.fps = fps
        self.fftBlockSize = fftBlockSize
        self.frameSize = MemoryLayout<Float>.size * (1 + metricKeys.count + 1 + (MeasurementDataFormat.thirdOctaveBandCount * 3))

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
        thirdOctaveC: [Float]
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

        var frame = Data(capacity: frameSize)
        frame.appendFloatLE(timestamp)
        metricValues.forEach { frame.appendFloatLE($0) }
        frame.appendFloatLE(broadbandLevel)
        thirdOctaveZ.forEach { frame.appendFloatLE($0) }
        thirdOctaveA.forEach { frame.appendFloatLE($0) }
        thirdOctaveC.forEach { frame.appendFloatLE($0) }

        fileHandle.write(frame)
        frameCount += 1
    }

    func close() throws {
        guard !isClosed else { return }
        isClosed = true
        try fileHandle.synchronize()
        try updateFrameCount()
        try fileHandle.close()
    }

    private func writeHeader(frameCount: UInt64) throws {
        var header = Data(capacity: MeasurementDataFormat.fixedHeaderSize + (metricKeys.count * 16))
        header.appendUInt32LE(MeasurementDataFormat.magic)
        header.appendUInt16LE(MeasurementDataFormat.version)
        header.appendUInt16LE(0) // reserved
        header.appendUInt64LE(frameCount)
        header.appendDoubleLE(sampleRate)
        header.appendFloatLE(fps)
        header.appendUInt32LE(UInt32(max(1, fftBlockSize)))
        header.appendUInt16LE(UInt16(min(metricKeys.count, Int(UInt16.max))))
        header.appendUInt16LE(0) // reserved

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


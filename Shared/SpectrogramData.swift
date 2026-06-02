import Foundation

public enum MicrophoneSource: String, Codable, CaseIterable {
    case iPhone = "iPhone"
    case appleWatch = "Apple Watch"
}

public struct SpectrogramData: Codable {
    public let frequencies: [Float]
    public let magnitudes: [Float]       // Z-gewichtet (ungewichtet/linear)
    public let magnitudesA: [Float]?     // A-gewichtet
    public let magnitudesC: [Float]?     // C-gewichtet
    public let visualFrequencies: [Float]?
    public let visualMagnitudes: [Float]?
    /// 31 third-octave SPL bands (Z). Optional watch→phone extension.
    public let thirdOctaveBandsZ: [Float]?
    public let thirdOctaveBandsA: [Float]?
    public let thirdOctaveBandsC: [Float]?
    /// Per-band Leq EMA (31 thirds). Optional watch→phone extension.
    public let bandLeqZ: [Float]?
    public let bandLeqA: [Float]?
    public let bandLeqC: [Float]?
    /// 24 Bark bands (Z). Optional watch→phone extension.
    public let barkBandsZ: [Float]?
    public let broadbandLevel: Float
    public let levels: [String: Float]
    public let timestamp: Date
    public let sampleRate: Double

    public init(
        frequencies: [Float],
        magnitudes: [Float],
        magnitudesA: [Float]? = nil,
        magnitudesC: [Float]? = nil,
        visualFrequencies: [Float]? = nil,
        visualMagnitudes: [Float]? = nil,
        thirdOctaveBandsZ: [Float]? = nil,
        thirdOctaveBandsA: [Float]? = nil,
        thirdOctaveBandsC: [Float]? = nil,
        bandLeqZ: [Float]? = nil,
        bandLeqA: [Float]? = nil,
        bandLeqC: [Float]? = nil,
        barkBandsZ: [Float]? = nil,
        broadbandLevel: Float = -120.0,
        levels: [String: Float] = [:],
        sampleRate: Double,
        timestamp: Date = Date()
    ) {
        self.frequencies = frequencies
        self.magnitudes = magnitudes
        self.magnitudesA = magnitudesA
        self.magnitudesC = magnitudesC
        self.visualFrequencies = visualFrequencies
        self.visualMagnitudes = visualMagnitudes
        self.thirdOctaveBandsZ = thirdOctaveBandsZ
        self.thirdOctaveBandsA = thirdOctaveBandsA
        self.thirdOctaveBandsC = thirdOctaveBandsC
        self.bandLeqZ = bandLeqZ
        self.bandLeqA = bandLeqA
        self.bandLeqC = bandLeqC
        self.barkBandsZ = barkBandsZ
        self.broadbandLevel = broadbandLevel
        self.levels = levels
        self.timestamp = timestamp
        self.sampleRate = sampleRate
    }

    /// Gibt die Magnituden für die gewählte Bewertungskurve zurück.
    /// Falls back to Z (unweighted) when the requested weighting array is nil.
    /// In DEBUG builds, logs a warning when fallback occurs — a fallback during
    /// live rendering means the widget's weighting requirement was not registered
    /// in `widgetSpectralWeightingRequirements` before the frame arrived (R5).
    public func magnitudes(for weighting: String) -> [Float] {
        switch weighting.uppercased() {
        case "A":
            if let a = magnitudesA { return a }
            #if DEBUG
            print("[SpectrogramData] magnitudes(for:\"A\") fallback to Z — A-weighting not computed this frame (R5: check widgetSpectralWeightingRequirements)")
            #endif
            return magnitudes
        case "C":
            if let c = magnitudesC { return c }
            #if DEBUG
            print("[SpectrogramData] magnitudes(for:\"C\") fallback to Z — C-weighting not computed this frame (R5: check widgetSpectralWeightingRequirements)")
            #endif
            return magnitudes
        default: // "Z" oder andere
            return magnitudes
        }
    }

    // MARK: - Binary Encoding
    //
    // Wire format (M13 task-7):
    //   [0] version: UInt8 = currentVersion (0x01)
    //   [1..] payload — Float broadbandLevel, Double sampleRate, etc.
    //
    // Trailing float arrays (count-prefixed, empty = absent) after magnitudesC:
    //   thirdOctaveBandsZ/A/C, bandLeqZ/A/C, barkBandsZ

    /// Current spectrogram-payload schema version. Bump on any
    /// breaking layout change to fields after this byte.
    public static let currentSchemaVersion: UInt8 = 0x01

    public func toBinaryData() -> Data {
        var data = Data()

        data.append(Self.currentSchemaVersion)

        var level = broadbandLevel
        data.append(Data(bytes: &level, count: MemoryLayout<Float>.size))

        var rate = sampleRate
        data.append(Data(bytes: &rate, count: MemoryLayout<Double>.size))

        var magCount = Int32(magnitudes.count)
        data.append(Data(bytes: &magCount, count: MemoryLayout<Int32>.size))
        magnitudes.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                data.append(Data(bytes: baseAddress, count: magnitudes.count * MemoryLayout<Float>.size))
            }
        }

        var freqCount = Int32(frequencies.count)
        data.append(Data(bytes: &freqCount, count: MemoryLayout<Int32>.size))
        frequencies.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                data.append(Data(bytes: baseAddress, count: frequencies.count * MemoryLayout<Float>.size))
            }
        }

        var levelsCount = Int32(levels.count)
        data.append(Data(bytes: &levelsCount, count: MemoryLayout<Int32>.size))
        for (key, value) in levels {
            let keyData = key.data(using: .utf8) ?? Data()
            var keyLen = Int32(keyData.count)
            data.append(Data(bytes: &keyLen, count: MemoryLayout<Int32>.size))
            data.append(keyData)
            var val = value
            data.append(Data(bytes: &val, count: MemoryLayout<Float>.size))
        }

        appendFloatArray(visualMagnitudes ?? [], to: &data)
        appendFloatArray(visualFrequencies ?? [], to: &data)
        appendFloatArray(magnitudesA ?? [], to: &data)
        appendFloatArray(magnitudesC ?? [], to: &data)
        appendFloatArray(thirdOctaveBandsZ ?? [], to: &data)
        appendFloatArray(thirdOctaveBandsA ?? [], to: &data)
        appendFloatArray(thirdOctaveBandsC ?? [], to: &data)
        appendFloatArray(bandLeqZ ?? [], to: &data)
        appendFloatArray(bandLeqA ?? [], to: &data)
        appendFloatArray(bandLeqC ?? [], to: &data)
        appendFloatArray(barkBandsZ ?? [], to: &data)

        return data
    }

    private func appendFloatArray(_ values: [Float], to data: inout Data) {
        var count = Int32(values.count)
        data.append(Data(bytes: &count, count: MemoryLayout<Int32>.size))
        values.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                data.append(Data(bytes: baseAddress, count: values.count * MemoryLayout<Float>.size))
            }
        }
    }

    public static func fromBinaryData(_ data: Data) -> SpectrogramData? {
        let floatSize = MemoryLayout<Float>.size
        let doubleSize = MemoryLayout<Double>.size
        let int32Size = MemoryLayout<Int32>.size

        func canReadByteCount(_ byteCount: Int, _ offset: Int, _ total: Int) -> Bool {
            guard byteCount >= 0, offset >= 0 else { return false }
            return offset <= total - byteCount
        }

        func readInt32(_ bytes: Data, _ offset: inout Int) -> Int32? {
            guard canReadByteCount(int32Size, offset, bytes.count) else { return nil }
            var value: Int32 = 0
            _ = withUnsafeMutableBytes(of: &value) { destination in
                bytes.copyBytes(to: destination, from: offset..<(offset + int32Size))
            }
            offset += int32Size
            return Int32(littleEndian: value)
        }

        func readFloat(_ bytes: Data, _ offset: inout Int) -> Float? {
            guard canReadByteCount(floatSize, offset, bytes.count) else { return nil }
            var bits: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &bits) { destination in
                bytes.copyBytes(to: destination, from: offset..<(offset + floatSize))
            }
            offset += floatSize
            return Float(bitPattern: UInt32(littleEndian: bits))
        }

        func readDouble(_ bytes: Data, _ offset: inout Int) -> Double? {
            guard canReadByteCount(doubleSize, offset, bytes.count) else { return nil }
            var bits: UInt64 = 0
            _ = withUnsafeMutableBytes(of: &bits) { destination in
                bytes.copyBytes(to: destination, from: offset..<(offset + doubleSize))
            }
            offset += doubleSize
            return Double(bitPattern: UInt64(littleEndian: bits))
        }

        func readFloatArray(_ bytes: Data, _ offset: inout Int) -> [Float]? {
            guard let countRaw = readInt32(bytes, &offset) else { return nil }
            guard countRaw >= 0 else { return nil }
            let count = Int(countRaw)
            guard count > 0 else { return [] }
            let byteCount = count * floatSize
            guard canReadByteCount(byteCount, offset, bytes.count) else { return nil }
            let values = bytes.withUnsafeBytes {
                Array(UnsafeBufferPointer(start: $0.baseAddress!.advanced(by: offset).bindMemory(to: Float.self, capacity: count), count: count))
            }
            offset += byteCount
            return values
        }

        func readOptionalFloatArray(_ bytes: Data, _ offset: inout Int) -> [Float]? {
            guard offset < bytes.count else { return nil }
            guard let values = readFloatArray(bytes, &offset) else { return nil }
            return values.isEmpty ? nil : values
        }

        var offset = 0

        guard data.count > 0 else { return nil }
        let version = data[data.startIndex]
        guard version == SpectrogramData.currentSchemaVersion else {
            print("[SpectrogramData] Unknown schema version \(version); expected \(SpectrogramData.currentSchemaVersion) — dropping payload")
            return nil
        }
        offset = 1

        guard let broadbandLevel = readFloat(data, &offset) else { return nil }
        guard let sampleRate = readDouble(data, &offset) else { return nil }

        guard let magCountRaw = readInt32(data, &offset) else { return nil }
        guard magCountRaw >= 0 else { return nil }
        let magCount = Int(magCountRaw)

        let magByteCount = magCount * floatSize
        guard canReadByteCount(magByteCount, offset, data.count) else { return nil }
        let magnitudes = data.withUnsafeBytes {
            Array(UnsafeBufferPointer(start: $0.baseAddress!.advanced(by: offset).bindMemory(to: Float.self, capacity: magCount), count: magCount))
        }
        offset += magByteCount

        guard let freqCountRaw = readInt32(data, &offset) else { return nil }
        guard freqCountRaw >= 0 else { return nil }
        let freqCount = Int(freqCountRaw)

        let freqByteCount = freqCount * floatSize
        guard canReadByteCount(freqByteCount, offset, data.count) else { return nil }
        let frequencies = data.withUnsafeBytes {
            Array(UnsafeBufferPointer(start: $0.baseAddress!.advanced(by: offset).bindMemory(to: Float.self, capacity: freqCount), count: freqCount))
        }
        offset += freqByteCount

        guard let levelsCountRaw = readInt32(data, &offset) else { return nil }
        guard levelsCountRaw >= 0 else { return nil }
        let levelsCount = Int(levelsCountRaw)

        var levels = [String: Float]()
        for _ in 0..<levelsCount {
            guard let keyLenRaw = readInt32(data, &offset) else { return nil }
            guard keyLenRaw >= 0 else { return nil }
            let keyLen = Int(keyLenRaw)

            guard canReadByteCount(keyLen, offset, data.count) else { return nil }
            let keyData = data.subdata(in: offset..<offset+keyLen)
            guard let key = String(data: keyData, encoding: .utf8) else { return nil }
            offset += keyLen

            guard let val = readFloat(data, &offset) else { return nil }
            levels[key] = val
        }

        var visualMagnitudes: [Float]?
        var visualFrequencies: [Float]?
        if offset < data.count {
            guard let values = readFloatArray(data, &offset) else { return nil }
            visualMagnitudes = values.isEmpty ? nil : values
        }
        if offset < data.count {
            guard let values = readFloatArray(data, &offset) else { return nil }
            visualFrequencies = values.isEmpty ? nil : values
        }

        var magnitudesA: [Float]?
        var magnitudesC: [Float]?
        if offset < data.count {
            magnitudesA = readOptionalFloatArray(data, &offset)
        }
        if offset < data.count {
            magnitudesC = readOptionalFloatArray(data, &offset)
        }

        var thirdOctaveBandsZ: [Float]?
        var thirdOctaveBandsA: [Float]?
        var thirdOctaveBandsC: [Float]?
        var bandLeqZ: [Float]?
        var bandLeqA: [Float]?
        var bandLeqC: [Float]?
        var barkBandsZ: [Float]?
        if offset < data.count { thirdOctaveBandsZ = readOptionalFloatArray(data, &offset) }
        if offset < data.count { thirdOctaveBandsA = readOptionalFloatArray(data, &offset) }
        if offset < data.count { thirdOctaveBandsC = readOptionalFloatArray(data, &offset) }
        if offset < data.count { bandLeqZ = readOptionalFloatArray(data, &offset) }
        if offset < data.count { bandLeqA = readOptionalFloatArray(data, &offset) }
        if offset < data.count { bandLeqC = readOptionalFloatArray(data, &offset) }
        if offset < data.count { barkBandsZ = readOptionalFloatArray(data, &offset) }

        return SpectrogramData(
            frequencies: frequencies,
            magnitudes: magnitudes,
            magnitudesA: magnitudesA,
            magnitudesC: magnitudesC,
            visualFrequencies: visualFrequencies,
            visualMagnitudes: visualMagnitudes,
            thirdOctaveBandsZ: thirdOctaveBandsZ,
            thirdOctaveBandsA: thirdOctaveBandsA,
            thirdOctaveBandsC: thirdOctaveBandsC,
            bandLeqZ: bandLeqZ,
            bandLeqA: bandLeqA,
            bandLeqC: bandLeqC,
            barkBandsZ: barkBandsZ,
            broadbandLevel: broadbandLevel,
            levels: levels,
            sampleRate: sampleRate
        )
    }
}

public struct SpectrogramFrame: Identifiable {
    public let id = UUID()
    public let magnitudes: [Float]
    public let timestamp: Date

    public init(magnitudes: [Float], timestamp: Date) {
        self.magnitudes = magnitudes
        self.timestamp = timestamp
    }
}

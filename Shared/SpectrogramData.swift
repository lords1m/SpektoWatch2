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
        self.broadbandLevel = broadbandLevel
        self.levels = levels
        self.timestamp = timestamp
        self.sampleRate = sampleRate
    }

    /// Gibt die Magnituden für die gewählte Bewertungskurve zurück
    public func magnitudes(for weighting: String) -> [Float] {
        switch weighting.uppercased() {
        case "A":
            return magnitudesA ?? magnitudes
        case "C":
            return magnitudesC ?? magnitudes
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
    // Versioning rationale: prior to M13, payloads started directly
    // with the broadbandLevel Float and had no schema marker. The
    // outer `BinaryPacketKind` byte in `WatchConnectivityProtocol`
    // already provides packet-type dispatch; the new version byte
    // here lets the spectrogram payload itself evolve without
    // colliding with that. Old-build watches reading new-build
    // payloads will misparse and return nil; the receiver logs
    // "unknown protocol version" and keeps running.

    /// Current spectrogram-payload schema version. Bump on any
    /// breaking layout change to fields after this byte.
    public static let currentSchemaVersion: UInt8 = 0x01

    public func toBinaryData() -> Data {
        var data = Data()

        // 0. Schema version (UInt8 - 1 byte). MUST be the very first
        // byte; the decoder rejects unknown values before any field
        // parse.
        data.append(Self.currentSchemaVersion)

        // 1. Broadband Level (Float - 4 bytes)
        var level = broadbandLevel
        data.append(Data(bytes: &level, count: MemoryLayout<Float>.size))
        
        // 2. Sample Rate (Double - 8 bytes)
        var rate = sampleRate
        data.append(Data(bytes: &rate, count: MemoryLayout<Double>.size))
        
        // 3. Magnitudes Count (Int32 - 4 bytes)
        var magCount = Int32(magnitudes.count)
        data.append(Data(bytes: &magCount, count: MemoryLayout<Int32>.size))
        
        // 4. Magnitudes Data (Bulk copy)
        magnitudes.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                data.append(Data(bytes: baseAddress, count: magnitudes.count * MemoryLayout<Float>.size))
            }
        }
        
        // 5. Frequencies Count (Int32 - 4 bytes)
        var freqCount = Int32(frequencies.count)
        data.append(Data(bytes: &freqCount, count: MemoryLayout<Int32>.size))
        
        // 6. Frequencies Data (Bulk copy)
        frequencies.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                data.append(Data(bytes: baseAddress, count: frequencies.count * MemoryLayout<Float>.size))
            }
        }
        
        // 7. Levels Dictionary
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

        // Optional visual-only DCT payload. Kept after the v1 fields so older
        // receivers can ignore the trailing bytes and still parse measurements.
        appendFloatArray(visualMagnitudes ?? [], to: &data)
        appendFloatArray(visualFrequencies ?? [], to: &data)
        
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
        
        var offset = 0

        // 0. Schema version (UInt8 - 1 byte). Reject unknown versions
        // before any field parse — sender is on a different schema.
        guard data.count > 0 else { return nil }
        let version = data[data.startIndex]
        guard version == SpectrogramData.currentSchemaVersion else {
            // Future: when we ship a v2 layout, dispatch here.
            return nil
        }
        offset = 1

        // 1. Broadband Level
        guard let broadbandLevel = readFloat(data, &offset) else { return nil }
        
        // 2. Sample Rate
        guard let sampleRate = readDouble(data, &offset) else { return nil }
        
        // 3. Magnitudes
        guard let magCountRaw = readInt32(data, &offset) else { return nil }
        guard magCountRaw >= 0 else { return nil }
        let magCount = Int(magCountRaw)
        
        let magByteCount = magCount * floatSize
        guard canReadByteCount(magByteCount, offset, data.count) else { return nil }
        let magnitudes = data.withUnsafeBytes {
            Array(UnsafeBufferPointer(start: $0.baseAddress!.advanced(by: offset).bindMemory(to: Float.self, capacity: magCount), count: magCount))
        }
        offset += magByteCount
        
        // 4. Frequencies
        guard let freqCountRaw = readInt32(data, &offset) else { return nil }
        guard freqCountRaw >= 0 else { return nil }
        let freqCount = Int(freqCountRaw)
        
        let freqByteCount = freqCount * floatSize
        guard canReadByteCount(freqByteCount, offset, data.count) else { return nil }
        let frequencies = data.withUnsafeBytes {
            Array(UnsafeBufferPointer(start: $0.baseAddress!.advanced(by: offset).bindMemory(to: Float.self, capacity: freqCount), count: freqCount))
        }
        offset += freqByteCount
        
        // 5. Levels
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
        
        return SpectrogramData(
            frequencies: frequencies,
            magnitudes: magnitudes,
            visualFrequencies: visualFrequencies,
            visualMagnitudes: visualMagnitudes,
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

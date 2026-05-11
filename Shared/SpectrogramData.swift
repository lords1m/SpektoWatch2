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
    public let broadbandLevel: Float
    public let levels: [String: Float]
    public let timestamp: Date
    public let sampleRate: Double

    public init(frequencies: [Float], magnitudes: [Float], magnitudesA: [Float]? = nil, magnitudesC: [Float]? = nil, broadbandLevel: Float = -120.0, levels: [String: Float] = [:], sampleRate: Double, timestamp: Date = Date()) {
        self.frequencies = frequencies
        self.magnitudes = magnitudes
        self.magnitudesA = magnitudesA
        self.magnitudesC = magnitudesC
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
    
    public func toBinaryData() -> Data {
        var data = Data()
        
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
        
        return data
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
        
        var offset = 0
        
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
        
        return SpectrogramData(
            frequencies: frequencies,
            magnitudes: magnitudes,
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

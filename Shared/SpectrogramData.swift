import Foundation

public enum MicrophoneSource: String, Codable, CaseIterable {
    case iPhone = "iPhone"
    case appleWatch = "Apple Watch"
}

public struct SpectrogramData: Codable {
    public let frequencies: [Float]
    public let magnitudes: [Float]
    public let broadbandLevel: Float
    public let levels: [String: Float]
    public let timestamp: Date
    public let sampleRate: Double

    public init(frequencies: [Float], magnitudes: [Float], broadbandLevel: Float = -120.0, levels: [String: Float] = [:], sampleRate: Double) {
        self.frequencies = frequencies
        self.magnitudes = magnitudes
        self.broadbandLevel = broadbandLevel
        self.levels = levels
        self.timestamp = Date()
        self.sampleRate = sampleRate
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
        
        var offset = 0
        
        // 1. Broadband Level
        guard data.count >= offset + floatSize else { return nil }
        let broadbandLevel = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Float.self) }
        offset += floatSize
        
        // 2. Sample Rate
        guard data.count >= offset + doubleSize else { return nil }
        let sampleRate = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Double.self) }
        offset += doubleSize
        
        // 3. Magnitudes
        guard data.count >= offset + int32Size else { return nil }
        let magCount = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int32.self) })
        offset += int32Size
        
        let magByteCount = magCount * floatSize
        guard data.count >= offset + magByteCount else { return nil }
        let magnitudes = data.withUnsafeBytes {
            Array(UnsafeBufferPointer(start: $0.baseAddress!.advanced(by: offset).bindMemory(to: Float.self, capacity: magCount), count: magCount))
        }
        offset += magByteCount
        
        // 4. Frequencies
        guard data.count >= offset + int32Size else { return nil }
        let freqCount = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int32.self) })
        offset += int32Size
        
        let freqByteCount = freqCount * floatSize
        guard data.count >= offset + freqByteCount else { return nil }
        let frequencies = data.withUnsafeBytes {
            Array(UnsafeBufferPointer(start: $0.baseAddress!.advanced(by: offset).bindMemory(to: Float.self, capacity: freqCount), count: freqCount))
        }
        offset += freqByteCount
        
        // 5. Levels
        guard data.count >= offset + int32Size else { return nil }
        let levelsCount = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int32.self) })
        offset += int32Size
        
        var levels = [String: Float]()
        for _ in 0..<levelsCount {
            guard data.count >= offset + int32Size else { return nil }
            let keyLen = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int32.self) })
            offset += int32Size
            
            guard data.count >= offset + keyLen else { return nil }
            let keyData = data.subdata(in: offset..<offset+keyLen)
            guard let key = String(data: keyData, encoding: .utf8) else { return nil }
            offset += keyLen
            
            guard data.count >= offset + floatSize else { return nil }
            let val = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Float.self) }
            offset += floatSize
            
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

public struct AudioData: Codable {
    public let samples: [Float]
    public let sampleRate: Double
    public let timestamp: Date

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.timestamp = Date()
    }
    
    // MARK: - Binary Encoding
    
    public func toBinaryData() -> Data {
        var data = Data()
        
        // 1. Sample Rate (Double - 8 bytes)
        var rate = sampleRate
        data.append(Data(bytes: &rate, count: MemoryLayout<Double>.size))
        
        // 2. Sample Count (Int32 - 4 bytes)
        var count = Int32(samples.count)
        data.append(Data(bytes: &count, count: MemoryLayout<Int32>.size))
        
        // 3. Samples Data (Bulk copy)
        samples.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                data.append(Data(bytes: baseAddress, count: samples.count * MemoryLayout<Float>.size))
            }
        }
        
        return data
    }
    
    public static func fromBinaryData(_ data: Data) -> AudioData? {
        let doubleSize = MemoryLayout<Double>.size
        let int32Size = MemoryLayout<Int32>.size
        let floatSize = MemoryLayout<Float>.size
        
        var offset = 0
        
        // 1. Sample Rate
        guard data.count >= offset + doubleSize else { return nil }
        let sampleRate = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Double.self) }
        offset += doubleSize
        
        // 2. Sample Count
        guard data.count >= offset + int32Size else { return nil }
        let count = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int32.self) })
        offset += int32Size
        
        // 3. Samples
        let samplesByteCount = count * floatSize
        guard data.count >= offset + samplesByteCount else { return nil }
        let samples = data.withUnsafeBytes {
            Array(UnsafeBufferPointer(start: $0.baseAddress!.advanced(by: offset).bindMemory(to: Float.self, capacity: count), count: count))
        }
        
        return AudioData(samples: samples, sampleRate: sampleRate)
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

import Foundation

struct SpectrogramData: Codable {
    let frequencies: [Float]
    let magnitudes: [Float]
    let broadbandLevel: Float
    let levels: [String: Float]
    let sampleRate: Double
    
    // MARK: - Binary Encoding
    
    func toBinaryData() -> Data {
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
        // Format: Count(Int32) -> [KeyLen(Int32) + KeyBytes + Value(Float)]
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
    
    static func fromBinaryData(_ data: Data) -> SpectrogramData? {
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
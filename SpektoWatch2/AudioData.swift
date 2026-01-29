import Foundation

public struct AudioData: Codable {
    public let level: Float
    public let peakLevel: Float
    public let timestamp: TimeInterval
    public let samples: [Float]
    
    public init(level: Float, peakLevel: Float, timestamp: TimeInterval, samples: [Float] = []) {
        self.level = level
        self.peakLevel = peakLevel
        self.timestamp = timestamp
        self.samples = samples
    }
    
    // MARK: - Binary Encoding
    
    public func toBinaryData() -> Data {
        var data = Data()
        
        var lvl = level
        data.append(Data(bytes: &lvl, count: MemoryLayout<Float>.size))
        
        var peak = peakLevel
        data.append(Data(bytes: &peak, count: MemoryLayout<Float>.size))
        
        var time = timestamp
        data.append(Data(bytes: &time, count: MemoryLayout<TimeInterval>.size))
        
        // Samples (Bulk copy)
        samples.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                data.append(Data(bytes: baseAddress, count: samples.count * MemoryLayout<Float>.size))
            }
        }
        return data
    }
    
    public static func fromBinaryData(_ data: Data) -> AudioData? {
        let floatSize = MemoryLayout<Float>.size
        let timeSize = MemoryLayout<TimeInterval>.size
        
        guard data.count >= 2 * floatSize + timeSize else { return nil }
        
        var offset = 0
        let level = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Float.self) }
        offset += floatSize
        
        let peakLevel = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Float.self) }
        offset += floatSize
        
        let timestamp = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: TimeInterval.self) }
        
        offset += timeSize
        
        let remainingBytes = data.count - offset
        let sampleCount = remainingBytes / MemoryLayout<Float>.size
        let samples = data.withUnsafeBytes { Array(UnsafeBufferPointer(start: $0.baseAddress!.advanced(by: offset).bindMemory(to: Float.self, capacity: sampleCount), count: sampleCount)) }
        
        return AudioData(level: level, peakLevel: peakLevel, timestamp: timestamp, samples: samples)
    }
}

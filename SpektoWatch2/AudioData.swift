import Foundation

public struct AudioData: Codable {
    public let level: Float
    public let peakLevel: Float
    public let timestamp: TimeInterval
    
    public init(level: Float, peakLevel: Float, timestamp: TimeInterval) {
        self.level = level
        self.peakLevel = peakLevel
        self.timestamp = timestamp
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
        
        return AudioData(level: level, peakLevel: peakLevel, timestamp: timestamp)
    }
}

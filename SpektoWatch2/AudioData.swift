import Foundation

struct AudioData {
    let samples: [Float]
    let sampleRate: Double
    
    func toBinaryData() -> Data {
        var data = Data()
        var rate = sampleRate
        data.append(Data(bytes: &rate, count: MemoryLayout<Double>.size))
        
        samples.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                data.append(Data(bytes: baseAddress, count: samples.count * MemoryLayout<Float>.size))
            }
        }
        return data
    }
    
    static func fromBinaryData(_ data: Data) -> AudioData? {
        let doubleSize = MemoryLayout<Double>.size
        guard data.count >= doubleSize else { return nil }
        
        let sampleRate = data.withUnsafeBytes { $0.load(as: Double.self) }
        
        let floatSize = MemoryLayout<Float>.size
        let samplesCount = (data.count - doubleSize) / floatSize
        
        guard samplesCount > 0 else { return nil }
        
        let samples = data.withUnsafeBytes { buffer -> [Float] in
            let start = buffer.baseAddress!.advanced(by: doubleSize).bindMemory(to: Float.self, capacity: samplesCount)
            return Array(UnsafeBufferPointer(start: start, count: samplesCount))
        }
        
        return AudioData(samples: samples, sampleRate: sampleRate)
    }
}
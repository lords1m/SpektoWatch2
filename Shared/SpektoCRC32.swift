import Foundation
import zlib

enum SpektoCRC32 {
    /// IEEE CRC32 (PNG/zlib polynomial).
    static func checksum(_ data: Data) -> UInt32 {
        guard !data.isEmpty else { return 0 }
        return data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return 0 }
            return UInt32(crc32(0, base, uInt(buffer.count)))
        }
    }

    /// CRC over `data` with `zeroRange` bytes forced to zero (header CRC field).
    static func checksum(_ data: Data, zeroingRange zeroRange: Range<Int>) -> UInt32 {
        guard !data.isEmpty else { return 0 }
        var copy = data
        for index in zeroRange {
            guard copy.indices.contains(index) else { continue }
            copy[index] = 0
        }
        return checksum(copy)
    }
}

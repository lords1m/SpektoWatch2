import Foundation

enum MeasurementDataError: LocalizedError {
    case invalidMagic
    case unsupportedVersion(UInt16)
    case invalidHeader
    case metricCountMismatch(expected: Int, got: Int)
    case invalidFrameIndex
    case ioFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidMagic:
            return "Ungültiges .spekto-Format (Magic mismatch)."
        case .unsupportedVersion(let version):
            return "Nicht unterstützte .spekto-Version: \(version)."
        case .invalidHeader:
            return "Ungültiger .spekto-Header."
        case .metricCountMismatch(let expected, let got):
            return "Metrikanzahl passt nicht (erwartet \(expected), erhalten \(got))."
        case .invalidFrameIndex:
            return "Frame-Index außerhalb des gültigen Bereichs."
        case .ioFailure(let details):
            return "Dateifehler: \(details)"
        }
    }
}

enum MeasurementDataFormat {
    static let magic: UInt32 = 0x53504B54 // "SPKT"
    static let version: UInt16 = 2
    static let thirdOctaveBandCount = 31
    static let fixedHeaderSize = 36
    static let frameCountOffset = 8
    static let flagHasFullFFT: UInt16 = 1 << 0
}

struct MeasurementDataHeader {
    let version: UInt16
    let frameCount: UInt64
    let metricKeys: [String]
    let sampleRate: Double
    let fps: Float
    let fftBlockSize: Int
    let fftBinCount: Int
    let flags: UInt16
    let headerSize: Int

    var hasFullFFT: Bool { (flags & MeasurementDataFormat.flagHasFullFFT) != 0 }
}

struct MeasurementFrame {
    let timestamp: Float
    let metrics: [Float]
    let broadbandLevel: Float
    let thirdOctaveZ: [Float]
    let thirdOctaveA: [Float]
    let thirdOctaveC: [Float]
    let fullFFT: [Float]
}

extension MeasurementFrame {
    func value(forMetric key: String, using metricKeys: [String]) -> Float? {
        guard let index = metricKeys.firstIndex(of: key), index < metrics.count else { return nil }
        return metrics[index]
    }
}

extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt64LE(_ value: UInt64) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendFloatLE(_ value: Float) {
        appendUInt32LE(value.bitPattern)
    }

    mutating func appendDoubleLE(_ value: Double) {
        appendUInt64LE(value.bitPattern)
    }
}

struct MeasurementDataCursor {
    private let bytes: Data
    private(set) var offset: Int = 0

    init(data: Data) {
        self.bytes = data
    }

    mutating func readUInt16() throws -> UInt16 {
        guard offset + 2 <= bytes.count else { throw MeasurementDataError.invalidHeader }
        var value: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &value) { destination in
            bytes.copyBytes(to: destination, from: offset..<(offset + 2))
        }
        offset += 2
        return UInt16(littleEndian: value)
    }

    mutating func readUInt32() throws -> UInt32 {
        guard offset + 4 <= bytes.count else { throw MeasurementDataError.invalidHeader }
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { destination in
            bytes.copyBytes(to: destination, from: offset..<(offset + 4))
        }
        offset += 4
        return UInt32(littleEndian: value)
    }

    mutating func readUInt64() throws -> UInt64 {
        guard offset + 8 <= bytes.count else { throw MeasurementDataError.invalidHeader }
        var value: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &value) { destination in
            bytes.copyBytes(to: destination, from: offset..<(offset + 8))
        }
        offset += 8
        return UInt64(littleEndian: value)
    }

    mutating func readFloat() throws -> Float {
        let bits = try readUInt32()
        return Float(bitPattern: bits)
    }

    mutating func readDouble() throws -> Double {
        let bits = try readUInt64()
        return Double(bitPattern: bits)
    }

    mutating func readUTF8String(length: Int) throws -> String {
        guard length >= 0, offset + length <= bytes.count else { throw MeasurementDataError.invalidHeader }
        let chunk = bytes.subdata(in: offset..<(offset + length))
        offset += length
        return String(data: chunk, encoding: .utf8) ?? ""
    }
}

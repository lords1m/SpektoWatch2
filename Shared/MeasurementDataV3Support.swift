import Foundation

/// Calibration / provenance metadata stored in the v3 TLV header section.
struct MeasurementCalibrationMetadata: Equatable, Sendable {
    var microphoneSource: String?
    var gain: Float?
    var calibrationOffset: Float?
    var deviceModel: String?
    var frequencyWeighting: String?
}

enum MeasurementDataV3Support {

    enum TLVType: UInt16 {
        case microphoneSource = 1
        case gain = 2
        case calibrationOffset = 3
        case deviceModel = 4
        case frequencyWeighting = 5
    }

    static func encodeTLV(_ metadata: MeasurementCalibrationMetadata) -> Data {
        var data = Data()
        if let source = metadata.microphoneSource {
            appendTLV(type: .microphoneSource, utf8: source, to: &data)
        }
        if let gain = metadata.gain {
            appendTLV(type: .gain, float: gain, to: &data)
        }
        if let offset = metadata.calibrationOffset {
            appendTLV(type: .calibrationOffset, float: offset, to: &data)
        }
        if let model = metadata.deviceModel {
            appendTLV(type: .deviceModel, utf8: model, to: &data)
        }
        if let weighting = metadata.frequencyWeighting {
            appendTLV(type: .frequencyWeighting, utf8: weighting, to: &data)
        }
        return data
    }

    static func decodeTLV(_ data: Data) -> MeasurementCalibrationMetadata {
        var metadata = MeasurementCalibrationMetadata()
        var offset = 0
        let bytes = data
        while offset + 4 <= bytes.count {
            let typeRaw = readUInt16(bytes, &offset)
            let length = Int(readUInt16(bytes, &offset))
            guard length >= 0, offset + length <= bytes.count else { break }
            let value = bytes.subdata(in: offset..<(offset + length))
            offset += length
            guard let type = TLVType(rawValue: typeRaw) else { continue }
            switch type {
            case .microphoneSource:
                metadata.microphoneSource = String(data: value, encoding: .utf8)
            case .gain:
                metadata.gain = readFloat(value)
            case .calibrationOffset:
                metadata.calibrationOffset = readFloat(value)
            case .deviceModel:
                metadata.deviceModel = String(data: value, encoding: .utf8)
            case .frequencyWeighting:
                metadata.frequencyWeighting = String(data: value, encoding: .utf8)
            }
        }
        return metadata
    }

    static func headerCRC32(for headerBytes: Data) -> UInt32 {
        SpektoCRC32.checksum(
            headerBytes,
            zeroingRange: MeasurementDataFormat.v3HeaderCRCOffset..<(MeasurementDataFormat.v3HeaderCRCOffset + 4)
        )
    }

    static func encodeSeekIndex(frameOffsets: [UInt64]) -> Data {
        var data = Data()
        data.appendUInt32LE(MeasurementDataFormat.seekIndexMagic)
        data.appendUInt64LE(UInt64(frameOffsets.count))
        for offset in frameOffsets {
            data.appendUInt64LE(offset)
        }
        return data
    }

    static func decodeSeekIndex(from data: Data) -> [UInt64]? {
        guard data.count >= 12 else { return nil }
        var cursor = MeasurementDataCursor(data: data)
        guard (try? cursor.readUInt32()) == MeasurementDataFormat.seekIndexMagic else { return nil }
        guard let count = try? cursor.readUInt64(), count <= UInt64(Int.max) else { return nil }
        var offsets: [UInt64] = []
        offsets.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let offset = try? cursor.readUInt64() else { return nil }
            offsets.append(offset)
        }
        return offsets
    }

    // MARK: - Private

    private static func appendTLV(type: TLVType, utf8: String, to data: inout Data) {
        let payload = utf8.data(using: .utf8) ?? Data()
        appendTLV(type: type, payload: payload, to: &data)
    }

    private static func appendTLV(type: TLVType, float: Float, to data: inout Data) {
        var bits = float.bitPattern.littleEndian
        let payload = Data(bytes: &bits, count: MemoryLayout<UInt32>.size)
        appendTLV(type: type, payload: payload, to: &data)
    }

    private static func appendTLV(type: TLVType, payload: Data, to data: inout Data) {
        let length = UInt16(min(payload.count, Int(UInt16.max)))
        data.appendUInt16LE(type.rawValue)
        data.appendUInt16LE(length)
        data.append(payload.prefix(Int(length)))
    }

    private static func readUInt16(_ bytes: Data, _ offset: inout Int) -> UInt16 {
        guard offset + 2 <= bytes.count else { return 0 }
        var value: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &value) { destination in
            bytes.copyBytes(to: destination, from: offset..<(offset + 2))
        }
        offset += 2
        return UInt16(littleEndian: value)
    }

    private static func readFloat(_ bytes: Data) -> Float? {
        guard bytes.count == MemoryLayout<UInt32>.size else { return nil }
        var bits: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &bits) { destination in
            bytes.copyBytes(to: destination)
        }
        return Float(bitPattern: UInt32(littleEndian: bits))
    }
}

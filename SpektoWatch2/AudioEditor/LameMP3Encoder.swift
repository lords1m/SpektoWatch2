import AVFoundation
import Foundation
#if canImport(LAME)
import LAME
#endif

protocol MP3EncoderBackend: Sendable {
    func encodeToMP3(
        sourceURL: URL,
        destinationURL: URL,
        options: AudioExportOptions,
        progress: (@Sendable (Double) -> Void)?
    ) async throws
}

enum LameMP3EncoderError: LocalizedError {
    case unavailable
    case invalidSource
    case initializationFailed
    case encodeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable:           return "MP3-Encoder (LAME) ist auf diesem Ziel nicht verfügbar."
        case .invalidSource:         return "Die Quelldatei konnte nicht für MP3 gelesen werden."
        case .initializationFailed:  return "LAME MP3-Encoder konnte nicht initialisiert werden."
        case .encodeFailed(let code): return "MP3-Kodierung fehlgeschlagen (Code \(code))."
        }
    }
}

struct LameMP3Encoder: MP3EncoderBackend {
    private static let chunkSize: AVAudioFrameCount = 8192

    func encodeToMP3(
        sourceURL: URL,
        destinationURL: URL,
        options: AudioExportOptions,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        #if canImport(LAME)
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let inputFile = try AVAudioFile(forReading: sourceURL)
            let inputFormat = inputFile.processingFormat
            guard inputFile.length > 0, inputFormat.sampleRate > 0 else {
                throw LameMP3EncoderError.invalidSource
            }

            let outSampleRate = options.targetSampleRate ?? inputFormat.sampleRate
            let outChannels = options.downmixToMono ? 1 : max(1, min(2, Int(inputFormat.channelCount)))
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outSampleRate,
                channels: AVAudioChannelCount(outChannels),
                interleaved: false
            ) else {
                throw LameMP3EncoderError.invalidSource
            }

            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw LameMP3EncoderError.invalidSource
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
            let outHandle = try FileHandle(forWritingTo: destinationURL)

            var succeeded = false
            defer {
                try? outHandle.close()
                if !succeeded {
                    try? FileManager.default.removeItem(at: destinationURL)
                }
            }

            guard let gfp = lame_init() else {
                throw LameMP3EncoderError.initializationFailed
            }
            defer { lame_close(gfp) }

            lame_set_in_samplerate(gfp, Int32(outSampleRate))
            lame_set_out_samplerate(gfp, Int32(outSampleRate))
            lame_set_num_channels(gfp, Int32(outChannels))
            lame_set_mode(gfp, outChannels == 1 ? MONO : JOINT_STEREO)

            if options.useVBR {
                lame_set_VBR(gfp, vbr_default)
                lame_set_VBR_q(gfp, 2)
            } else {
                lame_set_VBR(gfp, vbr_off)
                lame_set_brate(gfp, Int32(options.bitrateKbps))
                lame_set_quality(gfp, 2)
            }

            id3tag_init(gfp)
            id3tag_v2_only(gfp)
            if !options.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                options.title.withCString { cStr in
                    id3tag_set_title(gfp, cStr)
                }
            }
            "SpektoWatch2 Audio-Editor".withCString { cStr in
                id3tag_set_comment(gfp, cStr)
            }

            guard lame_init_params(gfp) >= 0 else {
                throw LameMP3EncoderError.initializationFailed
            }

            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: Self.chunkSize),
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: Self.chunkSize * 2) else {
                throw LameMP3EncoderError.initializationFailed
            }

            let mp3Capacity = Int(1.25 * Double(Self.chunkSize * 2) + 7200)
            var mp3Buffer = [UInt8](repeating: 0, count: mp3Capacity)

            let totalSourceFrames = max(AVAudioFramePosition(1), inputFile.length)
            var reachedEOF = false

            while !reachedEOF {
                try Task.checkCancellation()

                var convError: NSError?
                let status = converter.convert(to: convertedBuffer, error: &convError) { _, outStatus in
                    if inputFile.framePosition >= inputFile.length {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    do {
                        inputBuffer.frameLength = 0
                        try inputFile.read(into: inputBuffer, frameCount: Self.chunkSize)
                        if inputBuffer.frameLength == 0 {
                            outStatus.pointee = .endOfStream
                            return nil
                        }
                        outStatus.pointee = .haveData
                        return inputBuffer
                    } catch {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                }

                if let convError { throw convError }

                let frames = Int(convertedBuffer.frameLength)
                if frames > 0, let channelData = convertedBuffer.floatChannelData {
                    let leftPtr = channelData[0]
                    let rightPtr = outChannels > 1 ? channelData[1] : channelData[0]

                    let encodedBytes: Int32 = mp3Buffer.withUnsafeMutableBytes { rawBuf in
                        guard let base = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                        return lame_encode_buffer_ieee_float(
                            gfp,
                            leftPtr,
                            rightPtr,
                            Int32(frames),
                            base,
                            Int32(mp3Capacity)
                        )
                    }

                    if encodedBytes < 0 {
                        throw LameMP3EncoderError.encodeFailed(encodedBytes)
                    }
                    if encodedBytes > 0 {
                        try outHandle.write(contentsOf: Data(mp3Buffer.prefix(Int(encodedBytes))))
                    }
                }

                progress?(min(0.95, Double(inputFile.framePosition) / Double(totalSourceFrames)))

                if status == .endOfStream || status == .error {
                    reachedEOF = true
                }
            }

            try Task.checkCancellation()
            let flushedBytes: Int32 = mp3Buffer.withUnsafeMutableBytes { rawBuf in
                guard let base = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return lame_encode_flush(gfp, base, Int32(mp3Capacity))
            }
            if flushedBytes < 0 {
                throw LameMP3EncoderError.encodeFailed(flushedBytes)
            }
            if flushedBytes > 0 {
                try outHandle.write(contentsOf: Data(mp3Buffer.prefix(Int(flushedBytes))))
            }

            try outHandle.synchronize()
            progress?(1.0)
            succeeded = true
        }.value
        #else
        throw LameMP3EncoderError.unavailable
        #endif
    }
}

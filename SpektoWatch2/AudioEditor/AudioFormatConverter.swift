import AVFoundation
import Foundation

enum AudioFormatConverterError: LocalizedError {
    case unreadableSource
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableSource:          return "Quelldatei konnte nicht konvertiert werden."
        case .conversionFailed(let msg): return "Format-Konvertierung fehlgeschlagen: \(msg)"
        }
    }
}

enum AudioFormatConverter {
    private static let chunkSize: AVAudioFrameCount = 8192

    /// Applies `recipe` offline and converts the rendered PCM audio into `options.format`.
    static func renderAndConvert(
        sourceURL: URL,
        recipe: AudioEditRecipe,
        options: AudioExportOptions,
        destinationURL: URL? = nil,
        mp3Backend: MP3EncoderBackend = LameMP3Encoder(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let finalURL = destinationURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("sw2_export_\(UUID().uuidString).\(options.format.fileExtension)")

        let renderedWAV = try await AudioEditRenderer.renderToTemporaryWAV(
            sourceURL: sourceURL,
            recipe: recipe
        ) { p in
            progress?(p * 0.60)
        }
        defer {
            try? FileManager.default.removeItem(at: renderedWAV)
        }

        return try await convert(
            sourceURL: renderedWAV,
            destinationURL: finalURL,
            options: options,
            mp3Backend: mp3Backend
        ) { p in
            progress?(0.60 + p * 0.40)
        }
    }

    static func convert(
        sourceURL: URL,
        destinationURL: URL,
        options: AudioExportOptions,
        mp3Backend: MP3EncoderBackend = LameMP3Encoder(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        if options.format == .mp3 {
            try await mp3Backend.encodeToMP3(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                options: options,
                progress: progress
            )
            return destinationURL
        }

        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let inputFile = try AVAudioFile(forReading: sourceURL)
            let inputFormat = inputFile.processingFormat
            guard inputFile.length > 0, inputFormat.sampleRate > 0 else {
                throw AudioFormatConverterError.unreadableSource
            }

            let outSampleRate = options.targetSampleRate ?? inputFormat.sampleRate
            let outChannels = options.downmixToMono ? 1 : max(1, min(2, Int(inputFormat.channelCount)))

            let outputSettings = buildOutputSettings(
                format: options.format,
                sampleRate: outSampleRate,
                channels: outChannels,
                bitDepth: options.pcmBitDepth,
                bitrateKbps: options.bitrateKbps
            )

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }

            var succeeded = false
            defer {
                if !succeeded {
                    try? FileManager.default.removeItem(at: destinationURL)
                }
            }

            let outputFile = try AVAudioFile(forWriting: destinationURL, settings: outputSettings)
            guard let targetPCMFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outSampleRate,
                channels: AVAudioChannelCount(outChannels),
                interleaved: outputFile.processingFormat.isInterleaved
            ),
            let converter = AVAudioConverter(from: inputFormat, to: targetPCMFormat),
            let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: chunkSize),
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetPCMFormat, frameCapacity: chunkSize * 2) else {
                throw AudioFormatConverterError.conversionFailed("AudioConverter konnte nicht erzeugt werden.")
            }

            let totalFrames = max(AVAudioFramePosition(1), inputFile.length)
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
                        try inputFile.read(into: inputBuffer, frameCount: chunkSize)
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

                if convertedBuffer.frameLength > 0 {
                    try outputFile.write(from: convertedBuffer)
                }

                progress?(min(0.98, Double(inputFile.framePosition) / Double(totalFrames)))

                if status == .endOfStream || status == .error {
                    reachedEOF = true
                }
            }

            progress?(1.0)
            succeeded = true
            return destinationURL
        }.value
    }

    private static func buildOutputSettings(
        format: AudioExportFormat,
        sampleRate: Double,
        channels: Int,
        bitDepth: Int,
        bitrateKbps: Int
    ) -> [String: Any] {
        switch format {
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: bitDepth,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .aiff:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: bitDepth,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: true,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .caf:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: bitDepth,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .m4aAAC:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: bitrateKbps * 1000,
            ]
        case .alac:
            return [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitDepthHintKey: 16,
            ]
        case .mp3:
            return [:]
        }
    }
}

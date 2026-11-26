import Accelerate
import AVFoundation
import Foundation

enum AudioEditRenderError: LocalizedError {
    case invalidSource
    case emptyOutput
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSource:         return "Die Quelldatei konnte nicht gelesen werden."
        case .emptyOutput:           return "Die bearbeitete Audiodatei ist leer."
        case .renderFailed(let msg): return "Rendering fehlgeschlagen: \(msg)"
        }
    }
}

enum AudioEditRenderer {
    private static let chunkSize: AVAudioFrameCount = 4096
    private static let crossfadeDuration: TimeInterval = 0.008 // 8 ms cosine micro-crossfade

    /// Renders `recipe` off the main thread to a temporary 32-bit float WAV file
    /// ready for format conversion or playback. Caller owns cleanup of returned URL.
    static func renderToTemporaryWAV(
        sourceURL: URL,
        recipe: AudioEditRecipe,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let inputFile = try AVAudioFile(forReading: sourceURL)
            let format = inputFile.processingFormat
            let sampleRate = format.sampleRate
            let totalSourceFrames = inputFile.length
            guard sampleRate > 0, totalSourceFrames > 0 else {
                throw AudioEditRenderError.invalidSource
            }

            let tempDir = FileManager.default.temporaryDirectory
            let splicedURL = tempDir.appendingPathComponent("sw2_splice_\(UUID().uuidString).caf")
            let outputURL = tempDir.appendingPathComponent("sw2_rendered_\(UUID().uuidString).wav")
            defer {
                try? FileManager.default.removeItem(at: splicedURL)
            }

            do {
                // Stage 1: Splice keptRanges + micro-crossfade + fade-in/out (0.0 ... 0.35)
                let splicedFrameCount = try writeSplicedPCM(
                    from: inputFile,
                    to: splicedURL,
                    format: format,
                    recipe: recipe
                ) { p in
                    progress?(p * 0.35)
                }

                guard splicedFrameCount > 0 else {
                    throw AudioEditRenderError.emptyOutput
                }
                try Task.checkCancellation()

                // Stage 2: Offline AVAudioEngine EQ/Filter/Gain pass (0.35 ... 0.85)
                try runOfflineEQPass(
                    inputURL: splicedURL,
                    outputURL: outputURL,
                    format: format,
                    frameCount: splicedFrameCount,
                    recipe: recipe
                ) { p in
                    progress?(0.35 + p * 0.50)
                }
                try Task.checkCancellation()

                // Stage 3: Optional two-pass peak normalization (0.85 ... 1.0)
                if recipe.normalizeEnabled || recipe.filters.enhanceVoiceEnabled {
                    try normalizeInPlaceIfNeeded(url: outputURL, targetPeakDBFS: -1.0)
                }
                progress?(1.0)
                return outputURL
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
        }.value
    }

    // MARK: - Stage 1: Segment concatenation + micro-crossfades + fades

    private static func writeSplicedPCM(
        from inputFile: AVAudioFile,
        to destinationURL: URL,
        format: AVAudioFormat,
        recipe: AudioEditRecipe,
        progress: (Double) -> Void
    ) throws -> AVAudioFramePosition {
        let sampleRate = format.sampleRate
        let channels = Int(format.channelCount)
        let totalSourceFrames = inputFile.length

        let segments: [(start: AVAudioFramePosition, end: AVAudioFramePosition)] = recipe.keptRanges.compactMap { range in
            let s = max(0, min(totalSourceFrames - 1, AVAudioFramePosition(range.start * sampleRate)))
            let e = max(s, min(totalSourceFrames, AVAudioFramePosition(range.end * sampleRate)))
            return (e > s) ? (s, e) : nil
        }

        guard !segments.isEmpty else {
            throw AudioEditRenderError.emptyOutput
        }

        let crossfadeFrames = AVAudioFramePosition(crossfadeDuration * sampleRate)
        let totalOutputEstimate = segments.reduce(AVAudioFramePosition(0)) { $0 + ($1.end - $1.start) }
        let fadeInFrames = AVAudioFramePosition(min(recipe.fadeInDuration * sampleRate, Double(totalOutputEstimate) * 0.45))
        let fadeOutFrames = AVAudioFramePosition(min(recipe.fadeOutDuration * sampleRate, Double(totalOutputEstimate) * 0.45))

        let floatSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            // File data is always interleaved (WAV/CAF can't hold planar
            // PCM); the processing format below stays planar to match the
            // read buffers.
            AVLinearPCMIsNonInterleaved: false,
        ]
        let outFile = try AVAudioFile(forWriting: destinationURL, settings: floatSettings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)

        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            throw AudioEditRenderError.renderFailed("Buffer konnte nicht allokiert werden.")
        }

        // Compute total frames written accounting for overlaps
        var totalWritten: AVAudioFramePosition = 0
        let totalUnfolded = max(1, totalOutputEstimate)
        var processedUnfolded: AVAudioFramePosition = 0

        for (segIndex, seg) in segments.enumerated() {
            let segLen = seg.end - seg.start
            let hasPrevJoin = segIndex > 0 && crossfadeFrames > 4 && segLen > crossfadeFrames * 2
            let hasNextJoin = (segIndex < segments.count - 1) && crossfadeFrames > 4 && segLen > crossfadeFrames * 2
            let fadeFramesHere = hasPrevJoin ? crossfadeFrames : 0
            let nextFadeFrames = hasNextJoin ? crossfadeFrames : 0

            inputFile.framePosition = seg.start
            var remaining = segLen
            var segOffset: AVAudioFramePosition = 0

            while remaining > 0 {
                try Task.checkCancellation()
                let toRead = AVAudioFrameCount(min(AVAudioFramePosition(chunkSize), remaining))
                readBuffer.frameLength = 0
                try inputFile.read(into: readBuffer, frameCount: toRead)
                let n = Int(readBuffer.frameLength)
                guard n > 0, let channelData = readBuffer.floatChannelData else { break }

                for i in 0..<n {
                    let posInSeg = segOffset + AVAudioFramePosition(i)
                    let globalPos = totalWritten + AVAudioFramePosition(i)
                    var env: Float = 1.0

                    // Micro fade-in at interior splice start
                    if hasPrevJoin && posInSeg < fadeFramesHere {
                        let t = Float(posInSeg) / Float(fadeFramesHere)
                        env *= 0.5 - 0.5 * cosf(.pi * t)
                    }
                    // Micro fade-out at interior splice end
                    if hasNextJoin && posInSeg >= (segLen - nextFadeFrames) {
                        let t = Float(segLen - posInSeg) / Float(nextFadeFrames)
                        env *= 0.5 - 0.5 * cosf(.pi * max(0, min(1, t)))
                    }
                    // User Fade-In
                    if fadeInFrames > 0 && globalPos < fadeInFrames {
                        env *= Float(globalPos) / Float(fadeInFrames)
                    }
                    // User Fade-Out
                    let distFromEnd = totalOutputEstimate - 1 - globalPos
                    if fadeOutFrames > 0 && distFromEnd >= 0 && distFromEnd < fadeOutFrames {
                        env *= Float(distFromEnd) / Float(fadeOutFrames)
                    }

                    if abs(env - 1.0) > 1e-5 {
                        for ch in 0..<channels {
                            channelData[ch][i] *= env
                        }
                    }
                }

                try outFile.write(from: readBuffer)
                totalWritten += AVAudioFramePosition(n)
                segOffset += AVAudioFramePosition(n)
                remaining -= AVAudioFramePosition(n)
                processedUnfolded += AVAudioFramePosition(n)
                progress(Double(processedUnfolded) / Double(totalUnfolded))
            }
        }

        return totalWritten
    }

    // MARK: - Stage 2: Offline AVAudioEngine Manual Rendering

    private static func runOfflineEQPass(
        inputURL: URL,
        outputURL: URL,
        format: AVAudioFormat,
        frameCount: AVAudioFramePosition,
        recipe: AudioEditRecipe,
        progress: (Double) -> Void
    ) throws {
        let inputFile = try AVAudioFile(forReading: inputURL)

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let eqNode = AVAudioUnitEQ(numberOfBands: AudioUnitEQConfigurator.bandCount)
        engine.attach(playerNode)
        engine.attach(eqNode)

        engine.connect(playerNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)

        // Gain is the EQ's globalGain (set by the configurator); the mixer
        // stays at unity so it isn't applied twice.
        AudioUnitEQConfigurator.configure(eqNode: eqNode, recipe: recipe, bypassed: false)
        engine.mainMixerNode.outputVolume = 1.0

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunkSize)
        try engine.start()

        defer {
            playerNode.stop()
            engine.stop()
            engine.disableManualRenderingMode()
        }

        playerNode.scheduleFile(inputFile, at: nil, completionHandler: nil)
        playerNode.play()

        let outSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: format.isInterleaved
        )

        guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunkSize) else {
            throw AudioEditRenderError.renderFailed("Offline-Renderbuffer fehlgeschlagen.")
        }

        let targetFrames = max(AVAudioFramePosition(1), frameCount)
        var stalledRenders = 0
        while engine.manualRenderingSampleTime < frameCount {
            try Task.checkCancellation()
            let remaining = frameCount - engine.manualRenderingSampleTime
            let framesToRender = AVAudioFrameCount(min(AVAudioFramePosition(chunkSize), remaining))
            let status = try engine.renderOffline(framesToRender, to: renderBuffer)
            switch status {
            case .success:
                stalledRenders = 0
                if renderBuffer.frameLength > 0 {
                    try outputFile.write(from: renderBuffer)
                }
                progress(min(1.0, Double(engine.manualRenderingSampleTime) / Double(targetFrames)))
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                // Retry, but never spin forever on a stuck graph.
                stalledRenders += 1
                if stalledRenders > 2_000 {
                    throw AudioEditRenderError.renderFailed("Offline-Rendering hängt.")
                }
            case .error:
                throw AudioEditRenderError.renderFailed("AVAudioEngine renderOffline Status .error")
            @unknown default:
                throw AudioEditRenderError.renderFailed("Unbekannter Render-Status")
            }
        }
    }

    // MARK: - Stage 3: Two-Pass Peak Normalization

    private static func normalizeInPlaceIfNeeded(url: URL, targetPeakDBFS: Float) throws {
        let readFile = try AVAudioFile(forReading: url)
        let format = readFile.processingFormat
        let channels = Int(format.channelCount)
        guard readFile.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else { return }

        var maxPeak: Float = 0
        readFile.framePosition = 0
        while readFile.framePosition < readFile.length {
            try Task.checkCancellation()
            buffer.frameLength = 0
            try readFile.read(into: buffer)
            let n = Int(buffer.frameLength)
            guard n > 0, let ptrs = buffer.floatChannelData else { break }
            for ch in 0..<channels {
                var chPeak: Float = 0
                vDSP_maxmgv(ptrs[ch], 1, &chPeak, vDSP_Length(n))
                maxPeak = max(maxPeak, chPeak)
            }
        }

        guard maxPeak > 1e-5 else { return }
        let targetLinear = powf(10.0, targetPeakDBFS / 20.0)
        var scale = targetLinear / maxPeak
        guard abs(scale - 1.0) > 0.02 else { return }

        let tempNormURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw2_norm_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempNormURL) }

        let writeFile = try AVAudioFile(
            forWriting: tempNormURL,
            settings: readFile.fileFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: format.isInterleaved
        )

        readFile.framePosition = 0
        while readFile.framePosition < readFile.length {
            try Task.checkCancellation()
            buffer.frameLength = 0
            try readFile.read(into: buffer)
            let n = Int(buffer.frameLength)
            guard n > 0, let ptrs = buffer.floatChannelData else { break }
            for ch in 0..<channels {
                vDSP_vsmul(ptrs[ch], 1, &scale, ptrs[ch], 1, vDSP_Length(n))
            }
            try writeFile.write(from: buffer)
        }

        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: tempNormURL, to: url)
    }
}

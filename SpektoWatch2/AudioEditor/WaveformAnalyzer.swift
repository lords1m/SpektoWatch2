import Accelerate
import AVFoundation
import Foundation

struct WaveformBin: Sendable, Equatable {
    let min: Float
    let max: Float
    let rms: Float
}

struct WaveformData: Sendable, Equatable {
    let duration: TimeInterval
    let sampleRate: Double
    let channelCount: Int
    let bins: [WaveformBin]
}

enum WaveformAnalyzerError: LocalizedError {
    case unreadableFile
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "Audiodatei konnte nicht gelesen werden."
        case .emptyAudio:     return "Die Audiodatei enthält keine Samples."
        }
    }
}

actor WaveformAnalyzer {
    static let shared = WaveformAnalyzer()

    private struct CacheKey: Hashable {
        let path: String
        let modTime: TimeInterval
        let targetBins: Int
        let rangeStart: Int64
        let rangeEnd: Int64
    }

    private var cache: [CacheKey: WaveformData] = [:]
    private var cacheOrder: [CacheKey] = []
    private let maxCacheEntries = 16

    func extractWaveform(
        url: URL,
        targetBins: Int = 1000,
        timeRange: AudioTimeRange? = nil
    ) async throws -> WaveformData {
        try Task.checkCancellation()

        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.processingFormat.sampleRate
        let totalFrames = file.length
        let channelCount = Int(file.processingFormat.channelCount)
        guard sampleRate > 0, totalFrames > 0 else {
            throw WaveformAnalyzerError.emptyAudio
        }

        let startFrame: AVAudioFramePosition
        let endFrame: AVAudioFramePosition
        if let timeRange {
            startFrame = max(0, min(totalFrames - 1, AVAudioFramePosition(timeRange.start * sampleRate)))
            endFrame = max(startFrame + 1, min(totalFrames, AVAudioFramePosition(timeRange.end * sampleRate)))
        } else {
            startFrame = 0
            endFrame = totalFrames
        }

        let binCount = max(32, min(4000, targetBins))
        let modTime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSinceReferenceDate ?? 0
        let key = CacheKey(
            path: url.standardizedFileURL.path,
            modTime: modTime,
            targetBins: binCount,
            rangeStart: startFrame,
            rangeEnd: endFrame
        )
        if let cached = cache[key] {
            return cached
        }

        let framesToRead = endFrame - startFrame
        let framesPerBin = max(1, Double(framesToRead) / Double(binCount))

        var bins = [WaveformBin](repeating: WaveformBin(min: 0, max: 0, rms: 0), count: binCount)

        file.framePosition = startFrame
        let chunkCapacity: AVAudioFrameCount = 8192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkCapacity) else {
            throw WaveformAnalyzerError.unreadableFile
        }

        var binMin = [Float](repeating: 0, count: binCount)
        var binMax = [Float](repeating: 0, count: binCount)
        var binSumSq = [Double](repeating: 0, count: binCount)
        var binCounts = [Int](repeating: 0, count: binCount)

        var currentFrameOffset: Int64 = 0
        while currentFrameOffset < framesToRead {
            try Task.checkCancellation()

            let remaining = framesToRead - currentFrameOffset
            let toRead = AVAudioFrameCount(min(Int64(chunkCapacity), remaining))
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: toRead)
            let readCount = Int(buffer.frameLength)
            guard readCount > 0, let channelData = buffer.floatChannelData else { break }

            let ptr = channelData[0]
            var localStart = 0
            while localStart < readCount {
                let globalFrame = currentFrameOffset + Int64(localStart)
                let binIdx = min(binCount - 1, Int(Double(globalFrame) / framesPerBin))
                let nextBinBoundaryFrame = Int64(ceil(Double(binIdx + 1) * framesPerBin))
                let framesUntilBoundary = max(1, Int(nextBinBoundaryFrame - globalFrame))
                let sliceLen = min(readCount - localStart, framesUntilBoundary)

                let slicePtr = ptr.advanced(by: localStart)
                var sliceMin: Float = 0
                var sliceMax: Float = 0
                var sliceRMS: Float = 0
                vDSP_minv(slicePtr, 1, &sliceMin, vDSP_Length(sliceLen))
                vDSP_maxv(slicePtr, 1, &sliceMax, vDSP_Length(sliceLen))
                vDSP_rmsqv(slicePtr, 1, &sliceRMS, vDSP_Length(sliceLen))

                if binCounts[binIdx] == 0 {
                    binMin[binIdx] = sliceMin
                    binMax[binIdx] = sliceMax
                } else {
                    binMin[binIdx] = Swift.min(binMin[binIdx], sliceMin)
                    binMax[binIdx] = Swift.max(binMax[binIdx], sliceMax)
                }
                binSumSq[binIdx] += Double(sliceRMS * sliceRMS) * Double(sliceLen)
                binCounts[binIdx] += sliceLen
                localStart += sliceLen
            }

            currentFrameOffset += Int64(readCount)
        }

        for i in 0..<binCount {
            let count = binCounts[i]
            let rms = count > 0 ? Float(sqrt(binSumSq[i] / Double(count))) : 0
            bins[i] = WaveformBin(
                min: max(-1, min(1, binMin[i])),
                max: max(-1, min(1, binMax[i])),
                rms: max(0, min(1, rms))
            )
        }

        let result = WaveformData(
            duration: Double(totalFrames) / sampleRate,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bins: bins
        )

        storeCache(result, for: key)
        return result
    }

    private func storeCache(_ data: WaveformData, for key: CacheKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
        }
        cache[key] = data
        while cacheOrder.count > maxCacheEntries {
            let oldest = cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}

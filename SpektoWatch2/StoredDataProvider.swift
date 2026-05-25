import Foundation
import Combine

struct StoredMetricRow: Identifiable {
    let id = UUID()
    let time: Float
    let values: [String: Float]
}

struct SpectrogramFrameWindow {
    let startFrame: Int
    let frameCount: Int
    let bins: [[Float]]
}

final class StoredDataProvider: AudioDataProvider {
    @Published private(set) var currentSpectrogramData: SpectrogramData?
    @Published private(set) var levelHistory: [Float] = []
    @Published private(set) var currentOctaveBands: [Float] = Array(repeating: -120.0, count: MeasurementDataFormat.thirdOctaveBandCount)
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var metricRows: [StoredMetricRow] = []

    private let fileURL: URL
    private let reader: MeasurementDataReader
    private var playTimer: Timer?
    private var frameDuration: TimeInterval

    private static let thirdOctaveCenters: [Float] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
        1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ]

    var metricKeys: [String] {
        reader.header.metricKeys
    }
    var sampleRate: Double { reader.header.sampleRate }
    var fftBinCount: Int { reader.header.fftBinCount }
    var hasFullFFT: Bool { reader.header.hasFullFFT }
    var frameCount: Int { reader.frameCount }

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.reader = try MeasurementDataReader(fileURL: fileURL)
        self.frameDuration = TimeInterval(1.0 / max(1.0, Double(reader.header.fps)))
        try bootstrap()
    }

    deinit {
        playTimer?.invalidate()
    }

    func play() {
        pause()
        playTimer = Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { [weak self] _ in
            guard let self else { return }
            let next = self.currentTime + self.frameDuration
            if next >= self.duration {
                self.scrub(to: self.duration)
                self.pause()
            } else {
                self.scrub(to: next)
            }
        }
    }

    func pause() {
        playTimer?.invalidate()
        playTimer = nil
    }

    func scrub(to time: TimeInterval) {
        guard reader.frameCount > 0 else { return }
        let clamped = max(0, min(time, duration))
        let index = min(max(Int(clamped / max(frameDuration, 1e-6)), 0), reader.frameCount - 1)

        do {
            let frame = try reader.readFrameSummary(at: index)
            currentTime = TimeInterval(frame.timestamp)
            currentOctaveBands = frame.thirdOctaveZ

            var levels: [String: Float] = [:]
            for (idx, key) in reader.header.metricKeys.enumerated() where idx < frame.metrics.count {
                levels[key] = frame.metrics[idx]
            }

            currentSpectrogramData = SpectrogramData(
                frequencies: Self.thirdOctaveCenters,
                magnitudes: frame.thirdOctaveZ,
                magnitudesA: frame.thirdOctaveA,
                magnitudesC: frame.thirdOctaveC,
                broadbandLevel: frame.broadbandLevel,
                levels: levels,
                sampleRate: reader.header.sampleRate
            )
        } catch {
            print("[StoredDataProvider] Scrub failed: \(error)")
        }
    }

    func spectrogramFrames(in range: Range<Int>) async throws -> SpectrogramFrameWindow {
        try Task.checkCancellation()

        let frameCount = reader.frameCount
        guard frameCount > 0 else {
            return SpectrogramFrameWindow(startFrame: 0, frameCount: 0, bins: [])
        }

        let start = max(0, min(range.lowerBound, frameCount))
        let end = max(start, min(range.upperBound, frameCount))
        let boundedRange = start..<end

        var bins: [[Float]] = []
        bins.reserveCapacity(boundedRange.count)
        let reader = try MeasurementDataReader(fileURL: fileURL)

        for (offset, index) in boundedRange.enumerated() {
            if offset.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let frame = try reader.readFrame(at: index)
            bins.append(frame.fullFFT.isEmpty ? frame.thirdOctaveZ : frame.fullFFT)
        }

        return SpectrogramFrameWindow(startFrame: start, frameCount: bins.count, bins: bins)
    }

    func spectrogramOverview(maxFrameCount requestedMaxFrameCount: Int) async throws -> SpectrogramFrameWindow {
        try Task.checkCancellation()

        let totalFrameCount = reader.frameCount
        guard totalFrameCount > 0 else {
            return SpectrogramFrameWindow(startFrame: 0, frameCount: 0, bins: [])
        }

        let maxFrameCount = max(1, requestedMaxFrameCount)
        if totalFrameCount <= maxFrameCount {
            return try await spectrogramFrames(in: 0..<totalFrameCount)
        }

        var bins: [[Float]] = []
        bins.reserveCapacity(maxFrameCount)
        let reader = try MeasurementDataReader(fileURL: fileURL)
        let denominator = Double(max(maxFrameCount - 1, 1))

        for outputIndex in 0..<maxFrameCount {
            if outputIndex.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let position = Double(outputIndex) / denominator
            let sourceIndex = Int((position * Double(totalFrameCount - 1)).rounded())
            let frame = try reader.readFrame(at: sourceIndex)
            bins.append(frame.fullFFT.isEmpty ? frame.thirdOctaveZ : frame.fullFFT)
        }

        return SpectrogramFrameWindow(startFrame: 0, frameCount: bins.count, bins: bins)
    }

    func rows(in range: ClosedRange<TimeInterval>, step: Int = 1) -> [StoredMetricRow] {
        guard !metricRows.isEmpty else { return [] }
        let stride = max(step, 1)
        return metricRows.enumerated().compactMap { (index, row) in
            guard index % stride == 0 else { return nil }
            let time = TimeInterval(row.time)
            return range.contains(time) ? row : nil
        }
    }

    private func bootstrap() throws {
        guard reader.frameCount > 0 else {
            duration = 0
            return
        }

        metricRows.removeAll(keepingCapacity: true)
        levelHistory.removeAll(keepingCapacity: true)
        metricRows.reserveCapacity(reader.frameCount)
        levelHistory.reserveCapacity(reader.frameCount)

        for index in 0..<reader.frameCount {
            let frame = try reader.readFrameSummary(at: index)
            levelHistory.append(frame.broadbandLevel)

            var valueMap: [String: Float] = [:]
            for (metricIndex, key) in reader.header.metricKeys.enumerated() where metricIndex < frame.metrics.count {
                valueMap[key] = frame.metrics[metricIndex]
            }
            valueMap["broadband"] = frame.broadbandLevel
            metricRows.append(StoredMetricRow(time: frame.timestamp, values: valueMap))
        }

        duration = TimeInterval(metricRows.last?.time ?? 0)
        scrub(to: 0)
    }
}

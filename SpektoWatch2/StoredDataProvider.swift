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
    /// Upper bound on decimated level-history points loaded at open.
    private static let maxBootstrapRows = 4_000
    /// Cap rows returned per `rows(in:)` query (disk-backed).
    private static let maxRowsPerQuery = 500

    @Published private(set) var currentSpectrogramData: SpectrogramData?
    @Published private(set) var levelHistory: [Float] = []
    @Published private(set) var currentOctaveBands: [Float] = Array(repeating: -120.0, count: MeasurementDataFormat.thirdOctaveBandCount)
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// Decimated overview only; metric tables use `rows(in:)` (disk-backed).
    @Published private(set) var metricRows: [StoredMetricRow] = []

    private let fileURL: URL
    private let reader: MeasurementDataReader
    private var playTimer: Timer?
    private var frameDuration: TimeInterval
    // Intended playback position, advanced by the timer independent of whether a
    // frame read succeeds. Keeping play() off this cursor (rather than the stored
    // frame timestamp in `currentTime`) avoids stalling on a bad frame and avoids
    // drift when stored per-frame timestamps are not on a uniform fps grid.
    private var playCursor: TimeInterval = 0

    private static let thirdOctaveCenters = SpectrogramHistoryAxis.thirdOctaveCenterFrequencies

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
            let next = self.playCursor + self.frameDuration
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
        // Advance the play cursor to the requested time up front so playback keeps
        // progressing even if the frame read below fails.
        playCursor = clamped
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

    func spectrogramFrames(
        in range: Range<Int>,
        weighting: FrequencyWeighting = .z
    ) async throws -> SpectrogramFrameWindow {
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
            bins.append(Self.spectralBins(from: frame, weighting: weighting))
        }

        return SpectrogramFrameWindow(startFrame: start, frameCount: bins.count, bins: bins)
    }

    func spectrogramOverview(
        maxFrameCount requestedMaxFrameCount: Int,
        weighting: FrequencyWeighting = .z
    ) async throws -> SpectrogramFrameWindow {
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
            bins.append(Self.spectralBins(from: frame, weighting: weighting))
        }

        return SpectrogramFrameWindow(startFrame: 0, frameCount: bins.count, bins: bins)
    }

    /// Reads a higher-resolution spectrogram window for a sub-range of the
    /// recording, used by the navigable spectrogram for level-of-detail
    /// zoom-in. When the range fits within `maxColumns` frames the frames are
    /// returned at full disk resolution; otherwise they are decimated to
    /// `maxColumns` columns. Returns frames covering exactly the requested time
    /// range so the caller can map them across the visible window.
    func spectrogramTile(
        timeRange: ClosedRange<TimeInterval>,
        maxColumns: Int,
        weighting: FrequencyWeighting = .z
    ) async throws -> SpectrogramFrameWindow {
        try Task.checkCancellation()

        let totalFrameCount = reader.frameCount
        guard totalFrameCount > 0 else {
            return SpectrogramFrameWindow(startFrame: 0, frameCount: 0, bins: [])
        }

        let lower = frameIndex(for: timeRange.lowerBound)
        let upper = min(frameIndex(for: timeRange.upperBound) + 1, totalFrameCount)
        let start = max(0, min(lower, upper))
        let end = max(start + 1, upper)
        let span = end - start
        let columns = max(1, maxColumns)

        if span <= columns {
            return try await spectrogramFrames(in: start..<end, weighting: weighting)
        }

        var bins: [[Float]] = []
        bins.reserveCapacity(columns)
        let reader = try MeasurementDataReader(fileURL: fileURL)
        let denominator = Double(max(columns - 1, 1))

        for outputIndex in 0..<columns {
            if outputIndex.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let position = Double(outputIndex) / denominator
            let sourceIndex = start + Int((position * Double(span - 1)).rounded())
            let frame = try reader.readFrame(at: min(sourceIndex, totalFrameCount - 1))
            bins.append(Self.spectralBins(from: frame, weighting: weighting))
        }

        return SpectrogramFrameWindow(startFrame: start, frameCount: bins.count, bins: bins)
    }

    private static func spectralBins(from frame: MeasurementFrame, weighting: FrequencyWeighting) -> [Float] {
        WaterfallSpectrogramBins.bins(
            from: frame,
            weighting: weighting,
            preferFullFFT: !frame.fullFFT.isEmpty
        )
    }

    /// Reads metric rows for a time window directly from disk (not from bootstrap cache).
    func rows(in range: ClosedRange<TimeInterval>, step: Int = 1) -> [StoredMetricRow] {
        guard reader.frameCount > 0 else { return [] }

        let startFrame = frameIndex(for: range.lowerBound)
        let endFrame = frameIndex(for: range.upperBound)
        guard startFrame <= endFrame else { return [] }

        let userStep = max(step, 1)
        let frameSpan = endFrame - startFrame + 1
        let frameStride = max(
            userStep,
            max(1, (frameSpan + Self.maxRowsPerQuery - 1) / Self.maxRowsPerQuery)
        )

        var rows: [StoredMetricRow] = []
        rows.reserveCapacity(min(frameSpan / frameStride + 1, Self.maxRowsPerQuery + 1))

        var index = startFrame
        while index <= endFrame {
            if let row = try? metricRow(atFrameIndex: index) {
                rows.append(row)
            }
            index += frameStride
        }

        if endFrame > startFrame, (endFrame - startFrame) % frameStride != 0 {
            if let row = try? metricRow(atFrameIndex: endFrame), rows.last?.time != row.time {
                rows.append(row)
            }
        }

        return rows
    }

    private func bootstrap() throws {
        metricRows = []
        guard reader.frameCount > 0 else {
            duration = 0
            levelHistory = []
            return
        }

        try loadDecimatedLevelHistory()

        let last = try reader.readFrameSummary(at: reader.frameCount - 1)
        duration = TimeInterval(last.timestamp)
        scrub(to: 0)
    }

    private func loadDecimatedLevelHistory() throws {
        levelHistory.removeAll(keepingCapacity: true)

        let totalFrames = reader.frameCount
        let stride = bootstrapStride(frameCount: totalFrames)
        let reserved = min(totalFrames, Self.maxBootstrapRows + 1)
        levelHistory.reserveCapacity(reserved)

        var lastAppendedIndex = -1
        for index in Swift.stride(from: 0, to: totalFrames, by: stride) {
            let frame = try reader.readFrameSummary(at: index)
            levelHistory.append(frame.broadbandLevel)
            lastAppendedIndex = index
        }

        let finalIndex = totalFrames - 1
        if finalIndex > lastAppendedIndex {
            let frame = try reader.readFrameSummary(at: finalIndex)
            levelHistory.append(frame.broadbandLevel)
        }
    }

    private func bootstrapStride(frameCount: Int) -> Int {
        guard frameCount > Self.maxBootstrapRows else { return 1 }
        return max(1, (frameCount + Self.maxBootstrapRows - 1) / Self.maxBootstrapRows)
    }

    private func frameIndex(for time: TimeInterval) -> Int {
        let clamped = max(0, min(time, duration))
        return min(max(Int(clamped / max(frameDuration, 1e-6)), 0), max(reader.frameCount - 1, 0))
    }

    private func metricRow(atFrameIndex index: Int) throws -> StoredMetricRow {
        let frame = try reader.readFrameSummary(at: index)
        var valueMap: [String: Float] = [:]
        for (metricIndex, key) in reader.header.metricKeys.enumerated() where metricIndex < frame.metrics.count {
            valueMap[key] = frame.metrics[metricIndex]
        }
        valueMap["broadband"] = frame.broadbandLevel
        return StoredMetricRow(time: frame.timestamp, values: valueMap)
    }
}

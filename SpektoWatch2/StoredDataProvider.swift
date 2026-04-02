import Foundation
import Combine

struct StoredMetricRow: Identifiable {
    let id = UUID()
    let time: Float
    let values: [String: Float]
}

final class StoredDataProvider: AudioDataProvider {
    @Published private(set) var currentSpectrogramData: SpectrogramData?
    @Published private(set) var levelHistory: [Float] = []
    @Published private(set) var currentOctaveBands: [Float] = Array(repeating: -120.0, count: MeasurementDataFormat.thirdOctaveBandCount)
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var spectrogramHistory: [[Float]] = []
    @Published private(set) var metricRows: [StoredMetricRow] = []

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

    init(fileURL: URL) throws {
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
            let frame = try reader.readFrame(at: index)
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

        spectrogramHistory.removeAll(keepingCapacity: true)
        metricRows.removeAll(keepingCapacity: true)
        levelHistory.removeAll(keepingCapacity: true)
        spectrogramHistory.reserveCapacity(reader.frameCount)
        metricRows.reserveCapacity(reader.frameCount)
        levelHistory.reserveCapacity(reader.frameCount)

        for index in 0..<reader.frameCount {
            let frame = try reader.readFrame(at: index)
            if !frame.fullFFT.isEmpty {
                spectrogramHistory.append(frame.fullFFT)
            } else {
                spectrogramHistory.append(frame.thirdOctaveZ)
            }
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

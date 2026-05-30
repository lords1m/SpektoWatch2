import Foundation
import AVFoundation
import os

/// One in-progress standalone watch recording. Writes audio (`.caf`) and a
/// measurement sidecar (`.swr`, shared `MeasurementDataFormat`) under a stable
/// app-container directory so the capture survives force-quit and relaunch.
/// Files are named by a stable recording `id` that doubles as the sync-back
/// idempotency key ([[task-5-sync-back]]).
final class WatchRecordingSession {
    /// Ordered metric keys persisted per frame. Must match the value order in
    /// `writeMeasurementFrame`. The watch computes LAF/LAeq/LCpeak.
    static let metricKeys = ["LAF", "LAeq", "LCpeak"]

    let id: UUID
    let audioURL: URL
    let measurementURL: URL
    let startDate: Date
    let format: AVAudioFormat
    let weighting: String
    private(set) var peakLevel: Float = 0
    private(set) var frameCount: AVAudioFramePosition = 0

    private let audioFile: AVAudioFile
    private let measurementWriter: MeasurementDataWriter
    private let log = Logger(subsystem: "com.spektowatch.watch", category: "RecordingSession")
    private let emptyBands = [Float](repeating: 0, count: MeasurementDataFormat.thirdOctaveBandCount)
    private var isFinalized = false
    /// Most recent metrics frame. LAeq is cumulative and LCpeak is a running max,
    /// so the last frame holds the session aggregates surfaced in the catalog UI.
    private var lastLevels: [String: Float]?

    var duration: TimeInterval {
        guard format.sampleRate > 0 else { return 0 }
        return Double(frameCount) / format.sampleRate
    }

    init(format: AVAudioFormat, directory: URL, weighting: String, fps: Float) throws {
        let id = UUID()
        self.id = id
        self.startDate = Date()
        self.format = format
        self.weighting = weighting
        let audioURL = directory.appendingPathComponent("\(id.uuidString).caf")
        let measurementURL = directory.appendingPathComponent("\(id.uuidString).swr")
        self.audioURL = audioURL
        self.measurementURL = measurementURL
        self.audioFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        self.measurementWriter = try MeasurementDataWriter(
            fileURL: measurementURL,
            metricKeys: WatchRecordingSession.metricKeys,
            sampleRate: format.sampleRate,
            fps: fps,
            fftBlockSize: 0,
            fftBinCount: 0
        )
    }

    func writeBuffer(_ buffer: AVAudioPCMBuffer) {
        if let channel = buffer.floatChannelData?[0] {
            let count = Int(buffer.frameLength)
            for i in 0..<count {
                let abs = fabsf(channel[i])
                if abs > peakLevel { peakLevel = abs }
            }
        }
        do {
            try audioFile.write(from: buffer)
            frameCount += AVAudioFramePosition(buffer.frameLength)
        } catch {
            log.error("audio write error: \(String(describing: error), privacy: .public)")
        }
    }

    /// Persists one measurement frame. `levels` is the calculator's dictionary;
    /// values are projected onto the fixed `metricKeys` order. Audio-thread safe:
    /// the writer dispatches the actual disk write onto its own queue.
    func writeMeasurementFrame(levels: [String: Float], timestamp: Float) {
        lastLevels = levels
        let values = WatchRecordingSession.metricKeys.map { levels[$0] ?? -120.0 }
        do {
            try measurementWriter.writeFrame(
                timestamp: timestamp,
                metricValues: values,
                broadbandLevel: levels["LAF"] ?? -120.0,
                thirdOctaveZ: emptyBands,
                thirdOctaveA: emptyBands,
                thirdOctaveC: emptyBands,
                fullFFT: []
            )
        } catch {
            log.error("measurement write error: \(String(describing: error), privacy: .public)")
        }
    }

    /// Flushes both files to disk and returns durable catalog metadata. Safe to
    /// call more than once; only the first call finalizes.
    @discardableResult
    func finalize(title: String) -> WatchRecordingMetadata {
        if !isFinalized {
            isFinalized = true
            try? measurementWriter.close()
            // AVAudioFile flushes on dealloc; nothing else to close explicitly.
        }
        return WatchRecordingMetadata(
            id: id,
            title: title,
            createdAt: startDate,
            duration: duration,
            sampleRate: format.sampleRate,
            weighting: weighting,
            audioFileName: audioURL.lastPathComponent,
            measurementFileName: measurementURL.lastPathComponent,
            syncState: .local,
            laeq: lastLevels?["LAeq"],
            lcPeak: lastLevels?["LCpeak"]
        )
    }
}

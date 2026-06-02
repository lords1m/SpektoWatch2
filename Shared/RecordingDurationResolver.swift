import Foundation
import AVFoundation

/// Resolves recording duration from on-disk audio and measurement sidecars.
public enum RecordingDurationResolver {
    public static func audioFileDuration(at url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return nil }
        return Double(file.length) / rate
    }

    public static func measurementLastTimestamp(at url: URL) -> TimeInterval? {
        guard let reader = try? MeasurementDataReader(fileURL: url),
              reader.frameCount > 0,
              let frame = try? reader.readFrameSummary(at: reader.frameCount - 1) else {
            return nil
        }
        return TimeInterval(frame.timestamp)
    }

    public static func resolved(
        audioURL: URL,
        measurementURL: URL?,
        fallback: TimeInterval
    ) -> TimeInterval {
        var duration = fallback
        if let audioDuration = audioFileDuration(at: audioURL) {
            duration = max(duration, audioDuration)
        }
        if let measurementURL,
           let measurementDuration = measurementLastTimestamp(at: measurementURL) {
            duration = max(duration, measurementDuration)
        }
        return duration
    }
}

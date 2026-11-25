import Foundation
import Observation

/// Recording-session state extracted from `AudioEngine`.
@Observable
final class RecordingCoordinator {

    @ObservationIgnored var onRecordingToFileChanged: ((Bool) -> Void)?
    @ObservationIgnored var onMeasurementRecordingChanged: ((_ newValue: Bool, _ oldValue: Bool) -> Void)?

    /// Audio is actively being written to a file on disk.
    var isRecordingToFile: Bool = false {
        didSet {
            onRecordingToFileChanged?(isRecordingToFile)
        }
    }

    /// Measurement-data (per-frame metrics + spectral snapshot) is
    /// being streamed to disk alongside the audio file.
    var isMeasurementRecording: Bool = false {
        didSet {
            onMeasurementRecordingChanged?(isMeasurementRecording, oldValue)
        }
    }

    /// Wall-clock duration of the current session, in seconds.
    /// Driven by AudioEngine on every spectrogram emit.
    var recordingDuration: TimeInterval = 0.0
}

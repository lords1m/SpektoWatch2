import Combine
import Foundation

/// Recording-session state extracted from `AudioEngine` as part of
/// M13 task-5. Owns the four `@Published` flags that downstream
/// consumers (`ControlBarView`, `DashboardViewModel`,
/// `WaterfallView`, the recording UI) read to know whether a
/// recording is in progress and how long it has been running.
///
/// Same conservative-extraction pattern as M13 task-4
/// (`LiveAcousticState`): AudioEngine keeps `@MainActor` ownership
/// of the actual start/stop control flow and the
/// `MeasurementDataWriter` lifecycle. AudioEngine bridges this
/// coordinator's `objectWillChange` into its own and subscribes to
/// `$isMeasurementRecording` to run the file-setup / writer-close
/// side effects, so existing consumers keep updating transparently
/// without any call-site migration.
///
/// The control methods (`startRecording()` / `stopRecording()` /
/// `cancelRecording()`) currently still live on AudioEngine because
/// they orchestrate the AVAudioEngine session itself. Moving them
/// fully into this coordinator is a follow-up — Phase 2 of this
/// task, deferred for the same reasons task-4 Phase 2 was deferred:
/// the seam is the prerequisite; the migration is incremental.
final class RecordingCoordinator: ObservableObject {

    /// Audio is actively being written to a file on disk.
    @Published var isRecordingToFile: Bool = false

    /// Measurement-data (per-frame metrics + spectral snapshot) is
    /// being streamed to disk alongside the audio file.
    @Published var isMeasurementRecording: Bool = false

    /// Wall-clock duration of the current session, in seconds.
    /// Driven by AudioEngine on every spectrogram emit.
    @Published var recordingDuration: TimeInterval = 0.0
}

import Foundation
import AVFoundation
import OSLog

/// Owns the two real-time file writers (audio `.caf` + measurement `.spekto`),
/// their cross-thread `OSAllocatedUnfairLock`s, the last-written file URLs, and
/// the measurement metric-key schema.
///
/// AE-2 writer cross-thread safety: both writers are created/nulled on the main
/// thread but read on the audio render thread. The lock duration covers only
/// the reference load/store; the strong reference keeps the object alive past
/// the unlock. The audio thread reads via `rtLoad…Writer()` (real-time safe);
/// the main thread sets up / closes via the methods below.
///
/// Recording-mode gating (`recording.isRecordingToFile` / `isMeasurementRecording`)
/// stays in `AudioEngine`; this type only creates/closes the files it is told to.
///
/// Extracted from `AudioEngine` in VERBESSERUNGSPLAN Phase 3 (post-3.5 shrink).
final class RecordingWriterCoordinator {
    let metricKeys: [String] = [
        "LAF", "LAS", "LCF", "LCS", "LZF", "LZS",
        "LAeq", "LAFmin", "LAFmax", "LCpeak",
        "LAFT5", "LAF5", "LAF95", "LAFTeq"
    ]

    var lastRecordingURL: URL?
    var lastMeasurementDataURL: URL?

    private let audioFileWriterLock = OSAllocatedUnfairLock<RealtimeAudioFileWriter?>(initialState: nil)
    private let measurementWriterLock = OSAllocatedUnfairLock<MeasurementDataWriter?>(initialState: nil)

    /// Main-thread accessor for the audio writer; the audio thread loads
    /// directly via `rtLoadAudioWriter()`.
    private var audioFileWriter: RealtimeAudioFileWriter? {
        get { audioFileWriterLock.withLockUnchecked { $0 } }
        set { audioFileWriterLock.withLock { $0 = newValue } }
    }
    /// Main-thread accessor for the measurement writer.
    private var measurementWriter: MeasurementDataWriter? {
        get { measurementWriterLock.withLockUnchecked { $0 } }
        set { measurementWriterLock.withLock { $0 = newValue } }
    }

    /// Audio-render-thread load of the audio writer (AE-2, real-time safe).
    func rtLoadAudioWriter() -> RealtimeAudioFileWriter? {
        audioFileWriterLock.withLockUnchecked { $0 }
    }
    /// Audio-render-thread load of the measurement writer (AE-2, real-time safe).
    func rtLoadMeasurementWriter() -> MeasurementDataWriter? {
        measurementWriterLock.withLockUnchecked { $0 }
    }

    func setupRecordingFile(format: AVAudioFormat, frameCapacity: AVAudioFrameCount) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording_\(Date().timeIntervalSince1970).caf")
        do {
            self.audioFileWriter = try RealtimeAudioFileWriter(
                fileURL: tempURL,
                format: format,
                settings: format.settings,
                frameCapacity: frameCapacity
            )
            self.lastRecordingURL = tempURL
            Logger.audioEngine.info("Recording file setup at: \(tempURL.lastPathComponent)")
        } catch {
            self.audioFileWriter = nil
            self.lastRecordingURL = nil
            Logger.audioEngine.error("Recording file setup failed: \(error.localizedDescription)")
        }
    }

    /// Creates the measurement writer if one is not already open. The caller is
    /// responsible for the recording-mode gating.
    func setupMeasurementFileIfNeeded(sampleRate: Double, fps: Float, fftBlockSize: Int, fftBinCount: Int) {
        if measurementWriter != nil { return }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("measurement_\(Date().timeIntervalSince1970).spekto")
        do {
            let writer = try MeasurementDataWriter(
                fileURL: tempURL,
                metricKeys: metricKeys,
                sampleRate: sampleRate,
                fps: fps,
                fftBlockSize: fftBlockSize,
                fftBinCount: fftBinCount
            )
            measurementWriter = writer
            lastMeasurementDataURL = tempURL
            Logger.audioEngine.info("Measurement file setup at: \(tempURL.lastPathComponent)")
        } catch {
            measurementWriter = nil
            lastMeasurementDataURL = nil
            Logger.audioEngine.error("Measurement writer setup failed: \(error.localizedDescription)")
        }
    }

    func closeMeasurement() {
        // Atomically swap nil so the audio thread sees nil before close() runs.
        let writer = measurementWriterLock.withLock { old -> MeasurementDataWriter? in
            let w = old; old = nil; return w
        }
        guard let writer else { return }
        do {
            try writer.close()
        } catch {
            Logger.audioEngine.error("Measurement writer close failed: \(error.localizedDescription)")
        }
    }

    func closeAudio() {
        // Atomically swap nil into the lock so the audio thread sees nil immediately,
        // then call close() outside the lock (close() may block briefly).
        let writer = audioFileWriterLock.withLock { old -> RealtimeAudioFileWriter? in
            let w = old; old = nil; return w
        }
        writer?.close()
    }
}

import Observation
import SwiftUI

/// Single container for the long-lived service graph.
///
/// Consumer views read sub-services via `@Environment(AppServices.self)`;
/// deferred audio engines are exposed as `services.audioEngine` /
/// `services.maskingEngine` after `startAudio()`.
@Observable
@MainActor
final class AppServices {

    // MARK: - Sub-services (eager)

    let filterManager: BandstopFilterManager
    let connectivityManager: WatchConnectivityManager
    let recordingManager: RecordingManager
    let fftConfiguration: FFTConfiguration
    let maskingProfileManager: MaskingProfileManager

    // MARK: - Deferred audio surfaces
    //
    // AudioEngine needs the Metal device touched + FFT config applied
    // after the first frame is on screen, so they construct
    // asynchronously via `startAudio()`. This mirrors the previous
    // `AudioEngineContainer` behavior.

    private(set) var audioEngine: AudioEngine?
    private(set) var maskingEngine: MaskingEngine?

    /// True once `startAudio()` has produced both engines.
    var isAudioReady: Bool { audioEngine != nil && maskingEngine != nil }

    // MARK: - Init

    init(
        filterManager: BandstopFilterManager,
        connectivityManager: WatchConnectivityManager,
        recordingManager: RecordingManager,
        fftConfiguration: FFTConfiguration,
        maskingProfileManager: MaskingProfileManager
    ) {
        self.filterManager = filterManager
        self.connectivityManager = connectivityManager
        self.recordingManager = recordingManager
        self.fftConfiguration = fftConfiguration
        self.maskingProfileManager = maskingProfileManager

        // Phone-side ingest of standalone watch recordings (M21 task-5).
        // Runs on the main actor; idempotent by recording id.
        connectivityManager.onWatchRecordingReceived = { [weak recordingManager] recording in
            MainActor.assumeIsolated {
                recordingManager?.ingestWatchRecording(recording) ?? false
            }
        }
    }

    /// Convenience no-arg initializer that constructs every sub-service
    /// with its default initializer. Defined inside the MainActor-
    /// isolated class so the sub-service initializers (most of which
    /// are also MainActor) compile cleanly.
    convenience init() {
        self.init(
            filterManager: BandstopFilterManager(),
            connectivityManager: WatchConnectivityManager(),
            recordingManager: RecordingManager(),
            fftConfiguration: FFTConfiguration(),
            maskingProfileManager: MaskingProfileManager()
        )
    }

    /// Construct the audio + masking engines after the first frame.
    /// Idempotent — calling twice is a no-op.
    func startAudio() {
        guard audioEngine == nil else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            MetalWidgetManager.shared.prewarmSharedDevice()

            await MainActor.run { [weak self] in
                guard let self, self.audioEngine == nil else { return }

                let engine = AudioEngine(
                    filterManager: self.filterManager,
                    connectivityManager: self.connectivityManager
                )
                engine.applyFFTConfiguration(self.fftConfiguration)
                engine.applyRealtimeHop(from: self.fftConfiguration)
                self.observeRealtimeHopSettings(of: engine)

                self.audioEngine = engine
                self.maskingEngine = MaskingEngine(audioEngine: engine)

                if Self.shouldPrewarmCaptureGraph {
                    // Defer graph prewarm so published engine state reaches
                    // SwiftUI before AVAudioEngine graph work on the main actor.
                    Task { @MainActor in
                        engine.prewarmCaptureGraph()
                    }
                }
            }
        }
    }
}

// MARK: - Realtime hop

extension AppServices {
    /// Keeps the engine's live hop in sync with the FFT settings wherever they
    /// are edited (settings, lab widget, advanced analysis).
    fileprivate func observeRealtimeHopSettings(of engine: AudioEngine) {
        let cfg = fftConfiguration
        cfg.onConfigurationChanged = { [weak engine, weak cfg] in
            guard let engine, let cfg else { return }
            engine.applyRealtimeHop(
                configuredHop: cfg.hopSize,
                matchDisplayRefreshRate: cfg.matchDisplayRefreshRate
            )
        }
    }
}

// MARK: - Test fixture

extension AppServices {
    /// Synchronous fixture for unit / snapshot tests. Constructs every
    /// service, including AudioEngine + MaskingEngine immediately
    /// (no deferred startup). Callers can override individual services
    /// by passing in pre-configured instances.
    static func testFixture(
        filterManager: BandstopFilterManager? = nil,
        connectivityManager: WatchConnectivityManager? = nil,
        recordingManager: RecordingManager? = nil,
        fftConfiguration: FFTConfiguration? = nil,
        maskingProfileManager: MaskingProfileManager? = nil,
        audioEngine: AudioEngine? = nil
    ) -> AppServices {
        let fm = filterManager ?? BandstopFilterManager()
        let cm = connectivityManager ?? WatchConnectivityManager()
        let rm = recordingManager ?? RecordingManager()
        let cfg = fftConfiguration ?? FFTConfiguration()
        let mpm = maskingProfileManager ?? MaskingProfileManager()

        let services = AppServices(
            filterManager: fm,
            connectivityManager: cm,
            recordingManager: rm,
            fftConfiguration: cfg,
            maskingProfileManager: mpm
        )

        // Tests want audio engines available synchronously.
        MetalWidgetManager.shared.prewarmSharedDevice()
        let engine = audioEngine ?? AudioEngine(filterManager: fm, connectivityManager: cm)
        if shouldPrewarmCaptureGraph {
            engine.prewarmCaptureGraph()
        }
        services.audioEngine = engine
        services.maskingEngine = MaskingEngine(audioEngine: engine)
        return services
    }

    /// AVAudioEngine prewarm can block the main thread on Simulator; UI tests
    /// use the synthetic generator and never need the real graph.
    private static var shouldPrewarmCaptureGraph: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        #if DEBUG
        if UITestRuntime.useTestAudio { return false }
        #endif
        return true
        #endif
    }
}

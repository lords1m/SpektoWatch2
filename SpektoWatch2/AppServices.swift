import Combine
import SwiftUI

/// Single container for the long-lived service graph.
///
/// Replaces the previous pattern of seven hand-wired `@StateObject`s in
/// `SpektoWatch2App` + seven `.environmentObject(...)` calls under
/// `ContentView`. This is *only* the producer side — consumer views
/// Consumer migration to `@EnvironmentObject var services: AppServices` is
/// in progress (Phase 4); some views still read individual services for now.
/// Source: M13 task-1 (architecture review A7).
@MainActor
final class AppServices: ObservableObject {

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

    @Published private(set) var audioEngine: AudioEngine?
    @Published private(set) var maskingEngine: MaskingEngine?

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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            MetalWidgetManager.shared.prewarmSharedDevice()

            DispatchQueue.main.async {
                guard let self, self.audioEngine == nil else { return }

                let engine = AudioEngine(
                    filterManager: self.filterManager,
                    connectivityManager: self.connectivityManager
                )
                engine.applyFFTConfiguration(self.fftConfiguration)
                engine.scrollSpeed = .closest(to: self.fftConfiguration.hopSize)

                self.audioEngine = engine
                self.maskingEngine = MaskingEngine(audioEngine: engine)

                if Self.shouldPrewarmCaptureGraph {
                    DispatchQueue.main.async {
                        engine.prewarmCaptureGraph()
                    }
                }
            }
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

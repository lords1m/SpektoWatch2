import XCTest
import AVFoundation
@testable import SpektoWatch2

/// Regression tests for M22 task-4 (audio session coordinator, AS-1…AS-9).
/// Interruptions, route changes and tone + capture on real hardware are in
/// the task-8 matrix.
final class M22AudioSessionRegressionTests: XCTestCase {

    private final class FakeSession: AudioSessionConfiguring {
        var category: AVAudioSession.Category?
        var mode: AVAudioSession.Mode?
        var options: AVAudioSession.CategoryOptions = []
        var active = false
        var setCategoryCalls = 0
        var failNextSetCategory = false

        func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
            if failNextSetCategory {
                failNextSetCategory = false
                throw NSError(domain: "fake", code: 1)
            }
            setCategoryCalls += 1
            self.category = category
            self.mode = mode
            self.options = options
        }

        func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
            self.active = active
        }
    }

    // MARK: - Configuration table

    func testCaptureOnlyIsRecordMeasurement() {
        let config = AudioSessionCoordinator.configuration(for: [.capture])
        XCTAssertEqual(config?.category, .record)
        XCTAssertEqual(config?.mode, .measurement)
    }

    func testCaptureWithToneKeepsMeasurementMode() {
        let config = AudioSessionCoordinator.configuration(for: [.capture, .tone])
        XCTAssertEqual(config?.category, .playAndRecord)
        XCTAssertEqual(config?.mode, .measurement, "AS-3: a tone must not disable measurement mode")
        XCTAssertTrue(config?.options.contains(.defaultToSpeaker) ?? false)
    }

    func testOutputOnlyIsPlayback() {
        XCTAssertEqual(AudioSessionCoordinator.configuration(for: [.tone])?.category, .playback)
        XCTAssertEqual(AudioSessionCoordinator.configuration(for: [.maskingPreview, .playback])?.category, .playback)
        XCTAssertNil(AudioSessionCoordinator.configuration(for: []))
    }

    // MARK: - Leases

    func testReleaseRestoresRemainingConfiguration() throws {
        let fake = FakeSession()
        let coordinator = AudioSessionCoordinator(session: fake, observeSystemNotifications: false)

        let capture = try coordinator.acquire(.capture)
        XCTAssertEqual(fake.category, .record)
        XCTAssertTrue(fake.active)

        let tone = try coordinator.acquire(.tone)
        XCTAssertEqual(fake.category, .playAndRecord)
        XCTAssertEqual(fake.mode, .measurement)

        coordinator.release(tone)
        XCTAssertEqual(fake.category, .record, "Ending the tone restores pure capture")
        XCTAssertEqual(fake.mode, .measurement)

        coordinator.release(capture)
        XCTAssertFalse(fake.active, "No leases → session deactivated")
        XCTAssertNil(coordinator.currentConfiguration)

        coordinator.release(capture) // idempotent
    }

    func testRedundantLeaseDoesNotReapplyCategory() throws {
        let fake = FakeSession()
        let coordinator = AudioSessionCoordinator(session: fake, observeSystemNotifications: false)
        let a = try coordinator.acquire(.capture)
        let b = try coordinator.acquire(.capture)
        XCTAssertEqual(fake.setCategoryCalls, 1)
        coordinator.release(a)
        XCTAssertTrue(fake.active, "Second capture lease still holds the session")
        coordinator.release(b)
        XCTAssertFalse(fake.active)
    }

    func testFailedAcquireRegistersNothing() throws {
        let fake = FakeSession()
        let coordinator = AudioSessionCoordinator(session: fake, observeSystemNotifications: false)
        _ = try coordinator.acquire(.capture)
        fake.failNextSetCategory = true
        XCTAssertThrowsError(try coordinator.acquire(.tone))
        XCTAssertEqual(coordinator.activeClients, [.capture])
    }

    // MARK: - Suspend / resume (AS-5 / AS-7)

    func testSuspendOnIdleEngineDoesNotStartCaptureOnResume() {
        let engine = AudioEngine(filterManager: BandstopFilterManager(), connectivityManager: WatchConnectivityManager())
        XCTAssertEqual(engine.engineStatus, .idle)
        let token = engine.suspendCapture()
        XCTAssertFalse(token.wasActive)
        engine.resumeCapture(token)
        XCTAssertEqual(engine.engineStatus, .idle, "AS-5: resume must not force the iPhone mic on")
    }

    func testSuspendIsSynchronousSoImmediateResumeRestarts() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Relies on the simulator's synthetic capture path")
        #else
        let engine = AudioEngine(filterManager: BandstopFilterManager(), connectivityManager: WatchConnectivityManager())
        engine.startLiveMode()
        XCTAssertEqual(engine.engineStatus, .running)
        let token = engine.suspendCapture()
        XCTAssertEqual(engine.engineStatus, .idle, "AS-7: status flips synchronously on main")
        XCTAssertEqual(token.source, .iPhone)
        engine.resumeCapture(token)
        XCTAssertEqual(engine.engineStatus, .running)
        engine.stopLiveMode()
        #endif
    }

    // MARK: - Tone DSP (UI-15, shipped with AS-3)

    func testPolyBLEPWaveformsStayBounded() {
        let dt = 5_000.0 / 44_100.0
        var t = 0.0
        for _ in 0..<2_000 {
            for wf in ToneGenerator.Waveform.allCases {
                let v = ToneGenerator.sample(wf, t: t, dt: dt)
                XCTAssertLessThanOrEqual(abs(v), 1.5, "\(wf) at t=\(t)")
            }
            t += dt
            if t >= 1 { t -= 1 }
        }
        XCTAssertEqual(ToneGenerator.sample(.sine, t: 0.25, dt: 0.01), 1, accuracy: 1e-9)
        XCTAssertEqual(ToneGenerator.polyBLEP(0.5, 0.01), 0)
    }
}

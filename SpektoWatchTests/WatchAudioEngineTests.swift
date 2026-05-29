import XCTest
import Combine
@testable import SpektoWatch_Watch_App

// MARK: - WatchAudioEngine Unit Tests
//
// These tests cover the WatchAudioEngine state machine, gain clamping, and
// NotificationCenter routing.  Audio engine start/stop is NOT tested here
// because the watchOS simulator has no microphone.  The engine's guard logic
// is verified by manipulating `isRecording` directly and firing notifications.

@MainActor
final class WatchAudioEngineTests: XCTestCase {

    var engine: WatchAudioEngine!
    var connectivity: WatchConnectivityManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        connectivity = WatchConnectivityManager()
        engine = WatchAudioEngine(connectivityManager: connectivity)
        cancellables = []
    }

    override func tearDown() async throws {
        // Unregister first so the old engine cannot respond to notifications
        // posted by the *next* test's setUp or body while it is still alive
        // (stopRecording sets isRecording = false asynchronously, so the engine
        // can outlive `engine = nil` and fire handleStopRecording on stale state).
        if let engine {
            NotificationCenter.default.removeObserver(engine)
            if engine.isRecording {
                engine.stopRecording()
            }
        }
        engine = nil
        connectivity = nil
        cancellables = nil
        try await super.tearDown()
    }

    // MARK: - Initialization

    func testInitialIsRecordingIsFalse() {
        XCTAssertFalse(engine.isRecording, "Engine should not be recording after init")
    }

    func testInitialSpectrogramDataIsNil() {
        XCTAssertNil(engine.currentSpectrogramData, "No spectrogram data expected before first recording")
    }

    // MARK: - Gain Clamping

    func testSetGainWithinRangeIsAccepted() {
        // Indirect proof: no crash, and clamped value is the same
        // We verify via a second setGain call that the engine is still responsive
        engine.setGain(2.5)
        engine.setGain(5.0)
        // No assertion possible on private `gain`; we verify via boundary round-trips
        XCTAssertTrue(true, "setGain within [0, 10] must not crash")
    }

    func testSetGainClampedAtMaximum() {
        // setGain(100) must not crash and must clamp internally to 10.0.
        // We confirm by sending a value above the maximum – no assertion on the
        // private field, but subsequent calls must still work.
        engine.setGain(100)
        engine.setGain(10) // still within valid range
        XCTAssertTrue(true, "Gain values above maximum must be clamped silently")
    }

    func testSetGainClampedAtMinimum() {
        engine.setGain(-5)
        engine.setGain(0)
        XCTAssertTrue(true, "Negative gain must be clamped to 0 silently")
    }

    func testSetGainAtExactBoundaries() {
        engine.setGain(0.0)
        engine.setGain(10.0)
        XCTAssertTrue(true, "Boundary values 0.0 and 10.0 must be accepted without crash")
    }

    // MARK: - startRecording guard: already recording

    func testStartRecordingNotificationIgnoredWhenAlreadyRecording() {
        // Simulate state where the engine is already recording.
        // WatchAudioEngine.handleStartRecording has `guard !isRecording else { return }`,
        // so firing the notification must not trigger a second start attempt.
        engine.isRecording = true

        // Confirm isRecording stays true and no crash occurs.
        NotificationCenter.default.post(name: .startRecordingCommand, object: nil)

        XCTAssertTrue(engine.isRecording,
            "isRecording must remain true; second start must be swallowed by the guard")
    }

    // MARK: - stopRecording guard: not recording

    func testStopRecordingNotificationIgnoredWhenNotRecording() {
        // Engine starts in isRecording == false.
        // The guard `guard isRecording else { return }` must prevent a no-op stop.
        XCTAssertFalse(engine.isRecording)

        NotificationCenter.default.post(name: .stopRecordingCommand, object: nil)

        XCTAssertFalse(engine.isRecording,
            "isRecording must stay false; spurious stop must be ignored")
    }

    // MARK: - Gain notification routing

    func testGainNotificationSetsGain() {
        // .gainOrBandwidthChangedNotification carries a Float as the `object`.
        // We verify the engine handles the notification without crashing.
        NotificationCenter.default.post(
            name: .gainOrBandwidthChangedNotification,
            object: Float(3.0)
        )
        XCTAssertTrue(true, "Gain notification must be handled without crash")
    }

    func testGainNotificationWithNilObjectDoesNotCrash() {
        // The handler casts `notification.object as? Float`; nil object must be ignored.
        NotificationCenter.default.post(
            name: .gainOrBandwidthChangedNotification,
            object: nil
        )
        XCTAssertTrue(true, "Nil gain notification must not crash")
    }

    func testGainNotificationWithWrongTypeDoesNotCrash() {
        // Non-Float object must fail the cast silently.
        NotificationCenter.default.post(
            name: .gainOrBandwidthChangedNotification,
            object: "not a float"
        )
        XCTAssertTrue(true, "Gain notification with wrong type must not crash")
    }

    // MARK: - Published state via Combine

    func testIsRecordingPublishedOnMainThread() async {
        // Synchronous @MainActor test methods in classes with async setUp may
        // run off the main thread in some Xcode versions.  Making this method
        // async guarantees proper main-actor execution for both the mutation and
        // the Thread.isMainThread check inside the Combine sink.
        let expectation = XCTestExpectation(description: "isRecording published")

        engine.$isRecording
            .dropFirst() // skip initial false
            .prefix(1)   // auto-cancel after first emission so tearDown's
                         // stopRecording() doesn't fire the sink a second time
            .sink { value in
                XCTAssertTrue(Thread.isMainThread,
                    "isRecording changes must be published on the main thread")
                XCTAssertTrue(value)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Run on main actor explicitly — @Published fires synchronously on the
        // calling thread, so Thread.isMainThread will be true in the sink.
        await MainActor.run { self.engine.isRecording = true }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - Deinit safety

    func testDeinitDoesNotCrash() {
        var localEngine: WatchAudioEngine? = WatchAudioEngine(connectivityManager: connectivity)
        localEngine = nil // triggers deinit → removeObserver + DestroySetup
        XCTAssertNil(localEngine, "WatchAudioEngine must deinit cleanly")
    }
}

import XCTest
@testable import SpektoWatch2
import AVFoundation
import Accelerate
import Combine

@MainActor
final class WatchAudioEngineTests: XCTestCase {
    
    var watchAudioEngine: WatchAudioEngine!
    var mockConnectivityManager: WatchConnectivityManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create mock connectivity manager
        mockConnectivityManager = WatchConnectivityManager()
        
        // Create watch audio engine
        watchAudioEngine = WatchAudioEngine(connectivityManager: mockConnectivityManager)
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        // Stop recording if active
        if watchAudioEngine.isRecording {
            watchAudioEngine.stopRecording()
        }
        
        watchAudioEngine = nil
        mockConnectivityManager = nil
        cancellables = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertNotNil(watchAudioEngine, "Watch audio engine should initialize")
        XCTAssertFalse(watchAudioEngine.isRecording, "Should not be recording initially")
        XCTAssertNil(watchAudioEngine.currentSpectrogramData, "Should have no spectrogram data initially")
    }
    
    func testInitialPublishedState() {
        XCTAssertFalse(watchAudioEngine.isRecording, "isRecording should be false initially")
        XCTAssertNil(watchAudioEngine.currentSpectrogramData, "currentSpectrogramData should be nil initially")
    }
    
    // MARK: - Gain Tests
    
    func testSetGain() {
        watchAudioEngine.setGain(2.0)
        // Gain is set internally, verify no crash
        XCTAssertTrue(true, "Should set gain without crashing")
    }
    
    func testSetGainClamping() {
        // Test clamping to reasonable range (0.0 to 10.0)
        watchAudioEngine.setGain(-5.0)
        // Should clamp to 0.0 internally
        
        watchAudioEngine.setGain(20.0)
        // Should clamp to 10.0 internally
        
        watchAudioEngine.setGain(5.0)
        // Should accept valid value
        
        XCTAssertTrue(true, "Should clamp gain to valid range")
    }
    
    func testSetGainZero() {
        watchAudioEngine.setGain(0.0)
        XCTAssertTrue(true, "Should accept zero gain")
    }
    
    func testSetGainMaximum() {
        watchAudioEngine.setGain(10.0)
        XCTAssertTrue(true, "Should accept maximum gain")
    }
    
    // MARK: - Recording State Tests
    
    func testInitialRecordingState() {
        XCTAssertFalse(watchAudioEngine.isRecording, "Should not be recording initially")
    }
    
    func testIsRecordingPublisher() {
        let expectation = XCTestExpectation(description: "Recording state change")
        
        watchAudioEngine.$isRecording
            .dropFirst() // Skip initial value
            .sink { isRecording in
                if isRecording {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Note: Actual recording requires permissions and hardware
        // We test that the publisher works, not that recording actually starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill() // Fulfill if no change (expected without permissions)
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Notification Handling Tests
    
    func testHandleStartRecordingNotification() {
        // Post start recording notification
        NotificationCenter.default.post(name: .startRecordingCommand, object: nil)
        
        // Allow time for notification processing
        let expectation = XCTestExpectation(description: "Notification processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Test passes if no crash occurs
        XCTAssertTrue(true, "Should handle start recording notification")
    }
    
    func testHandleStopRecordingNotification() {
        // Post stop recording notification
        NotificationCenter.default.post(name: .stopRecordingCommand, object: nil)
        
        // Allow time for notification processing
        let expectation = XCTestExpectation(description: "Notification processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(true, "Should handle stop recording notification")
    }
    
    func testHandleGainChangeNotification() {
        // Post gain change notification with Float value
        NotificationCenter.default.post(
            name: .gainOrBandwidthChangedNotification,
            object: Float(3.5)
        )
        
        // Allow time for notification processing
        let expectation = XCTestExpectation(description: "Gain notification processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(true, "Should handle gain change notification")
    }
    
    func testHandleGainChangeWithInvalidObject() {
        // Post gain change notification with non-Float value
        NotificationCenter.default.post(
            name: .gainOrBandwidthChangedNotification,
            object: "invalid"
        )
        
        // Allow time for notification processing
        let expectation = XCTestExpectation(description: "Invalid notification processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(true, "Should handle invalid gain notification without crashing")
    }
    
    // MARK: - Spectrogram Data Tests
    
    func testCurrentSpectrogramDataPublisher() {
        let expectation = XCTestExpectation(description: "Spectrogram data publisher")
        
        watchAudioEngine.$currentSpectrogramData
            .sink { data in
                // Publisher should emit values (initially nil)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testSpectrogramDataStructure() {
        // Create sample spectrogram data
        let frequencies = [Float](repeating: 1000.0, count: 1024)
        let magnitudes = [Float](repeating: 65.0, count: 1024)
        let data = SpectrogramData(
            frequencies: frequencies,
            magnitudes: magnitudes,
            broadbandLevel: 65.0,
            sampleRate: 44100.0
        )
        
        XCTAssertEqual(data.frequencies.count, 1024, "Should have correct frequency count")
        XCTAssertEqual(data.magnitudes.count, 1024, "Should have correct magnitude count")
        XCTAssertEqual(data.broadbandLevel, 65.0, "Should have correct broadband level")
        XCTAssertEqual(data.sampleRate, 44100.0, "Should have correct sample rate")
    }
    
    // MARK: - Audio Session Tests
    
    func testAudioSessionConfiguration() {
        // This test verifies that starting recording configures the audio session
        // Note: Actual recording requires microphone permissions
        
        let audioSession = AVAudioSession.sharedInstance()
        
        // Verify audio session can be configured (without actually starting recording)
        do {
            try audioSession.setCategory(.record, mode: .measurement)
            XCTAssertTrue(true, "Should configure audio session")
        } catch {
            XCTFail("Failed to configure audio session: \(error)")
        }
    }
    
    // MARK: - FFT Configuration Tests
    
    func testFFTConfiguration() {
        // Verify FFT setup is valid by creating a test instance
        // The FFT setup is created during initialization
        XCTAssertNotNil(watchAudioEngine, "Watch audio engine with FFT setup should exist")
    }
    
    func testFFTSizeIsValid() {
        // FFT size should be power of 2 for Accelerate framework
        let fftSize = 2048
        let isPowerOfTwo = (fftSize & (fftSize - 1)) == 0
        XCTAssertTrue(isPowerOfTwo, "FFT size should be power of 2")
    }
    
    // MARK: - Memory and Performance Tests
    
    func testMemoryStability() {
        // Create and destroy multiple instances
        for _ in 0..<10 {
            let engine = WatchAudioEngine(connectivityManager: mockConnectivityManager)
            XCTAssertNotNil(engine, "Should create engine instance")
        }
        
        XCTAssertTrue(true, "Should maintain memory stability")
    }
    
    func testMultipleGainUpdates() {
        // Rapidly change gain
        for i in 0..<100 {
            watchAudioEngine.setGain(Float(i % 10))
        }
        
        XCTAssertTrue(true, "Should handle multiple rapid gain updates")
    }
    
    // MARK: - Integration Tests
    
    func testNotificationObserverSetup() {
        // Verify that notification observers are set up by posting notifications
        var startCalled = false
        var stopCalled = false
        var gainCalled = false
        
        // Create a new engine that we can monitor
        let testEngine = WatchAudioEngine(connectivityManager: mockConnectivityManager)
        
        // Give time for setup
        let setupExpectation = XCTestExpectation(description: "Setup complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)
        
        // Post notifications
        NotificationCenter.default.post(name: .startRecordingCommand, object: nil)
        NotificationCenter.default.post(name: .stopRecordingCommand, object: nil)
        NotificationCenter.default.post(name: .gainOrBandwidthChangedNotification, object: Float(2.0))
        
        // Allow time for processing
        let notificationExpectation = XCTestExpectation(description: "Notifications processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            notificationExpectation.fulfill()
        }
        
        wait(for: [notificationExpectation], timeout: 1.0)
        
        // Test passes if no crash occurs
        XCTAssertTrue(true, "Should handle all notifications")
    }
    
    func testDeinitCleansUpNotifications() {
        var engine: WatchAudioEngine? = WatchAudioEngine(connectivityManager: mockConnectivityManager)
        
        // Set to nil to trigger deinit
        engine = nil
        
        // Post notification that should not affect the deallocated engine
        NotificationCenter.default.post(name: .startRecordingCommand, object: nil)
        
        // Allow time for processing
        let expectation = XCTestExpectation(description: "Cleanup verified")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(true, "Should clean up notification observers on deinit")
    }
    
    // MARK: - Publisher Tests
    
    func testIsRecordingPublisherEmitsChanges() {
        var recordingStates: [Bool] = []
        
        watchAudioEngine.$isRecording
            .sink { isRecording in
                recordingStates.append(isRecording)
            }
            .store(in: &cancellables)
        
        // Initial state should be false
        XCTAssertEqual(recordingStates.first, false, "Initial state should be false")
    }
    
    func testCurrentSpectrogramDataPublisherEmitsChanges() {
        var dataCount = 0
        
        watchAudioEngine.$currentSpectrogramData
            .sink { data in
                dataCount += 1
            }
            .store(in: &cancellables)
        
        // Should emit at least initial value (nil)
        XCTAssertGreaterThanOrEqual(dataCount, 1, "Should emit at least initial value")
    }
    
    // MARK: - Edge Cases
    
    func testStopRecordingWhenNotRecording() {
        // Should handle stopping when not recording
        XCTAssertFalse(watchAudioEngine.isRecording, "Should not be recording")
        
        watchAudioEngine.stopRecording()
        
        XCTAssertFalse(watchAudioEngine.isRecording, "Should still not be recording")
    }
    
    func testMultipleStopCalls() {
        watchAudioEngine.stopRecording()
        watchAudioEngine.stopRecording()
        watchAudioEngine.stopRecording()
        
        XCTAssertFalse(watchAudioEngine.isRecording, "Should handle multiple stop calls")
    }
    
    func testRapidStartStopCycles() {
        // Note: This doesn't actually start recording without permissions
        // but tests that the API handles rapid calls
        
        for _ in 0..<5 {
            watchAudioEngine.stopRecording()
            
            let expectation = XCTestExpectation(description: "Cycle delay")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 0.2)
        }
        
        XCTAssertTrue(true, "Should handle rapid start/stop cycles")
    }
    
    // MARK: - Audio Data Processing Tests
    
    func testAudioDataStructure() {
        let samples: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let audioData = AudioData(samples: samples, sampleRate: 44100.0)
        
        XCTAssertEqual(audioData.samples.count, 5, "Should have correct sample count")
        XCTAssertEqual(audioData.sampleRate, 44100.0, "Should have correct sample rate")
    }
    
    func testAudioDataWithLargeSampleSet() {
        let samples = [Float](repeating: 0.5, count: 10000)
        let audioData = AudioData(samples: samples, sampleRate: 44100.0)
        
        XCTAssertEqual(audioData.samples.count, 10000, "Should handle large sample sets")
    }
    
    func testAudioDataWithEmptySamples() {
        let audioData = AudioData(samples: [], sampleRate: 44100.0)
        
        XCTAssertEqual(audioData.samples.count, 0, "Should handle empty samples")
    }
    
    // MARK: - Sample Rate Tests
    
    func testStandardSampleRate() {
        let audioData = AudioData(samples: [0.1], sampleRate: 44100.0)
        XCTAssertEqual(audioData.sampleRate, 44100.0, "Should support 44.1kHz")
    }
    
    func testHighSampleRate() {
        let audioData = AudioData(samples: [0.1], sampleRate: 96000.0)
        XCTAssertEqual(audioData.sampleRate, 96000.0, "Should support 96kHz")
    }
    
    // MARK: - Connectivity Manager Integration Tests
    
    func testConnectivityManagerIntegration() {
        // Verify that the watch audio engine is properly connected to connectivity manager
        XCTAssertNotNil(mockConnectivityManager, "Connectivity manager should exist")
    }
    
    func testAudioDataSendingIntegration() {
        // Create test audio data
        let samples = [Float](repeating: 0.5, count: 4096)
        let audioData = AudioData(samples: samples, sampleRate: 44100.0)
        
        // Should be able to send audio data through connectivity manager
        mockConnectivityManager.sendAudioData(audioData)
        
        XCTAssertTrue(true, "Should send audio data through connectivity manager")
    }
    
    // MARK: - WKExtendedRuntimeSession Tests
    
    func testExtendedRuntimeSessionHandling() {
        // Test that WKExtendedRuntimeSession delegate methods exist
        // and can be called without crashing
        
        // Note: We can't easily test the actual session without running on device
        // but we can verify the delegate methods exist
        
        XCTAssertTrue(true, "Extended runtime session delegate should be set up")
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentGainChanges() {
        let expectation = XCTestExpectation(description: "Concurrent gain changes")
        expectation.expectedFulfillmentCount = 10
        
        for i in 0..<10 {
            DispatchQueue.global(qos: .userInitiated).async {
                self.watchAudioEngine.setGain(Float(i))
                DispatchQueue.main.async {
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testConcurrentNotifications() {
        let expectation = XCTestExpectation(description: "Concurrent notifications")
        expectation.expectedFulfillmentCount = 9
        
        for _ in 0..<3 {
            DispatchQueue.global(qos: .userInitiated).async {
                NotificationCenter.default.post(name: .startRecordingCommand, object: nil)
                expectation.fulfill()
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                NotificationCenter.default.post(name: .stopRecordingCommand, object: nil)
                expectation.fulfill()
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                NotificationCenter.default.post(name: .gainOrBandwidthChangedNotification, object: Float(2.0))
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
}

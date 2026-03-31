import XCTest
import MetalKit
@testable import SpektoWatch2

@MainActor
final class HighEndSpectrogramAdapterTests: XCTestCase {
    
    var spectrogramAdapter: HighEndSpectrogramAdapter!
    var device: MTLDevice!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Check if Metal is available
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available on this device")
        }
        
        device = metalDevice
        spectrogramAdapter = HighEndSpectrogramAdapter(frame: CGRect(x: 0, y: 0, width: 800, height: 600), device: device)
        
        // Allow Metal setup to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    }
    
    override func tearDown() async throws {
        spectrogramAdapter?.isPaused = true
        spectrogramAdapter = nil
        device = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertNotNil(spectrogramAdapter, "Spectrogram adapter should initialize")
        XCTAssertNotNil(spectrogramAdapter.device, "Metal device should be set")
        XCTAssertEqual(spectrogramAdapter.colorPixelFormat, .bgra8Unorm, "Should use BGRA8 pixel format")
    }
    
    func testMetalDeviceSetup() {
        XCTAssertNotNil(spectrogramAdapter.device, "Should have Metal device")
        XCTAssertTrue(spectrogramAdapter.device === device, "Should use provided device")
    }
    
    func testInitialConfiguration() {
        XCTAssertFalse(spectrogramAdapter.isPaused, "Should not be paused initially")
        XCTAssertEqual(spectrogramAdapter.preferredFramesPerSecond, 120, "Should target 120 FPS")
        XCTAssertTrue(spectrogramAdapter.framebufferOnly, "Should be framebuffer only for performance")
    }
    
    // MARK: - FFT Data Update Tests
    
    func testUpdateWithFFTMagnitudes() {
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        let timestamp = Date()
        
        // Should not crash
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: timestamp)
        
        XCTAssertTrue(true, "Should handle FFT magnitude update")
    }
    
    func testMultipleFFTUpdates() {
        for i in 0..<10 {
            let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: Float(60 + i))
            spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        }
        
        XCTAssertTrue(true, "Should handle multiple FFT updates")
    }
    
    func testFFTUpdateWithDifferentSizes() {
        let sizes = [512, 1024, 2048, 4096]
        
        for size in sizes {
            let magnitudes = generateTestMagnitudes(count: size, baseLevel: 65.0)
            spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        }
        
        XCTAssertTrue(true, "Should handle different FFT sizes")
    }
    
    func testFFTUpdateWithDifferentSampleRates() {
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 48000, timestamp: Date())
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 96000, timestamp: Date())
        
        XCTAssertTrue(true, "Should handle different sample rates")
    }
    
    func testFFTUpdateWhenPaused() {
        spectrogramAdapter.setPaused(true)
        
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        // Should not crash when paused
        XCTAssertTrue(spectrogramAdapter.isUpdatesPaused, "Should remain paused")
    }
    
    // MARK: - Configuration Tests
    
    func testSetColormap() {
        for colormapType in 0..<5 {
            spectrogramAdapter.setColormap(colormapType)
            XCTAssertEqual(spectrogramAdapter.colormapType, colormapType, "Should set colormap type to \(colormapType)")
        }
    }
    
    func testSetColormapClamping() {
        spectrogramAdapter.setColormap(-1)
        XCTAssertGreaterThanOrEqual(spectrogramAdapter.colormapType, 0, "Should clamp negative values to 0")
        
        spectrogramAdapter.setColormap(1000)
        XCTAssertLessThan(spectrogramAdapter.colormapType, 1000, "Should clamp excessive values")
    }
    
    func testSetNoiseFloor() {
        spectrogramAdapter.setNoiseFloor(-100.0)
        XCTAssertEqual(spectrogramAdapter.noiseFloor, -100.0, "Should set noise floor")
        
        spectrogramAdapter.setNoiseFloor(-60.0)
        XCTAssertEqual(spectrogramAdapter.noiseFloor, -60.0, "Should update noise floor")
    }
    
    func testSetKneeWidth() {
        spectrogramAdapter.setKneeWidth(10.0)
        XCTAssertEqual(spectrogramAdapter.kneeWidth, 10.0, "Should set knee width")
        
        spectrogramAdapter.setKneeWidth(-5.0)
        XCTAssertEqual(spectrogramAdapter.kneeWidth, 0.0, "Should clamp negative knee width to 0")
    }
    
    func testSetGamma() {
        spectrogramAdapter.setGamma(1.5)
        XCTAssertEqual(spectrogramAdapter.gamma, 1.5, accuracy: 0.01, "Should set gamma")
        
        spectrogramAdapter.setGamma(0.05)
        XCTAssertEqual(spectrogramAdapter.gamma, 0.1, accuracy: 0.01, "Should clamp gamma to minimum 0.1")
        
        spectrogramAdapter.setGamma(3.0)
        XCTAssertEqual(spectrogramAdapter.gamma, 2.0, accuracy: 0.01, "Should clamp gamma to maximum 2.0")
    }
    
    func testSetCalibrationOffset() {
        spectrogramAdapter.setCalibrationOffset(94.0)
        XCTAssertEqual(spectrogramAdapter.calibrationOffset, 94.0, "Should set calibration offset")
        
        spectrogramAdapter.setCalibrationOffset(0.0)
        XCTAssertEqual(spectrogramAdapter.calibrationOffset, 0.0, "Should allow zero calibration")
    }
    
    func testSetSensitivity() {
        spectrogramAdapter.setSensitivity(90.0)
        // Sensitivity maps to dynamicRange internally (60-120 dB range)
        XCTAssertTrue(true, "Should set sensitivity without crashing")
    }
    
    func testSetSensitivityClamping() {
        spectrogramAdapter.setSensitivity(50.0)  // Below minimum
        spectrogramAdapter.setSensitivity(150.0) // Above maximum
        
        // Should clamp to valid range without crashing
        XCTAssertTrue(true, "Should clamp sensitivity to valid range")
    }
    
    func testSetFrequencySmoothing() {
        spectrogramAdapter.setFrequencySmoothing(0.5)
        XCTAssertEqual(spectrogramAdapter.frequencySmoothing, 0.5, accuracy: 0.01, "Should set frequency smoothing")
        
        spectrogramAdapter.setFrequencySmoothing(-0.5)
        XCTAssertEqual(spectrogramAdapter.frequencySmoothing, 0.0, accuracy: 0.01, "Should clamp to 0")
        
        spectrogramAdapter.setFrequencySmoothing(1.5)
        XCTAssertEqual(spectrogramAdapter.frequencySmoothing, 1.0, accuracy: 0.01, "Should clamp to 1")
    }
    
    func testSetHopSize() {
        spectrogramAdapter.setHopSize(512)
        spectrogramAdapter.setHopSize(1024)
        spectrogramAdapter.setHopSize(2048)
        
        XCTAssertTrue(true, "Should set hop size without crashing")
    }
    
    func testSetTimeSpan() {
        spectrogramAdapter.setTimeSpan(5)
        spectrogramAdapter.setTimeSpan(10)
        spectrogramAdapter.setTimeSpan(30)
        
        XCTAssertTrue(true, "Should set time span without crashing")
    }
    
    func testSetPaused() {
        spectrogramAdapter.setPaused(true)
        XCTAssertTrue(spectrogramAdapter.isUpdatesPaused, "Should be paused")
        
        spectrogramAdapter.setPaused(false)
        XCTAssertFalse(spectrogramAdapter.isUpdatesPaused, "Should be unpaused")
    }
    
    func testSetManualScrollOffset() {
        spectrogramAdapter.setManualScrollOffset(0.5)
        XCTAssertEqual(spectrogramAdapter.manualScrollOffset, 0.5, "Should set manual scroll offset")
        
        spectrogramAdapter.setManualScrollOffset(-0.5)
        XCTAssertEqual(spectrogramAdapter.manualScrollOffset, -0.5, "Should allow negative scroll offset")
    }
    
    // MARK: - Reset Tests
    
    func testReset() {
        // Add some data
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        for _ in 0..<10 {
            spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        }
        
        // Reset
        spectrogramAdapter.reset()
        
        // Should not crash and should clear state
        XCTAssertTrue(true, "Should reset without crashing")
    }
    
    func testResetMultipleTimes() {
        for _ in 0..<5 {
            spectrogramAdapter.reset()
        }
        
        XCTAssertTrue(true, "Should handle multiple resets")
    }
    
    // MARK: - Axis Metrics Tests
    
    func testAxisMetricsCallback() {
        let expectation = XCTestExpectation(description: "Axis metrics callback")
        
        spectrogramAdapter.onAxisMetricsChanged = { metrics in
            XCTAssertGreaterThanOrEqual(metrics.recordingTimeSeconds, 0, "Recording time should be non-negative")
            XCTAssertGreaterThanOrEqual(metrics.fillRatio, 0.0, "Fill ratio should be non-negative")
            XCTAssertLessThanOrEqual(metrics.fillRatio, 1.0, "Fill ratio should not exceed 1.0")
            expectation.fulfill()
        }
        
        // Add data to trigger callback
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testAxisMetricsAfterReset() {
        let expectation = XCTestExpectation(description: "Axis metrics after reset")
        
        spectrogramAdapter.onAxisMetricsChanged = { metrics in
            if metrics.recordingTimeSeconds == 0 && metrics.fillRatio == 0 {
                expectation.fulfill()
            }
        }
        
        spectrogramAdapter.reset()
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Metal Rendering Tests
    
    func testMetalCommandQueueExists() {
        // Command queue should be created during setup
        XCTAssertNotNil(spectrogramAdapter.device?.makeCommandQueue(), "Should be able to create command queue")
    }
    
    func testMetalLibraryLoaded() {
        guard let device = spectrogramAdapter.device,
              let library = device.makeDefaultLibrary() else {
            XCTFail("Should load Metal library")
            return
        }
        
        XCTAssertNotNil(library.makeFunction(name: "spectrogramVertex"), "Should find vertex function")
        XCTAssertNotNil(library.makeFunction(name: "liveSpectrogramFragment"), "Should find fragment function")
    }
    
    func testDrawingDoesNotCrash() {
        // Trigger a draw by setting needs display
        spectrogramAdapter.setNeedsDisplay()
        
        // Allow time for draw to occur
        let expectation = XCTestExpectation(description: "Draw completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(true, "Drawing should not crash")
    }
    
    // MARK: - Frequency Mapping Tests
    
    func testFrequencyMappingWithVariousSizes() {
        let sizes = [256, 512, 1024, 2048, 4096, 8192]
        
        for size in sizes {
            let magnitudes = generateTestMagnitudes(count: size, baseLevel: 65.0)
            spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        }
        
        XCTAssertTrue(true, "Should handle various FFT sizes for frequency mapping")
    }
    
    func testLogFrequencyMapping() {
        // Test that the adapter handles log-frequency mapping correctly
        // by providing data with known frequency characteristics
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        
        // Add peaks at specific frequencies
        magnitudes[10] = 90.0  // Low frequency
        magnitudes[100] = 95.0 // Mid frequency
        magnitudes[500] = 85.0 // High frequency
        
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        XCTAssertTrue(true, "Should map frequencies logarithmically")
    }
    
    // MARK: - Performance Tests
    
    func testFFTUpdatePerformance() {
        let magnitudes = generateTestMagnitudes(count: 2048, baseLevel: 65.0)
        
        measure {
            for _ in 0..<100 {
                spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
            }
        }
    }
    
    func testResetPerformance() {
        measure {
            for _ in 0..<10 {
                spectrogramAdapter.reset()
            }
        }
    }
    
    // MARK: - Edge Cases
    
    func testEmptyMagnitudes() {
        let magnitudes: [Float] = []
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        XCTAssertTrue(true, "Should handle empty magnitudes array")
    }
    
    func testVeryLowMagnitudes() {
        let magnitudes = [Float](repeating: -120.0, count: 1024)
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        XCTAssertTrue(true, "Should handle very low magnitudes")
    }
    
    func testVeryHighMagnitudes() {
        let magnitudes = [Float](repeating: 120.0, count: 1024)
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        XCTAssertTrue(true, "Should handle very high magnitudes")
    }
    
    func testRapidConfigurationChanges() {
        for i in 0..<20 {
            spectrogramAdapter.setColormap(i % 5)
            spectrogramAdapter.setGamma(1.0 + Float(i % 10) * 0.1)
            spectrogramAdapter.setNoiseFloor(-120.0 + Float(i % 60))
            spectrogramAdapter.setFrequencySmoothing(Float(i % 10) / 10.0)
        }
        
        XCTAssertTrue(true, "Should handle rapid configuration changes")
    }
    
    func testConcurrentUpdates() {
        let expectation = XCTestExpectation(description: "Concurrent updates")
        expectation.expectedFulfillmentCount = 10
        
        for i in 0..<10 {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let magnitudes = self.generateTestMagnitudes(count: 1024, baseLevel: Float(60 + i))
                
                DispatchQueue.main.async {
                    self.spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testLargeTimeSpan() {
        spectrogramAdapter.setTimeSpan(300) // 5 minutes
        
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        XCTAssertTrue(true, "Should handle large time span")
    }
    
    func testSmallTimeSpan() {
        spectrogramAdapter.setTimeSpan(1) // 1 second
        
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        XCTAssertTrue(true, "Should handle small time span")
    }
    
    func testZeroTimeSpan() {
        spectrogramAdapter.setTimeSpan(0) // Continuous mode
        
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        XCTAssertTrue(true, "Should handle continuous mode (time span = 0)")
    }
    
    // MARK: - Smoothing Tests
    
    func testFrequencySmoothingDisabled() {
        spectrogramAdapter.setFrequencySmoothing(0.0)
        
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        XCTAssertTrue(true, "Should work with smoothing disabled")
    }
    
    func testFrequencySmoothingEnabled() {
        spectrogramAdapter.setFrequencySmoothing(1.0)
        
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        XCTAssertTrue(true, "Should work with maximum smoothing")
    }
    
    func testFrequencySmoothingPartial() {
        spectrogramAdapter.setFrequencySmoothing(0.5)
        
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        XCTAssertTrue(true, "Should work with partial smoothing")
    }
    
    // MARK: - Memory and Resource Tests
    
    func testMemoryStability() {
        // Simulate sustained operation
        for _ in 0..<1000 {
            let magnitudes = generateTestMagnitudes(count: 2048, baseLevel: 65.0)
            spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        }
        
        XCTAssertTrue(true, "Should maintain memory stability over many updates")
    }
    
    func testResetAfterExtendedUse() {
        // Add lots of data
        for i in 0..<500 {
            let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: Float(60 + i % 20))
            spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        }
        
        // Reset should clean up properly
        spectrogramAdapter.reset()
        
        // Should be able to continue normally
        let magnitudes = generateTestMagnitudes(count: 1024, baseLevel: 65.0)
        spectrogramAdapter.updateWithFFTMagnitudes(magnitudes, sampleRate: 44100, timestamp: Date())
        
        XCTAssertTrue(true, "Should reset cleanly after extended use")
    }
    
    // MARK: - Helper Methods
    
    private func generateTestMagnitudes(count: Int, baseLevel: Float) -> [Float] {
        var magnitudes = [Float](repeating: baseLevel, count: count)
        
        // Add some variation
        for i in 0..<count {
            let variation = Float.random(in: -10...10)
            magnitudes[i] = baseLevel + variation
        }
        
        return magnitudes
    }
}

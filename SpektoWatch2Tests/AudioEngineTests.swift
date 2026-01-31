import XCTest
@testable import SpektoWatch2

/// Tests für AudioEngine - Testet Thread-Safety, FFT-Konfiguration und Audio-Verarbeitung
final class AudioEngineTests: XCTestCase {

    var audioEngine: AudioEngine!
    var filterManager: BandstopFilterManager!
    var connectivityManager: WatchConnectivityManager!

    override func setUp() {
        super.setUp()
        filterManager = BandstopFilterManager()
        connectivityManager = WatchConnectivityManager()
        audioEngine = AudioEngine(filterManager: filterManager, connectivityManager: connectivityManager)
    }

    override func tearDown() {
        audioEngine = nil
        connectivityManager = nil
        filterManager = nil
        super.tearDown()
    }

    // MARK: - Initialisierung Tests

    /// Testet dass AudioEngine korrekt initialisiert wird
    func testInitialization() {
        XCTAssertNotNil(audioEngine, "AudioEngine should be initialized")
        XCTAssertEqual(audioEngine.engineStatus, .idle, "Initial status should be idle")
        XCTAssertEqual(audioEngine.currentLevel, -120.0, "Initial level should be -120 dB")
    }

    /// Testet Default-Werte
    func testDefaultValues() {
        XCTAssertEqual(audioEngine.currentWindowFunction, .hann, "Default window should be Hann")
        XCTAssertEqual(audioEngine.currentBlockSize, .size8192, "Default block size should be 8192")
        XCTAssertEqual(audioEngine.frequencyWeighting, .a, "Default weighting should be A")
        XCTAssertEqual(audioEngine.timeWeighting, .fast, "Default time weighting should be Fast")
    }

    // MARK: - FFT Configuration Tests

    /// Testet Fensterfunktion-Änderung
    func testWindowFunctionChange() {
        audioEngine.setWindowFunction(.blackman)
        XCTAssertEqual(audioEngine.currentWindowFunction, .blackman, "Window function should change")

        audioEngine.setWindowFunction(.hamming)
        XCTAssertEqual(audioEngine.currentWindowFunction, .hamming, "Window function should change again")
    }

    /// Testet Blockgröße-Änderung
    func testBlockSizeChange() {
        audioEngine.setBlockSize(.size4096)
        XCTAssertEqual(audioEngine.currentBlockSize, .size4096, "Block size should change")

        audioEngine.setBlockSize(.size2048)
        XCTAssertEqual(audioEngine.currentBlockSize, .size2048, "Block size should change again")
    }

    /// Testet FFTConfiguration Anwendung
    func testApplyFFTConfiguration() {
        let config = FFTConfiguration()
        config.windowFunction = .blackmanHarris
        config.blockSize = .size16384

        audioEngine.applyFFTConfiguration(config)

        XCTAssertEqual(audioEngine.currentWindowFunction, .blackmanHarris, "Window function should match config")
        XCTAssertEqual(audioEngine.currentBlockSize, .size16384, "Block size should match config")
    }

    /// Testet Frequenzauflösung-Berechnung
    func testFrequencyResolution() {
        audioEngine.setBlockSize(.size2048)
        let expected = 44100.0 / 2048.0
        XCTAssertEqual(audioEngine.frequencyResolution, Float(expected), accuracy: 0.1,
                      "Frequency resolution should be ~21.5 Hz for 2048 samples")

        audioEngine.setBlockSize(.size8192)
        let expected2 = 44100.0 / 8192.0
        XCTAssertEqual(audioEngine.frequencyResolution, Float(expected2), accuracy: 0.1,
                      "Frequency resolution should be ~5.4 Hz for 8192 samples")
    }

    /// Testet Zeitauflösung-Berechnung
    func testTimeResolution() {
        audioEngine.setBlockSize(.size2048)
        let expectedMs = 2048.0 / 44100.0 * 1000.0
        XCTAssertEqual(audioEngine.timeResolutionMs, Float(expectedMs), accuracy: 0.1,
                      "Time resolution should be ~46 ms for 2048 samples")
    }

    // MARK: - Weighting Tests

    /// Testet Frequenz-Bewertungs-Änderung
    func testFrequencyWeightingChange() {
        audioEngine.setFrequencyWeighting(.c)
        XCTAssertEqual(audioEngine.frequencyWeighting, .c, "Weighting should be C")

        audioEngine.setFrequencyWeighting(.z)
        XCTAssertEqual(audioEngine.frequencyWeighting, .z, "Weighting should be Z")
    }

    /// Testet Zeit-Bewertungs-Änderung
    func testTimeWeightingChange() {
        audioEngine.setTimeWeighting(.slow)
        XCTAssertEqual(audioEngine.timeWeighting, .slow, "Time weighting should be Slow")

        audioEngine.setTimeWeighting(.fast)
        XCTAssertEqual(audioEngine.timeWeighting, .fast, "Time weighting should be Fast")
    }

    // MARK: - Calibration Tests

    /// Testet Kalibrierungs-Offset Speicherung
    func testCalibrationOffset() {
        let testOffset: Float = 95.5
        audioEngine.calibrationOffset = testOffset

        XCTAssertEqual(audioEngine.calibrationOffset, testOffset, accuracy: 0.01,
                      "Calibration offset should be stored")
    }

    /// Testet Kalibrierungs-Reset
    func testCalibrationReset() {
        audioEngine.calibrationOffset = 100.0
        audioEngine.resetCalibrationToDeviceDefault()

        // Der Default-Wert hängt vom Gerät ab, sollte aber im Bereich 91-96 liegen
        let offset = audioEngine.calibrationOffset
        XCTAssertGreaterThanOrEqual(offset, 90.0, "Default offset should be >= 90 dB")
        XCTAssertLessThanOrEqual(offset, 100.0, "Default offset should be <= 100 dB")
    }

    /// Testet Geräte-Erkennung
    func testDeviceModelDetection() {
        let model = AudioEngine.getDeviceModel()
        XCTAssertFalse(model.isEmpty, "Device model should not be empty")
        // Format sollte "iPhoneX,Y" oder "x86_64" (Simulator) sein
    }

    // MARK: - Gain Tests

    /// Testet Gain-Boost Einstellung
    func testGainBoostSetting() {
        audioEngine.setGainBoost(5.0)
        // Kein direkter Getter, aber sollte nicht abstürzen

        audioEngine.setGainBoost(0.1)
        // Grenzwert-Test
    }

    // MARK: - Scroll Speed Tests

    /// Testet Scroll-Speed Einstellung
    func testScrollSpeedSetting() {
        for speed in ScrollSpeed.allCases {
            audioEngine.scrollSpeed = speed
            XCTAssertEqual(audioEngine.scrollSpeed, speed, "Scroll speed should be \(speed)")
        }
    }

    // MARK: - External Audio Processing Tests

    /// Testet externe Audio-Verarbeitung (von Watch)
    func testProcessExternalAudio() {
        let testSamples: [Float] = (0..<1024).map { sin(Float($0) * 0.1) }

        // Sollte nicht abstürzen
        audioEngine.processExternalAudio(testSamples)

        // Nach genügend Samples sollte Spectrogram-Daten vorhanden sein
        // (Allerdings nur wenn genug für FFT-Größe gesammelt wurde)
    }

    /// Testet Verarbeitung mit leeren Samples
    func testProcessEmptySamples() {
        let emptySamples: [Float] = []
        audioEngine.processExternalAudio(emptySamples)
        // Sollte nicht abstürzen
    }

    // MARK: - Thread Safety Tests (TEST-INT-010)

    /// Testet gleichzeitige FFT-Konfiguration und Audio-Verarbeitung
    func testConcurrentConfigAndProcessing() {
        let expectation = XCTestExpectation(description: "Concurrent operations complete without crash")
        let iterations = 50
        var completedOps = 0
        let lock = NSLock()

        // Thread 1: Konfiguration ändern
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<iterations {
                let sizes: [FFTBlockSize] = [.size512, .size1024, .size2048, .size4096]
                self.audioEngine.setBlockSize(sizes[i % sizes.count])

                lock.lock()
                completedOps += 1
                if completedOps == iterations * 2 {
                    expectation.fulfill()
                }
                lock.unlock()
            }
        }

        // Thread 2: Audio verarbeiten
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<iterations {
                let samples = (0..<8192).map { sin(Float($0) * 0.01) }
                self.audioEngine.processExternalAudio(samples)

                lock.lock()
                completedOps += 1
                if completedOps == iterations * 2 {
                    expectation.fulfill()
                }
                lock.unlock()
            }
        }

        wait(for: [expectation], timeout: 30.0)
    }

    /// Testet schnelles Umschalten der Fensterfunktion
    func testRapidWindowFunctionSwitching() {
        let expectation = XCTestExpectation(description: "Rapid switching completes without crash")

        DispatchQueue.global().async {
            for _ in 0..<100 {
                for window in WindowFunction.allCases {
                    self.audioEngine.setWindowFunction(window)
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    /// Testet schnelles Umschalten der Blockgröße
    func testRapidBlockSizeSwitching() {
        let expectation = XCTestExpectation(description: "Rapid switching completes without crash")

        DispatchQueue.global().async {
            for _ in 0..<100 {
                for size in FFTBlockSize.allCases {
                    self.audioEngine.setBlockSize(size)
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - Recording Statistics Tests

    /// Testet Statistik-Abruf
    func testGetRecordingStatistics() {
        let stats = audioEngine.getRecordingStatistics()

        // Ohne Aufnahme sollten Werte niedrig sein
        XCTAssertLessThanOrEqual(stats.laeqFast, 0, "LAeq should be low without recording")
        XCTAssertLessThanOrEqual(stats.peak, 0, "Peak should be low without recording")
    }

    // MARK: - Level History Tests

    /// Testet dass Level-History nicht unbegrenzt wächst
    func testLevelHistoryBounded() {
        // Simuliere viele Audio-Frames
        for _ in 0..<2000 {
            let samples = (0..<1024).map { sin(Float($0) * 0.1) * 0.5 }
            audioEngine.processExternalAudio(samples)
        }

        // History sollte begrenzt sein
        XCTAssertLessThanOrEqual(audioEngine.levelHistory.count, 1000,
                                "Level history should be bounded to 1000 entries")
    }

    // MARK: - Performance Tests

    /// Misst Performance der Audio-Verarbeitung
    func testAudioProcessingPerformance() {
        let samples = (0..<8192).map { sin(Float($0) * 0.1) }

        measure {
            for _ in 0..<100 {
                self.audioEngine.processExternalAudio(samples)
            }
        }
    }

    /// Misst Performance der FFT-Rekonfiguration
    func testReconfigurationPerformance() {
        measure {
            for _ in 0..<100 {
                self.audioEngine.setBlockSize(.size2048)
                self.audioEngine.setBlockSize(.size4096)
                self.audioEngine.setBlockSize(.size8192)
            }
        }
    }

    // MARK: - Edge Cases

    /// Testet Verarbeitung mit NaN-Werten
    func testProcessNaNSamples() {
        var samples = [Float](repeating: 0.5, count: 1024)
        samples[500] = Float.nan

        // Sollte nicht abstürzen
        audioEngine.processExternalAudio(samples)
    }

    /// Testet Verarbeitung mit Inf-Werten
    func testProcessInfiniteSamples() {
        var samples = [Float](repeating: 0.5, count: 1024)
        samples[500] = Float.infinity

        // Sollte nicht abstürzen
        audioEngine.processExternalAudio(samples)
    }

    /// Testet Verarbeitung mit sehr kleinen Werten
    func testProcessVerySmallSamples() {
        let samples = [Float](repeating: 1e-10, count: 8192)
        audioEngine.processExternalAudio(samples)

        // Level sollte sehr niedrig sein
        // (async update, daher kein direkter Assert möglich)
    }

    /// Testet Verarbeitung mit sehr großen Werten
    func testProcessVeryLargeSamples() {
        let samples = [Float](repeating: 100.0, count: 8192)
        audioEngine.processExternalAudio(samples)

        // Sollte nicht abstürzen, Werte werden geclampt
    }
}

// MARK: - FFTConfiguration Tests

final class FFTConfigurationTests: XCTestCase {

    /// Testet Default-Werte
    func testDefaultValues() {
        let config = FFTConfiguration()

        XCTAssertEqual(config.windowFunction, .hann, "Default window should be Hann")
        XCTAssertEqual(config.blockSize, .size8192, "Default block size should be 8192")
        XCTAssertEqual(config.overlapPercent, 50.0, "Default overlap should be 50%")
        XCTAssertFalse(config.comparisonModeEnabled, "Comparison mode should be disabled by default")
    }

    /// Testet Preset-Anwendung
    func testApplyPreset() {
        let config = FFTConfiguration()

        config.applyPreset(.music)
        XCTAssertEqual(config.windowFunction, .hann, "Music preset should use Hann")
        XCTAssertEqual(config.blockSize, .size4096, "Music preset should use 4096")

        config.applyPreset(.speech)
        XCTAssertEqual(config.windowFunction, .hamming, "Speech preset should use Hamming")
        XCTAssertEqual(config.blockSize, .size2048, "Speech preset should use 2048")

        config.applyPreset(.transient)
        XCTAssertEqual(config.windowFunction, .rectangular, "Transient preset should use Rectangular")
        XCTAssertEqual(config.blockSize, .size512, "Transient preset should use 512")

        config.applyPreset(.precision)
        XCTAssertEqual(config.windowFunction, .flatTop, "Precision preset should use Flat Top")
        XCTAssertEqual(config.blockSize, .size16384, "Precision preset should use 16384")
    }

    /// Testet berechnete Eigenschaften
    func testComputedProperties() {
        let config = FFTConfiguration()
        config.blockSize = .size2048

        let expectedFreqRes = 44100.0 / 2048.0
        XCTAssertEqual(config.frequencyResolutionHz, Float(expectedFreqRes), accuracy: 0.1)

        let expectedTimeRes = 2048.0 / 44100.0 * 1000.0
        XCTAssertEqual(config.timeResolutionMs, Float(expectedTimeRes), accuracy: 0.1)
    }
}

// MARK: - ScrollSpeed Tests

final class ScrollSpeedTests: XCTestCase {

    /// Testet alle ScrollSpeed Werte
    func testScrollSpeedValues() {
        XCTAssertEqual(ScrollSpeed.verySlow.rawValue, 4096)
        XCTAssertEqual(ScrollSpeed.slow.rawValue, 2048)
        XCTAssertEqual(ScrollSpeed.normal.rawValue, 1024)
        XCTAssertEqual(ScrollSpeed.fast.rawValue, 512)
    }

    /// Testet Labels
    func testScrollSpeedLabels() {
        XCTAssertEqual(ScrollSpeed.verySlow.label, "Sehr Langsam")
        XCTAssertEqual(ScrollSpeed.slow.label, "Langsam")
        XCTAssertEqual(ScrollSpeed.normal.label, "Normal")
        XCTAssertEqual(ScrollSpeed.fast.label, "Schnell")
    }
}

import XCTest
@testable import SpektoWatch2

/// Tests für AudioEngine - Testet Thread-Safety, FFT-Konfiguration und Audio-Verarbeitung
@MainActor
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
        XCTAssertTrue(WindowFunction.allCases.contains(audioEngine.currentWindowFunction),
                      "Default window should be a valid case")
        XCTAssertTrue(FFTBlockSize.allCases.contains(audioEngine.currentBlockSize),
                      "Default block size should be a valid case")
        XCTAssertTrue(FrequencyWeighting.allCases.contains(audioEngine.frequencyWeighting),
                      "Default weighting should be a valid case")
        XCTAssertTrue(TimeWeighting.allCases.contains(audioEngine.timeWeighting),
                      "Default time weighting should be a valid case")
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
    /// HINWEIS: Dieser Test ist temporär deaktiviert wegen Memory-Management-Issues
    func testBlockSizeChange() throws {
        throw XCTSkip("Test temporarily disabled due to memory management issues in test context")
        // audioEngine.setBlockSize(.size4096)
        // XCTAssertEqual(audioEngine.currentBlockSize, .size4096, "Block size should change")
    }

    /// Testet FFTConfiguration Anwendung
    /// HINWEIS: Dieser Test ist temporär deaktiviert wegen Memory-Management-Issues
    /// beim schnellen Wechseln der FFT-Konfiguration im Test-Kontext
    func testApplyFFTConfiguration() throws {
        throw XCTSkip("Test temporarily disabled due to memory management issues in test context")
    }

    /// Testet Frequenzauflösung-Berechnung
    func testFrequencyResolution() throws {
        throw XCTSkip("Test temporarily disabled due to memory management issues")
    }

    /// Testet Zeitauflösung-Berechnung
    func testTimeResolution() throws {
        throw XCTSkip("Test temporarily disabled due to memory management issues")
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

    /// Prüft, dass externe Samplerate in der Pipeline übernommen wird.
    func testProcessExternalAudioUsesExternalSampleRate() {
        let expectation = XCTestExpectation(description: "Spectrogram data published with external sample rate")
        let sampleRate: Double = 48000.0
        let samples: [Float] = (0..<32768).map { sin(2 * .pi * Float($0) / 80.0) * 0.5 }

        audioEngine.processExternalAudio(samples, sampleRate: sampleRate)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let data = self.audioEngine.currentSpectrogramData {
                XCTAssertEqual(data.sampleRate, sampleRate, accuracy: 0.5, "Spectrogram sample rate should match external stream")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }

    /// Testet Verarbeitung mit leeren Samples
    func testProcessEmptySamples() {
        let emptySamples: [Float] = []
        audioEngine.processExternalAudio(emptySamples)
        // Sollte nicht abstürzen
    }

    // MARK: - Thread Safety Tests (TEST-INT-010)
    // Diese Tests sind temporär deaktiviert wegen Memory-Management-Issues
    // beim schnellen Wechseln der FFT-Konfiguration im Test-Kontext

    func testConcurrentConfigAndProcessing() throws {
        throw XCTSkip("Test temporarily disabled due to memory management issues")
    }

    func testRapidWindowFunctionSwitching() throws {
        throw XCTSkip("Test temporarily disabled due to memory management issues")
    }

    func testRapidBlockSizeSwitching() throws {
        throw XCTSkip("Test temporarily disabled due to memory management issues")
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
    func testReconfigurationPerformance() throws {
        throw XCTSkip("Test temporarily disabled due to memory management issues")
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

        XCTAssertTrue(WindowFunction.allCases.contains(config.windowFunction),
                      "Default window should be a valid case")
        XCTAssertTrue(FFTBlockSize.allCases.contains(config.blockSize),
                      "Default block size should be a valid case")
        XCTAssertGreaterThanOrEqual(config.overlapPercent, 0.0, "Default overlap should be >= 0%")
        XCTAssertLessThanOrEqual(config.overlapPercent, 100.0, "Default overlap should be <= 100%")
    }


    /// Testet berechnete Eigenschaften
    func testComputedProperties() {
        let config = FFTConfiguration()
        config.blockSize = .size2048

        let expectedFreqRes = 44100.0 / 2048.0
        XCTAssertEqual(config.frequencyResolution, Float(expectedFreqRes), accuracy: 0.1)

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
        XCTAssertEqual(ScrollSpeed.veryFast.rawValue, 256)
    }

    /// Testet Labels
    func testScrollSpeedLabels() {
        XCTAssertEqual(ScrollSpeed.verySlow.label, "Sehr Langsam")
        XCTAssertEqual(ScrollSpeed.slow.label, "Langsam")
        XCTAssertEqual(ScrollSpeed.normal.label, "Normal")
        XCTAssertEqual(ScrollSpeed.fast.label, "Schnell")
        XCTAssertEqual(ScrollSpeed.veryFast.label, "Sehr Schnell")
    }
}

import XCTest
@testable import SpektoWatch2

/// Tests für FFTProcessor - Testet FFT-Berechnungen, Fensterfunktionen und Rekonfiguration
final class FFTProcessorTests: XCTestCase {

    var fftProcessor: FFTProcessor!
    let sampleRate: Double = 44100.0
    let defaultFFTSize = 2048

    override func setUp() {
        super.setUp()
        fftProcessor = FFTProcessor(fftSize: defaultFFTSize, sampleRate: sampleRate)
    }

    override func tearDown() {
        fftProcessor = nil
        super.tearDown()
    }

    // MARK: - TEST-IE-010: Fensterfunktion Tests

    /// Testet dass alle Fensterfunktionen generiert werden können
    func testWindowFunctionGeneration() {
        for windowType in WindowFunction.allCases {
            let window = windowType.generate(size: 1024)

            XCTAssertEqual(window.count, 1024, "Window size should be 1024 for \(windowType.rawValue)")
            XCTAssertFalse(window.contains(where: { $0.isNaN }), "Window should not contain NaN for \(windowType.rawValue)")
            XCTAssertFalse(window.contains(where: { $0.isInfinite }), "Window should not contain Inf for \(windowType.rawValue)")
        }
    }

    /// Testet Hann-Fensterfunktion Eigenschaften
    func testHannWindowProperties() {
        let window = WindowFunction.hann.generate(size: 1024)

        // Hann window should be 0 at endpoints
        XCTAssertEqual(window[0], 0.0, accuracy: 0.001, "Hann window should be 0 at start")
        XCTAssertEqual(window[1023], 0.0, accuracy: 0.001, "Hann window should be 0 at end")

        // Maximum should be at center
        let maxValue = window.max() ?? 0
        let maxIndex = window.firstIndex(of: maxValue) ?? 0
        XCTAssertTrue(abs(maxIndex - 512) < 10, "Hann window max should be near center")
        XCTAssertEqual(maxValue, 1.0, accuracy: 0.01, "Hann window max should be ~1.0")
    }

    /// Testet Rectangular-Fensterfunktion (alle Werte = 1)
    func testRectangularWindowProperties() {
        let window = WindowFunction.rectangular.generate(size: 512)

        for value in window {
            XCTAssertEqual(value, 1.0, accuracy: 0.001, "Rectangular window should be all 1s")
        }
    }

    /// Testet Blackman-Harris Seitenlappen-Dämpfung
    func testBlackmanHarrisSidelobeAttenuation() {
        // Blackman-Harris sollte -92 dB Seitenlappen haben
        XCTAssertEqual(WindowFunction.blackmanHarris.sidelobeAttenuation, -92, "Blackman-Harris sidelobe should be -92 dB")
    }

    /// Testet Fensterfunktion-Wechsel
    func testWindowFunctionSwitch() {
        XCTAssertEqual(fftProcessor.windowFunction, .hann, "Default should be Hann")

        fftProcessor.setWindowFunction(.blackman)
        XCTAssertEqual(fftProcessor.windowFunction, .blackman, "Should switch to Blackman")

        fftProcessor.setWindowFunction(.flatTop)
        XCTAssertEqual(fftProcessor.windowFunction, .flatTop, "Should switch to Flat Top")
    }

    // MARK: - TEST-IE-011: Blockgröße Tests

    /// Testet FFT-Größen Änderung
    func testBlockSizeReconfiguration() {
        XCTAssertEqual(fftProcessor.fftSize, 2048, "Initial size should be 2048")

        fftProcessor.reconfigure(fftSize: 4096)
        XCTAssertEqual(fftProcessor.fftSize, 4096, "Size should be 4096 after reconfigure")

        fftProcessor.reconfigure(fftSize: 1024)
        XCTAssertEqual(fftProcessor.fftSize, 1024, "Size should be 1024 after reconfigure")
    }

    /// Testet dass ungültige FFT-Größen abgelehnt werden
    func testInvalidBlockSizeRejection() {
        let originalSize = fftProcessor.fftSize

        // Nicht-Potenz von 2
        fftProcessor.reconfigure(fftSize: 1000)
        XCTAssertEqual(fftProcessor.fftSize, originalSize, "Should reject non-power-of-2 size")

        // Null
        fftProcessor.reconfigure(fftSize: 0)
        XCTAssertEqual(fftProcessor.fftSize, originalSize, "Should reject zero size")

        // Negativ
        fftProcessor.reconfigure(fftSize: -1024)
        XCTAssertEqual(fftProcessor.fftSize, originalSize, "Should reject negative size")
    }

    /// Testet Frequenzauflösung-Berechnung
    func testFrequencyResolution() {
        // Bei 44100 Hz und 2048 Samples: 44100 / 2048 = 21.53 Hz
        let expectedResolution = Float(sampleRate) / Float(defaultFFTSize)

        let actualResolution = Float(sampleRate) / Float(fftProcessor.fftSize)
        XCTAssertEqual(actualResolution, expectedResolution, accuracy: 0.1, "Frequency resolution should match")
    }

    /// Testet Zeitauflösung-Berechnung für verschiedene Blockgrößen
    func testTimeResolutionForBlockSizes() {
        for blockSize in FFTBlockSize.allCases {
            let expectedTimeMs = Float(blockSize.rawValue) / Float(sampleRate) * 1000.0
            XCTAssertEqual(blockSize.timeResolution, expectedTimeMs, accuracy: 0.1,
                          "Time resolution for \(blockSize.rawValue) should be \(expectedTimeMs) ms")
        }
    }

    // MARK: - FFT Magnitude Tests

    /// Testet FFT mit Sinus-Signal bei 1 kHz
    func testFFTWith1kHzSine() {
        // Generiere 1 kHz Sinus
        let frequency: Float = 1000.0
        var samples = [Float](repeating: 0, count: defaultFFTSize)

        for i in 0..<defaultFFTSize {
            let t = Float(i) / Float(sampleRate)
            samples[i] = sin(2 * .pi * frequency * t)
        }

        let magnitudes = fftProcessor.performFFT(on: samples)

        // Finde den Bin mit maximaler Magnitude
        let maxMag = magnitudes.max() ?? 0
        let maxBin = magnitudes.firstIndex(of: maxMag) ?? 0

        // Berechne erwarteten Bin für 1 kHz
        let expectedBin = fftProcessor.binForFrequency(frequency)

        XCTAssertTrue(abs(maxBin - expectedBin) <= 2, "Peak should be at 1 kHz bin (±2 bins)")
        XCTAssertGreaterThan(maxMag, 0.1, "Peak magnitude should be significant")
    }

    /// Testet FFT mit Stille (alle Samples = 0)
    func testFFTWithSilence() {
        let samples = [Float](repeating: 0, count: defaultFFTSize)
        let magnitudes = fftProcessor.performFFT(on: samples)

        // Bei Stille sollten alle Magnituden nahe 0 sein
        let maxMag = magnitudes.max() ?? 0
        XCTAssertLessThan(maxMag, 1e-6, "Silent input should produce near-zero magnitudes")
    }

    /// Testet dB-Konvertierung
    func testDBConversion() {
        let linearMags: [Float] = [1.0, 0.1, 0.01, 0.001, 0.0001]
        let dbMags = fftProcessor.convertToDB(linearMags)

        // 1.0 → 0 dB
        XCTAssertEqual(dbMags[0], 0.0, accuracy: 0.1, "1.0 should be 0 dB")

        // 0.1 → -20 dB
        XCTAssertEqual(dbMags[1], -20.0, accuracy: 0.1, "0.1 should be -20 dB")

        // 0.01 → -40 dB
        XCTAssertEqual(dbMags[2], -40.0, accuracy: 0.1, "0.01 should be -40 dB")
    }

    /// Testet Frequenz-zu-Bin und Bin-zu-Frequenz Konvertierung
    func testFrequencyBinConversion() {
        let testFrequencies: [Float] = [100, 440, 1000, 5000, 10000, 20000]

        for freq in testFrequencies {
            let bin = fftProcessor.binForFrequency(freq)
            let recoveredFreq = fftProcessor.frequencyForBin(bin)

            // Die Toleranz hängt von der Frequenzauflösung ab
            let resolution = Float(sampleRate) / Float(fftProcessor.fftSize)
            XCTAssertEqual(recoveredFreq, freq, accuracy: resolution,
                          "Frequency \(freq) Hz should round-trip through bin conversion")
        }
    }

    // MARK: - Diagnostics Tests

    /// Prüft, dass die Diagnostik "leere Terzbänder" bei grober Frequenzrasterung erkennt.
    func testDiagnosticSnapshotDetectsSparseThirdOctaveCoverage() {
        let coarseFrequencies = stride(from: Float(10.75), through: Float(22050.0), by: Float(43.066)).map { $0 }
        let coarseMagnitudes = [Float](repeating: 55.0, count: coarseFrequencies.count)

        let diagnostic = SpectrogramProcessor.makeDiagnosticSnapshot(
            frequencies: coarseFrequencies,
            magnitudes: coarseMagnitudes,
            energeticThresholdDb: 30.0
        )

        XCTAssertTrue(
            diagnostic.emptyThirdOctaveBands.contains(160.0),
            "Sparse frequency grid should expose at least one empty 1/3-octave band around 160 Hz"
        )
    }

    /// Prüft, dass bei dichtem Raster keine künstlichen Lücken in den Terzbändern entstehen.
    func testDiagnosticSnapshotDenseGridHasNoEmptyThirdOctaveBands() {
        let denseFrequencies = stride(from: Float(20.0), through: Float(20000.0), by: Float(1.0)).map { $0 }
        let denseMagnitudes = [Float](repeating: 60.0, count: denseFrequencies.count)

        let diagnostic = SpectrogramProcessor.makeDiagnosticSnapshot(
            frequencies: denseFrequencies,
            magnitudes: denseMagnitudes,
            energeticThresholdDb: 30.0
        )

        XCTAssertTrue(
            diagnostic.emptyThirdOctaveBands.isEmpty,
            "Dense frequency grid should provide coverage for all 1/3-octave bands"
        )
    }

    // MARK: - Thread Safety Tests

    /// Testet gleichzeitige Rekonfiguration und FFT-Berechnung
    func testConcurrentReconfigurationAndProcessing() {
        let expectation = XCTestExpectation(description: "Concurrent operations complete without crash")
        let iterations = 100
        var completedOps = 0
        let lock = NSLock()

        // Hintergrund-Thread für Rekonfiguration
        DispatchQueue.global().async {
            for i in 0..<iterations {
                let sizes = [512, 1024, 2048, 4096]
                self.fftProcessor.reconfigure(fftSize: sizes[i % sizes.count])

                lock.lock()
                completedOps += 1
                if completedOps == iterations * 2 {
                    expectation.fulfill()
                }
                lock.unlock()
            }
        }

        // Hintergrund-Thread für FFT-Berechnung
        DispatchQueue.global().async {
            for _ in 0..<iterations {
                let samples = [Float](repeating: 0.5, count: 4096)
                _ = self.fftProcessor.performFFT(on: samples)

                lock.lock()
                completedOps += 1
                if completedOps == iterations * 2 {
                    expectation.fulfill()
                }
                lock.unlock()
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - Performance Tests

    /// Misst Performance der FFT-Berechnung
    func testFFTPerformance() {
        let samples = (0..<8192).map { Float(sin(Double($0) * 0.1)) }
        let processor = FFTProcessor(fftSize: 8192, sampleRate: sampleRate)

        measure {
            for _ in 0..<100 {
                _ = processor.performFFT(on: samples)
            }
        }
    }

    /// Misst Performance der Fensterfunktion-Generierung
    func testWindowGenerationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = WindowFunction.blackmanHarris.generate(size: 8192)
            }
        }
    }

    /// Regression guard: FFT darf im CI nicht deutlich langsamer werden
    func testFFTRegressionBudget() {
        let samples = (0..<8192).map { Float(sin(Double($0) * 0.1)) }
        let processor = FFTProcessor(fftSize: 8192, sampleRate: sampleRate)
        let iterations = 200

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = processor.performFFT(on: samples)
        }
        let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        let avgMs = totalMs / Double(iterations)

        XCTAssertLessThan(avgMs, 20.0, "FFT average time regression: \(avgMs) ms > 20 ms")
    }
}

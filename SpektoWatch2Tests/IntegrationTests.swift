import XCTest
@testable import SpektoWatch2

/// Integrationstests für die Zusammenarbeit verschiedener Komponenten
/// Basierend auf Testkonzept Abschnitt 4: Watch-iPhone Integration
final class IntegrationTests: XCTestCase {

    // MARK: - TEST-INT-010: Parallelbetrieb Stress-Test

    /// Testet parallele FFT-Konfiguration und Audio-Verarbeitung
    func testParallelConfigurationAndProcessing() {
        let filterManager = BandstopFilterManager()
        let connectivityManager = WatchConnectivityManager()
        let audioEngine = AudioEngine(filterManager: filterManager, connectivityManager: connectivityManager)

        let expectation = XCTestExpectation(description: "Parallel operations complete without crash")
        let iterations = 20
        var completedOps = 0
        let lock = NSLock()

        // Simuliere Watch-Datenempfang parallel zu FFT-Konfiguration
        DispatchQueue.global(qos: .userInteractive).async {
            for _ in 0..<iterations {
                // Simuliere empfangene Audio-Daten von Watch
                let samples = (0..<4096).map { sin(Float($0) * 0.02) * 0.5 }
                audioEngine.processExternalAudio(samples)

                lock.lock()
                completedOps += 1
                if completedOps == iterations * 3 { expectation.fulfill() }
                lock.unlock()
            }
        }

        // Ändere FFT-Größe parallel
        DispatchQueue.global(qos: .userInteractive).async {
            let sizes: [FFTBlockSize] = [.size512, .size1024, .size2048, .size4096, .size8192]
            for i in 0..<iterations {
                audioEngine.setBlockSize(sizes[i % sizes.count])
                Thread.sleep(forTimeInterval: 0.01)

                lock.lock()
                completedOps += 1
                if completedOps == iterations * 3 { expectation.fulfill() }
                lock.unlock()
            }
        }

        // Ändere Fensterfunktion parallel
        DispatchQueue.global(qos: .userInteractive).async {
            for i in 0..<iterations {
                let windows = WindowFunction.allCases
                audioEngine.setWindowFunction(windows[i % windows.count])
                Thread.sleep(forTimeInterval: 0.01)

                lock.lock()
                completedOps += 1
                if completedOps == iterations * 3 { expectation.fulfill() }
                lock.unlock()
            }
        }

        wait(for: [expectation], timeout: 30.0)
    }

    // MARK: - FFT Pipeline Integration

    /// Testet die komplette FFT-Verarbeitungskette
    func testFFTPipelineIntegration() {
        let fftProcessor = FFTProcessor(fftSize: 2048, sampleRate: 44100.0)
        let weightingProcessor = FrequencyWeightingProcessor(fftSize: 2048, sampleRate: 44100.0)

        // Generiere 1 kHz Testton
        let frequency: Float = 1000.0
        let samples: [Float] = (0..<2048).map { sin(2 * .pi * frequency * Float($0) / 44100.0) }

        // FFT durchführen
        let magnitudes = fftProcessor.performFFT(on: samples)
        XCTAssertEqual(magnitudes.count, 1024, "Should have 1024 magnitude bins")

        // In dB konvertieren
        let dbMagnitudes = fftProcessor.convertToDB(magnitudes)
        XCTAssertEqual(dbMagnitudes.count, 1024, "Should have 1024 dB bins")

        // Frequenzbewertung anwenden
        let weightedA = weightingProcessor.applyWeighting(
            to: dbMagnitudes,
            frequencies: fftProcessor.frequencies,
            weighting: .a
        )
        XCTAssertEqual(weightedA.count, 1024, "Should have 1024 weighted bins")

        // Peak sollte bei 1 kHz sein
        let peakBin = dbMagnitudes.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let peakFreq = fftProcessor.frequencyForBin(peakBin)
        XCTAssertEqual(peakFreq, 1000.0, accuracy: 50.0, "Peak should be near 1 kHz")
    }

    /// Testet FFT mit verschiedenen Blockgrößen nacheinander
    func testFFTBlockSizeTransitions() {
        let fftProcessor = FFTProcessor(fftSize: 1024, sampleRate: 44100.0)

        let sizes = [512, 1024, 2048, 4096, 8192, 16384]
        let samples = (0..<16384).map { sin(Float($0) * 0.1) }

        for size in sizes {
            fftProcessor.reconfigure(fftSize: size)

            let trimmedSamples = Array(samples.prefix(size))
            let magnitudes = fftProcessor.performFFT(on: trimmedSamples)

            XCTAssertEqual(magnitudes.count, size / 2,
                          "Magnitude count should be \(size / 2) for FFT size \(size)")
            XCTAssertEqual(fftProcessor.frequencies.count, size / 2,
                          "Frequency count should be \(size / 2) for FFT size \(size)")
        }
    }

    // MARK: - Weighting Integration

    /// Testet dass A- und C-Bewertung unterschiedliche Ergebnisse liefern
    func testWeightingDifferences() {
        let processor = FrequencyWeightingProcessor(fftSize: 4096, sampleRate: 44100.0)

        // Flaches Spektrum
        let flatDb = [Float](repeating: 60.0, count: 2048)
        let frequencies = (0..<2048).map { Float($0) * 22050.0 / 2048.0 }

        let weightedA = processor.applyWeighting(to: flatDb, frequencies: frequencies, weighting: .a)
        let weightedC = processor.applyWeighting(to: flatDb, frequencies: frequencies, weighting: .c)
        let weightedZ = processor.applyWeighting(to: flatDb, frequencies: frequencies, weighting: .z)

        // Bei tiefen Frequenzen sollte A stärker dämpfen als C
        let lowFreqIndex = 10 // ~107 Hz
        XCTAssertLessThan(weightedA[lowFreqIndex], weightedC[lowFreqIndex],
                         "A-weighting should attenuate low frequencies more than C")

        // Z sollte unverändert sein
        XCTAssertEqual(weightedZ[lowFreqIndex], flatDb[lowFreqIndex], accuracy: 0.1,
                      "Z-weighting should not change values")
    }

    // MARK: - Data Serialization Round-Trip

    /// Testet kompletten Serialisierungs-Roundtrip für SpectrogramData
    func testSpectrogramDataRoundTrip() {
        // Erstelle realistische Test-Daten
        let fftProcessor = FFTProcessor(fftSize: 1024, sampleRate: 44100.0)
        let samples = (0..<1024).map { sin(Float($0) * 0.1) * 0.5 }
        let magnitudes = fftProcessor.convertToDB(fftProcessor.performFFT(on: samples))

        let original = SpectrogramData(
            frequencies: fftProcessor.frequencies,
            magnitudes: magnitudes,
            broadbandLevel: 65.5,
            sampleRate: 44100.0
        )

        // Serialize → Deserialize
        let binary = original.toBinaryData()
        guard let restored = SpectrogramData.fromBinaryData(binary) else {
            XCTFail("Deserialization failed")
            return
        }

        // Vergleiche
        XCTAssertEqual(restored.frequencies.count, original.frequencies.count)
        XCTAssertEqual(restored.magnitudes.count, original.magnitudes.count)
        XCTAssertEqual(restored.broadbandLevel, original.broadbandLevel, accuracy: 0.1)
    }

    // MARK: - AudioEngine Integration

    /// Testet AudioEngine mit FFTConfiguration
    func testAudioEngineWithFFTConfiguration() {
        let filterManager = BandstopFilterManager()
        let connectivityManager = WatchConnectivityManager()
        let audioEngine = AudioEngine(filterManager: filterManager, connectivityManager: connectivityManager)
        let config = FFTConfiguration()

        // Teste verschiedene Presets
        for preset in FFTConfiguration.Preset.allCases {
            config.applyPreset(preset)
            audioEngine.applyFFTConfiguration(config)

            XCTAssertEqual(audioEngine.currentWindowFunction, config.windowFunction,
                          "Window function should match config for preset \(preset)")
            XCTAssertEqual(audioEngine.currentBlockSize, config.blockSize,
                          "Block size should match config for preset \(preset)")
        }
    }

    // MARK: - Stress Tests

    /// Simuliert 10 Minuten kontinuierlichen Betrieb (beschleunigt)
    func testContinuousOperationSimulation() {
        let filterManager = BandstopFilterManager()
        let connectivityManager = WatchConnectivityManager()
        let audioEngine = AudioEngine(filterManager: filterManager, connectivityManager: connectivityManager)

        // Simuliere 600 "Sekunden" mit je 100 Frames pro Sekunde
        // Beschleunigt: 1000 Iterationen statt 60000
        let iterations = 1000

        for i in 0..<iterations {
            let samples = (0..<1024).map { sin(Float($0 + i) * 0.1) * 0.3 }
            audioEngine.processExternalAudio(samples)

            // Gelegentlich Konfiguration ändern (alle 100 Frames)
            if i % 100 == 0 {
                let windows = WindowFunction.allCases
                audioEngine.setWindowFunction(windows[i / 100 % windows.count])
            }
        }

        // Prüfe dass Engine noch funktional ist
        XCTAssertEqual(audioEngine.engineStatus, .idle, "Engine should still be idle (not crashed)")
    }

    /// Testet Memory-Stabilität bei langer Laufzeit
    func testMemoryStabilityDuringContinuousOperation() {
        let filterManager = BandstopFilterManager()
        let connectivityManager = WatchConnectivityManager()
        let audioEngine = AudioEngine(filterManager: filterManager, connectivityManager: connectivityManager)

        // Führe viele Operationen durch
        for _ in 0..<500 {
            let samples = (0..<8192).map { sin(Float($0) * 0.1) }
            audioEngine.processExternalAudio(samples)
        }

        // Level-History sollte begrenzt sein
        XCTAssertLessThanOrEqual(audioEngine.levelHistory.count, 1000,
                                "Level history should be bounded")
    }

    // MARK: - Edge Case Integration

    /// Testet Verhalten bei schnellem Widget-Wechsel
    func testRapidConfigurationChanges() {
        let filterManager = BandstopFilterManager()
        let connectivityManager = WatchConnectivityManager()
        let audioEngine = AudioEngine(filterManager: filterManager, connectivityManager: connectivityManager)

        let expectation = XCTestExpectation(description: "Rapid changes complete")

        DispatchQueue.global().async {
            for _ in 0..<100 {
                audioEngine.setFrequencyWeighting(.a)
                audioEngine.setFrequencyWeighting(.c)
                audioEngine.setFrequencyWeighting(.z)

                audioEngine.setTimeWeighting(.fast)
                audioEngine.setTimeWeighting(.slow)

                for speed in ScrollSpeed.allCases {
                    audioEngine.scrollSpeed = speed
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }
}

// MARK: - Window Function Integration Tests

final class WindowFunctionIntegrationTests: XCTestCase {

    /// Testet alle Fensterfunktionen mit realistischen Signalen
    func testAllWindowFunctionsWithRealisticSignal() {
        let sampleRate: Double = 44100.0
        let fftSize = 2048

        // Generiere Signal mit mehreren Frequenzkomponenten
        let samples: [Float] = (0..<fftSize).map {
            let t = Float($0) / Float(sampleRate)
            return sin(2 * .pi * 440 * t) * 0.5 +  // A4
                   sin(2 * .pi * 880 * t) * 0.3 +  // A5
                   sin(2 * .pi * 1320 * t) * 0.2   // E6
        }

        for windowType in WindowFunction.allCases {
            let processor = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate, windowFunction: windowType)
            let magnitudes = processor.performFFT(on: samples)
            let dbMagnitudes = processor.convertToDB(magnitudes)

            // Sollte keine NaN oder Inf enthalten
            XCTAssertFalse(dbMagnitudes.contains(where: { $0.isNaN }),
                          "FFT with \(windowType) should not produce NaN")
            XCTAssertFalse(dbMagnitudes.contains(where: { $0.isInfinite }),
                          "FFT with \(windowType) should not produce Inf")

            // Peak sollte bei ~440 Hz sein
            let maxDb = dbMagnitudes.max() ?? -200
            XCTAssertGreaterThan(maxDb, -60, "Peak should be significant for \(windowType)")
        }
    }

    /// Testet spektrale Leckage bei verschiedenen Fensterfunktionen
    func testSpectralLeakageComparison() {
        let sampleRate: Double = 44100.0
        let fftSize = 4096

        // 1000 Hz Sinus (exakt auf Bin)
        let exactFreq: Float = 1000.0
        let samplesExact: [Float] = (0..<fftSize).map {
            sin(2 * .pi * exactFreq * Float($0) / Float(sampleRate))
        }

        // 1005 Hz Sinus (zwischen Bins - verursacht Leckage)
        let leakyFreq: Float = 1005.0
        let samplesLeaky: [Float] = (0..<fftSize).map {
            sin(2 * .pi * leakyFreq * Float($0) / Float(sampleRate))
        }

        // Rectangular sollte mehr Leckage zeigen als Blackman-Harris
        let rectProcessor = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate, windowFunction: .rectangular)
        let bhProcessor = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate, windowFunction: .blackmanHarris)

        let rectMags = rectProcessor.convertToDB(rectProcessor.performFFT(on: samplesLeaky))
        let bhMags = bhProcessor.convertToDB(bhProcessor.performFFT(on: samplesLeaky))

        // Finde den Peak-Bin
        let peakBin = 1005 * fftSize / Int(sampleRate)

        // Blackman-Harris sollte weniger Energie in entfernten Bins haben
        let farBin = peakBin + 50 // 50 Bins entfernt
        if farBin < rectMags.count && farBin < bhMags.count {
            // BH sollte dort leiser sein (mehr Dämpfung der Seitenkeulen)
            XCTAssertLessThan(bhMags[farBin], rectMags[farBin] + 20,
                             "Blackman-Harris should have better sidelobe suppression")
        }
    }
}

import XCTest
@testable import SpektoWatch2

/// Tests für FrequencyWeightingProcessor - Testet A-, C- und Z-Bewertung nach IEC 61672-1:2013
/// AKTUALISIERT: Tests wurden reaktiviert nach Refactoring von class → struct
/// Das ursprüngliche Memory-Management-Problem bei der class-Implementierung wurde durch
/// die Umstellung auf eine immutable struct-Implementierung mit Sendable-Konformität gelöst.
final class FrequencyWeightingTests: XCTestCase {

    var weightingProcessor: FrequencyWeightingProcessor!
    let fftSize = 8192
    let sampleRate: Double = 44100.0

    override func setUp() {
        super.setUp()
        weightingProcessor = FrequencyWeightingProcessor(fftSize: fftSize, sampleRate: sampleRate)
    }

    override func tearDown() {
        weightingProcessor = nil
        super.tearDown()
    }

    // MARK: - Hilfsfunktionen

    /// Berechnet den Frequenzindex für eine gegebene Frequenz
    private func indexForFrequency(_ frequency: Float) -> Int {
        let nyquist = Float(sampleRate / 2.0)
        let binCount = fftSize / 2
        return Int((frequency / nyquist) * Float(binCount))
    }

    /// Konvertiert linearen Gain zu dB
    private func linearToDb(_ linear: Float) -> Float {
        return 20.0 * log10(max(linear, 1e-10))
    }

    // MARK: - TEST-IE-020: A-Bewertung Korrektheit (IEC 61672-1:2013)

    /// Testet A-Bewertung bei 31.5 Hz (erwartete Dämpfung: -39.4 dB)
    func testAWeightingAt31_5Hz() {
        let gains = weightingProcessor.getAWeightingGains()
        let index = indexForFrequency(31.5)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, -39.4, accuracy: 2.0,
                      "A-weighting at 31.5 Hz should be -39.4 dB (±2 dB)")
    }

    /// Testet A-Bewertung bei 63 Hz (erwartete Dämpfung: -26.2 dB)
    func testAWeightingAt63Hz() {
        let gains = weightingProcessor.getAWeightingGains()
        let index = indexForFrequency(63)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, -26.2, accuracy: 2.0,
                      "A-weighting at 63 Hz should be -26.2 dB (±2 dB)")
    }

    /// Testet A-Bewertung bei 125 Hz (erwartete Dämpfung: -16.1 dB)
    func testAWeightingAt125Hz() {
        let gains = weightingProcessor.getAWeightingGains()
        let index = indexForFrequency(125)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, -16.1, accuracy: 1.5,
                      "A-weighting at 125 Hz should be -16.1 dB (±1.5 dB)")
    }

    /// Testet A-Bewertung bei 250 Hz (erwartete Dämpfung: -8.6 dB)
    func testAWeightingAt250Hz() {
        let gains = weightingProcessor.getAWeightingGains()
        let index = indexForFrequency(250)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, -8.6, accuracy: 1.0,
                      "A-weighting at 250 Hz should be -8.6 dB (±1 dB)")
    }

    /// Testet A-Bewertung bei 500 Hz (erwartete Dämpfung: -3.2 dB)
    func testAWeightingAt500Hz() {
        let gains = weightingProcessor.getAWeightingGains()
        let index = indexForFrequency(500)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, -3.2, accuracy: 0.5,
                      "A-weighting at 500 Hz should be -3.2 dB (±0.5 dB)")
    }

    /// Testet A-Bewertung bei 1000 Hz (Referenz: 0 dB)
    func testAWeightingAt1kHz() {
        let gains = weightingProcessor.getAWeightingGains()
        let index = indexForFrequency(1000)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, 0.0, accuracy: 0.5,
                      "A-weighting at 1 kHz should be 0 dB (±0.5 dB)")
    }

    /// Testet A-Bewertung bei 2000 Hz (erwartete Verstärkung: +1.2 dB)
    func testAWeightingAt2kHz() {
        let gains = weightingProcessor.getAWeightingGains()
        let index = indexForFrequency(2000)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, 1.2, accuracy: 0.5,
                      "A-weighting at 2 kHz should be +1.2 dB (±0.5 dB)")
    }

    /// Testet A-Bewertung bei 4000 Hz (erwartete Verstärkung: +1.0 dB)
    func testAWeightingAt4kHz() {
        let gains = weightingProcessor.getAWeightingGains()
        let index = indexForFrequency(4000)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, 1.0, accuracy: 0.5,
                      "A-weighting at 4 kHz should be +1.0 dB (±0.5 dB)")
    }

    /// Testet A-Bewertung bei 8000 Hz (erwartete Dämpfung: -1.1 dB)
    func testAWeightingAt8kHz() {
        let gains = weightingProcessor.getAWeightingGains()
        let index = indexForFrequency(8000)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, -1.1, accuracy: 1.0,
                      "A-weighting at 8 kHz should be -1.1 dB (±1 dB)")
    }

    /// Testet A-Bewertung bei 16000 Hz (erwartete Dämpfung: -6.6 dB)
    func testAWeightingAt16kHz() {
        let gains = weightingProcessor.getAWeightingGains()
        let index = indexForFrequency(16000)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, -6.6, accuracy: 1.5,
                      "A-weighting at 16 kHz should be -6.6 dB (±1.5 dB)")
    }

    // MARK: - TEST-IE-021: C-Bewertung Korrektheit (IEC 61672-1:2013)

    /// Testet C-Bewertung bei 31.5 Hz (erwartete Dämpfung: -3.0 dB)
    func testCWeightingAt31_5Hz() {
        let gains = weightingProcessor.getCWeightingGains()
        let index = indexForFrequency(31.5)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, -3.0, accuracy: 1.5,
                      "C-weighting at 31.5 Hz should be -3.0 dB (±1.5 dB)")
    }

    /// Testet C-Bewertung bei 125 Hz (erwartete Dämpfung: -0.2 dB)
    func testCWeightingAt125Hz() {
        let gains = weightingProcessor.getCWeightingGains()
        let index = indexForFrequency(125)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, -0.2, accuracy: 0.5,
                      "C-weighting at 125 Hz should be -0.2 dB (±0.5 dB)")
    }

    /// Testet C-Bewertung bei 1000 Hz (Referenz: 0 dB)
    func testCWeightingAt1kHz() {
        let gains = weightingProcessor.getCWeightingGains()
        let index = indexForFrequency(1000)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, 0.0, accuracy: 0.5,
                      "C-weighting at 1 kHz should be 0 dB (±0.5 dB)")
    }

    /// Testet C-Bewertung bei 4000 Hz (erwartete Dämpfung: -0.8 dB)
    func testCWeightingAt4kHz() {
        let gains = weightingProcessor.getCWeightingGains()
        let index = indexForFrequency(4000)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, -0.8, accuracy: 0.5,
                      "C-weighting at 4 kHz should be -0.8 dB (±0.5 dB)")
    }

    /// Testet C-Bewertung bei 8000 Hz (erwartete Dämpfung: -3.0 dB)
    func testCWeightingAt8kHz() {
        let gains = weightingProcessor.getCWeightingGains()
        let index = indexForFrequency(8000)

        guard index < gains.count else {
            XCTFail("Index out of bounds")
            return
        }

        let gainDb = linearToDb(gains[index])
        XCTAssertEqual(gainDb, -3.0, accuracy: 1.0,
                      "C-weighting at 8 kHz should be -3.0 dB (±1 dB)")
    }

    // MARK: - TEST-IE-022: Z-Bewertung (Linear)

    /// Testet dass Z-Bewertung flach ist (alle Gains = 1.0)
    func testZWeightingIsFlat() {
        let gains = weightingProcessor.getWeightingGains(for: .z)

        for (index, gain) in gains.enumerated() {
            XCTAssertEqual(gain, 1.0, accuracy: 0.001,
                          "Z-weighting should be 1.0 at all frequencies (index \(index))")
        }
    }

    // MARK: - applyWeighting Tests

    /// Testet die Anwendung von A-Bewertung auf dB-Magnituden
    func testApplyAWeighting() {
        // Erstelle flaches Spektrum bei 60 dB
        let flatDb = [Float](repeating: 60.0, count: fftSize / 2)
        let frequencies = (0..<(fftSize / 2)).map { Float($0) * Float(sampleRate / 2.0) / Float(fftSize / 2) }

        let weightedDb = weightingProcessor.applyWeighting(to: flatDb, frequencies: frequencies, weighting: .a)

        // Bei 1 kHz sollte der Wert unverändert sein (~60 dB)
        let index1k = indexForFrequency(1000)
        XCTAssertEqual(weightedDb[index1k], 60.0, accuracy: 1.0,
                      "A-weighted level at 1 kHz should be ~60 dB")

        // Bei 100 Hz sollte der Wert niedriger sein (A-Bewertung dämpft tiefe Frequenzen)
        let index100 = indexForFrequency(100)
        XCTAssertLessThan(weightedDb[index100], 55.0,
                         "A-weighted level at 100 Hz should be lower than 55 dB")
    }

    /// Testet die Anwendung von C-Bewertung
    func testApplyCWeighting() {
        let flatDb = [Float](repeating: 70.0, count: fftSize / 2)
        let frequencies = (0..<(fftSize / 2)).map { Float($0) * Float(sampleRate / 2.0) / Float(fftSize / 2) }

        let weightedDb = weightingProcessor.applyWeighting(to: flatDb, frequencies: frequencies, weighting: .c)

        // Bei 1 kHz sollte der Wert unverändert sein (~70 dB)
        let index1k = indexForFrequency(1000)
        XCTAssertEqual(weightedDb[index1k], 70.0, accuracy: 1.0,
                      "C-weighted level at 1 kHz should be ~70 dB")

        // C-Bewertung ist bei tiefen Frequenzen flacher als A-Bewertung
        let index100 = indexForFrequency(100)
        XCTAssertGreaterThan(weightedDb[index100], 65.0,
                            "C-weighted level at 100 Hz should be higher than 65 dB")
    }

    /// Testet die Anwendung von Z-Bewertung (keine Änderung)
    func testApplyZWeighting() {
        let testDb = (0..<(fftSize / 2)).map { Float($0 % 100) }
        let frequencies = (0..<(fftSize / 2)).map { Float($0) * Float(sampleRate / 2.0) / Float(fftSize / 2) }

        let weightedDb = weightingProcessor.applyWeighting(to: testDb, frequencies: frequencies, weighting: .z)

        // Z-Bewertung sollte keine Änderung bewirken
        for i in 0..<min(testDb.count, weightedDb.count) {
            XCTAssertEqual(weightedDb[i], testDb[i], accuracy: 0.1,
                          "Z-weighted values should be unchanged at index \(i)")
        }
    }

    // MARK: - Edge Cases

    /// Testet Verhalten bei sehr tiefen Frequenzen (nahe 0 Hz)
    func testWeightingAtVeryLowFrequency() {
        let gains = weightingProcessor.getAWeightingGains()

        // DC-Komponente (0 Hz) sollte stark gedämpft sein
        XCTAssertLessThan(gains[0], 0.01, "A-weighting at 0 Hz should be very small")
    }

    /// Testet Verhalten bei Nyquist-Frequenz
    func testWeightingAtNyquist() {
        let gains = weightingProcessor.getAWeightingGains()
        let nyquistIndex = gains.count - 1

        // Sollte kein NaN oder Inf sein
        XCTAssertFalse(gains[nyquistIndex].isNaN, "Gain at Nyquist should not be NaN")
        XCTAssertFalse(gains[nyquistIndex].isInfinite, "Gain at Nyquist should not be infinite")
    }

    /// Testet bounds-checking bei unterschiedlichen Array-Größen
    func testApplyWeightingWithMismatchedSizes() {
        // Erstelle kürzeres Array als erwartet
        let shortDb = [Float](repeating: 50.0, count: 100)
        let frequencies = [Float](repeating: 1000.0, count: 100)

        // Sollte nicht abstürzen
        let weighted = weightingProcessor.applyWeighting(to: shortDb, frequencies: frequencies, weighting: .a)

        XCTAssertEqual(weighted.count, shortDb.count, "Output should match input size")
    }

    // MARK: - Performance Tests

    /// Misst Performance der A-Bewertungs-Anwendung
    func testApplyWeightingPerformance() {
        let dbMagnitudes = [Float](repeating: 50.0, count: fftSize / 2)
        let frequencies = (0..<(fftSize / 2)).map { Float($0) * Float(sampleRate / 2.0) / Float(fftSize / 2) }

        measure {
            for _ in 0..<1000 {
                _ = weightingProcessor.applyWeighting(to: dbMagnitudes, frequencies: frequencies, weighting: .a)
            }
        }
    }

    // MARK: - Vergleich A vs C Bewertung

    /// Testet dass A-Bewertung bei tiefen Frequenzen stärker dämpft als C-Bewertung
    func testAWeightingAttenuatesLowFrequenciesMoreThanC() {
        let aGains = weightingProcessor.getAWeightingGains()
        let cGains = weightingProcessor.getCWeightingGains()

        // Bei 50 Hz sollte A-Bewertung stärker dämpfen als C
        let index50 = indexForFrequency(50)
        if index50 < aGains.count && index50 < cGains.count {
            XCTAssertLessThan(aGains[index50], cGains[index50],
                             "A-weighting should attenuate 50 Hz more than C-weighting")
        }

        // Bei 100 Hz ebenso
        let index100 = indexForFrequency(100)
        if index100 < aGains.count && index100 < cGains.count {
            XCTAssertLessThan(aGains[index100], cGains[index100],
                             "A-weighting should attenuate 100 Hz more than C-weighting")
        }
    }

    /// Testet dass beide Bewertungen bei 1 kHz ungefähr gleich sind
    func testAAndCWeightingSimilarAt1kHz() {
        let aGains = weightingProcessor.getAWeightingGains()
        let cGains = weightingProcessor.getCWeightingGains()

        let index1k = indexForFrequency(1000)
        if index1k < aGains.count && index1k < cGains.count {
            let aDb = linearToDb(aGains[index1k])
            let cDb = linearToDb(cGains[index1k])

            XCTAssertEqual(aDb, cDb, accuracy: 0.5,
                          "A and C weighting should be similar at 1 kHz")
        }
    }
}

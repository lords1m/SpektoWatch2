//
//  LoudnessCalculatorTests.swift
//  SpektoWatch2Tests
//
//  Unit-Tests für Lautheit-Rechner (ISO 226/532)
//

import XCTest
@testable import SpektoWatch2

final class LoudnessCalculatorTests: XCTestCase {
    
    var calculator: LoudnessCalculator!
    
    override func setUp() {
        super.setUp()
        calculator = LoudnessCalculator()
    }
    
    override func tearDown() {
        calculator = nil
        super.tearDown()
    }
    
    // MARK: - Grundlegende Berechnungen
    
    func testBasicCalculation() {
        // Given: Standard-Eingabewerte
        let spl = 60.0
        let frequency = 1000.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: frequency)
        
        // Then: Ergebnis sollte vorhanden sein
        XCTAssertNotNil(calculator.result)
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        XCTAssertEqual(result.inputSPL, spl)
        XCTAssertEqual(result.inputFrequency, frequency)
    }
    
    // MARK: - Referenzfrequenz Tests (1000 Hz)
    
    func testReferenceFrequency_SPLEqualsPhon() {
        // Given: Verschiedene SPL-Werte bei 1000 Hz
        let testCases: [(spl: Double, expectedPhon: Double)] = [
            (20, 20),
            (40, 40),
            (60, 60),
            (80, 80),
            (100, 100)
        ]
        
        for testCase in testCases {
            // When: Berechnung bei 1000 Hz
            calculator.calculate(spl: testCase.spl, frequency: 1000.0)
            
            // Then: Bei 1000 Hz gilt: dB SPL = Phon
            guard let result = calculator.result else {
                XCTFail("Result should not be nil for SPL \(testCase.spl)")
                continue
            }
            XCTAssertEqual(
                result.phon,
                testCase.expectedPhon,
                accuracy: 0.1,
                "Bei 1000 Hz sollte \(testCase.spl) dB SPL = \(testCase.expectedPhon) Phon sein"
            )
        }
    }
    
    // MARK: - Stevens' Power Law Tests
    
    func testStevens40Phon() {
        // Given: 40 Phon bei 1000 Hz
        let spl = 40.0
        let frequency = 1000.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: frequency)
        
        // Then: 40 Phon = 1 Sone (Referenz)
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        XCTAssertEqual(
            result.sone,
            1.0,
            accuracy: 0.01,
            "40 Phon sollte 1 Sone entsprechen (Referenz)"
        )
    }
    
    func testStevens50Phon() {
        // Given: 50 Phon bei 1000 Hz
        let spl = 50.0
        let frequency = 1000.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: frequency)
        
        // Then: 50 Phon = 2 Sone (Verdopplung)
        // S = 2^((P-40)/10) = 2^((50-40)/10) = 2^1 = 2
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        XCTAssertEqual(
            result.sone,
            2.0,
            accuracy: 0.01,
            "50 Phon sollte 2 Sone entsprechen (+10 Phon = Verdopplung)"
        )
    }
    
    func testStevens60Phon() {
        // Given: 60 Phon bei 1000 Hz
        let spl = 60.0
        let frequency = 1000.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: frequency)
        
        // Then: 60 Phon = 4 Sone (nochmal Verdopplung)
        // S = 2^((60-40)/10) = 2^2 = 4
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        XCTAssertEqual(
            result.sone,
            4.0,
            accuracy: 0.01,
            "60 Phon sollte 4 Sone entsprechen"
        )
    }
    
    func testStevens70Phon() {
        // Given: 70 Phon bei 1000 Hz
        let spl = 70.0
        let frequency = 1000.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: frequency)
        
        // Then: 70 Phon = 8 Sone
        // S = 2^((70-40)/10) = 2^3 = 8
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        XCTAssertEqual(
            result.sone,
            8.0,
            accuracy: 0.01,
            "70 Phon sollte 8 Sone entsprechen"
        )
    }
    
    func testStevensBelow40Phon() {
        // Given: 30 Phon bei 1000 Hz
        let spl = 30.0
        let frequency = 1000.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: frequency)
        
        // Then: Unter 40 Phon gilt modifizierte Formel
        // S = (P/40)^2.642
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        let expectedSone = pow(30.0 / 40.0, 2.642)
        XCTAssertEqual(
            result.sone,
            expectedSone,
            accuracy: 0.01,
            "30 Phon sollte ca. \(expectedSone) Sone entsprechen"
        )
    }
    
    // MARK: - Frequenzabhängigkeit Tests
    
    func testLowFrequencyRequiresHigherSPL() {
        // Given: Gleicher SPL bei tiefer Frequenz
        let spl = 60.0
        let lowFrequency = 100.0
        let referenceFrequency = 1000.0
        
        // When: Berechnung bei beiden Frequenzen
        calculator.calculate(spl: spl, frequency: lowFrequency)
        guard let lowFreqResult = calculator.result else {
            XCTFail("Result should not be nil for low frequency")
            return
        }
        let lowFreqPhon = lowFreqResult.phon
        
        calculator.calculate(spl: spl, frequency: referenceFrequency)
        guard let refFreqResult = calculator.result else {
            XCTFail("Result should not be nil for reference frequency")
            return
        }
        let refFreqPhon = refFreqResult.phon
        
        // Then: Tiefe Frequenzen werden leiser wahrgenommen
        XCTAssertLessThan(
            lowFreqPhon,
            refFreqPhon,
            "60 dB SPL bei 100 Hz sollte weniger Phon ergeben als bei 1000 Hz"
        )
    }
    
    func testHighFrequency() {
        // Given: Hohe Frequenz
        let spl = 60.0
        let highFrequency = 4000.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: highFrequency)
        
        // Then: Sollte sinnvolle Werte liefern
        XCTAssertNotNil(calculator.result)
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        XCTAssertGreaterThan(result.phon, 0)
        XCTAssertGreaterThan(result.sone, 0)
    }
    
    // MARK: - Verdopplungs-Test
    
    func testDoubleLoudness() {
        // Given: 60 Phon bei 1000 Hz
        let spl = 60.0
        let frequency = 1000.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: frequency)
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        
        // Then: Doppelte Lautheit sollte ca. 70 dB SPL sein (+10 Phon)
        let doubleLoudnessSPL = result.doubleLoudnessSPL
        XCTAssertEqual(
            doubleLoudnessSPL,
            70.0,
            accuracy: 0.5,
            "Für doppelte Lautheit von 60 Phon werden ca. 70 dB SPL benötigt"
        )
        
        // Verify: Sone-Verdopplung
        let originalSone = result.sone
        calculator.calculate(spl: doubleLoudnessSPL, frequency: frequency)
        guard let doubleResult = calculator.result else {
            XCTFail("Result should not be nil for double loudness")
            return
        }
        let doubleSone = doubleResult.sone
        
        XCTAssertEqual(
            doubleSone / originalSone,
            2.0,
            accuracy: 0.1,
            "10 Phon mehr sollte doppelte Sone-Werte ergeben"
        )
    }
    
    // MARK: - Edge Cases
    
    func testMinimumSPL() {
        // Given: Minimaler SPL-Wert
        let spl = 0.0
        let frequency = 1000.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: frequency)
        
        // Then: Sollte gültige Ergebnisse liefern
        XCTAssertNotNil(calculator.result)
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        XCTAssertGreaterThanOrEqual(result.phon, 0)
        XCTAssertGreaterThanOrEqual(result.sone, 0)
    }
    
    func testMaximumSPL() {
        // Given: Maximaler SPL-Wert
        let spl = 130.0
        let frequency = 1000.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: frequency)
        
        // Then: Sollte gültige Ergebnisse liefern
        XCTAssertNotNil(calculator.result)
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        XCTAssertGreaterThan(result.phon, 100)
        XCTAssertGreaterThan(result.sone, 100)
    }
    
    func testMinimumFrequency() {
        // Given: Minimale Frequenz
        let spl = 60.0
        let frequency = 20.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: frequency)
        
        // Then: Sollte gültige Ergebnisse liefern
        XCTAssertNotNil(calculator.result)
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        XCTAssertGreaterThanOrEqual(result.phon, 0)
        XCTAssertTrue(result.sone.isFinite)
    }
    
    func testMaximumFrequency() {
        // Given: Maximale Frequenz
        let spl = 60.0
        let frequency = 20000.0
        
        // When: Berechnung durchführen
        calculator.calculate(spl: spl, frequency: frequency)
        
        // Then: Sollte gültige Ergebnisse liefern
        XCTAssertNotNil(calculator.result)
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        XCTAssertGreaterThan(result.phon, 0)
    }
    
    // MARK: - Interpretation Tests
    
    func testPhonInterpretation() {
        // Given: Verschiedene Phon-Level
        let testCases: [(spl: Double, expectedContains: String)] = [
            (10, "leise"),
            (30, "Leise"),
            (50, "Normal"),
            (70, "Laut"),
            (90, "Sehr laut"),
            (110, "Extrem laut")
        ]
        
        for testCase in testCases {
            // When: Berechnung bei 1000 Hz
            calculator.calculate(spl: testCase.spl, frequency: 1000.0)
            
            // Then: Interpretation sollte sinnvoll sein
            guard let result = calculator.result else {
                XCTFail("Result should not be nil for SPL \(testCase.spl)")
                continue
            }
            let interpretation = result.phonInterpretation
            XCTAssertFalse(
                interpretation.isEmpty,
                "Interpretation für \(testCase.spl) dB SPL sollte nicht leer sein"
            )
        }
    }
    
    func testSoneInterpretation() {
        // Given: 40 Phon (= 1 Sone, Referenz)
        calculator.calculate(spl: 40.0, frequency: 1000.0)
        
        // Then: Interpretation sollte auf Referenz hinweisen
        guard let result = calculator.result else {
            XCTFail("Result should not be nil")
            return
        }
        let interpretation = result.soneInterpretation
        XCTAssertFalse(interpretation.isEmpty)
        XCTAssertTrue(interpretation.contains("1") || interpretation.contains("40"))
    }
    
    // MARK: - Konsistenz Tests
    
    func testConsistencyAcrossMultipleCalls() {
        // Given: Gleiche Eingabewerte
        let spl = 60.0
        let frequency = 1000.0
        
        // When: Mehrfache Berechnung
        calculator.calculate(spl: spl, frequency: frequency)
        guard let firstResult = calculator.result else {
            XCTFail("First result should not be nil")
            return
        }
        let firstPhon = firstResult.phon
        let firstSone = firstResult.sone
        
        calculator.calculate(spl: spl, frequency: frequency)
        guard let secondResult = calculator.result else {
            XCTFail("Second result should not be nil")
            return
        }
        let secondPhon = secondResult.phon
        let secondSone = secondResult.sone
        
        // Then: Ergebnisse sollten identisch sein
        XCTAssertEqual(firstPhon, secondPhon, "Wiederholte Berechnungen sollten identische Phon-Werte liefern")
        XCTAssertEqual(firstSone, secondSone, "Wiederholte Berechnungen sollten identische Sone-Werte liefern")
    }
    
    func testMonotonicIncreaseWithSPL() {
        // Given: Steigende SPL-Werte bei gleicher Frequenz
        let frequency = 1000.0
        var previousSone = 0.0
        
        // When/Then: Sone sollte monoton steigen
        for spl in stride(from: 20.0, through: 100.0, by: 10.0) {
            calculator.calculate(spl: spl, frequency: frequency)
            guard let result = calculator.result else {
                XCTFail("Result should not be nil for SPL \(spl)")
                continue
            }
            let currentSone = result.sone
            
            XCTAssertGreaterThan(
                currentSone,
                previousSone,
                "Sone sollte mit steigendem SPL monoton wachsen"
            )
            previousSone = currentSone
        }
    }
    
    // MARK: - Performance Tests
    
    func testCalculationPerformance() {
        measure {
            for _ in 0..<1000 {
                calculator.calculate(spl: 60.0, frequency: 1000.0)
            }
        }
    }
}

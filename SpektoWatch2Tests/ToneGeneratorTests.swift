import XCTest
@testable import SpektoWatch2

/// Tests für ToneGenerator - Testet Retain-Cycle Fix und Audio-Generierung
final class ToneGeneratorTests: XCTestCase {

    // MARK: - TEST-IE-052: Memory Leak Tests

    /// Testet dass ToneGenerator korrekt deallokiert wird
    func testToneGeneratorDeallocation() {
        weak var weakGenerator: ToneGenerator?

        autoreleasepool {
            let generator = ToneGenerator()
            weakGenerator = generator

            generator.start()
            Thread.sleep(forTimeInterval: 0.1)
            generator.stop()
        }

        // Nach autoreleasepool sollte Generator deallokiert sein
        // Warte kurz für async operations
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertNil(weakGenerator, "ToneGenerator should be deallocated after going out of scope")
    }

    /// Testet mehrfaches Start/Stop ohne Memory Leak
    func testMultipleStartStopCycles() {
        weak var weakGenerator: ToneGenerator?

        autoreleasepool {
            let generator = ToneGenerator()
            weakGenerator = generator

            // 50x Start/Stop wie im Testkonzept
            for _ in 0..<50 {
                generator.start()
                Thread.sleep(forTimeInterval: 0.01)
                generator.stop()
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertNil(weakGenerator, "ToneGenerator should be deallocated after multiple cycles")
    }

    /// Testet Toggle-Funktion
    func testToggleFunction() {
        let generator = ToneGenerator()

        XCTAssertFalse(generator.isPlaying, "Should not be playing initially")

        generator.toggle()
        // isPlaying wird async gesetzt, daher kurz warten
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertTrue(generator.isPlaying, "Should be playing after toggle")

        generator.toggle()
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(generator.isPlaying, "Should not be playing after second toggle")

        generator.stop() // Cleanup
    }

    // MARK: - Frequenz Tests

    /// Testet Frequenz-Einstellung
    func testFrequencySetting() {
        let generator = ToneGenerator()

        generator.frequency = 440.0
        XCTAssertEqual(generator.frequency, 440.0, accuracy: 0.1, "Frequency should be 440 Hz")

        generator.frequency = 1000.0
        XCTAssertEqual(generator.frequency, 1000.0, accuracy: 0.1, "Frequency should be 1000 Hz")

        generator.frequency = 20.0
        XCTAssertEqual(generator.frequency, 20.0, accuracy: 0.1, "Frequency should be 20 Hz")

        generator.frequency = 20000.0
        XCTAssertEqual(generator.frequency, 20000.0, accuracy: 0.1, "Frequency should be 20000 Hz")
    }

    /// Testet Amplitude-Einstellung
    func testAmplitudeSetting() {
        let generator = ToneGenerator()

        generator.amplitude = 0.5
        XCTAssertEqual(generator.amplitude, 0.5, accuracy: 0.01, "Amplitude should be 0.5")

        generator.amplitude = 1.0
        XCTAssertEqual(generator.amplitude, 1.0, accuracy: 0.01, "Amplitude should be 1.0")

        generator.amplitude = 0.0
        XCTAssertEqual(generator.amplitude, 0.0, accuracy: 0.01, "Amplitude should be 0.0")
    }

    /// Testet Wellenform-Einstellung
    func testWaveformSetting() {
        let generator = ToneGenerator()

        for waveform in ToneGenerator.Waveform.allCases {
            generator.waveform = waveform
            XCTAssertEqual(generator.waveform, waveform, "Waveform should be \(waveform)")
        }
    }

    // MARK: - Edge Cases

    /// Testet Start ohne vorheriges Stop
    func testStartWithoutStop() {
        let generator = ToneGenerator()

        generator.start()
        Thread.sleep(forTimeInterval: 0.1)

        // Zweiter Start sollte nicht abstürzen
        generator.start()
        Thread.sleep(forTimeInterval: 0.1)

        generator.stop()
    }

    /// Testet Stop ohne vorheriges Start
    func testStopWithoutStart() {
        let generator = ToneGenerator()

        // Stop ohne Start sollte nicht abstürzen
        generator.stop()
        XCTAssertFalse(generator.isPlaying, "Should not be playing")
    }

    /// Testet Frequenzänderung während Wiedergabe
    func testFrequencyChangeDuringPlayback() {
        let generator = ToneGenerator()

        generator.start()
        Thread.sleep(forTimeInterval: 0.1)

        // Frequenz während Wiedergabe ändern
        generator.frequency = 440.0
        Thread.sleep(forTimeInterval: 0.05)
        generator.frequency = 880.0
        Thread.sleep(forTimeInterval: 0.05)
        generator.frequency = 220.0

        generator.stop()
    }

    /// Testet Amplitudenänderung während Wiedergabe
    func testAmplitudeChangeDuringPlayback() {
        let generator = ToneGenerator()

        generator.start()
        Thread.sleep(forTimeInterval: 0.1)

        // Amplitude während Wiedergabe ändern
        generator.amplitude = 0.8
        Thread.sleep(forTimeInterval: 0.05)
        generator.amplitude = 0.3
        Thread.sleep(forTimeInterval: 0.05)
        generator.amplitude = 1.0

        generator.stop()
    }

    /// Testet Wellenform-Änderung während Wiedergabe
    func testWaveformChangeDuringPlayback() {
        let generator = ToneGenerator()

        generator.start()
        Thread.sleep(forTimeInterval: 0.1)

        // Wellenform während Wiedergabe ändern
        for waveform in ToneGenerator.Waveform.allCases {
            generator.waveform = waveform
            Thread.sleep(forTimeInterval: 0.05)
        }

        generator.stop()
    }

    // MARK: - Performance Tests

    /// Misst Performance von Start/Stop
    func testStartStopPerformance() {
        let generator = ToneGenerator()

        measure {
            for _ in 0..<10 {
                generator.start()
                generator.stop()
            }
        }
    }

    // MARK: - Concurrent Access Tests

    /// Testet gleichzeitigen Zugriff auf ToneGenerator
    func testConcurrentAccess() {
        let generator = ToneGenerator()
        let expectation = XCTestExpectation(description: "Concurrent access completes")
        var completedOps = 0
        let lock = NSLock()
        let totalOps = 200

        // Thread 1: Frequenz ändern
        DispatchQueue.global().async {
            for i in 0..<50 {
                generator.frequency = Float(100 + i * 10)
            }
            lock.lock()
            completedOps += 50
            if completedOps == totalOps { expectation.fulfill() }
            lock.unlock()
        }

        // Thread 2: Amplitude ändern
        DispatchQueue.global().async {
            for i in 0..<50 {
                generator.amplitude = Float(i % 10) / 10.0
            }
            lock.lock()
            completedOps += 50
            if completedOps == totalOps { expectation.fulfill() }
            lock.unlock()
        }

        // Thread 3: Start/Stop
        DispatchQueue.global().async {
            for _ in 0..<50 {
                generator.toggle()
                Thread.sleep(forTimeInterval: 0.01)
            }
            lock.lock()
            completedOps += 50
            if completedOps == totalOps { expectation.fulfill() }
            lock.unlock()
        }

        // Thread 4: Wellenform ändern
        DispatchQueue.global().async {
            for i in 0..<50 {
                let waveforms = ToneGenerator.Waveform.allCases
                generator.waveform = waveforms[i % waveforms.count]
            }
            lock.lock()
            completedOps += 50
            if completedOps == totalOps { expectation.fulfill() }
            lock.unlock()
        }

        wait(for: [expectation], timeout: 10.0)
        generator.stop()
    }
}

// MARK: - Waveform Tests

final class WaveformTests: XCTestCase {

    /// Testet dass alle Wellenformen existieren
    func testAllWaveformsExist() {
        let waveforms = ToneGenerator.Waveform.allCases

        XCTAssertTrue(waveforms.contains(.sine), "Sine waveform should exist")
        XCTAssertTrue(waveforms.contains(.square), "Square waveform should exist")
        XCTAssertTrue(waveforms.contains(.sawtooth), "Sawtooth waveform should exist")
        XCTAssertTrue(waveforms.contains(.triangle), "Triangle waveform should exist")
        XCTAssertEqual(waveforms.count, 4, "Should have exactly 4 waveforms")
    }
}

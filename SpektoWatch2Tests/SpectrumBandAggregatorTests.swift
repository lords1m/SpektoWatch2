//
//  SpectrumBandAggregatorTests.swift
//  SpektoWatch2Tests
//
//  Unit tests for the centralized band aggregator (M13 task-6).
//  Verifies the band-power computation against synthetic inputs and
//  guards against regression of the M12 "negative offset" bug
//  (mean-vs-sum band aggregation).
//

import XCTest
@testable import SpektoWatch2

final class SpectrumBandAggregatorTests: XCTestCase {

    // MARK: - Constants & helpers

    private let centers = SpectrumBandAggregator.thirdOctaveCenters

    /// Build a uniform spectrum (every bin at `level` dB) spanning
    /// `count` bins from 0 to ~22 kHz on a linear scale.
    private func uniformSpectrum(level: Float, count: Int = 1024, sampleRate: Float = 44100) -> ([Float], [Float]) {
        let nyquist = sampleRate / 2
        let frequencies = (0..<count).map { Float($0) / Float(count - 1) * nyquist }
        let spectrum = [Float](repeating: level, count: count)
        return (frequencies, spectrum)
    }

    // MARK: - Layout & metadata

    func testThirdOctaveCentersAndLabelsAlign() {
        XCTAssertEqual(centers.count, 31)
        XCTAssertEqual(SpectrumBandAggregator.thirdOctaveLabels.count, 31)
        XCTAssertEqual(centers.first, 20)
        XCTAssertEqual(centers.last, 20000)
    }

    func testOctaveLabelsLength() {
        XCTAssertEqual(SpectrumBandAggregator.octaveLabels.count, 10)
    }

    func testBarkProducesTwentyFourBands() {
        let (frequencies, spectrum) = uniformSpectrum(level: 60)
        let bark = SpectrumBandAggregator.barkBands(frequencies: frequencies, spectrum: spectrum)
        XCTAssertEqual(bark.count, 24)
    }

    // MARK: - Aggregation math (M12 regression guard)

    func testThirdOctavePowerSum_HigherThanPerBinForMultiBinBands() {
        // Sum-of-power aggregation: for N bins at level `L`, band SPL
        // = L + 10·log10(N). Mean-of-power (the M12 bug) gave plain
        // `L`. We assert at least one mid-band lands above the
        // per-bin level — proves we're summing, not averaging.
        let perBinLevel: Float = 50.0
        let (frequencies, spectrum) = uniformSpectrum(level: perBinLevel, count: 2048)
        let bands = SpectrumBandAggregator.thirdOctaveBands(frequencies: frequencies, spectrum: spectrum)

        // 1 kHz band has ~46 bins in a 2048-bin spectrum up to 22 kHz
        // (band edges 891-1122 Hz, bin spacing ≈ 10.8 Hz).
        let indexOf1kHz = centers.firstIndex(of: 1000)!
        let oneKHzBand = bands[indexOf1kHz]
        // Expect well above the per-bin level — the exact value
        // depends on bin count, but it MUST be > perBinLevel for
        // any band with ≥ 2 bins (10·log10(2) ≈ 3 dB minimum).
        XCTAssertGreaterThan(oneKHzBand, perBinLevel + 3,
            "1 kHz band should aggregate to >L+3dB for >1 bin (sum-of-power). Got \(oneKHzBand) for L=\(perBinLevel).")
    }

    func testThirdOctaveSilenceFloor() {
        // All-silent input → all bands at the -120 dB floor.
        let (frequencies, spectrum) = uniformSpectrum(level: -120)
        let bands = SpectrumBandAggregator.thirdOctaveBands(frequencies: frequencies, spectrum: spectrum)
        // Tolerance: with sum-of-power across many bins of -120 dB,
        // result could rise by 10·log10(N). Apply a generous bound.
        for band in bands {
            XCTAssertLessThan(band, -90, "Silent-input bands should stay below -90 dB; got \(band).")
        }
    }

    func testEmptyInputsReturnFloor() {
        let bands = SpectrumBandAggregator.thirdOctaveBands(frequencies: [], spectrum: [])
        XCTAssertEqual(bands.count, 31)
        XCTAssertTrue(bands.allSatisfy { $0 == -120 })
    }

    // MARK: - Octave aggregation

    func testOctaveSumsThreeThirds() {
        // If three adjacent third-octave bands each contribute equally,
        // the octave (power-sum of three) should be ~ third + 10·log10(3)
        // ≈ third + 4.77 dB.
        let thirds = [Float](repeating: -120, count: 31).enumerated().map { idx, _ -> Float in
            // Set the 1k-octave thirds (indices 16, 17, 18 = 800/1k/1.25k) to 70 dB each.
            return [16, 17, 18].contains(idx) ? 70 : -120
        }
        let octaves = SpectrumBandAggregator.octaveBands(
            frequencies: [],
            spectrum: [],
            fromThirds: thirds
        )
        // octave index 5 = "1k" label.
        XCTAssertEqual(SpectrumBandAggregator.octaveLabels[5], "1k")
        XCTAssertEqual(octaves[5], 70 + 10 * log10(Float(3)), accuracy: 0.01)
    }
}

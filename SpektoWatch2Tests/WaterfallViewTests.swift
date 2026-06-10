import XCTest
import simd
@testable import SpektoWatch2

final class WaterfallSpectralFrameTests: XCTestCase {

    private func sampleData(
        z: [Float] = [10, 20, 30],
        a: [Float]? = [11, 21, 31],
        c: [Float]? = [12, 22, 32],
        visual: [Float]? = nil,
        visualFreqs: [Float]? = nil
    ) -> SpectrogramData {
        SpectrogramData(
            frequencies: [100, 200, 400],
            magnitudes: z,
            magnitudesA: a,
            magnitudesC: c,
            visualFrequencies: visualFreqs,
            visualMagnitudes: visual,
            sampleRate: 48_000
        )
    }

    func testUsesVisualMagnitudesWhenPresent() {
        let data = sampleData(visual: [1, 2, 3], visualFreqs: [50, 150, 250])
        let frame = WaterfallSpectralFrame.magnitudesAndFrequencies(from: data, freqWeighting: "A")
        XCTAssertEqual(frame.magnitudes, [1, 2, 3])
        XCTAssertEqual(frame.frequencies, [50, 150, 250])
    }

    func testUsesWeightedBandsWhenNoVisualTrack() {
        let data = sampleData()
        let aFrame = WaterfallSpectralFrame.magnitudesAndFrequencies(from: data, freqWeighting: "A")
        XCTAssertEqual(aFrame.magnitudes, [11, 21, 31])
        let cFrame = WaterfallSpectralFrame.magnitudesAndFrequencies(from: data, freqWeighting: "C")
        XCTAssertEqual(cFrame.magnitudes, [12, 22, 32])
        let zFrame = WaterfallSpectralFrame.magnitudesAndFrequencies(from: data, freqWeighting: "Z")
        XCTAssertEqual(zFrame.magnitudes, [10, 20, 30])
    }

    func testEmptyVisualFallsBackToWeighting() {
        let data = sampleData(visual: [])
        let frame = WaterfallSpectralFrame.magnitudesAndFrequencies(from: data, freqWeighting: "A")
        XCTAssertEqual(frame.magnitudes, [11, 21, 31])
    }
}

final class WaterfallCameraProjectionTests: XCTestCase {

    func testOriginProjectsToOrigin() {
        let camera = WaterfallCameraProjection(pitchRad: 0.7, yawRad: 0.3)
        let p = camera.project(SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(p.x, 0, accuracy: 1e-5)
        XCTAssertEqual(p.y, 0, accuracy: 1e-5)
        XCTAssertEqual(p.depth, 0, accuracy: 1e-5)
    }

    func testIdentityWhenPitchAndYawZero() {
        // With no rotation, x maps straight through (scaled by perspective)
        // and depth equals world z.
        let camera = WaterfallCameraProjection(pitchRad: 0, yawRad: 0)
        let p = camera.project(SIMD3<Float>(0.5, 0, 0))
        XCTAssertEqual(p.depth, 0, accuracy: 1e-5)
        XCTAssertEqual(p.x, 0.5, accuracy: 1e-5)
        XCTAssertEqual(p.y, 0, accuracy: 1e-5)
    }

    func testYAxisInvertedForScreenSpace() {
        // World +y (louder) must project to a smaller screen y (upward).
        let camera = WaterfallCameraProjection(pitchRad: 0, yawRad: 0)
        let top = camera.project(SIMD3<Float>(0, 0.5, 0))
        XCTAssertLessThan(top.y, 0)
    }

    func testDepthOrderingAlongTimeAxis() {
        // Newer slices (z increasing) should yield monotonically increasing
        // depth so the painter's-algorithm sort is well-defined.
        let camera = WaterfallCameraProjection(pitchRad: 0.4 * .pi / 2,
                                               yawRad: 0.35 * .pi / 2)
        var lastDepth = -Float.greatestFiniteMagnitude
        for i in 0...10 {
            let z = Float(i) / 10 - 0.5
            let depth = camera.project(SIMD3<Float>(0, 0, z)).depth
            XCTAssertGreaterThan(depth, lastDepth)
            lastDepth = depth
        }
    }
}

final class WaterfallAnalysisTests: XCTestCase {

    func testPeaksFindsLocalMaximaSortedLoudestFirst() {
        // Two clear peaks at bins 2 (40 dB) and 5 (60 dB) above the mean.
        let mags: [Float] = [10, 12, 40, 11, 13, 60, 12, 10]
        let freqs: [Float] = [50, 100, 200, 400, 800, 1_600, 3_200, 6_400]
        let peaks = WaterfallAnalysis.peaks(magnitudes: mags, frequencies: freqs, minProminence: 3, limit: 6)
        XCTAssertEqual(peaks.count, 2)
        XCTAssertEqual(peaks[0].binIndex, 5)        // loudest first
        XCTAssertEqual(peaks[0].frequency, 1_600)
        XCTAssertEqual(peaks[1].binIndex, 2)
    }

    func testPeaksRespectsLimit() {
        let mags: [Float] = [0, 50, 0, 50, 0, 50, 0, 50, 0]
        let freqs: [Float] = (0..<mags.count).map { Float($0) * 100 }
        let peaks = WaterfallAnalysis.peaks(magnitudes: mags, frequencies: freqs, minProminence: 1, limit: 2)
        XCTAssertEqual(peaks.count, 2)
    }

    func testPeaksIgnoresTooFewBins() {
        XCTAssertTrue(WaterfallAnalysis.peaks(magnitudes: [1, 2], frequencies: [10, 20]).isEmpty)
    }

    func testMaxHoldTakesPerBinMaximum() {
        let slices: [[Float]] = [[1, 9, 3], [4, 2, 8], [7, 5, 6]]
        XCTAssertEqual(WaterfallAnalysis.maxHold(slices: slices), [7, 9, 8])
    }

    func testMaxHoldIgnoresMismatchedSlices() {
        let slices: [[Float]] = [[1, 2, 3], [9, 9]]   // second is a different width
        XCTAssertEqual(WaterfallAnalysis.maxHold(slices: slices), [1, 2, 3])
    }

    func testAverageIsPerBinMean() {
        let slices: [[Float]] = [[0, 10, 20], [10, 20, 40]]
        XCTAssertEqual(WaterfallAnalysis.average(slices: slices), [5, 15, 30])
    }

    func testFrequencyTicksStayWithinRange() {
        let ticks = WaterfallAnalysis.frequencyTicks(lo: 90, hi: 2_500)
        XCTAssertEqual(ticks.first, 100)
        XCTAssertEqual(ticks.last, 2_000)
        XCTAssertFalse(ticks.contains(50))
        XCTAssertFalse(ticks.contains(4_000))
    }
}

@MainActor
final class WaterfallHistoryStoreTests: XCTestCase {

    private func frame(_ count: Int, value: Float = 50) -> [Float] {
        Array(repeating: value, count: count)
    }

    private func freqs(_ count: Int) -> [Float] {
        (0..<count).map { Float(20) * powf(1000, Float($0) / Float(max(count - 1, 1))) }
    }

    func testAppendProducesDataSet() {
        let store = WaterfallHistoryStore()
        XCTAssertTrue(store.dataSet.isEmpty)
        store.append(magnitudes: frame(32), frequencies: freqs(32), timestamp: Date())
        XCTAssertFalse(store.dataSet.isEmpty)
    }

    func testEmptyInputIsIgnored() {
        let store = WaterfallHistoryStore()
        store.append(magnitudes: [], frequencies: [], timestamp: Date())
        XCTAssertTrue(store.dataSet.isEmpty)
    }

    func testBinCountDriftResetsHistory() {
        let store = WaterfallHistoryStore()
        store.append(magnitudes: frame(32), frequencies: freqs(32), timestamp: Date())
        XCTAssertEqual(store.dataSet.frequencies.count, 32)
        // A different bin count must drop the old (axis-incompatible) history
        // and rebuild against the new axis rather than blending.
        store.append(magnitudes: frame(16), frequencies: freqs(16), timestamp: Date())
        XCTAssertEqual(store.dataSet.frequencies.count, 16)
    }

    func testResetClearsData() {
        let store = WaterfallHistoryStore()
        store.append(magnitudes: frame(32), frequencies: freqs(32), timestamp: Date())
        XCTAssertFalse(store.dataSet.isEmpty)
        store.reset()
        XCTAssertTrue(store.dataSet.isEmpty)
    }

    func testDBSettingsPropagateToDataSet() {
        let store = WaterfallHistoryStore()
        var settings = WaterfallHistoryStore.Settings.default
        settings.minDB = 25
        settings.maxDB = 95
        store.update(settings: settings)
        store.append(magnitudes: frame(32), frequencies: freqs(32), timestamp: Date())
        XCTAssertEqual(store.dataSet.minDB, 25)
        XCTAssertEqual(store.dataSet.maxDB, 95)
    }

    func testSliceCountChangeIsApplied() {
        let store = WaterfallHistoryStore()
        // Feed enough frames that a slice-count cap is observable.
        for _ in 0..<200 {
            store.append(magnitudes: frame(32), frequencies: freqs(32), timestamp: Date())
        }
        var settings = WaterfallHistoryStore.Settings.default
        settings.sliceCount = 12
        store.update(settings: settings)
        store.append(magnitudes: frame(32), frequencies: freqs(32), timestamp: Date())
        XCTAssertLessThanOrEqual(store.dataSet.slices.count, 12)
    }
}

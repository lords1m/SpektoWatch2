import XCTest
import simd
@testable import SpektoWatch2

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

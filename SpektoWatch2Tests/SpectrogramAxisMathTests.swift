import XCTest
import CoreGraphics
@testable import SpektoWatch2

final class SpectrogramAxisMathTests: XCTestCase {

    // MARK: - yPosition

    func testYPositionEndpoints() {
        let h: CGFloat = 600
        // 20 Hz at the bottom, 20 kHz at the top.
        XCTAssertEqual(SpectrogramAxisMath.yPosition(for: 20, height: h), h, accuracy: 0.001)
        XCTAssertEqual(SpectrogramAxisMath.yPosition(for: 20_000, height: h), 0, accuracy: 0.001)
    }

    func testYPositionGeometricMidpointIsCenter() {
        // The geometric mean of 20 and 20000 maps to the vertical center.
        let h: CGFloat = 600
        let mid = sqrt(20.0 * 20_000.0)
        XCTAssertEqual(SpectrogramAxisMath.yPosition(for: mid, height: h), h / 2, accuracy: 0.5)
    }

    func testYPositionClampsOutOfRange() {
        let h: CGFloat = 600
        XCTAssertEqual(SpectrogramAxisMath.yPosition(for: 1, height: h), h, accuracy: 0.001)
        XCTAssertEqual(SpectrogramAxisMath.yPosition(for: 50_000, height: h), 0, accuracy: 0.001)
    }

    func testYPositionMonotonicallyDecreasing() {
        let h: CGFloat = 600
        let freqs: [Double] = [20, 63, 250, 1000, 4000, 16000, 20000]
        var last = CGFloat.greatestFiniteMagnitude
        for f in freqs {
            let y = SpectrogramAxisMath.yPosition(for: f, height: h)
            XCTAssertLessThan(y, last)
            last = y
        }
    }

    // MARK: - frequencyLabel

    func testFrequencyLabelFormatting() {
        XCTAssertEqual(SpectrogramAxisMath.frequencyLabel(20_000), "20 k")
        XCTAssertEqual(SpectrogramAxisMath.frequencyLabel(1000), "1 k")
        XCTAssertEqual(SpectrogramAxisMath.frequencyLabel(63), "63")
        // The previously-divergent case: 31.5 must keep its decimal, not round to 32.
        XCTAssertEqual(SpectrogramAxisMath.frequencyLabel(31.5), "31.5")
    }

    // MARK: - xAxisTickStep

    func testXAxisTickStepSelection() {
        XCTAssertEqual(SpectrogramAxisMath.xAxisTickStep(for: 0), 0.1)      // guard
        XCTAssertEqual(SpectrogramAxisMath.xAxisTickStep(for: 5), 2)        // rough 1.25 → 2
        XCTAssertEqual(SpectrogramAxisMath.xAxisTickStep(for: 1), 0.5)      // rough 0.25 → 0.5
        XCTAssertEqual(SpectrogramAxisMath.xAxisTickStep(for: 60), 15)      // rough 15 → 15
        XCTAssertEqual(SpectrogramAxisMath.xAxisTickStep(for: 10_000), 60)  // beyond candidates
    }

    // MARK: - formatAxisTime

    func testFormatAxisTime() {
        XCTAssertEqual(SpectrogramAxisMath.formatAxisTime(5.5), "5.5")
        XCTAssertEqual(SpectrogramAxisMath.formatAxisTime(30), "30")
        XCTAssertEqual(SpectrogramAxisMath.formatAxisTime(90), "1:30")
        XCTAssertEqual(SpectrogramAxisMath.formatAxisTime(605), "10:05")
    }
}

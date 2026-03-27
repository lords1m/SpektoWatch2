import Foundation
import SwiftUI

enum ScientificChartPalette {
    static let axis = Color.primary.opacity(0.80)
    static let gridMajor = Color.primary.opacity(0.22)
    static let gridMinor = Color.primary.opacity(0.10)
    static let series = Color.accentColor
    static let secondarySeries = Color.orange
    static let fill = Color.accentColor.opacity(0.14)
}

enum ScientificAxis {
    static func niceStep(range: Double, targetTicks: Int) -> Double {
        guard range > 0, targetTicks > 0 else { return 1 }
        let rough = range / Double(targetTicks)
        let exponent = floor(log10(rough))
        let base = pow(10, exponent)
        let fraction = rough / base

        let niceFraction: Double
        if fraction <= 1 { niceFraction = 1 }
        else if fraction <= 2 { niceFraction = 2 }
        else if fraction <= 5 { niceFraction = 5 }
        else { niceFraction = 10 }

        return niceFraction * base
    }

    static func majorTicks(min: Double, max: Double, targetTicks: Int = 8) -> [Double] {
        guard max > min else { return [min] }
        let step = niceStep(range: max - min, targetTicks: targetTicks)
        let start = floor(min / step) * step
        let end = ceil(max / step) * step
        var ticks: [Double] = []
        var value = start
        while value <= end + step * 0.5 {
            ticks.append(value)
            value += step
        }
        return ticks
    }

    static func minorTicks(major: [Double], subdivisions: Int = 2) -> [Double] {
        guard major.count >= 2, subdivisions > 1 else { return [] }
        var ticks: [Double] = []
        for i in 0..<(major.count - 1) {
            let start = major[i]
            let step = (major[i + 1] - start) / Double(subdivisions)
            for j in 1..<subdivisions {
                ticks.append(start + Double(j) * step)
            }
        }
        return ticks
    }

    static func normalized(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        let range = Swift.max(maxValue - minValue, 1e-9)
        return (value - minValue) / range
    }
}

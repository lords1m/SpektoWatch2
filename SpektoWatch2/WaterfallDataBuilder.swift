import Foundation

struct WaterfallSlice: Identifiable {
    let id: Int
    let time: TimeInterval
    let magnitudes: [Float]
}

struct WaterfallDataSet {
    let slices: [WaterfallSlice]
    let frequencies: [Float]
    let duration: TimeInterval
    let minDB: Float
    let maxDB: Float

    var isEmpty: Bool {
        slices.isEmpty || frequencies.isEmpty
    }
}

enum WaterfallDataBuilder {
    static let thirdOctaveCenters: [Float] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
        1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ]

    static func sourceFrequencies(
        binCount: Int,
        sampleRate: Double,
        storedProviderHasFullFFT: Bool
    ) -> [Float] {
        guard binCount > 0 else { return [] }
        if binCount == thirdOctaveCenters.count {
            return thirdOctaveCenters
        }

        let nyquist = Float(sampleRate / 2.0)
        if storedProviderHasFullFFT {
            return (0..<binCount).map { Float($0) * nyquist / Float(max(binCount - 1, 1)) }
        }

        let minFrequency: Float = 20
        let maxFrequency = min(nyquist, 20_000)
        let denominator = Float(max(binCount - 1, 1))
        return (0..<binCount).map { index in
            let t = Float(index) / denominator
            return minFrequency * powf(maxFrequency / minFrequency, t)
        }
    }

    static func build(
        history: [[Float]],
        sourceFrequencies: [Float],
        duration: TimeInterval,
        targetSliceCount: Int = 96,
        targetFrequencyCount: Int = 160,
        minDB: Float = -110,
        maxDB: Float = 20
    ) -> WaterfallDataSet {
        let columns = history.filter { !$0.isEmpty }
        guard !columns.isEmpty, !sourceFrequencies.isEmpty else {
            return WaterfallDataSet(slices: [], frequencies: [], duration: duration, minDB: minDB, maxDB: maxDB)
        }

        let sourceCount = min(columns.first?.count ?? 0, sourceFrequencies.count)
        guard sourceCount > 0 else {
            return WaterfallDataSet(slices: [], frequencies: [], duration: duration, minDB: minDB, maxDB: maxDB)
        }

        // Pass-through: when the producer already emits a perceptually-
        // spaced axis at the target resolution (e.g. the iOS mel pipeline
        // emits 128 mel-spaced bins and we ask for 128), build a fresh
        // log axis on top would double-log the frequencies and cluster
        // the lows. Use source frequencies as-is and identity-map the
        // bin indices.
        let useSourceAxis = (sourceCount <= targetFrequencyCount)
        let targetFrequencies: [Float]
        let sourceIndices: [Int]
        if useSourceAxis {
            targetFrequencies = Array(sourceFrequencies.prefix(sourceCount))
            sourceIndices = Array(0..<sourceCount)
        } else {
            targetFrequencies = makeTargetFrequencies(
                sourceFrequencies: Array(sourceFrequencies.prefix(sourceCount)),
                targetCount: targetFrequencyCount
            )
            sourceIndices = targetFrequencies.map {
                nearestIndex(for: $0, in: sourceFrequencies, upperBound: sourceCount)
            }
        }

        let sliceCount = min(max(targetSliceCount, 1), columns.count)
        let framesPerSlice = Double(columns.count) / Double(sliceCount)
        var slices: [WaterfallSlice] = []
        slices.reserveCapacity(sliceCount)

        for sliceIndex in 0..<sliceCount {
            let frameStart = Int(floor(Double(sliceIndex) * framesPerSlice))
            let frameEnd = min(columns.count, max(frameStart + 1, Int(ceil(Double(sliceIndex + 1) * framesPerSlice))))
            var magnitudes = [Float](repeating: minDB, count: targetFrequencies.count)

            for frame in columns[frameStart..<frameEnd] {
                for (targetIndex, sourceIndex) in sourceIndices.enumerated() where sourceIndex < frame.count {
                    magnitudes[targetIndex] = max(magnitudes[targetIndex], frame[sourceIndex])
                }
            }

            let time = duration * (Double(sliceIndex) / Double(max(sliceCount - 1, 1)))
            slices.append(WaterfallSlice(id: sliceIndex, time: time, magnitudes: magnitudes))
        }

        return WaterfallDataSet(
            slices: slices,
            frequencies: targetFrequencies,
            duration: duration,
            minDB: minDB,
            maxDB: maxDB
        )
    }

    private static func makeTargetFrequencies(sourceFrequencies: [Float], targetCount: Int) -> [Float] {
        let positiveFrequencies = sourceFrequencies.filter { $0 > 0 }
        guard let minSource = positiveFrequencies.first, let maxSource = positiveFrequencies.last else { return [] }

        let minFrequency = max(20, minSource)
        let maxFrequency = min(20_000, maxSource)
        let count = min(max(targetCount, 2), sourceFrequencies.count)
        let denominator = Float(max(count - 1, 1))

        return (0..<count).map { index in
            let t = Float(index) / denominator
            return minFrequency * powf(maxFrequency / minFrequency, t)
        }
    }

    private static func nearestIndex(for frequency: Float, in sourceFrequencies: [Float], upperBound: Int) -> Int {
        let count = min(sourceFrequencies.count, upperBound)
        guard count > 1 else { return 0 }

        var low = 0
        var high = count - 1
        while low < high {
            let mid = (low + high) / 2
            if sourceFrequencies[mid] < frequency {
                low = mid + 1
            } else {
                high = mid
            }
        }

        if low == 0 { return 0 }
        let previous = low - 1
        return abs(sourceFrequencies[previous] - frequency) < abs(sourceFrequencies[low] - frequency) ? previous : low
    }
}

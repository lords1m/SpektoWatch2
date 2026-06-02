import Foundation
import Combine

/// Builds `WaterfallDataSet` for recording playback off the main thread.
@MainActor
final class WaterfallPlaybackController: ObservableObject {
    @Published private(set) var dataSet: WaterfallDataSet = WaterfallDataSet(
        slices: [],
        frequencies: [],
        duration: 0,
        minDB: WidgetSettings.defaultWaterfallMinDB,
        maxDB: WidgetSettings.defaultWaterfallMaxDB
    )
    @Published private(set) var isBuilding = false

    var display = WaterfallDisplaySettings.playbackDefault

    private var buildTask: Task<Void, Never>?

    func rebuild(
        history: [[Float]],
        axis: SpectrogramHistoryAxisKind,
        sampleRate: Double,
        duration: TimeInterval,
        storedProviderHasFullFFT: Bool,
        fftBinCount: Int
    ) {
        buildTask?.cancel()
        guard !history.isEmpty, let first = history.first, !first.isEmpty else {
            let range = display.clampedDBRange()
            dataSet = WaterfallDataSet(
                slices: [],
                frequencies: [],
                duration: duration,
                minDB: range.minDB,
                maxDB: range.maxDB
            )
            isBuilding = false
            return
        }

        isBuilding = true
        let displaySnapshot = display
        let historySnapshot = history
        let durationSnapshot = max(duration, 0)

        let binCount = first.count
        buildTask = Task {
            let built = await Task.detached(priority: .userInitiated) {
                let range = displaySnapshot.clampedDBRange()
                let sourceFrequencies = WaterfallDataBuilder.sourceFrequencies(
                    binCount: binCount,
                    sampleRate: sampleRate,
                    axis: axis,
                    storedProviderHasFullFFT: storedProviderHasFullFFT,
                    fftBinCount: fftBinCount
                )
                let remapped = WaterfallDataBuilder.remapHistory(
                    history: historySnapshot,
                    sourceFrequencies: sourceFrequencies,
                    mode: displaySnapshot.spectrumMode
                )
                return WaterfallDataBuilder.build(
                    history: remapped.history,
                    sourceFrequencies: remapped.frequencies,
                    duration: durationSnapshot,
                    targetSliceCount: displaySnapshot.sliceCount,
                    targetFrequencyCount: displaySnapshot.targetFrequencyCount,
                    minDB: range.minDB,
                    maxDB: range.maxDB
                )
            }.value

            guard !Task.isCancelled else { return }
            dataSet = built
            isBuilding = false
        }
    }

    func cancel() {
        buildTask?.cancel()
        buildTask = nil
        isBuilding = false
    }
}

import SwiftUI

struct WatchSpectrogramWidget: View {
    @EnvironmentObject var audioEngine: WatchAudioEngine

    private static let maxFrames = 40
    // Fixed-capacity ring buffer — O(1) append-and-drop-oldest, replacing the
    // previous `[[Float]]` + `removeFirst()` (O(n) per audio frame).
    @State private var frames: RingBuffer<[Float]> = RingBuffer(capacity: WatchSpectrogramWidget.maxFrames)
    private let maxFrames = WatchSpectrogramWidget.maxFrames
    private let displayBins = 32

    private let minDB: Float = -180.0
    private let maxDB: Float = -40.0

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let colWidth = width / CGFloat(maxFrames)
                let rowHeight = height / CGFloat(displayBins)

                let orderedFrames = frames.inOrder()
                for (i, magnitudes) in orderedFrames.enumerated() {
                    let x = CGFloat(i) * colWidth
                    let chunkSize = max(1, magnitudes.count / displayBins)

                    for f in 0..<displayBins {
                        let mag = displayMagnitude(for: f, in: magnitudes, chunkSize: chunkSize)

                        let normalized = (mag - minDB) / (maxDB - minDB)

                        if normalized > 0.05 {
                            let color = spectrogramColor(Double(normalized))
                            let y = height - CGFloat(f + 1) * rowHeight
                            let rect = CGRect(x: x, y: y, width: colWidth + 0.5, height: rowHeight + 0.5)
                            context.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            }
            .drawingGroup()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Single source of truth: `liveData` reflects whichever mode is active
        // (companion -> phone-pushed; wearableMic -> local audio). No branching.
        .onReceive(audioEngine.$liveData) { data in
            guard let data else { return }
            processData(data)
        }
    }

    private func processData(_ data: SpectrogramData) {
        frames.append(data.visualMagnitudes ?? data.magnitudes)
    }

    private func displayMagnitude(for bin: Int, in magnitudes: [Float], chunkSize: Int) -> Float {
        guard !magnitudes.isEmpty else { return minDB }
        if magnitudes.count == displayBins, bin < magnitudes.count {
            return magnitudes[bin]
        }

        let start = bin * chunkSize
        let end = min(start + chunkSize, magnitudes.count)
        guard start < end else { return minDB }

        var peak = magnitudes[start]
        if end > start + 1 {
            for index in (start + 1)..<end {
                peak = max(peak, magnitudes[index])
            }
        }
        return peak
    }

    private func spectrogramColor(_ value: Double) -> Color {
        if value <= 0.0 { return .black }

        if value < 0.2 {
            return Color(red: 0, green: 0, blue: value * 2.5)
        } else if value < 0.5 {
            let t = (value - 0.2) / 0.3
            return Color(red: 0, green: t, blue: 1.0)
        } else {
            let t = (value - 0.5) / 0.5
            return Color(red: t, green: 1.0 - t * 0.5, blue: 1.0 - t)
        }
    }
}

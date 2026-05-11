import SwiftUI

struct WatchSpectrogramWidget: View {
    @EnvironmentObject var audioEngine: WatchAudioEngine

    @State private var frames: [[Float]] = []
    private let maxFrames = 40
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

                for (i, magnitudes) in frames.enumerated() {
                    let x = CGFloat(i) * colWidth
                    let chunkSize = max(1, magnitudes.count / displayBins)

                    for f in 0..<displayBins {
                        let start = f * chunkSize
                        let end = min(start + chunkSize, magnitudes.count)
                        let mag = (start < end && start < magnitudes.count) ?
                            (magnitudes[start..<min(end, magnitudes.count)].max() ?? minDB) : minDB

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
        // (companion → phone-pushed; wearableMic → local FFT). No branching.
        .onReceive(audioEngine.$liveData) { data in
            guard let data else { return }
            processData(data)
        }
    }

    private func processData(_ data: SpectrogramData) {
        frames.append(data.magnitudes)
        if frames.count > maxFrames {
            frames.removeFirst()
        }
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

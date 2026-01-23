import SwiftUI

struct WatchSpectrogramView: View {
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var spectrogramFrames: [SpectrogramFrame] = []

    let maxFrames = 150

    var body: some View {
        VStack {
            if spectrogramFrames.isEmpty {
                VStack {
                    Image(systemName: "waveform")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("Warte auf Daten...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                WatchSpectrogramCanvasWithAxes(frames: spectrogramFrames, maxFrames: maxFrames)
            }
        }
        .onReceive(connectivityManager.$spectrogramData) { data in
            if let data = data {
                updateSpectrogramFrames(data)
            }
        }
    }

    private func updateSpectrogramFrames(_ data: SpectrogramData) {
        let frame = SpectrogramFrame(magnitudes: data.magnitudes, timestamp: data.timestamp)

        spectrogramFrames.append(frame)

        if spectrogramFrames.count > maxFrames {
            spectrogramFrames.removeFirst()
        }
    }
}

struct WatchSpectrogramCanvasWithAxes: View {
    let frames: [SpectrogramFrame]
    let maxFrames: Int

    let axisWidth: CGFloat = 30
    let axisHeight: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                // Y-Achse (Frequenz)
                VStack(spacing: 0) {
                    ForEach(0..<3) { i in
                        Spacer()
                        Text(frequencyLabel(index: i))
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                            .frame(width: axisWidth)
                    }
                    Spacer()
                    Text("0")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                        .frame(width: axisWidth)
                        .padding(.bottom, axisHeight)
                }

                VStack(spacing: 0) {
                    // Spektrogramm
                    WatchSpectrogramCanvas(frames: frames)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // X-Achse (Zeit)
                    HStack(spacing: 0) {
                        Text(timeLabel(isStart: true))
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(timeLabel(isStart: false))
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(height: axisHeight)
                }
            }
        }
    }

    private func frequencyLabel(index: Int) -> String {
        let maxFreq = 22.0
        let freq = maxFreq * Double(3 - index) / 3.0
        return String(format: "%.0fk", freq)
    }

    private func timeLabel(isStart: Bool) -> String {
        guard !frames.isEmpty else { return "0s" }

        if isStart {
            let oldestFrame = frames.first!
            let elapsed = Date().timeIntervalSince(oldestFrame.timestamp)
            return String(format: "-%.1fs", elapsed)
        } else {
            return "0s"
        }
    }
}

struct WatchSpectrogramCanvas: View {
    let frames: [SpectrogramFrame]

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Mehr Frames für flüssigere Darstellung
                let frameWidth = max(1.0, size.width / CGFloat(frames.count))
                let maxMagnitude = frames.flatMap { $0.magnitudes }.max() ?? 1.0

                // Höhere vertikale Auflösung
                let targetBins = 120

                for (frameIndex, frame) in frames.enumerated() {
                    let x = CGFloat(frameIndex) * frameWidth

                    let sampledMagnitudes = sampleMagnitudesSmooth(frame.magnitudes, targetCount: targetBins)

                    for (binIndex, magnitude) in sampledMagnitudes.enumerated() {
                        let normalizedMagnitude = magnitude / maxMagnitude
                        let binHeight = size.height / CGFloat(sampledMagnitudes.count)
                        let y = size.height - (CGFloat(binIndex + 1) * binHeight)

                        // Verbesserte Farbpalette für besseren Kontrast
                        let color = spectrogramColor(for: normalizedMagnitude)

                        // Wichtig: ceil() auf width/height für lückenlose Darstellung
                        let rect = CGRect(
                            x: x,
                            y: y,
                            width: ceil(frameWidth + 0.5),
                            height: ceil(binHeight + 0.5)
                        )

                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .drawingGroup() // GPU-Beschleunigung für flüssigere Darstellung
        }
    }

    private func sampleMagnitudesSmooth(_ magnitudes: [Float], targetCount: Int) -> [Float] {
        guard magnitudes.count > targetCount else { return magnitudes }

        var result = [Float]()
        let ratio = Float(magnitudes.count) / Float(targetCount)

        for i in 0..<targetCount {
            let startIdx = Float(i) * ratio
            let endIdx = Float(i + 1) * ratio

            let startInt = Int(floor(startIdx))
            let endInt = min(Int(ceil(endIdx)), magnitudes.count - 1)

            // Interpolation für glattere Übergänge
            if startInt == endInt {
                result.append(magnitudes[startInt])
            } else {
                let sum = magnitudes[startInt...endInt].reduce(0, +)
                let count = Float(endInt - startInt + 1)
                result.append(sum / count)
            }
        }

        return result
    }

    private func spectrogramColor(for normalizedMagnitude: Float) -> Color {
        // Logarithmische Skalierung für besseren Dynamikbereich
        let value = Double(log10(max(normalizedMagnitude, 0.001) + 1) / log10(2))
        
        if value < 0.1 {
            // Dunkelblau für niedrige Werte
            return Color(red: 0, green: 0, blue: value * 5)
        } else if value < 0.3 {
            // Blau zu Cyan
            let t = (value - 0.1) / 0.2
            return Color(red: 0, green: t * 0.5, blue: 0.5 + t * 0.5)
        } else if value < 0.6 {
            // Cyan zu Grün
            let t = (value - 0.3) / 0.3
            return Color(red: 0, green: 0.5 + t * 0.5, blue: 1.0 - t)
        } else if value < 0.85 {
            // Grün zu Gelb
            let t = (value - 0.6) / 0.25
            return Color(red: t, green: 1.0, blue: 0)
        } else {
            // Gelb zu Rot
            let t = (value - 0.85) / 0.15
            return Color(red: 1.0, green: 1.0 - t, blue: 0)
        }
    }
}

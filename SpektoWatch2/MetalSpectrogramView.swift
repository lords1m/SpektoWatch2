import SwiftUI
import MetalKit

/// SwiftUI wrapper for the Metal-based spectrogram view
struct MetalSpectrogramView: UIViewRepresentable {
    
    typealias UIViewType = SpectrogramMetalView
    
    func makeUIView(context: Context) -> SpectrogramMetalView {
        let metalView = SpectrogramMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        return metalView
    }
    
    func updateUIView(_ uiView: SpectrogramMetalView, context: Context) {
        // Update logic handled through binding or coordinator
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: MetalSpectrogramView
        
        init(_ parent: MetalSpectrogramView) {
            self.parent = parent
        }
    }
}

/// Container view with axis labels
struct MetalSpectrogramWithAxes: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var metalView: SpectrogramMetalView?
    @State private var previousRecordingDuration: TimeInterval = 0

    let axisWidth: CGFloat = 60
    let axisHeight: CGFloat = 30

    // Configuration for time axis
    var showTimeAxis: Bool = true  // Toggle to show/hide time axis
    var showOnlyNow: Bool = false  // Changed to false to show full dynamic time axis
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Y-Axis (Frequency)
                VStack(spacing: 0) {
                    ForEach(0..<8) { i in
                        Spacer()
                        Text(frequencyLabel(index: i))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .frame(width: axisWidth, alignment: .trailing)
                            .padding(.trailing, 4)
                    }
                    Spacer()
                }
                
                VStack(spacing: 0) {
                    // Metal Spectrogram View
                    MetalSpectrogramViewRepresentable(audioEngine: audioEngine) { view in
                        metalView = view
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // X-Axis (Time) - RTL: Now is on the right, dynamically expands with recording
                    if showTimeAxis {
                        GeometryReader { geo in
                            Canvas { context, size in
                                let duration = audioEngine.recordingDuration
                                guard duration > 0 else { return }

                                // Cap display duration at 60 seconds for axis labels
                                let displayDuration = min(duration, 60.0)

                                // Calculate appropriate time intervals for labels
                                let (interval, labelCount) = calculateTimeInterval(duration: displayDuration, width: size.width)

                                // Draw time labels
                                for i in 0...labelCount {
                                    let timeValue = -displayDuration + Double(i) * interval
                                    let xPos = (Double(i) / Double(labelCount)) * size.width

                                    let label = i == labelCount ? "Now" : formatTimeLabel(timeValue)

                                    // Draw label
                                    context.draw(Text(label)
                                        .font(.caption2)
                                        .foregroundColor(.white),
                                        at: CGPoint(x: xPos, y: size.height / 2))
                                }
                            }
                        }
                        .frame(height: axisHeight)
                    }
                }
            }
        }
        .onChange(of: audioEngine.recordingDuration) { _, newDuration in
            // Reset the metal view when recording restarts (duration goes to 0)
            if newDuration < previousRecordingDuration && newDuration < 1.0 {
                metalView?.resetRecording()
            }
            previousRecordingDuration = newDuration
        }
    }

    private func frequencyLabel(index: Int) -> String {
        // Logarithmic frequency labels from 31.5 Hz to 16 kHz
        let frequencies: [Float] = [16000, 8000, 4000, 2000, 1000, 500, 250, 125, 63]

        guard index < frequencies.count else { return "" }
        let freq = frequencies[index]

        if freq >= 1000 {
            return String(format: "%.0f kHz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }

    private func formatTimeLabel(_ seconds: TimeInterval) -> String {
        let absSeconds = abs(seconds)

        if absSeconds < 60 {
            // Less than 1 minute: show seconds
            return String(format: "%.0fs", seconds)
        } else if absSeconds < 3600 {
            // Less than 1 hour: show minutes and seconds
            let minutes = Int(absSeconds) / 60
            let secs = Int(absSeconds) % 60
            let sign = seconds < 0 ? "-" : ""
            return String(format: "%@%d:%02d", sign, minutes, secs)
        } else {
            // 1 hour or more: show hours, minutes
            let hours = Int(absSeconds) / 3600
            let minutes = (Int(absSeconds) % 3600) / 60
            let sign = seconds < 0 ? "-" : ""
            return String(format: "%@%d:%02d:00", sign, hours, minutes)
        }
    }

    private func calculateTimeInterval(duration: TimeInterval, width: CGFloat) -> (interval: TimeInterval, labelCount: Int) {
        // Determine appropriate time interval and label count based on duration
        // Goal: 3-5 labels across the width

        let targetLabels = 4
        let rawInterval = duration / Double(targetLabels)

        // Round to nice intervals
        let niceIntervals: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]

        var bestInterval: TimeInterval = 1
        for interval in niceIntervals {
            if rawInterval <= interval {
                bestInterval = interval
                break
            }
        }

        // If duration is too large, use the largest interval
        if rawInterval > niceIntervals.last! {
            bestInterval = niceIntervals.last!
        }

        let count = Int(ceil(duration / bestInterval))
        return (bestInterval, max(count, 2))
    }
}

/// Representable that passes updates to the Metal view
struct MetalSpectrogramViewRepresentable: UIViewRepresentable {
    @ObservedObject var audioEngine: AudioEngine
    let onViewCreated: (SpectrogramMetalView) -> Void
    
    func makeUIView(context: Context) -> SpectrogramMetalView {
        let metalView = SpectrogramMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        
        // Notify parent that view was created
        DispatchQueue.main.async {
            onViewCreated(metalView)
        }
        
        return metalView
    }
    
    func updateUIView(_ uiView: SpectrogramMetalView, context: Context) {
        // Update is triggered by the data stream
        if let data = audioEngine.currentSpectrogramData {
            uiView.updateWithFFTData(data.magnitudes)
        }
    }
    
    static func dismantleUIView(_ uiView: SpectrogramMetalView, coordinator: ()) {
        // Cleanup if needed
    }
}

// MARK: - Preview Provider

#Preview {
    MetalSpectrogramWithAxes(audioEngine: AudioEngine( // This is line 203
        filterManager: BandstopFilterManager(),
        connectivityManager: WatchConnectivityManager()
    ))
        .background(Color.black)
}

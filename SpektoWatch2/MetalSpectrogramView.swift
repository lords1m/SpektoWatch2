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
    
    let axisWidth: CGFloat = 60
    let axisHeight: CGFloat = 30
    
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
                    
                    // X-Axis (Time)
                    HStack(spacing: 0) {
                        Text("10s")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("5s")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Text("Now")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(height: axisHeight)
                }
            }
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
    MetalSpectrogramWithAxes(audioEngine: AudioEngine())
        .background(Color.black)
}

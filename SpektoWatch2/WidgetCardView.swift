import SwiftUI

struct WidgetCardView: View {
    let widget: WidgetConfiguration
    @ObservedObject var audioEngine: AudioEngine
    var isEditMode: Bool
    var onDelete: () -> Void
    var onResize: (WidgetSize) -> Void
    var onUpdateSettings: ([String: String]) -> Void
    
    @State private var showSettings = false
    @State private var currentScale: CGFloat = 1.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header in Edit Mode
            if isEditMode {
                HStack {
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.gray)
                        .font(.caption)
                    Text(widget.type.rawValue)
                        .font(.caption)
                        .bold()
                    Spacer()
                    
                    // Quick Resize Buttons
                    HStack(spacing: 8) {
                        Button(action: { resizeToNextSmaller() }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.orange)
                                .font(.body)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { resizeToNextLarger() }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                                .font(.body)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Settings Button
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.gray)
                            .font(.body)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Delete Button
                    Button(action: {
                        print("[WidgetCardView] Delete tapped for widget \(widget.type.rawValue)")
                        onDelete()
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.body)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(8)
                .background(Color.gray.opacity(0.2))
            } else {
                // Mini-Title im normalen Modus
                HStack {
                    Text(widget.type.rawValue)
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                    Spacer()
                    Text(widget.size.rawValue)
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.4))
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            
            // Content
            renderWidgetContent()
                .frame(height: widget.size.height)
                .clipped()
        }
        .background(Color.black)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isEditMode ? Color.blue : Color.white.opacity(0.1), lineWidth: isEditMode ? 2 : 1)
        )
        .scaleEffect(currentScale)
        .gesture(
            isEditMode ? MagnificationGesture(minimumScaleDelta: 0.1)
                .onChanged { value in
                    currentScale = value
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        snapToNearestSize(scale: value)
                        currentScale = 1.0
                    }
                } : nil
        )
        .sheet(isPresented: $showSettings) {
            WidgetSettingsView(widget: widget, onSave: onUpdateSettings)
        }
        .onAppear {
            print("[WidgetCardView] Rendering widget: \(widget.type.rawValue) (Size: \(widget.size))")
        }
    }
    
    @ViewBuilder
    private func renderWidgetContent() -> some View {
        switch widget.type {
        case .spectrogram:
            SpectrogramWidget(audioEngine: audioEngine, settings: widget.settings)
        case .lafGraph:
            LAFGraphWidget(audioEngine: audioEngine, settings: widget.settings)
        case .frequencyDisplay:
            FrequencySpectrumWidget(audioEngine: audioEngine)
        case .levelMeter:
            LevelMeterWidget(audioEngine: audioEngine)
        case .octaveBands:
            OctaveBandWidget(audioEngine: audioEngine)
        case .phaseMeter:
            PhaseMeterWidget(audioEngine: audioEngine)
        }
    }
    
    // MARK: - Resize Logic
    
    private func resizeToNextLarger() {
        let sizes: [WidgetSize] = [.small, .medium, .large, .wide, .full]
        guard let currentIndex = sizes.firstIndex(of: widget.size),
              currentIndex < sizes.count - 1 else {
            // Bereits maximale Größe - Feedback geben
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            return
        }
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        print("[WidgetCardView] Resize larger: \(widget.size) -> \(sizes[currentIndex + 1])")
        onResize(sizes[currentIndex + 1])
    }
    
    private func resizeToNextSmaller() {
        let sizes: [WidgetSize] = [.small, .medium, .large, .wide, .full]
        guard let currentIndex = sizes.firstIndex(of: widget.size),
              currentIndex > 0 else {
            // Bereits minimale Größe - Feedback geben
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            return
        }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        print("[WidgetCardView] Resize smaller: \(widget.size) -> \(sizes[currentIndex - 1])")
        onResize(sizes[currentIndex - 1])
    }
    
    private func snapToNearestSize(scale: CGFloat) {
        let sizes: [WidgetSize] = [.small, .medium, .large, .wide, .full]
        guard let currentIndex = sizes.firstIndex(of: widget.size) else { return }
        
        let newSize: WidgetSize
        if scale > 1.3 {
            // Vergrößern
            let steps = Int((scale - 1.0) / 0.3)
            let targetIndex = min(currentIndex + steps, sizes.count - 1)
            newSize = sizes[targetIndex]
        } else if scale < 0.8 {
            // Verkleinern
            let steps = Int((1.0 - scale) / 0.2)
            let targetIndex = max(currentIndex - steps, 0)
            newSize = sizes[targetIndex]
        } else {
            // Keine Änderung - zu geringe Scale-Änderung
            return
        }
        
        if newSize != widget.size {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            print("[WidgetCardView] Pinch resize: \(widget.size) -> \(newSize) (scale: \(scale))")
            onResize(newSize)
        }
    }
}

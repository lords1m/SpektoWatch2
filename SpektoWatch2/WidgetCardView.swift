import SwiftUI

struct WidgetCardView: View {
    let widget: WidgetConfiguration
    @ObservedObject var audioEngine: AudioEngine
    var isEditMode: Bool
    var onDelete: () -> Void
    var onResize: (WidgetSize) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header in Edit Mode
            if isEditMode {
                HStack {
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.gray)
                    Text(widget.type.rawValue)
                        .font(.caption)
                        .bold()
                    Spacer()
                    
                    // Resize Menu
                    Menu {
                        ForEach(WidgetSize.allCases, id: \.self) { size in
                            Button(action: { onResize(size) }) {
                                Label(size.rawValue, systemImage: size == widget.size ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                    }
                    
                    // Delete Button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.2))
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
    }
    
    @ViewBuilder
    private func renderWidgetContent() -> some View {
        switch widget.type {
        case .spectrogram:
            SpectrogramWidget(audioEngine: audioEngine)
        case .lafGraph:
            LAFGraphWidget(audioEngine: audioEngine)
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
}
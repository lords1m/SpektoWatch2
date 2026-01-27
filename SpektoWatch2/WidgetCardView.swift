import SwiftUI

struct WidgetCardView: View {
    let widget: WidgetConfiguration
    @ObservedObject var audioEngine: AudioEngine
    var isEditMode: Bool
    var onDelete: () -> Void
    var onResize: (WidgetSize) -> Void
    var onUpdateSettings: ([String: String]) -> Void
    @State private var showSettings = false
    
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
                            Button(action: { 
                                print("[WidgetCardView] Resize selected: \(size) for widget \(widget.type.rawValue)")
                                onResize(size) 
                            }) {
                                Label(size.rawValue, systemImage: size == widget.size ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                    }
                    
                    // Settings Button
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.gray)
                    }
                    
                    // Delete Button
                    Button(action: {
                        print("[WidgetCardView] Delete tapped for widget \(widget.type.rawValue)")
                        onDelete()
                    }) {
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
        .onAppear {
            print("[WidgetCardView] Rendering widget: \(widget.type.rawValue) (ID: \(widget.id), Size: \(widget.size))")
        }
        .sheet(isPresented: $showSettings) {
            WidgetSettingsView(widget: widget, onSave: onUpdateSettings)
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
}
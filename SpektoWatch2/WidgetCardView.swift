// WidgetCardView.swift - ERSETZEN
import SwiftUI

struct WidgetCardView: View {
    let widget: WidgetConfiguration
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fftConfig: FFTConfiguration
    var isEditMode: Bool
    var columnWidth: CGFloat = 160 // Default fallback
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
                    
                    // Settings Button
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.gray)
                    }
                    
                    // Delete Button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onDelete()
                        }
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.2))
            } else {
                // Mini-Title im normalen Modus
                Text(widget.type.rawValue)
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
            
            // Content
            renderWidgetContent()
                .frame(height: widget.size.height)
                .clipped()
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isEditMode ? Color.blue : Color.white.opacity(0.1), lineWidth: isEditMode ? 2 : 1)
        )
        .overlay(
            resizeHandles
        )
        .sheet(isPresented: $showSettings) {
            WidgetSettingsView(widget: widget, onSave: onUpdateSettings)
        }
    }
    
    @ViewBuilder
    private func renderWidgetContent() -> some View {
        switch widget.type {
        case .spectrogram:
            SpectrogramWidget(audioEngine: audioEngine, settings: widget.settings)
        case .levelHistory:
            LevelHistoryWidget(audioEngine: audioEngine, settings: widget.settings)
        case .frequencyDisplay:
            FrequencySpectrumWidget(audioEngine: audioEngine)
        case .levelMeter:
            LevelMeterWidget(audioEngine: audioEngine)
        case .octaveBands:
            OctaveBandWidget(audioEngine: audioEngine)
        case .phaseMeter:
            PhaseMeterWidget(audioEngine: audioEngine)
        case .singleValue:
            SingleValueWidget(audioEngine: audioEngine, settings: widget.settings)
        case .toneGenerator:
            ToneGeneratorWidget(settings: widget.settings)
        // Spektralanalyse-Labor Widgets
        case .fftParameters:
            FFTParametersWidget(fftConfig: fftConfig, audioEngine: audioEngine)
        case .windowFunction:
            WindowFunctionWidget(fftConfig: fftConfig)
        case .heisenbergResolution:
            HeisenbergResolutionWidget(fftConfig: fftConfig)
        case .spectrumComparison:
            SpectrumComparisonWidget(fftConfig: fftConfig, audioEngine: audioEngine)
        }
    }
    
    @ViewBuilder
    private var resizeHandles: some View {
        if isEditMode {
            ZStack {
                // Right Handle - nur im unteren Bereich (nicht über Header)
                HStack {
                    Spacer()
                    VStack {
                        Spacer().frame(height: 44) // Header-Höhe aussparen
                        Rectangle()
                            .fill(Color.blue.opacity(0.01)) // Almost invisible but touchable
                            .contentShape(Rectangle())
                            .gesture(DragGesture().onEnded { v in handleResize(translation: v.translation, edge: .right) })
                            .overlay(
                                RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.5)).frame(width: 4, height: 40),
                                alignment: .center
                            )
                    }
                    .frame(width: 20)
                }

                // Left Handle - nur im unteren Bereich (nicht über Header)
                HStack {
                    VStack {
                        Spacer().frame(height: 44) // Header-Höhe aussparen
                        Rectangle()
                            .fill(Color.blue.opacity(0.01))
                            .contentShape(Rectangle())
                            .gesture(DragGesture().onEnded { v in handleResize(translation: v.translation, edge: .left) })
                            .overlay(
                                RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.5)).frame(width: 4, height: 40),
                                alignment: .center
                            )
                    }
                    .frame(width: 20)
                    Spacer()
                }

                // Bottom Handle
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.blue.opacity(0.01))
                        .frame(height: 20)
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onEnded { v in handleResize(translation: v.translation, edge: .bottom) })
                        .overlay(
                            RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.5)).frame(width: 40, height: 4).padding(.bottom, 4),
                            alignment: .bottom
                        )
                }

                // KEIN Top Handle mehr - kollidiert mit Header-Buttons
            }
            .allowsHitTesting(true)
        }
    }
    
    private enum ResizeEdge { case right, left, bottom, top }
    
    private func handleResize(translation: CGSize, edge: ResizeEdge) {
        var newCols = widget.size.columns
        var newRows = widget.size.rows
        
        switch edge {
        case .right:
            // Threshold for resizing: half a column width
            let deltaCols = Int(round(translation.width / (columnWidth + 12))) // 12 is spacing
            newCols = max(1, min(4, newCols + deltaCols))
        case .left:
            // Dragging left (negative) increases width
            let deltaCols = Int(round(-translation.width / (columnWidth + 12)))
            newCols = max(1, min(4, newCols + deltaCols))
        case .bottom:
            let rowHeight: CGFloat = 200 + 12
            let deltaRows = Double(translation.height / rowHeight)
            // Snap to 0.5 increments
            let targetRows = round((newRows + deltaRows) * 2) / 2.0
            newRows = max(0.5, targetRows)
        case .top:
            // Dragging up (negative) increases height
            let rowHeight: CGFloat = 200 + 12
            let deltaRows = Double(-translation.height / rowHeight)
            let targetRows = round((newRows + deltaRows) * 2) / 2.0
            newRows = max(0.5, targetRows)
        }
        
        if newCols != widget.size.columns || newRows != widget.size.rows {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            withAnimation(.spring()) {
                onResize(WidgetSize(columns: newCols, rows: newRows))
            }
        }
    }
}

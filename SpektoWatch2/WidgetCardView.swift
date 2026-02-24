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
    private let cornerRadius: CGFloat = 20
    private let editHeaderHeight: CGFloat = 46
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditMode {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(widget.type.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.thinMaterial, in: Circle())
                    }
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onDelete()
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(width: 28, height: 28)
                            .background(.thinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: editHeaderHeight)
                .background(.ultraThinMaterial)
            } else {
                HStack {
                    Text(widget.type.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            
            renderWidgetContent()
                .frame(height: widget.size.height)
                .clipped()
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isEditMode ? Color.accentColor.opacity(0.42) : Color.white.opacity(0.16),
                    lineWidth: isEditMode ? 1.6 : 1
                )
        )
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
            FrequencySpectrumWidget(audioEngine: audioEngine, settings: widget.settings)
        case .levelMeter:
            LevelMeterWidget(audioEngine: audioEngine)
        case .octaveBands:
            FrequencySpectrumWidget(audioEngine: audioEngine, settings: widget.settings)
        case .phaseMeter:
            PhaseMeterWidget(audioEngine: audioEngine)
        case .singleValue:
            SingleValueWidget(audioEngine: audioEngine, settings: widget.settings)
        case .toneGenerator:
            ToneGeneratorWidget(settings: widget.settings)
        case .spektralanalyseLab:
            SpektralanalyseLaborWidget(fftConfig: fftConfig, audioEngine: audioEngine)
        }
    }
    
    @ViewBuilder
    private var resizeHandles: some View {
        if isEditMode {
            ZStack {
                HStack {
                    Spacer()
                    VStack {
                        Spacer().frame(height: editHeaderHeight)
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.001))
                            .contentShape(Rectangle())
                            .gesture(DragGesture().onEnded { v in handleResize(translation: v.translation, edge: .right) })
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(0.45))
                                    .frame(width: 4, height: 40),
                                alignment: .center
                            )
                    }
                    .frame(width: 20)
                }

                HStack {
                    VStack {
                        Spacer().frame(height: editHeaderHeight)
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.001))
                            .contentShape(Rectangle())
                            .gesture(DragGesture().onEnded { v in handleResize(translation: v.translation, edge: .left) })
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(0.45))
                                    .frame(width: 4, height: 40),
                                alignment: .center
                            )
                    }
                    .frame(width: 20)
                    Spacer()
                }

                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.001))
                        .frame(height: 20)
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onEnded { v in handleResize(translation: v.translation, edge: .bottom) })
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(0.45))
                                .frame(width: 40, height: 4)
                                .padding(.bottom, 4),
                            alignment: .bottom
                        )
                }
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

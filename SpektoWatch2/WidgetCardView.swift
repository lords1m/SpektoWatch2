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
    private let overlayTopInset: CGFloat = 46
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            renderWidgetContent()
                .frame(height: widget.size.height)
                .clipped()

            if isEditMode {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    editActionPair
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isEditMode ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.28),
                    lineWidth: isEditMode ? 1.6 : 1
                )
        )
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
            OctaveBandWidget(audioEngine: audioEngine)
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
                        Spacer().frame(height: overlayTopInset)
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
                        Spacer().frame(height: overlayTopInset)
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

    private var editActionPair: some View {
        HStack(spacing: 0) {
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.primary.opacity(0.18))
                .frame(width: 1, height: 18)

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    onDelete()
                }
            }) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
    }
    
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

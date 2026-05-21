// WidgetCardView.swift - ERSETZEN
import SwiftUI

struct WidgetCardView: View {
    let widget: WidgetConfiguration
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fftConfig: FFTConfiguration
    @EnvironmentObject private var maskingEngine: MaskingEngine
    var isEditMode: Bool
    var columnWidth: CGFloat = 160 // Default fallback
    var onDelete: () -> Void
    var onResize: (WidgetSize) -> Void
    var onUpdateSettings: ([String: String]) -> Void

    @State private var showSettings = false
    @Environment(\.designAccent) private var accent
    @Environment(\.designNumerals) private var numerals
    private let cornerRadius: CGFloat = 22
    private let overlayTopInset: CGFloat = 46

    // Stable per-widget jiggle phase so cards rotate out of sync.
    private var jigglePhase: Double {
        let hash = abs(widget.id.uuidString.hashValue)
        return Double(hash % 100) / 100.0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            renderWidgetContent()
                .frame(height: widget.size.height)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .liquidGlassCard(cornerRadius: cornerRadius, isEditing: isEditMode, accent: accent)
        .overlay(alignment: .top) {
            if !isEditMode {
                cardHeader
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
        }
        .overlay(alignment: .topLeading) {
            if isEditMode {
                dragHandle
                    .padding(8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isEditMode {
                HStack(spacing: 6) {
                    settingsButton
                    deleteButton
                }
                .padding(8)
            }
        }
        .overlay(resizeHandles)
        .editJiggle(active: isEditMode, phase: jigglePhase)
        .sheet(isPresented: $showSettings) {
            WidgetSettingsView(widget: widget, onSave: onUpdateSettings)
        }
    }

    private var cardHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: widget.type.sfSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(headerTitle)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let meta = metaText {
                HStack(spacing: 3) {
                    Text(meta.value)
                        .font(.numerals(numerals, size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if let unit = meta.unit {
                        Text(unit)
                            .font(.numerals(numerals, size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.black.opacity(0.35))
                )
            }
        }
        .padding(.horizontal, 4)
    }

    private var headerTitle: String {
        widget.type.rawValue.uppercased()
    }

    /// Live numeric readout shown on the right side of the eyebrow.
    /// Returns nil for widget types where there is no obvious single
    /// scalar (visualizations, control surfaces). Pure-read from
    /// AudioEngine — no kernel changes required.
    private var metaText: (value: String, unit: String?)? {
        let levels = audioEngine.currentSpectrogramData?.levels ?? [:]
        switch widget.type {
        case .levelHistory, .levelMeter, .singleValue:
            if let v = levels["LAF"], v > -120 {
                return (String(format: "%.1f", v), "dB(A)")
            }
            return nil
        case .spectrogram, .waterfall, .frequencyDisplay, .octaveBands, .spektralanalyseLab:
            if let v = levels["LAeq"], v > -120 {
                return (String(format: "%.1f", v), "dB Leq")
            }
            return nil
        case .phaseMeter, .toneGenerator, .masking:
            return nil
        }
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.black)
            .frame(width: 28, height: 28)
            .background(Circle().fill(accent))
            .shadow(color: accent.opacity(0.4), radius: 6)
    }

    private var settingsButton: some View {
        Button(action: { showSettings = true }) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.thinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("widgetSettingsButton")
    }

    private var deleteButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { onDelete() }
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.red))
                .shadow(color: Color.red.opacity(0.4), radius: 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("widgetDeleteButton")
    }
    
    @ViewBuilder
    private func renderWidgetContent() -> some View {
        switch widget.type {
        case .spectrogram:
            SpectrogramWidget(audioEngine: audioEngine, settings: widget.settings)
        case .waterfall:
            WaterfallWidget(audioEngine: audioEngine, settings: widget.settings)
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
        case .masking:
            MaskingEntryWidget(engine: maskingEngine)
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

    private func handleResize(translation: CGSize, edge: ResizeEdge) {
        // Per-type bounds (M8) — drag snaps in whole grid cells and is
        // clamped against the widget type's allowed range.
        let range = WidgetConfiguration.sizeRange(for: widget.type)
        let columnStride = columnWidth + 12 // grid spacing
        let rowStride: CGFloat = 200 + 12   // baseHeight + spacing (see WidgetSize.height)

        var newCols = widget.size.columns
        var newRows = widget.size.rows

        switch edge {
        case .right:
            let deltaCols = Int((translation.width / columnStride).rounded())
            newCols = newCols + deltaCols
        case .left:
            // Dragging left (negative width) increases width
            let deltaCols = Int((-translation.width / columnStride).rounded())
            newCols = newCols + deltaCols
        case .bottom:
            let deltaRows = Int((translation.height / rowStride).rounded())
            newRows = newRows + deltaRows
        case .top:
            // Dragging up (negative height) increases height
            let deltaRows = Int((-translation.height / rowStride).rounded())
            newRows = newRows + deltaRows
        }

        let proposed = WidgetSize(columns: newCols, rows: newRows)
        let clamped = proposed.clamped(min: range.min, max: range.max)

        if clamped.columns != widget.size.columns || clamped.rows != widget.size.rows {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            withAnimation(.spring()) {
                onResize(clamped)
            }
        }
    }
}

// WidgetCardView.swift - ERSETZEN
import SwiftUI

struct WidgetCardView: View {
    let widget: WidgetConfiguration
    /// Non-observed: kernels (`SpectrogramWidget`, etc.) observe audioEngine
    /// themselves. Holding @ObservedObject here would re-render the card
    /// chrome (material, shadows, header) on every 15 Hz audio publish.
    let audioEngine: AudioEngine
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

    // Card-internal geometry. Header height is reserved unconditionally
    // (hidden via opacity in edit mode) so toggling edit doesn't reflow
    // the kernel and break Metal redraw assumptions.
    private let cardTopInset: CGFloat = 8
    private let headerHeight: CGFloat = 22
    private let headerGap: CGFloat = 6

    private var chromeOverhead: CGFloat {
        cardTopInset + headerHeight + headerGap
    }

    /// Kernel render height — preserved across edit-mode toggle. Floor at
    /// 60pt so the smallest widget (1×1 = 200pt total) still leaves a
    /// visible kernel area after chrome overhead.
    private var kernelHeight: CGFloat {
        max(60, widget.size.height - chromeOverhead)
    }

    // Stable per-widget jiggle phase so cards rotate out of sync. Uses
    // the UUID byte sum rather than `hashValue` (which is salted per
    // launch) so the rotation phase survives cold restarts.
    private var jigglePhase: Double {
        let bytes = widget.id.uuid
        let sum = Int(bytes.0) &+ Int(bytes.1) &+ Int(bytes.2) &+ Int(bytes.3)
            &+ Int(bytes.4) &+ Int(bytes.5) &+ Int(bytes.6) &+ Int(bytes.7)
            &+ Int(bytes.8) &+ Int(bytes.9) &+ Int(bytes.10) &+ Int(bytes.11)
            &+ Int(bytes.12) &+ Int(bytes.13) &+ Int(bytes.14) &+ Int(bytes.15)
        return Double(sum % 100) / 100.0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header strip — always reserved; hidden visually in edit mode
            // so the kernel area doesn't reflow when toggling.
            cardHeader
                .frame(height: headerHeight)
                .padding(.horizontal, 14)
                .padding(.top, cardTopInset)
                .padding(.bottom, headerGap)
                .opacity(isEditMode ? 0 : 1)

            // Kernel fills the remaining card area edge-to-edge so the
            // card material (.thinMaterial) acts as the kernel background,
            // with no visible inner frame. Outer rounded corners on the
            // card itself clip overflow.
            renderWidgetContent()
                .frame(maxWidth: .infinity)
                .frame(height: kernelHeight)
                .clipped()
        }
        .frame(height: widget.size.height)
        .liquidGlassCard(cornerRadius: cornerRadius, isEditing: isEditMode, accent: accent)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Resize handles go BEFORE the button overlays so the tap-eating
        // edge strips can't intercept touches meant for the gear/X buttons
        // in the top corners.
        .overlay(resizeHandles)
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
            // Meta readout is isolated in its own view so only it (not the
            // whole card chrome) re-renders on the 15 Hz audio publish.
            CardMetaReader(widgetType: widget.type, audioEngine: audioEngine, numerals: numerals)
        }
        .padding(.horizontal, 4)
    }

    private var headerTitle: String {
        widget.type.rawValue.uppercased()
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
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.thinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // High priority so the parent .onDrag in ModularDashboardView
        // can't swallow the tap.
        .highPriorityGesture(
            TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSettings = true
            }
        )
        .accessibilityIdentifier("widgetSettingsButton")
        .accessibilityLabel("Widget-Einstellungen")
    }

    private var deleteButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { onDelete() }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.red))
                .shadow(color: Color.red.opacity(0.4), radius: 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            TapGesture().onEnded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { onDelete() }
            }
        )
        .accessibilityIdentifier("widgetDeleteButton")
        .accessibilityLabel("Widget entfernen")
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
            LevelMeterWidget(audioEngine: audioEngine, settings: widget.settings)
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

/// Isolated meta-value reader so the parent `WidgetCardView` does NOT
/// have to observe `audioEngine`. Re-rendering this tiny view at 15 Hz
/// is cheap; re-rendering the full `WidgetCardView` chrome
/// (`.regularMaterial` + shadows + edit overlays) at 15 Hz is not.
private struct CardMetaReader: View {
    let widgetType: AudioWidgetType
    @ObservedObject var audioEngine: AudioEngine
    let numerals: NumeralStyle

    var body: some View {
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
            .background(Capsule().fill(Color.black.opacity(0.35)))
        }
    }

    private var metaText: (value: String, unit: String?)? {
        guard let data = audioEngine.currentSpectrogramData,
              data.broadbandLevel > -119 else { return nil }
        let levels = data.levels
        switch widgetType {
        case .levelHistory, .levelMeter, .singleValue:
            if let v = levels["LAF"], v.isFinite, v > -119.5 {
                return (String(format: "%.1f", v), "dB(A)")
            }
            return nil
        case .spectrogram, .waterfall, .frequencyDisplay, .octaveBands, .spektralanalyseLab:
            if let v = levels["LAeq"], v.isFinite, v > -119.5 {
                return (String(format: "%.1f", v), "dB Leq")
            }
            return nil
        case .phaseMeter, .toneGenerator, .masking:
            return nil
        }
    }
}

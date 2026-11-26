// WidgetCardView.swift - ERSETZEN
import SwiftUI

struct WidgetCardView: View {
    let widget: WidgetConfiguration
    /// Non-observed: kernels (`SpectrogramWidget`, etc.) observe audioEngine
    /// themselves.
    let audioEngine: AudioEngine
    var fftConfig: FFTConfiguration
    @Environment(AppServices.self) private var services

    private var maskingEngine: MaskingEngine { services.maskingEngine! }
    var isEditMode: Bool
    var columnWidth: CGFloat = 160 // Default fallback
    /// Actual grid spacing from the dashboard (density-dependent, 6–16pt).
    /// Used so drag-resize snap math matches the rendered geometry.
    var gridSpacing: CGFloat = 12
    var onDelete: () -> Void
    var onResize: (WidgetSize) -> Void
    var onUpdateSettings: ([String: String]) -> Void
    var onUpdateStyle: ((WidgetDisplayStyle) -> Void)? = nil
    var onLaunchFeature: ((WidgetConfiguration) -> Void)? = nil
    /// Invoked when the user long-presses the card outside edit mode.
    var onRequestEditMode: () -> Void = {}

    enum Chrome: Equatable {
        /// Classic dashboard card: square Ferrite card with resize handles,
        /// drag handle, gear and delete buttons in edit mode.
        case dashboard
        /// iOS Home Screen widget: rounded, fixed size from the Home grid.
        /// The Home Screen owns edit affordances (jiggle, "−", context
        /// menu, settings sheet), so the card draws none of its own.
        case homeWidget
    }
    var chrome: Chrome = .dashboard
    /// Exact card height from the Home grid (`.homeWidget` only).
    var heightOverride: CGFloat? = nil

    @State private var showSettings = false
    @State private var deleteRequested = false
    @Environment(\.designAccent) private var accent
    @Environment(\.ferriteLine) private var ferriteLine
    @Environment(\.designNumerals) private var numerals
    private let cornerRadius: CGFloat = Radius.card
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
    /// 60pt so the smallest widget still leaves a visible kernel area
    /// after chrome overhead.
    private var kernelHeight: CGFloat {
        max(60, widget.frameHeight - chromeOverhead)
    }

    /// Value widgets (number / meter) print their own designation inside the
    /// kernel, so the chrome header is clutter when idle: it appears only in
    /// edit mode, and the kernel fills the whole card otherwise. Chart widgets
    /// keep their header (title + live meta readout) visible as before.
    private var hidesHeaderWhenIdle: Bool {
        widget.displayStyle == .icon || widget.type == .singleValue || widget.type == .levelMeter
    }
    private var showsHeaderStrip: Bool {
        if widget.displayStyle == .icon { return false }
        return hidesHeaderWhenIdle ? isEditMode : true
    }
    private var headerOpacity: Double {
        hidesHeaderWhenIdle ? (isEditMode ? 1 : 0) : (isEditMode ? 0 : 1)
    }
    /// Value widgets reclaim the header strip when idle → larger content.
    /// Reflow on the edit toggle is harmless for these (Text / Canvas kernels).
    private var resolvedKernelHeight: CGFloat {
        (hidesHeaderWhenIdle && !isEditMode) || widget.displayStyle == .icon
            ? widget.frameHeight
            : kernelHeight
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
        switch chrome {
        case .dashboard: dashboardBody
        case .homeWidget: homeWidgetBody
        }
    }

    // MARK: Home Screen widget

    private var homeHeight: CGFloat { heightOverride ?? widget.frameHeight }
    private let homeContentInset: CGFloat = 8

    private var homeWidgetBody: some View {
        let shape = RoundedRectangle(cornerRadius: FerriteRadius.homeWidget, style: .continuous)
        return VStack(spacing: 0) {
            if !hidesHeaderWhenIdle {
                cardHeader
                    .frame(height: headerHeight)
                    .padding(.horizontal, 14)
                    .padding(.top, cardTopInset + 4)
                    .padding(.bottom, headerGap)
            }
            // Content margins like iOS widgets, so the rounded corners
            // never clip a kernel's edge (meter bars, axis labels).
            renderWidgetContent()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: FerriteRadius.homeWidget - homeContentInset, style: .continuous))
                .padding(.horizontal, homeContentInset)
                .padding(.bottom, homeContentInset)
                .padding(.top, hidesHeaderWhenIdle ? homeContentInset : 0)
        }
        .frame(height: homeHeight)
        .background(FerriteColor.surface, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
        // Lit rim + resting shadow, both from the static shape, so the live
        // kernel inside never re-renders them.
        .ferriteDepth(in: shape)
        .contentShape(shape)
    }

    // MARK: Dashboard card

    private var dashboardBody: some View {
        VStack(spacing: 0) {
            // Header strip. Chart widgets: reserved always, hidden via opacity
            // in edit mode (no reflow). Value widgets: omitted from layout when
            // idle (kernel fills the card) and shown only in edit mode.
            if showsHeaderStrip {
                cardHeader
                    .frame(height: headerHeight)
                    .padding(.horizontal, 14)
                    .padding(.top, cardTopInset)
                    .padding(.bottom, headerGap)
                    .opacity(headerOpacity)
            }

            // Kernel fills the remaining card area edge-to-edge so the
            // card surface (solid Ferrite fill) acts as the kernel background,
            // with no visible inner frame. Outer rounded corners on the
            // card itself clip overflow.
            renderWidgetContent()
                .frame(maxWidth: .infinity)
                .frame(height: resolvedKernelHeight)
                .clipped()
        }
        .frame(height: widget.frameHeight)
        .widgetCardChrome(cornerRadius: cornerRadius, isEditing: isEditMode)
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
        .onTapGesture {
            if widget.displayStyle == .icon && !isEditMode {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onLaunchFeature?(widget)
            }
        }
        // Long-press enters edit mode (iOS home-screen convention: hold →
        // jiggle → move/resize). Widget settings are reached via the gear
        // button each card shows in edit mode.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                guard !isEditMode else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onRequestEditMode()
            }
        )
        .sheet(isPresented: $showSettings) {
            WidgetSettingsView(
                widget: widget,
                onSave: onUpdateSettings,
                onSaveWithStyle: { newSettings, newStyle in
                    onUpdateSettings(newSettings)
                    if newStyle != widget.displayStyle {
                        onUpdateStyle?(newStyle)
                    }
                }
            )
        }
    }

    private var cardHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: widget.type.sfSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(headerTitle)
                .font(.readout(size: 10, weight: .regular))
                .tracking(1.8)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            // Meta readout is isolated in its own view so only it (not the
            // whole card chrome) re-renders on the 15 Hz audio publish.
            CardMetaReader(
                widgetType: widget.type,
                live: audioEngine.live,
                numerals: numerals,
                dimmed: isEditMode
            )
        }
        .padding(.horizontal, 4)
    }

    private var headerTitle: String {
        // Single-value cards otherwise all read "EINZELWERT"; surfacing the
        // configured metric (LAF / LAEQ / LCPEAK …) is what tells the four
        // near-identical cards apart at a glance.
        if widget.type == .singleValue {
            let metric = widget.settings["metric"] ?? WidgetSettings.defaultSingleValueMetric
            return metric.uppercased()
        }
        return widget.type.rawValue.uppercased()
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(ferriteLine.onColor)
            .frame(width: 28, height: 28)
            .background(Circle().fill(accent))
            .overlay(Circle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
    }

    private var settingsButton: some View {
        // usesHighPriorityTap: the parent .onDrag in ModularDashboardView
        // would otherwise swallow the tap.
        GlassIconButton(
            symbol: "gearshape.fill",
            iconSize: 13,
            diameter: 32,
            identifier: "widgetSettingsButton",
            label: "Widget-Einstellungen",
            usesHighPriorityTap: true
        ) {
            showSettings = true
        }
    }

    private var deleteButton: some View {
        // Two trigger paths by necessity: touch goes through the
        // highPriorityGesture (it must outrank the parent .onDrag), VoiceOver
        // activation goes through the Button action. requestDelete() guards
        // so the destructive callback can only ever fire once.
        Button(action: requestDelete) {
            // Identifier directly on the Image leaf — same iOS 26 PlainButtonStyle fix
            // as settingsButton: .accessibilityIdentifier on the Button wrapper is
            // ignored when PlainButtonStyle makes the Button accessibility-transparent.
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FerriteLine.u2.onColor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(FerriteStatus.recording))
                .overlay(Circle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
                .contentShape(Circle())
                .accessibilityIdentifier("widgetDeleteButton")
                .accessibilityLabel("Widget entfernen")
                .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            TapGesture().onEnded { requestDelete() }
        )
    }

    private func requestDelete() {
        guard !deleteRequested else { return }
        deleteRequested = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { onDelete() }
    }

    @ViewBuilder
    private func renderWidgetContent() -> some View {
        if widget.displayStyle == .icon {
            FeatureIconTileView(widget: widget)
        } else {
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
                ToneGeneratorWidget()
            case .spektralanalyseLab:
                SpektralanalyseLaborWidget(fftConfig: fftConfig, audioEngine: audioEngine)
            case .audioEditor:
                AudioEditorHomeWidget()
            case .recordings:
                RecordingsHomeWidget()
            case .settings:
                SettingsQuickWidget(audioEngine: audioEngine)
            case .masking:
                MaskingEntryWidget(engine: maskingEngine)
            }
        }
    }
    
    @ViewBuilder
    private var resizeHandles: some View {
        if isEditMode && widget.displayStyle == .liveWidget {
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
                    .frame(width: 28)
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
                    .frame(width: 28)
                    Spacer()
                }

                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.001))
                        .frame(height: 28)
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
            // VoiceOver path for resizing: the drag handles are invisible
            // gesture rects, so expose the whole handle layer as one
            // adjustable element that steps through the allowed sizes.
            .accessibilityElement()
            .accessibilityLabel("Widgetgröße")
            .accessibilityValue("\(widget.size.columns) Spalten, \(widget.size.rows) Zeilen")
            .accessibilityAdjustableAction { direction in
                adjustSizeForAccessibility(direction)
            }
        }
    }

    /// Allowed sizes for this widget type, deduplicated after per-type
    /// normalization, ordered small → large for the adjustable action.
    private var accessibilityResizeSteps: [WidgetSize] {
        let range = WidgetConfiguration.sizeRange(for: widget.type)
        var sizes: [WidgetSize] = []
        for rows in range.min.rows...range.max.rows {
            for columns in range.min.columns...range.max.columns {
                let normalized = WidgetConfiguration.normalizedSize(
                    for: widget.type,
                    size: WidgetSize(columns: columns, rows: rows),
                    settings: widget.settings
                )
                if !sizes.contains(normalized) {
                    sizes.append(normalized)
                }
            }
        }
        return sizes.sorted {
            ($0.columns * $0.rows, $0.columns) < ($1.columns * $1.rows, $1.columns)
        }
    }

    private func adjustSizeForAccessibility(_ direction: AccessibilityAdjustmentDirection) {
        let steps = accessibilityResizeSteps
        guard let current = steps.firstIndex(of: widget.size) else {
            if let first = steps.first { onResize(first) }
            return
        }
        let next: Int
        switch direction {
        case .increment: next = current + 1
        case .decrement: next = current - 1
        @unknown default: return
        }
        guard steps.indices.contains(next) else { return }
        withAnimation(.spring()) {
            onResize(steps[next])
        }
    }
    
    private enum ResizeEdge { case right, left, bottom, top }

    private func handleResize(translation: CGSize, edge: ResizeEdge) {
        // Per-type bounds (M8) — drag snaps in whole grid cells and is
        // clamped against the widget type's allowed range.
        let range = WidgetConfiguration.sizeRange(for: widget.type)
        let columnStride = columnWidth + gridSpacing
        // Row stride stays at 12 to match WidgetConfiguration.frameHeight,
        // which always uses 12pt inter-row spacing regardless of density.
        let rowStride: CGFloat = WidgetConfiguration.baseRowHeight(for: widget.type) + 12

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
        let clamped = WidgetConfiguration.normalizedSize(
            for: widget.type,
            size: proposed.clamped(min: range.min, max: range.max),
            settings: widget.settings
        )

        if clamped.columns != widget.size.columns || clamped.rows != widget.size.rows {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            withAnimation(.spring()) {
                onResize(clamped)
            }
        }
    }
}

// Equatable conformance for .equatable() guard in dashboardGrid. Only
// value-type inputs that affect visual output are compared; audioEngine
// and fftConfig are class references whose identity is stable across
// renders (M19 task-6).
extension WidgetCardView: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.widget == rhs.widget &&
        lhs.isEditMode == rhs.isEditMode &&
        lhs.columnWidth == rhs.columnWidth &&
        lhs.gridSpacing == rhs.gridSpacing &&
        lhs.chrome == rhs.chrome &&
        lhs.heightOverride == rhs.heightOverride
    }
}

/// Isolated meta-value reader so the parent `WidgetCardView` does NOT
/// have to observe `audioEngine`. Re-rendering this tiny view at 15 Hz
/// is cheap; re-rendering the full `WidgetCardView` chrome
/// (`.regularMaterial` + shadows + edit overlays) at 15 Hz is not.
private struct CardMetaReader: View {
    let widgetType: AudioWidgetType
    var live: LiveAcousticState
    let numerals: NumeralStyle
    var dimmed: Bool = false

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
            .background(Capsule().fill(FerriteColor.canvas.opacity(0.7)))
            .opacity(dimmed ? 0.35 : 1)
        }
    }

    private var metaText: (value: String, unit: String?)? {
        guard let data = live.currentSpectrogramData,
              data.broadbandLevel > -119 else { return nil }
        let levels = data.levels
        switch widgetType {
        case .levelHistory, .levelMeter, .singleValue:
            if let v = levels["LAF"], v.isFinite, v > -119.5 {
                return (v.formatted(.number.precision(.fractionLength(1))), "dB(A)")
            }
            return nil
        case .spectrogram, .waterfall, .frequencyDisplay, .octaveBands, .spektralanalyseLab:
            if let v = levels["LAeq"], v.isFinite, v > -119.5 {
                return (v.formatted(.number.precision(.fractionLength(1))), "dB Leq")
            }
            return nil
        case .phaseMeter, .toneGenerator, .masking, .audioEditor, .recordings, .settings:
            return nil
        }
    }
}

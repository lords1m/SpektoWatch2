import SwiftUI
import UniformTypeIdentifiers

// MARK: - App icon

/// iOS-style app icon in Ferrite colours: an ink squircle with a white
/// SF Symbol and a line-colour bar along the bottom edge (like the line
/// colour on a station sign), label underneath.
struct HomeAppIcon: View {
    let widget: WidgetConfiguration
    let iconSize: CGFloat
    var showsLabel: Bool = true

    @Environment(AppServices.self) private var services

    /// iOS badges are counts only — the recordings count.
    private var badgeText: String? {
        guard widget.type == .recordings else { return nil }
        let count = services.recordingManager.recordings.count
        return count > 0 ? (count > 99 ? "99+" : "\(count)") : nil
    }

    /// Single-value icons are told apart by their metric (LAF, LAeq …).
    private var label: String {
        if widget.type == .singleValue {
            return widget.settings["metric"] ?? WidgetSettings.defaultSingleValueMetric
        }
        return widget.type.homeShortName
    }

    var body: some View {
        VStack(spacing: 5) {
            HomeIconGlyph(symbol: widget.type.sfSymbol, line: widget.type.homeIconLine, size: iconSize)
                .overlay(alignment: .topTrailing) {
                    if let badgeText {
                        Text(badgeText)
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(FerriteLine.u2.onColor)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Capsule().fill(FerriteStatus.recording))
                            .overlay(Capsule().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
                            .offset(x: 8, y: -8)
                            .accessibilityHidden(true)
                    }
                }
            if showsLabel {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FerriteColor.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: iconSize + 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(widget.type == .singleValue ? "\(widget.type.rawValue) \(label)" : widget.type.rawValue)
        .accessibilityValue(badgeText.map { "\($0) Aufnahmen" } ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("featureIconTile-\(widget.type.rawValue)")
    }
}

/// The squircle itself, shared by Home icons and the dock.
struct HomeIconGlyph: View {
    let symbol: String
    var line: FerriteLine? = nil
    let size: CGFloat
    var symbolColor: Color = FerriteColor.onAccent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FerriteRadius.homeIcon(size), style: .continuous)
        shape
            .fill(FerriteColor.label)
            .overlay(alignment: .bottom) {
                if let line {
                    Rectangle()
                        .fill(line.color)
                        .frame(height: max(5, (size * 0.11).rounded()))
                }
            }
            // Sheen sits on the ink, under the symbol: the icon reads as a
            // lit, slightly domed tile rather than a flat stamp.
            .overlay { FerriteSheen(shape: shape, color: FerriteDepth.iconSheen) }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(symbolColor)
                    .offset(y: line == nil ? 0 : -size * 0.04)
            }
            .clipShape(shape)
            // Ink edge keeps the icon readable on a black wallpaper in dark mode.
            .overlay(shape.strokeBorder(FerriteColor.hairline, lineWidth: FerriteStroke.hairline))
            .ferriteDepth(in: shape)
            .frame(width: size, height: size)
    }
}

/// iOS press feel for icons: shrink and dim while held.
struct HomeIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Tile (icon or widget)

struct HomeScreenTileView: View {
    let widget: WidgetConfiguration
    /// Cells the tile occupies right now (the live preview while resizing).
    let span: HomeSpan
    let size: CGSize
    let metrics: HomeGridMetrics
    let isEditMode: Bool
    /// Columns from the tile's column to the right page edge: the widest it
    /// can grow by dragging without moving.
    let maxResizeColumns: Int
    let audioEngine: AudioEngine
    var fftConfig: FFTConfiguration
    let zoomNamespace: Namespace.ID

    var onLaunch: (WidgetConfiguration) -> Void
    var onDelete: (WidgetConfiguration) -> Void
    var onResize: (HomeSpan) -> Void
    /// Live span while an edge is dragged; `nil` when the drag ends.
    var onResizePreview: (HomeSpan?) -> Void
    var onUpdateSettings: ([String: String]) -> Void
    var onUpdateStyle: (WidgetDisplayStyle) -> Void
    var onEnterEditMode: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false
    @State private var resizeStart: HomeSpan?
    @State private var resizeTarget: HomeSpan?

    private var isIcon: Bool { widget.isHomeIcon }
    private var isResizing: Bool { resizeTarget != nil }

    /// Stable per-tile phase so tiles jiggle out of sync (UUID byte sum,
    /// not the per-launch-salted hashValue).
    private var jigglePhase: Double {
        let b = widget.id.uuid
        let sum = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7].reduce(0) { $0 &+ Int($1) }
        return Double(sum % 100) / 100
    }

    private var canResize: Bool {
        guard !isIcon else { return false }
        let range = WidgetConfiguration.homeSpanRange(for: widget.type)
        return range.min != range.max
    }

    var body: some View {
        content
            .overlay {
                if isEditMode && canResize { resizeHandles }
            }
            .overlay {
                if let resizeTarget { resizeBadge(resizeTarget) }
            }
            .overlay(alignment: .topLeading) {
                if isEditMode && !isResizing { removeBadge }
            }
            // Hold still while an edge is dragged, so the grip stays under the finger.
            .editJiggle(active: isEditMode && !isResizing, phase: jigglePhase, amplitude: isIcon ? 1.6 : 0.7)
            .contextMenu {
                if !isEditMode { menu }
            } preview: {
                preview
            }
            .sheet(isPresented: $showSettings) {
                WidgetSettingsView(
                    widget: widget,
                    onSave: onUpdateSettings,
                    onSaveWithStyle: { newSettings, newStyle in
                        onUpdateSettings(newSettings)
                        if newStyle != widget.displayStyle { onUpdateStyle(newStyle) }
                    }
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        if isIcon {
            Button {
                guard !isEditMode else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onLaunch(widget)
            } label: {
                HomeAppIcon(widget: widget, iconSize: metrics.iconSize)
                    .matchedTransitionSource(id: widget.id, in: zoomNamespace)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HomeIconPressStyle())
        } else {
            WidgetCardView(
                widget: widget,
                audioEngine: audioEngine,
                fftConfig: fftConfig,
                isEditMode: isEditMode,
                onDelete: { onDelete(widget) },
                onResize: { _ in },
                onUpdateSettings: onUpdateSettings,
                onUpdateStyle: onUpdateStyle,
                chrome: .homeWidget,
                heightOverride: size.height
            )
            .equatable()
            .frame(width: size.width, height: size.height)
            // In jiggle mode a tap edits the widget, like iOS; the live
            // content underneath stops taking touches.
            .overlay {
                if isEditMode {
                    Color.clear
                        .contentShape(RoundedRectangle(cornerRadius: FerriteRadius.homeWidget, style: .continuous))
                        .onTapGesture { showSettings = true }
                        .accessibilityLabel("\(widget.type.rawValue) bearbeiten")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("homeWidgetEditTarget-\(widget.type.rawValue)-\(span.columns)x\(span.rows)")
                }
            }
        }
    }

    private var removeBadge: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { onDelete(widget) }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(FerriteColor.label)
                .frame(width: 24, height: 24)
                .background(Circle().fill(FerriteGlass.fillStrong))
                .overlay(Circle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: isIcon ? (size.width - metrics.iconSize) / 2 - 20 : -20, y: -20)
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        .accessibilityIdentifier("widgetDeleteButton")
        .accessibilityLabel("\(widget.type.rawValue) entfernen")
    }

    // MARK: Drag-resize

    private enum ResizeEdge { case trailing, bottom, corner }

    /// Grips on the right edge, the bottom edge and the bottom-right corner.
    /// Dragging snaps to whole grid cells; the page re-flows live.
    private var resizeHandles: some View {
        ZStack {
            resizeGrip(.trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: 16)
            resizeGrip(.bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: 16)
            resizeGrip(.corner)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 12, y: 12)
        }
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Größe von \(widget.type.rawValue)")
        .accessibilityValue("\(span.columns) Spalten, \(span.rows) Zeilen")
        .accessibilityIdentifier("homeResizeHandle-\(widget.type.rawValue)-\(span.columns)x\(span.rows)")
        .accessibilityAction(named: "Breiter") { step(columns: 1, rows: 0) }
        .accessibilityAction(named: "Schmaler") { step(columns: -1, rows: 0) }
        .accessibilityAction(named: "Höher") { step(columns: 0, rows: 1) }
        .accessibilityAction(named: "Niedriger") { step(columns: 0, rows: -1) }
    }

    private func resizeGrip(_ edge: ResizeEdge) -> some View {
        Group {
            switch edge {
            case .trailing:
                Capsule().fill(FerriteColor.label).frame(width: 5, height: 30)
                    .overlay(Capsule().strokeBorder(FerriteColor.background, lineWidth: FerriteStroke.hairline))
            case .bottom:
                Capsule().fill(FerriteColor.label).frame(width: 30, height: 5)
                    .overlay(Capsule().strokeBorder(FerriteColor.background, lineWidth: FerriteStroke.hairline))
            case .corner:
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FerriteColor.label)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(FerriteGlass.fillStrong))
                    .overlay(Circle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        // Beats the reorder drag and the page scroll: touching a grip resizes.
        .highPriorityGesture(resizeGesture(edge))
    }

    private func resizeGesture(_ edge: ResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let start: HomeSpan
                if let resizeStart {
                    start = resizeStart
                } else {
                    start = span
                    resizeStart = span
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                let dc = edge == .bottom ? 0 : Int((value.translation.width / metrics.pitch).rounded())
                let dr = edge == .trailing ? 0 : Int((value.translation.height / metrics.pitch).rounded())
                let target = constrained(HomeSpan(columns: start.columns + dc, rows: start.rows + dr))
                guard target != resizeTarget else { return }
                if resizeTarget != nil { UISelectionFeedbackGenerator().selectionChanged() }
                resizeTarget = target
                onResizePreview(target)
            }
            .onEnded { _ in
                let start = resizeStart
                let target = resizeTarget
                resizeStart = nil
                resizeTarget = nil
                if let target, target != start {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onResize(target)
                }
                onResizePreview(nil)
            }
    }

    /// Per-type limits, and no wider than the room to the right page edge.
    private func constrained(_ raw: HomeSpan) -> HomeSpan {
        var result = WidgetConfiguration.normalizedHomeSpan(raw, for: widget.type, settings: widget.settings)
        let minColumns = WidgetConfiguration.homeSpanRange(for: widget.type).min.columns
        result.columns = min(result.columns, max(maxResizeColumns, minColumns))
        return result
    }

    /// VoiceOver resize: one cell per action.
    private func step(columns dc: Int, rows dr: Int) {
        let target = constrained(HomeSpan(columns: span.columns + dc, rows: span.rows + dr))
        guard target != span else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { onResize(target) }
    }

    private func resizeBadge(_ target: HomeSpan) -> some View {
        Text(target.label)
            .font(FerriteFont.headline.monospacedDigit())
            .foregroundStyle(FerriteColor.label)
            .padding(.horizontal, FerriteSpace.m)
            .frame(height: 30)
            .ferriteGlass()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Context menu

    @ViewBuilder
    private var menu: some View {
        Button {
            onEnterEditMode()
        } label: {
            Label("Home-Bildschirm bearbeiten", systemImage: "apps.iphone")
        }

        if isIcon {
            Button {
                onLaunch(widget)
            } label: {
                Label("Öffnen", systemImage: "arrow.up.forward.app")
            }
            Button {
                onUpdateStyle(.liveWidget)
            } label: {
                Label("Als Widget anzeigen", systemImage: "square.grid.2x2")
            }
        } else {
            Button {
                showSettings = true
            } label: {
                Label("Widget bearbeiten", systemImage: "info.circle")
            }
            let spans = widget.availableHomeSpans
            if spans.count > 1 {
                Menu {
                    ForEach(spans, id: \.self) { option in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { onResize(option) }
                        } label: {
                            let title = option.familyName.map { "\($0) (\(option.label))" } ?? option.label
                            if option == span {
                                Label(title, systemImage: "checkmark")
                            } else {
                                Text(title)
                            }
                        }
                    }
                } label: {
                    Label("Größe", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
            Button {
                onUpdateStyle(.icon)
            } label: {
                Label("Als Icon anzeigen", systemImage: "app")
            }
        }

        Divider()

        Button(role: .destructive) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { onDelete(widget) }
        } label: {
            Label(isIcon ? "Vom Home-Bildschirm entfernen" : "Widget entfernen",
                  systemImage: "minus.circle")
        }
    }

    /// Lightweight lift preview: never re-mounts the live kernel (Metal,
    /// 15 Hz subscriptions) just to show the context-menu snapshot.
    @ViewBuilder
    private var preview: some View {
        if isIcon {
            HomeIconGlyph(symbol: widget.type.sfSymbol, line: widget.type.homeIconLine, size: metrics.iconSize * 1.25)
        } else {
            let shape = RoundedRectangle(cornerRadius: FerriteRadius.homeWidget, style: .continuous)
            VStack(spacing: FerriteSpace.s) {
                Image(systemName: widget.type.sfSymbol)
                    .font(.system(size: 28, weight: .semibold))
                Text(widget.type.rawValue)
                    .font(FerriteFont.headline)
                FerriteStatusBadge(state: .live)
            }
            .foregroundStyle(FerriteColor.label)
            .frame(width: max(size.width, 160), height: min(max(size.height, 120), 360))
            .background(FerriteColor.surface, in: shape)
            .overlay(shape.strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
        }
    }
}

// MARK: - Page

/// One Home Screen page: the tiled-wall wallpaper and its tiles, packed
/// into the iOS 4-column grid.
struct HomeScreenPage: View {
    let widgets: [WidgetConfiguration]
    let isEditMode: Bool
    let isActive: Bool
    let audioEngine: AudioEngine
    let fftConfig: FFTConfiguration
    let zoomNamespace: Namespace.ID
    @Binding var reorderItems: [WidgetConfiguration]
    @Binding var draggedWidget: WidgetConfiguration?

    var onLaunch: (WidgetConfiguration) -> Void
    var onDelete: (WidgetConfiguration) -> Void
    var onResize: (UUID, HomeSpan) -> Void
    var onUpdateSettings: (UUID, [String: String]) -> Void
    var onUpdateStyle: (UUID, WidgetDisplayStyle) -> Void
    var onSetEditMode: (Bool) -> Void
    var onSaveOrder: () -> Void

    @State private var dropTargetID: UUID?
    /// Span of the widget whose edge is being dragged; the grid re-flows
    /// around it live and the span is saved when the finger lifts.
    @State private var resizePreview: ResizePreview?

    private struct ResizePreview: Equatable {
        let id: UUID
        let span: HomeSpan
    }

    private func span(of widget: WidgetConfiguration) -> HomeSpan {
        if let resizePreview, resizePreview.id == widget.id { return resizePreview.span }
        return widget.resolvedHomeSpan
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = HomeGridMetrics(width: geo.size.width)
            let packed = HomeGridPacker.pack(widgets.map { ($0.id, span(of: $0)) })

            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    // Empty wallpaper: long-press enters jiggle mode, a tap
                    // leaves it — the same as on iOS.
                    Color.clear
                        .frame(width: geo.size.width)
                        .frame(minHeight: max(metrics.height(rows: packed.rows), geo.size.height - 24))
                        .contentShape(Rectangle())
                        .onTapGesture { if isEditMode { onSetEditMode(false) } }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            guard !isEditMode else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onSetEditMode(true)
                        }

                    if widgets.isEmpty {
                        emptyState
                            .frame(width: geo.size.width)
                            .padding(.top, metrics.pitch)
                    }

                    ForEach(widgets) { widget in
                        if let placement = packed.placements[widget.id] {
                            let frame = metrics.frame(column: placement.column, row: placement.row,
                                                      span: placement.span, isIcon: widget.isHomeIcon)
                            tile(widget, placement: placement, frame: frame, metrics: metrics)
                                .zIndex(resizePreview?.id == widget.id ? 1 : 0)
                        }
                    }
                }
                .padding(.top, FerriteSpace.m)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: widgets.map(\.id))
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: widgets.map(\.resolvedHomeSpan))
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: resizePreview)
            }
            // Let the last row and its resize grips scroll clear of the dock.
            .contentMargins(.bottom, 44, for: .scrollContent)
            .scrollDisabled(resizePreview != nil)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("homeScreenPageScrollView")
        }
        .onChange(of: isEditMode) { _, editing in
            if !editing { resizePreview = nil }
        }
    }

    @ViewBuilder
    private func tile(_ widget: WidgetConfiguration, placement: HomeGridPacker.Placement, frame: CGRect, metrics: HomeGridMetrics) -> some View {
        let view = HomeScreenTileView(
            widget: widget,
            span: placement.span,
            size: frame.size,
            metrics: metrics,
            isEditMode: isEditMode,
            maxResizeColumns: HomeGridMetrics.columns - placement.column,
            audioEngine: audioEngine,
            fftConfig: fftConfig,
            zoomNamespace: zoomNamespace,
            onLaunch: onLaunch,
            onDelete: onDelete,
            onResize: { onResize(widget.id, $0) },
            onResizePreview: { span in
                resizePreview = span.map { ResizePreview(id: widget.id, span: $0) }
            },
            onUpdateSettings: { onUpdateSettings(widget.id, $0) },
            onUpdateStyle: { onUpdateStyle(widget.id, $0) },
            onEnterEditMode: { onSetEditMode(true) }
        )
        .frame(width: frame.width, height: frame.height)
        .opacity(dropTargetID == widget.id && draggedWidget?.id != widget.id ? 0.6 : 1)
        .offset(x: frame.minX, y: frame.minY)

        if isEditMode && isActive {
            view
                .onDrag {
                    draggedWidget = widget
                    return NSItemProvider(object: widget.id.uuidString as NSString)
                } preview: {
                    if widget.isHomeIcon {
                        HomeIconGlyph(symbol: widget.type.sfSymbol, line: widget.type.homeIconLine, size: metrics.iconSize)
                    } else {
                        RoundedRectangle(cornerRadius: FerriteRadius.homeWidget, style: .continuous)
                            .fill(FerriteColor.surface)
                            .overlay(Image(systemName: widget.type.sfSymbol).font(.title))
                            .frame(width: frame.width * 0.6, height: frame.height * 0.6)
                    }
                }
                .onDrop(of: [UTType.text], delegate: WidgetDropDelegate(
                    item: widget,
                    items: $reorderItems,
                    draggedItem: $draggedWidget,
                    dropTargetWidgetID: $dropTargetID,
                    isEnabled: true,
                    onSave: onSaveOrder
                ))
        } else {
            view
        }
    }

    private var emptyState: some View {
        VStack(spacing: FerriteSpace.s) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 36, weight: .regular))
            Text(isEditMode ? "Tippe auf +, um ein Widget hinzuzufügen." : "Lange drücken, um den Home-Bildschirm zu bearbeiten.")
                .font(FerriteFont.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(FerriteColor.labelSecondary)
        .padding(.horizontal, FerriteSpace.xxl)
        .allowsHitTesting(false)
    }
}

// MARK: - Wallpaper

/// Home wallpaper: the white (or black) tiled platform wall.
struct HomeWallpaper: View {
    var body: some View {
        ZStack {
            FerriteColor.background
            FerriteTileGrid(pitch: FerriteSpace.tile, color: FerriteColor.grout.opacity(0.5))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Page indicator

/// Page identity, position and status beside the iOS-style page dots.
struct HomePageIndicator<Status: View>: View {
    let pageName: String
    let count: Int
    let current: Int
    var showsEditButton: Bool = false
    var onEdit: () -> Void = {}
    var onSelect: (Int) -> Void
    @ViewBuilder var status: Status

    var body: some View {
        HStack(spacing: 0) {
            pageContent
            if showsEditButton {
                editButton
            }
        }
    }

    private var pageContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: FerriteSpace.m) {
                status
                if count > 1 { divider }
                pagePicker
            }
            VStack(alignment: .leading, spacing: FerriteSpace.xs) {
                pagePicker
                status
            }
        }
        .padding(.horizontal, FerriteSpace.s)
        .padding(.vertical, FerriteSpace.xs)
        .frame(maxWidth: .infinity, minHeight: 44)
        .ferriteGlass()
    }

    private var pagePicker: some View {
        VStack(spacing: FerriteSpace.xs) {
            pageIdentity
            if count > 1 {
                pageDots
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pageName), \(pagePosition)")
        .accessibilityIdentifier("homePageIndicator")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if current + 1 < count { onSelect(current + 1) }
            case .decrement: if current > 0 { onSelect(current - 1) }
            @unknown default: break
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(FerriteColor.separator)
            .frame(width: FerriteStroke.hairline, height: 14)
    }

    private var pageIdentity: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: FerriteSpace.xs) {
                Text(pageName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                pagePositionText
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pageName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                pagePositionText
            }
        }
    }

    private var pagePositionText: some View {
        Text(pagePosition)
            .font(.caption.monospacedDigit())
            .foregroundStyle(FerriteColor.labelSecondary)
            .fixedSize()
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.ferriteGlassRound)
        .accessibilityLabel("Home-Bildschirm bearbeiten")
        .accessibilityIdentifier("editDashboardButton")
    }

    private var pagePosition: String {
        "Seite \(current + 1) von \(count)"
    }

    private var pageDots: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: FerriteSpace.s) {
                ForEach(0..<count, id: \.self) { index in pageDot(index) }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(44), spacing: FerriteSpace.s), count: 4),
                spacing: FerriteSpace.s
            ) {
                ForEach(0..<count, id: \.self) { index in pageDot(index) }
            }
        }
    }

    private func pageDot(_ index: Int) -> some View {
        Button {
            onSelect(index)
        } label: {
            Circle()
                .fill(index == current ? FerriteColor.label : FerriteColor.labelTertiary.opacity(0.45))
                .frame(width: 7, height: 7)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}

// MARK: - Edit bar

/// Jiggle-mode top bar: "+" to add a widget on the left, page management
/// and "Fertig" on the right — the iOS Home Screen edit layout.
struct HomeEditBar: View {
    var onAdd: () -> Void
    var onPages: () -> Void
    var onDone: () -> Void

    var body: some View {
        // One glass group: the three buttons appear together and share the
        // same material. Spacing below the 8pt gap keeps them separate.
        FerriteGlassGroup(spacing: FerriteSpace.xs) {
            buttons
        }
        .padding(.horizontal, FerriteSpace.l)
        .padding(.top, FerriteSpace.xs)
    }

    private var buttons: some View {
        HStack(spacing: FerriteSpace.s) {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .accessibilityIdentifier("addWidgetButton")
                    .accessibilityLabel("Widget hinzufügen")
            }
            .buttonStyle(.ferriteGlassRound)

            Spacer(minLength: FerriteSpace.s)

            // At accessibility text sizes the labels no longer fit on one line
            // (they wrapped letter by letter); fall back to icon-only glass
            // buttons. VoiceOver labels and test identifiers stay the same, and
            // the large content viewer shows the label on long press.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: FerriteSpace.s) {
                    pagesButton(iconOnly: false)
                    doneButton(iconOnly: false)
                }
                HStack(spacing: FerriteSpace.s) {
                    pagesButton(iconOnly: true)
                    doneButton(iconOnly: true)
                }
            }
        }
    }

    @ViewBuilder
    private func pagesButton(iconOnly: Bool) -> some View {
        if iconOnly {
            Button(action: onPages) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 17, weight: .bold))
                    .accessibilityIdentifier("layoutsButton")
                    .accessibilityLabel("Seiten")
            }
            .buttonStyle(.ferriteGlassRound)
            .accessibilityShowsLargeContentViewer {
                Label("Seiten", systemImage: "square.stack.3d.up")
            }
        } else {
            Button(action: onPages) {
                Label("Seiten", systemImage: "square.stack.3d.up")
                    .font(FerriteFont.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("layoutsButton")
            }
            .buttonStyle(.ferriteGlass)
        }
    }

    @ViewBuilder
    private func doneButton(iconOnly: Bool) -> some View {
        if iconOnly {
            Button(action: onDone) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .accessibilityIdentifier("editDashboardButton")
                    .accessibilityLabel("Bearbeiten beenden")
            }
            .buttonStyle(.ferriteGlassProminent)
            .accessibilityShowsLargeContentViewer {
                Label("Fertig", systemImage: "checkmark")
            }
        } else {
            Button(action: onDone) {
                Text("Fertig")
                    .font(FerriteFont.headline)
                    .lineLimit(1)
                    .padding(.horizontal, FerriteSpace.xs)
                    .accessibilityIdentifier("editDashboardButton")
                    .accessibilityLabel("Bearbeiten beenden")
            }
            .buttonStyle(.ferriteGlassProminent)
        }
    }
}

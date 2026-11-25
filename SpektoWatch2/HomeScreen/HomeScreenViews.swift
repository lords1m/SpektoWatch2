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
    let family: HomeTileFamily
    let size: CGSize
    let metrics: HomeGridMetrics
    let isEditMode: Bool
    let audioEngine: AudioEngine
    var fftConfig: FFTConfiguration
    let zoomNamespace: Namespace.ID

    var onLaunch: (WidgetConfiguration) -> Void
    var onDelete: (WidgetConfiguration) -> Void
    var onResize: (WidgetSize) -> Void
    var onUpdateSettings: ([String: String]) -> Void
    var onUpdateStyle: (WidgetDisplayStyle) -> Void
    var onEnterEditMode: () -> Void

    @State private var showSettings = false

    /// Stable per-tile phase so tiles jiggle out of sync (UUID byte sum,
    /// not the per-launch-salted hashValue).
    private var jigglePhase: Double {
        let b = widget.id.uuid
        let sum = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7].reduce(0) { $0 &+ Int($1) }
        return Double(sum % 100) / 100
    }

    var body: some View {
        content
            .overlay(alignment: .topLeading) {
                if isEditMode { removeBadge }
            }
            .editJiggle(active: isEditMode, phase: jigglePhase, amplitude: family == .icon ? 1.6 : 0.7)
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
        if family == .icon {
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
                onResize: onResize,
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
        .offset(x: family == .icon ? (size.width - metrics.iconSize) / 2 - 20 : -20, y: -20)
        .transition(.scale.combined(with: .opacity))
        .accessibilityIdentifier("widgetDeleteButton")
        .accessibilityLabel("\(widget.type.rawValue) entfernen")
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            onEnterEditMode()
        } label: {
            Label("Home-Bildschirm bearbeiten", systemImage: "apps.iphone")
        }

        if family == .icon {
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
            let families = widget.availableHomeFamilies
            if families.count > 1 {
                Menu {
                    ForEach(families, id: \.family) { option in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { onResize(option.size) }
                        } label: {
                            if option.family == family {
                                Label(option.family.label, systemImage: "checkmark")
                            } else {
                                Label(option.family.label, systemImage: option.family.symbol)
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
            Label(family == .icon ? "Vom Home-Bildschirm entfernen" : "Widget entfernen",
                  systemImage: "minus.circle")
        }
    }

    /// Lightweight lift preview: never re-mounts the live kernel (Metal,
    /// 15 Hz subscriptions) just to show the context-menu snapshot.
    @ViewBuilder
    private var preview: some View {
        if family == .icon {
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
            .frame(width: size.width, height: min(size.height, 360))
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
    var onResize: (UUID, WidgetSize) -> Void
    var onUpdateSettings: (UUID, [String: String]) -> Void
    var onUpdateStyle: (UUID, WidgetDisplayStyle) -> Void
    var onSetEditMode: (Bool) -> Void
    var onSaveOrder: () -> Void

    @State private var dropTargetID: UUID?

    var body: some View {
        GeometryReader { geo in
            let metrics = HomeGridMetrics(width: geo.size.width)
            let packed = HomeGridPacker.pack(widgets.map { ($0.id, $0.homeFamily) })

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
                            let frame = metrics.frame(column: placement.column, row: placement.row, family: placement.family)
                            tile(widget, family: placement.family, frame: frame, metrics: metrics)
                        }
                    }
                }
                .padding(.top, FerriteSpace.m)
                .padding(.bottom, FerriteSpace.xl)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: widgets.map(\.id))
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: widgets.map(\.homeFamily))
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func tile(_ widget: WidgetConfiguration, family: HomeTileFamily, frame: CGRect, metrics: HomeGridMetrics) -> some View {
        let view = HomeScreenTileView(
            widget: widget,
            family: family,
            size: frame.size,
            metrics: metrics,
            isEditMode: isEditMode,
            audioEngine: audioEngine,
            fftConfig: fftConfig,
            zoomNamespace: zoomNamespace,
            onLaunch: onLaunch,
            onDelete: onDelete,
            onResize: { onResize(widget.id, $0) },
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
                    if family == .icon {
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

/// iOS page dots in a small glass capsule, with the instrument status on
/// the left (where iOS 26 shows its search pill).
struct HomePageIndicator<Status: View>: View {
    let count: Int
    let current: Int
    var onSelect: (Int) -> Void
    @ViewBuilder var status: Status

    var body: some View {
        HStack(spacing: FerriteSpace.m) {
            status
            if count > 1 {
                Rectangle()
                    .fill(FerriteColor.separator)
                    .frame(width: FerriteStroke.hairline, height: 14)
                HStack(spacing: 8) {
                    ForEach(0..<count, id: \.self) { index in
                        Circle()
                            .fill(index == current ? FerriteColor.label : FerriteColor.labelTertiary.opacity(0.45))
                            .frame(width: 7, height: 7)
                            .contentShape(Rectangle().inset(by: -6))
                            .onTapGesture { onSelect(index) }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Seite \(current + 1) von \(count)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: if current + 1 < count { onSelect(current + 1) }
                    case .decrement: if current > 0 { onSelect(current - 1) }
                    @unknown default: break
                    }
                }
            }
        }
        .padding(.horizontal, FerriteSpace.m)
        .frame(height: 30)
        .ferriteGlass()
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

            Spacer()

            Button(action: onPages) {
                Label("Seiten", systemImage: "square.stack.3d.up")
                    .font(FerriteFont.headline)
                    .accessibilityIdentifier("layoutsButton")
            }
            .buttonStyle(.ferriteGlass)

            Button(action: onDone) {
                Text("Fertig")
                    .font(FerriteFont.headline)
                    .padding(.horizontal, FerriteSpace.xs)
                    .accessibilityIdentifier("editDashboardButton")
                    .accessibilityLabel("Bearbeiten beenden")
            }
            .buttonStyle(.ferriteGlassProminent)
        }
    }
}

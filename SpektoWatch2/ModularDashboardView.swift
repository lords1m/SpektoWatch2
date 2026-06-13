import SwiftUI
import UniformTypeIdentifiers

struct ModularDashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @ObservedObject private var dashboardManager: DashboardManager
    @EnvironmentObject private var services: AppServices
    @Environment(\.designDensity) private var density
    @State private var isHeaderVisible: Bool = true
    @State private var isFooterVisible: Bool = true
    @State private var dropTargetWidgetID: UUID?
    @State private var showLayoutsSheet = false
    @State private var lastScrollOffset: CGFloat? = nil
    @State private var footerBarHeight: CGFloat = 0
    @AppStorage("dashboard.activePreset") private var activePresetID: String = "overview"
    private let barSwipeThreshold: CGFloat = 36
    private let handleDragThreshold: CGFloat = 12
    private let scrollThreshold: CGFloat = 20

    /// `dashboardManager` is owned by the caller (ContentView's @StateObject) —
    /// creating it here meant every re-init of this struct allocated a
    /// throwaway manager that @StateObject then discarded. The view-model
    /// autoclosure below is deferred, so it is built once with the stable
    /// instance from the first init.
    init(audioEngine: AudioEngine, connectivityManager: WatchConnectivityManager, dashboardManager: DashboardManager) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(dashboardManager: dashboardManager, audioEngine: audioEngine, connectivityManager: connectivityManager))
        _dashboardManager = ObservedObject(wrappedValue: dashboardManager)
    }

    var body: some View {
        DesignTokensReader { _ in
            mainBody
        }
    }

    private var mainBody: some View {
        ZStack {
            dashboardContent

            if !isHeaderVisible {
                VStack {
                    hiddenHandle(systemImage: "chevron.down")
                        .padding(.top, 8)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.22)) { isHeaderVisible = true }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .onEnded { value in
                                    if abs(value.translation.height) > handleDragThreshold {
                                        withAnimation(.easeInOut(duration: 0.22)) { isHeaderVisible = true }
                                    }
                                }
                        )
                    Spacer()
                }
                .transition(.opacity)
            }

            if !isFooterVisible {
                VStack {
                    Spacer()
                    hiddenHandle(systemImage: "chevron.up")
                        .padding(.bottom, 8)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.22)) { isFooterVisible = true }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .onEnded { value in
                                    if abs(value.translation.height) > handleDragThreshold {
                                        withAnimation(.easeInOut(duration: 0.22)) { isFooterVisible = true }
                                    }
                                }
                        )
                }
                .transition(.opacity)
            }

            if let toast = viewModel.widgetUndoToast {
                VStack {
                    Spacer()
                    widgetUndoSnackbar(toast)
                        .padding(.bottom, isFooterVisible ? footerBarHeight + 12 : 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isHeaderVisible {
                headerBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isFooterVisible {
                footerBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isHeaderVisible)
        .animation(.easeInOut(duration: 0.22), value: isFooterVisible)
        .animation(.easeInOut(duration: 0.2), value: viewModel.widgetUndoToast?.id)
        .onChange(of: dashboardManager.activePresetIndex) { _, _ in
            syncActivePresetStorage()
        }
        .onChange(of: dashboardManager.navigation) { _, _ in
            syncActivePresetStorage()
        }
        .onPreferenceChange(FooterBarHeightPreferenceKey.self) { value in
            footerBarHeight = value
        }
        .onAppear { syncActivePresetStorage() }
        .sheet(isPresented: $viewModel.showWidgetPicker) {
            WidgetPickerView(dashboardManager: viewModel.dashboardManager)
                .polishedSheetChrome()
        }
        .sheet(isPresented: $showLayoutsSheet) {
            LayoutsManagementView(dashboardManager: dashboardManager)
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsRootView(
                selectedMicrophoneSource: $viewModel.selectedMicrophoneSource,
                watchGain: $viewModel.watchGain,
                audioEngine: viewModel.audioEngine
            )
            .environmentObject(services)
            .polishedSheetChrome()
        }
        .onChange(of: viewModel.selectedMicrophoneSource) { _, newSource in
            viewModel.handleMicrophoneSourceChange(newSource)
        }
        .alert("Apple Watch nicht erreichbar", isPresented: $viewModel.showWatchNotReachableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Stelle sicher, dass die Watch-App geöffnet ist und Bluetooth aktiv ist.")
        }
        .onChange(of: viewModel.watchGain) { _, newValue in
            viewModel.updateWatchGain(newValue)
        }
        .task {
            dashboardManager.startLoading()
            if UITestLaunchFlags.installWidgetSizeScreenshotPreset {
                PersistenceMigrator.startMigrationsIfNeeded {
                    dashboardManager.installWidgetSizeScreenshotPreset()
                }
            }
        }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        GeometryReader { geo in
            if dashboardManager.isCustomMode {
                scrollableDashboard(geo: geo, widgets: dashboardManager.widgets, isActive: true)
            } else {
                let selection = Binding<Int>(
                    get: { dashboardManager.activePresetIndex },
                    set: { dashboardManager.setActivePresetIndex($0) }
                )
                TabView(selection: selection) {
                    ForEach(Array(PresetCatalogue.all.indices), id: \.self) { index in
                        Group {
                            // Paged TabView mounts all pages eagerly. Only the
                            // active page and its swipe neighbors get a live
                            // dashboard — otherwise every off-screen preset's
                            // widgets stay subscribed and re-render on each
                            // 15 Hz audio publish. Far pages mount on demand
                            // as the window moves with the selection.
                            if abs(index - dashboardManager.activePresetIndex) <= 1 {
                                scrollableDashboard(
                                    geo: geo,
                                    widgets: dashboardManager.widgets(forPresetIndex: index),
                                    isActive: index == dashboardManager.activePresetIndex
                                )
                            } else {
                                Color.clear
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }

    private func scrollableDashboard(geo: GeometryProxy, widgets: [WidgetConfiguration], isActive: Bool) -> some View {
        let isCompactWidth = geo.size.width <= 390
        let verticalInset: CGFloat = isCompactWidth ? 6 : 8
        return ScrollView {
            GeometryReader { scrollGeo in
                Color.clear.preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: scrollGeo.frame(in: .named("scroll")).minY
                )
            }
            .frame(height: 0)

            VStack(spacing: 0) {
                dashboardGrid(geo: geo, widgets: widgets, isActiveLayout: isActive)
                    .padding(.top, verticalInset)
                    .padding(.bottom, verticalInset)
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { handleScrollChange($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerBar: some View {
        VStack(spacing: 6) {
            DashboardHeaderView(
                isEditMode: $dashboardManager.isEditMode,
                isCustomLayout: dashboardManager.isCustomMode,
                currentLayoutName: dashboardManager.currentLayoutName,
                onAddWidget: viewModel.addWidget,
                onAddLayout: { dashboardManager.addCustomLayout(empty: true) },
                onSaveLayout: { dashboardManager.duplicateCurrentAsCustomLayout() },
                onShowLayouts: { showLayoutsSheet = true },
                onShowSettings: { viewModel.showSettings = true }
            )
            .equatable()
            PresetRailView(
                presets: PresetCatalogue.all,
                activeID: presetRailActiveID,
                dimmed: dashboardManager.isEditMode,
                onSelect: { preset in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        dashboardManager.selectPreset(id: preset.id)
                    }
                }
            )
        }
        .contentShape(Rectangle())
        .allowsHitTesting(isHeaderVisible)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    guard isHeaderVisible else { return }
                    if value.translation.height < -barSwipeThreshold {
                        withAnimation(.easeInOut(duration: 0.22)) { isHeaderVisible = false }
                    }
                }
        )
    }

    /// Empty string when in custom mode so no preset chip appears selected.
    private var presetRailActiveID: Binding<String> {
        Binding(
            get: {
                dashboardManager.isCustomMode ? "" : dashboardManager.activePresetID
            },
            set: { newID in
                guard !newID.isEmpty else { return }
                activePresetID = newID
            }
        )
    }

    private var footerBar: some View {
        ControlBarView(audioEngine: viewModel.audioEngine)
            .opacity(dashboardManager.isEditMode ? 0.35 : 1)
            .allowsHitTesting(isFooterVisible && !dashboardManager.isEditMode)
            .animation(.easeInOut(duration: 0.2), value: dashboardManager.isEditMode)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: FooterBarHeightPreferenceKey.self, value: geo.size.height)
                }
            )
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        guard isFooterVisible, !dashboardManager.isEditMode else { return }
                        if value.translation.height > barSwipeThreshold {
                            withAnimation(.easeInOut(duration: 0.22)) { isFooterVisible = false }
                        }
                    }
            )
    }

    private func syncActivePresetStorage() {
        guard !dashboardManager.isCustomMode else { return }
        let id = dashboardManager.activePresetID
        if activePresetID != id {
            activePresetID = id
        }
    }

    private func handleScrollChange(_ offset: CGFloat) {
        guard let previous = lastScrollOffset else {
            lastScrollOffset = offset
            return
        }
        let delta = offset - previous
        if abs(delta) > scrollThreshold && (isHeaderVisible || isFooterVisible) {
            withAnimation(.easeInOut(duration: 0.22)) {
                isHeaderVisible = false
                isFooterVisible = false
            }
        }
        lastScrollOffset = offset
    }

    private func hiddenHandle(systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary.opacity(0.72))
            Capsule()
                .fill(Color.primary.opacity(0.38))
                .frame(width: 30, height: 4)
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
        // Invisible padding lifts the tap target to ≥44pt while keeping the
        // 28pt visual; contentShape makes the padded area hit-testable.
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func dashboardGrid(geo: GeometryProxy, widgets: [WidgetConfiguration], isActiveLayout: Bool) -> some View {
        let isCompactWidth = geo.size.width <= 390
        let compactAdjust: CGFloat = isCompactWidth ? -2 : 0
        let horizontalPadding: CGFloat = max(8, density.cardPadding + compactAdjust)
        let topPadding: CGFloat = horizontalPadding
        let bottomPadding: CGFloat = horizontalPadding + 8
        let gridSpacing: CGFloat = max(6, density.cardGap + compactAdjust)
        let stackSpacing: CGFloat = gridSpacing + 2
        let minColumnWidth: CGFloat = isCompactWidth ? 150 : 160
        let availableWidth = max(minColumnWidth, geo.size.width - (horizontalPadding * 2))

        if widgets.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: isCompactWidth ? 68 : 80))
                    .foregroundColor(.gray.opacity(0.5))
                Text("Keine Widgets")
                    .font(isCompactWidth ? .title3 : .title2)
                    .foregroundColor(.gray)
                    .accessibilityIdentifier("keineWidgetsLabel")
                Button(action: viewModel.addWidget) {
                    Label("Widget hinzufügen", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .padding(.top, isCompactWidth ? 32 : 50)
        } else {
            VStack(spacing: stackSpacing) {
                if dashboardManager.isCustomMode && !dashboardManager.isEditMode {
                    Text("Benutzerdefiniert · Layouts zum Wechseln der Presets")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if dashboardManager.isEditMode && isActiveLayout {
                    Text("Widgets verschieben oder skalieren")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                let colCount = 3
                let rows = viewModel.computeRows(widgets: widgets, columns: colCount)
                let columnWidth = (availableWidth - CGFloat(colCount - 1) * gridSpacing) / CGFloat(colCount)

                Grid(horizontalSpacing: gridSpacing, verticalSpacing: gridSpacing) {
                    // Rows are identified by their first widget's id (computeRows
                    // never emits an empty row) so a widget moving between rows
                    // animates as a move, not as two rows changing content.
                    ForEach(rows, id: \.first?.id) { row in
                        GridRow {
                            ForEach(row, id: \.id) { widget in
                                let span = viewModel.getSpan(for: widget, colCount: colCount)
                                let card = widgetCard(widget: widget, columnWidth: columnWidth, gridSpacing: gridSpacing, isActiveLayout: isActiveLayout)

                                if dashboardManager.isEditMode && isActiveLayout {
                                    card
                                        .gridCellColumns(span)
                                        .onDrag {
                                            viewModel.draggedWidget = widget
                                            return NSItemProvider(object: widget.id.uuidString as NSString)
                                        }
                                        .onDrop(
                                            of: [UTType.text],
                                            delegate: WidgetDropDelegate(
                                                item: widget,
                                                items: $dashboardManager.widgets,
                                                draggedItem: $viewModel.draggedWidget,
                                                dropTargetWidgetID: $dropTargetWidgetID,
                                                isEnabled: dashboardManager.isEditMode && isActiveLayout,
                                                onSave: dashboardManager.saveConfiguration
                                            )
                                        )
                                        .overlay(
                                            // Radius.card so the drop-target dash
                                            // hugs the card shape exactly (was 20
                                            // on a 22pt card — visibly offset).
                                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                                .stroke(
                                                    dropTargetWidgetID == widget.id ? Color.accentColor.opacity(0.65) : .clear,
                                                    style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                                                )
                                        )
                                } else {
                                    card
                                        .gridCellColumns(span)
                                }
                            }
                        }
                    }
                }
                .animation(WidgetAnimations.reorderAnimation, value: widgets.map(\.id))

                if dashboardManager.isEditMode && isActiveLayout {
                    addWidgetDashedButton
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
        }
    }

    private var addWidgetDashedButton: some View {
        Button(action: viewModel.addWidget) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Widget hinzufügen")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.accentColor)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addWidgetDashedButton")
    }

    private func widgetCard(widget: WidgetConfiguration, columnWidth: CGFloat, gridSpacing: CGFloat, isActiveLayout: Bool) -> some View {
        WidgetCardView(
            widget: widget,
            audioEngine: viewModel.audioEngine,
            fftConfig: services.fftConfiguration,
            isEditMode: dashboardManager.isEditMode && isActiveLayout,
            columnWidth: columnWidth,
            gridSpacing: gridSpacing,
            onDelete: {
                viewModel.deleteWidget(widget)
            },
            onResize: { newSize in
                withAnimation(.spring()) {
                    dashboardManager.resizeWidget(id: widget.id, to: newSize)
                }
            },
            onUpdateSettings: { newSettings in
                dashboardManager.updateWidgetSettings(id: widget.id, settings: newSettings)
            },
            onRequestEditMode: {
                // Same spring as DashboardHeaderView.toggleEdit so both entry
                // points into edit mode feel identical.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    dashboardManager.isEditMode = true
                }
            }
        )
        .equatable()
    }

    private func widgetUndoSnackbar(_ toast: WidgetUndoToast) -> some View {
        HStack(spacing: 12) {
            Text("Widget entfernt")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Rückgängig") {
                viewModel.undoWidgetDelete()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .accessibilityIdentifier("widgetUndoSnackbar")
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FooterBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WidgetDropDelegate: DropDelegate {
    let item: WidgetConfiguration
    @Binding var items: [WidgetConfiguration]
    @Binding var draggedItem: WidgetConfiguration?
    @Binding var dropTargetWidgetID: UUID?
    let isEnabled: Bool
    var onSave: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        // draggedItem != nil rejects foreign text drags (iPad multitasking,
        // hardware-keyboard drags) that would otherwise trigger a spurious save.
        guard isEnabled, draggedItem != nil else { return false }
        dropTargetWidgetID = nil
        draggedItem = nil
        onSave()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard isEnabled else { return }
        dropTargetWidgetID = item.id
        guard let draggedItem = draggedItem else { return }
        if draggedItem.id != item.id {
            guard let from = items.firstIndex(where: { $0.id == draggedItem.id }),
                  let to = items.firstIndex(where: { $0.id == item.id }) else { return }
            if items[to].id != draggedItem.id {
                withAnimation {
                    items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEnabled else { return DropProposal(operation: .cancel) }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTargetWidgetID == item.id {
            dropTargetWidgetID = nil
        }
    }
}

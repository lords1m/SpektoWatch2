import SwiftUI
import UniformTypeIdentifiers

struct ModularDashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @EnvironmentObject private var fftConfig: FFTConfiguration
    @Environment(\.designDensity) private var density
    @State private var isHeaderVisible: Bool = true
    @State private var isFooterVisible: Bool = true
    @State private var dropTargetWidgetID: UUID?
    @State private var showLayoutsDialog = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var lastScrollOffset: CGFloat? = nil
    @State private var scrollOffset: CGFloat = 0
    @AppStorage("dashboard.activePreset") private var activePresetID: String = "overview"
    private let barSwipeThreshold: CGFloat = 36
    private let handleDragThreshold: CGFloat = 12
    private let scrollThreshold: CGFloat = 20

    init(audioEngine: AudioEngine, connectivityManager: WatchConnectivityManager) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(audioEngine: audioEngine, connectivityManager: connectivityManager))
    }
    
    var body: some View {
        DesignTokensReader { _ in
            mainBody
        }
    }

    private var mainBody: some View {
        ZStack {
            GeometryReader { geo in
                let selection = Binding<Int>(
                    get: { viewModel.dashboardManager.activeLayoutIndex },
                    set: { viewModel.dashboardManager.setActiveLayout(index: $0) }
                )

                TabView(selection: selection) {
                    ForEach(Array(viewModel.dashboardManager.layouts.indices), id: \.self) { index in
                        let isCompactWidth = geo.size.width <= 390
                        let verticalInset: CGFloat = isCompactWidth ? 6 : 8
                        ScrollView {
                            GeometryReader { scrollGeo in
                                Color.clear.preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: scrollGeo.frame(in: .named("scroll")).minY
                                )
                            }
                            .frame(height: 0)
                            
                            VStack(spacing: 0) {
                                dashboardGrid(
                                    geo: geo,
                                    widgets: viewModel.dashboardManager.widgets(forLayoutAt: index),
                                    isActiveLayout: index == viewModel.dashboardManager.activeLayoutIndex
                                )
                                .padding(.top, verticalInset)
                                .padding(.bottom, verticalInset)
                            }
                        }
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                            handleScrollChange(value)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            if !isHeaderVisible {
                VStack {
                    hiddenHandle(systemImage: "chevron.down")
                        .padding(.top, 8)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                isHeaderVisible = true
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .onEnded { value in
                                    if abs(value.translation.height) > handleDragThreshold {
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            isHeaderVisible = true
                                        }
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
                            withAnimation(.easeInOut(duration: 0.22)) {
                                isFooterVisible = true
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .onEnded { value in
                                    if abs(value.translation.height) > handleDragThreshold {
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            isFooterVisible = true
                                        }
                                    }
                                }
                        )
                }
                .transition(.opacity)
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
        .sheet(isPresented: $viewModel.showWidgetPicker) {
            WidgetPickerView(dashboardManager: viewModel.dashboardManager)
        }
        .confirmationDialog("Layouts", isPresented: $showLayoutsDialog, titleVisibility: .visible) {
            Button("Aktuelle Seite speichern") {
                viewModel.dashboardManager.saveCurrentAsNewLayout()
            }
            Button("Neue leere Seite") {
                viewModel.dashboardManager.addEmptyLayout()
            }
            Button("Screenshot-Preset: Widgetgrößen") {
                viewModel.dashboardManager.installWidgetSizeScreenshotPreset()
            }
            Button("Seite umbenennen") {
                renameText = viewModel.dashboardManager.currentLayoutName
                showRenameAlert = true
            }

            ForEach(Array(viewModel.dashboardManager.layouts.enumerated()), id: \.element.id) { index, layout in
                Button("Öffnen: \(layout.name)") {
                    viewModel.dashboardManager.setActiveLayout(index: index)
                }
            }

            if viewModel.dashboardManager.layouts.count > 1 {
                Button("Aktuelle Seite löschen", role: .destructive) {
                    viewModel.dashboardManager.deleteLayout(at: viewModel.dashboardManager.activeLayoutIndex)
                }
            }
        }
        .alert("Seite umbenennen", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Umbenennen") {
                viewModel.dashboardManager.renameLayout(at: viewModel.dashboardManager.activeLayoutIndex, name: renameText)
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SpectrogramSettingsView(
                selectedMicrophoneSource: $viewModel.selectedMicrophoneSource,
                watchGain: $viewModel.watchGain,
                audioEngine: viewModel.audioEngine
            )
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
        .onAppear {
            // Ensure audio engine is ready or started if needed
            print("[ModularDashboardView] View appeared. Widgets count: \(viewModel.dashboardManager.widgets.count)")
        }
        .onChange(of: viewModel.dashboardManager.isEditMode) { oldValue, newValue in
            print("[ModularDashboardView] Edit mode changed: \(oldValue) -> \(newValue)")
        }
        .accessibilityIdentifier("dashboardView")
    }

    private var headerBar: some View {
        VStack(spacing: 6) {
            DashboardHeaderView(
                isEditMode: $viewModel.dashboardManager.isEditMode,
                currentLayoutName: viewModel.dashboardManager.currentLayoutName,
                onAddWidget: viewModel.addWidget,
                onAddLayout: { viewModel.dashboardManager.addEmptyLayout() },
                onSaveLayout: { viewModel.dashboardManager.saveCurrentAsNewLayout() },
                onShowLayouts: { showLayoutsDialog = true },
                onShowSettings: { viewModel.showSettings = true }
            )
            PresetRailView(
                presets: PresetCatalogue.all,
                activeID: $activePresetID,
                dimmed: viewModel.dashboardManager.isEditMode,
                onSelect: { preset in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.dashboardManager.applyPreset(id: preset.id)
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
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isHeaderVisible = false
                        }
                    }
                }
        )
    }

    private var footerBar: some View {
        ControlBarView(audioEngine: viewModel.audioEngine)
            .contentShape(Rectangle())
            .allowsHitTesting(isFooterVisible)
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        guard isFooterVisible else { return }
                        if value.translation.height > barSwipeThreshold {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                isFooterVisible = false
                            }
                        }
                    }
            )
    }
    
    private func handleScrollChange(_ offset: CGFloat) {
        guard let previous = lastScrollOffset else {
            lastScrollOffset = offset
            return
        }

        let delta = offset - previous

        // Bei jeder signifikanten Scroll-Bewegung (egal in welche Richtung) ausblenden
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
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private func dashboardGrid(geo: GeometryProxy, widgets: [WidgetConfiguration], isActiveLayout: Bool) -> some View {
        let isCompactWidth = geo.size.width <= 390
        // Density token maps to redesign spec (compact 10/8, standard 14/12,
        // airy 18/16). Tighten by 2pt on iPhone-compact widths to keep
        // pre-token visual density on small screens.
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
                Button(action: viewModel.addWidget) {
                    Label("Widget hinzufügen", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .padding(.top, isCompactWidth ? 32 : 50)
        } else {
            VStack(spacing: stackSpacing) {
                if viewModel.dashboardManager.isEditMode && isActiveLayout {
                    Text("Widgets verschieben oder skalieren")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !isActiveLayout {
                    Text("Swipe für Layout-Wechsel")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                let colCount = 3  // Fest 3 Spalten
                let rows = viewModel.computeRows(widgets: widgets, columns: colCount)
                let columnWidth = (availableWidth - CGFloat(colCount - 1) * gridSpacing) / CGFloat(colCount)
                
                Grid(horizontalSpacing: gridSpacing, verticalSpacing: gridSpacing) {
                    ForEach(0..<rows.count, id: \.self) { rowIndex in
                        GridRow {
                            ForEach(rows[rowIndex]) { widget in
                                let span = viewModel.getSpan(for: widget, colCount: colCount)
                                let card = widgetCard(widget: widget, columnWidth: columnWidth, isActiveLayout: isActiveLayout)

                                if viewModel.dashboardManager.isEditMode && isActiveLayout {
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
                                                items: $viewModel.dashboardManager.widgets,
                                                draggedItem: $viewModel.draggedWidget,
                                                dropTargetWidgetID: $dropTargetWidgetID,
                                                isEnabled: viewModel.dashboardManager.isEditMode && isActiveLayout,
                                                onSave: viewModel.dashboardManager.saveConfiguration
                                            )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(
                                                    dropTargetWidgetID == widget.id ? Color.accentColor.opacity(0.65) : .clear,
                                                    style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                                                )
                                        )
                                        .transition(WidgetAnimations.cardTransition)
                                } else {
                                    card
                                        .gridCellColumns(span)
                                        .onLongPressGesture(minimumDuration: 0.45) {
                                            guard isActiveLayout else { return }
                                            let generator = UIImpactFeedbackGenerator(style: .medium)
                                            generator.impactOccurred()
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                viewModel.dashboardManager.isEditMode = true
                                            }
                                        }
                                        .transition(WidgetAnimations.cardTransition)
                                }
                            }
                        }
                    }
                }
                .animation(WidgetAnimations.reorderAnimation, value: widgets.map(\.id))
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
        }
    }

    private func widgetCard(widget: WidgetConfiguration, columnWidth: CGFloat, isActiveLayout: Bool) -> some View {
        WidgetCardView(
            widget: widget,
            audioEngine: viewModel.audioEngine,
            fftConfig: fftConfig,
            isEditMode: viewModel.dashboardManager.isEditMode && isActiveLayout,
            columnWidth: columnWidth,
            onDelete: {
                withAnimation(.spring()) {
                    viewModel.deleteWidget(widget)
                }
            },
            onResize: { newSize in
                withAnimation(.spring()) {
                    viewModel.dashboardManager.resizeWidget(id: widget.id, to: newSize)
                }
            },
            onUpdateSettings: { newSettings in
                viewModel.dashboardManager.updateWidgetSettings(id: widget.id, settings: newSettings)
            }
        )
    }

}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
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
        guard isEnabled else { return false }
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

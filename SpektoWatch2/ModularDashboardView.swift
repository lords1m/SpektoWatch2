import SwiftUI
import UniformTypeIdentifiers

struct ModularDashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @EnvironmentObject private var fftConfig: FFTConfiguration
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var isHeaderVisible: Bool = true
    @State private var isFooterVisible: Bool = true
    @State private var dropTargetWidgetID: UUID?

    init(audioEngine: AudioEngine, connectivityManager: WatchConnectivityManager) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(audioEngine: audioEngine, connectivityManager: connectivityManager))
    }
    
    var body: some View {
        ZStack {
            // Scrollable Grid (full height)
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        dashboardGrid(geo: geo)
                            .padding(.top, max(8, (isHeaderVisible ? headerHeight : 10) + 8))
                            .padding(.bottom, max(8, (isFooterVisible ? footerHeight : 10) + 8))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack {
                // Header (floating)
                DashboardHeaderView(
                    isEditMode: $viewModel.dashboardManager.isEditMode,
                    onAddWidget: viewModel.addWidget,
                    onShowSettings: {
                        viewModel.showSettings = true
                    }
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: DashboardHeaderHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
                .offset(y: isHeaderVisible ? 0 : -(headerHeight + 24))
                .opacity(isHeaderVisible ? 1 : 0)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onEnded { value in
                            if value.translation.height < -40 {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    isHeaderVisible = false
                                }
                            }
                        }
                )

                Spacer()

                // Control Bar (floating)
                ControlBarView(audioEngine: viewModel.audioEngine)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: DashboardFooterHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    )
                    .offset(y: isFooterVisible ? 0 : (footerHeight + 24))
                    .opacity(isFooterVisible ? 1 : 0)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { value in
                                if value.translation.height > 40 {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        isFooterVisible = false
                                    }
                                }
                            }
                    )
            }
            .animation(.easeInOut(duration: 0.22), value: isHeaderVisible)
            .animation(.easeInOut(duration: 0.22), value: isFooterVisible)

            if !isHeaderVisible {
                VStack {
                    Capsule()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 44, height: 5)
                        .padding(.top, 8)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 6)
                                .onEnded { value in
                                    if value.translation.height > 20 {
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
                    Capsule()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 44, height: 5)
                        .padding(.bottom, 8)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 6)
                                .onEnded { value in
                                    if value.translation.height < -20 {
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
        .sheet(isPresented: $viewModel.showWidgetPicker) {
            WidgetPickerView(dashboardManager: viewModel.dashboardManager)
        }
        .edgesIgnoringSafeArea(.bottom)
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
        .onPreferenceChange(DashboardHeaderHeightPreferenceKey.self) { headerHeight = $0 }
        .onPreferenceChange(DashboardFooterHeightPreferenceKey.self) { footerHeight = $0 }
    }
    
    @ViewBuilder
    private func dashboardGrid(geo: GeometryProxy) -> some View {
        if viewModel.dashboardManager.widgets.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.gray.opacity(0.5))
                Text("Keine Widgets")
                    .font(.title2)
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
            .padding(.top, 50)
        } else {
            VStack(spacing: 14) {
                if viewModel.dashboardManager.isEditMode {
                    Text("Widgets verschieben oder skalieren")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                let colCount = max(1, Int(geo.size.width / 160))
                let rows = viewModel.computeRows(widgets: viewModel.dashboardManager.widgets, columns: colCount)
                let columnWidth = (geo.size.width - CGFloat(colCount - 1) * 12) / CGFloat(colCount)
                
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(0..<rows.count, id: \.self) { rowIndex in
                        GridRow {
                            ForEach(rows[rowIndex]) { widget in
                                let span = viewModel.getSpan(for: widget, colCount: colCount)
                                let card = widgetCard(widget: widget, columnWidth: columnWidth)

                                if viewModel.dashboardManager.isEditMode {
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
                                                isEnabled: viewModel.dashboardManager.isEditMode,
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
                .animation(WidgetAnimations.reorderAnimation, value: viewModel.dashboardManager.widgets.map(\.id))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private func widgetCard(widget: WidgetConfiguration, columnWidth: CGFloat) -> some View {
        WidgetCardView(
            widget: widget,
            audioEngine: viewModel.audioEngine,
            fftConfig: fftConfig,
            isEditMode: viewModel.dashboardManager.isEditMode,
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

private struct DashboardHeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DashboardFooterHeightPreferenceKey: PreferenceKey {
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

import SwiftUI
import UniformTypeIdentifiers

struct ModularDashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    
    init(audioEngine: AudioEngine, connectivityManager: WatchConnectivityManager) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(audioEngine: audioEngine, connectivityManager: connectivityManager))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            DashboardHeaderView(
                isEditMode: $viewModel.dashboardManager.isEditMode,
                onAddWidget: viewModel.addWidget,
                onShowSettings: {
                    viewModel.showSettings = true
                }
            )
            
            // Scrollable Grid
            GeometryReader { geo in
                ScrollView {
                    dashboardGrid(geo: geo)
                }
            }
            
            // Control Bar
            ControlBarView(audioEngine: viewModel.audioEngine)
        }
        .edgesIgnoringSafeArea(.bottom)
        .sheet(isPresented: $viewModel.showWidgetPicker) {
            WidgetPickerView(dashboardManager: viewModel.dashboardManager)
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SpectrogramSettingsView(
                selectedMicrophoneSource: $viewModel.selectedMicrophoneSource,
                selectedColormap: $viewModel.dummyColormap,
                sensitivity: $viewModel.sensitivity,
                timeSpan: $viewModel.dummyTimeSpan,
                watchGain: $viewModel.watchGain,
                audioEngine: viewModel.audioEngine
            )
        }
        .onChange(of: viewModel.selectedMicrophoneSource) { _, newSource in
            viewModel.handleMicrophoneSourceChange(newSource)
        }
        .onChange(of: viewModel.sensitivity) { _, newVal in
            viewModel.updateSensitivity(newVal)
        }
        .onChange(of: viewModel.watchGain) { _, newValue in
            viewModel.updateWatchGain(newValue)
        }
        .onAppear {
            // Ensure audio engine is ready or started if needed
            print("[ModularDashboardView] View appeared. Widgets count: \(viewModel.dashboardManager.widgets.count)")
        }
        .onChange(of: viewModel.dashboardManager.isEditMode) { newValue in
            print("[ModularDashboardView] Edit mode changed: \(newValue)")
        }
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
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .padding(.top, 50)
        } else {
            let colCount = max(1, Int(geo.size.width / 160))
            let rows = viewModel.computeRows(widgets: viewModel.dashboardManager.widgets, columns: colCount)
            let columnWidth = (geo.size.width - CGFloat(colCount - 1) * 12) / CGFloat(colCount)
            
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(rows[rowIndex]) { widget in
                            let span = viewModel.getSpan(for: widget, colCount: colCount)
                            
                            WidgetCardView(
                                widget: widget,
                                audioEngine: viewModel.audioEngine,
                                isEditMode: viewModel.dashboardManager.isEditMode,
                                columnWidth: columnWidth,
                                onDelete: {
                                    withAnimation(.spring()) {
                                        viewModel.deleteWidget(widget)
                                    }
                                },
                                onResize: { newSize in
                                    print("[ModularDashboardView] Resize requested for widget: \(widget.id) to \(newSize)")
                                    withAnimation(.spring()) {
                                        viewModel.dashboardManager.resizeWidget(id: widget.id, to: newSize)
                                    }
                                },
                                onUpdateSettings: { newSettings in
                                    viewModel.dashboardManager.updateWidgetSettings(id: widget.id, settings: newSettings)
                                }
                            )
                            .gridCellColumns(span)
                            .onDrag {
                                viewModel.draggedWidget = widget
                                return NSItemProvider(object: widget.id.uuidString as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: WidgetDropDelegate(item: widget, items: $viewModel.dashboardManager.widgets, draggedItem: $viewModel.draggedWidget, onSave: viewModel.dashboardManager.saveConfiguration))
                            .transition(WidgetAnimations.cardTransition)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct WidgetDropDelegate: DropDelegate {
    let item: WidgetConfiguration
    @Binding var items: [WidgetConfiguration]
    @Binding var draggedItem: WidgetConfiguration?
    var onSave: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        onSave()
        return true
    }

    func dropEntered(info: DropInfo) {
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
}
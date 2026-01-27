import SwiftUI
import UniformTypeIdentifiers

struct ModularDashboardView: View {
    @ObservedObject var audioEngine: AudioEngine
    @StateObject private var dashboardManager = DashboardManager()
    @State private var showWidgetPicker = false
    @State private var draggedWidget: WidgetConfiguration?
    
    // Global Settings State
    @State private var showSettings = false
    @State private var selectedMicrophoneSource: MicrophoneSource = .iPhone
    @State private var sensitivity: Double = 10.0
    @State private var watchGain: Float = 1.0
    @State private var dummyColormap: Int = 0 // Nur für Binding-Kompatibilität
    @State private var dummyTimeSpan: SpectrogramTimeSpan = .seconds5 // Nur für Binding-Kompatibilität
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            DashboardHeaderView(
                isEditMode: $dashboardManager.isEditMode,
                onAddWidget: { 
                    print("[ModularDashboardView] Add widget button tapped")
                    showWidgetPicker = true 
                },
                onShowSettings: {
                    showSettings = true
                }
            )
            
            // Scrollable Grid
            GeometryReader { geo in
                ScrollView {
                    dashboardGrid(geo: geo)
                }
            }
            
            // Control Bar
            ControlBarView(audioEngine: audioEngine)
        }
        .edgesIgnoringSafeArea(.bottom)
        .sheet(isPresented: $showWidgetPicker) {
            WidgetPickerView(dashboardManager: dashboardManager)
        }
        .sheet(isPresented: $showSettings) {
            SpectrogramSettingsView(
                selectedMicrophoneSource: $selectedMicrophoneSource,
                selectedColormap: $dummyColormap, // Hat im Dashboard keine globale Auswirkung
                sensitivity: $sensitivity,
                timeWeighting: $audioEngine.timeWeighting,
                frequencyWeighting: $audioEngine.frequencyWeighting,
                timeSpan: $dummyTimeSpan, // Hat im Dashboard keine globale Auswirkung
                scrollSpeed: $audioEngine.scrollSpeed,
                watchGain: $watchGain,
                audioEngine: audioEngine
            )
        }
        .onChange(of: selectedMicrophoneSource) { _, newSource in
            handleMicrophoneSourceChange(newSource)
        }
        .onChange(of: sensitivity) { _, newVal in
            audioEngine.setGainBoost(Float(newVal))
        }
        .onChange(of: watchGain) { _, newValue in
            WatchConnectivityManager.shared.sendGainValue(newValue)
        }
        .onAppear {
            // Ensure audio engine is ready or started if needed
            print("[ModularDashboardView] View appeared. Widgets count: \(dashboardManager.widgets.count)")
        }
        .onChange(of: dashboardManager.isEditMode) { newValue in
            print("[ModularDashboardView] Edit mode changed: \(newValue)")
        }
    }
    
    @ViewBuilder
    private func dashboardGrid(geo: GeometryProxy) -> some View {
        if dashboardManager.widgets.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.gray.opacity(0.5))
                Text("Keine Widgets")
                    .font(.title2)
                    .foregroundColor(.gray)
                Button(action: { showWidgetPicker = true }) {
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
            let rows = computeRows(widgets: dashboardManager.widgets, columns: colCount)
            let columnWidth = (geo.size.width - CGFloat(colCount - 1) * 12) / CGFloat(colCount)
            
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(rows[rowIndex]) { widget in
                            let span = getSpan(for: widget, colCount: colCount)
                            
                            WidgetCardView(
                                widget: widget,
                                audioEngine: audioEngine,
                                isEditMode: dashboardManager.isEditMode,
                                columnWidth: columnWidth,
                                onDelete: {
                                    print("[ModularDashboardView] Delete requested for widget: \(widget.id)")
                                    withAnimation(.spring()) {
                                        dashboardManager.removeWidget(id: widget.id)
                                    }
                                },
                                onResize: { newSize in
                                    print("[ModularDashboardView] Resize requested for widget: \(widget.id) to \(newSize)")
                                    withAnimation(.spring()) {
                                        dashboardManager.resizeWidget(id: widget.id, to: newSize)
                                    }
                                },
                                onUpdateSettings: { newSettings in
                                    dashboardManager.updateWidgetSettings(id: widget.id, settings: newSettings)
                                }
                            )
                            .gridCellColumns(span)
                            .onDrag {
                                self.draggedWidget = widget
                                return NSItemProvider(object: widget.id.uuidString as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: WidgetDropDelegate(item: widget, items: $dashboardManager.widgets, draggedItem: $draggedWidget, onSave: dashboardManager.saveConfiguration))
                            .transition(WidgetAnimations.cardTransition)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func handleMicrophoneSourceChange(_ newSource: MicrophoneSource) {
        let connectivityManager = WatchConnectivityManager.shared
        connectivityManager.selectedMicrophoneSource = newSource
        connectivityManager.sendMicrophoneSourceSelection(newSource)
        
        if audioEngine.engineStatus == .running {
            audioEngine.stopRecording()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if newSource == .iPhone {
                    audioEngine.startRecording()
                } else {
                    connectivityManager.requestRecordingStart()
                }
            }
        }
    }
    
    private func computeRows(widgets: [WidgetConfiguration], columns: Int) -> [[WidgetConfiguration]] {
        var rows: [[WidgetConfiguration]] = []
        var currentRow: [WidgetConfiguration] = []
        var availableSpace = columns
        
        for widget in widgets {
            let span = getSpan(for: widget, colCount: columns)
            
            if span > availableSpace {
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                    currentRow = []
                    availableSpace = columns
                }
            }
            
            currentRow.append(widget)
            availableSpace -= span
        }
        
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
    
    private func getSpan(for widget: WidgetConfiguration, colCount: Int) -> Int {
        return min(widget.size.columns, colCount)
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
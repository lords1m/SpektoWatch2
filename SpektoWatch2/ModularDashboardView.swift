import SwiftUI
import UniformTypeIdentifiers

struct ModularDashboardView: View {
    @ObservedObject var audioEngine: AudioEngine
    @StateObject private var dashboardManager = DashboardManager()
    @State private var showWidgetPicker = false
    @State private var draggedWidget: WidgetConfiguration?
    
    // Flexibles Grid: 2 Spalten für bessere Größe
    var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }
    
    // Initializer mit Default-Parameter
    init(audioEngine: AudioEngine = AudioEngine()) {
        self.audioEngine = audioEngine
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - FIXED TOP
            DashboardHeaderView(
                isEditMode: $dashboardManager.isEditMode,
                onAddWidget: {
                    print("[ModularDashboardView] Add widget button tapped")
                    showWidgetPicker = true
                }
            )
            
            // Scrollable Content Area - FLEXIBLE MIDDLE
            ScrollView {
                if dashboardManager.widgets.isEmpty {
                    // Empty State
                    VStack(spacing: 20) {
                        Spacer(minLength: 100)
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
                        Spacer(minLength: 150)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    // Widget Grid
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(dashboardManager.widgets) { widget in
                            WidgetCardView(
                                widget: widget,
                                audioEngine: audioEngine,
                                isEditMode: dashboardManager.isEditMode,
                                onDelete: {
                                    print("[ModularDashboardView] Delete requested for widget: \(widget.id)")
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dashboardManager.removeWidget(id: widget.id)
                                    }
                                },
                                onResize: { newSize in
                                    print("[ModularDashboardView] Resize requested for widget: \(widget.id) to \(newSize)")
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dashboardManager.resizeWidget(id: widget.id, to: newSize)
                                    }
                                },
                                onUpdateSettings: { newSettings in
                                    dashboardManager.updateWidgetSettings(id: widget.id, settings: newSettings)
                                }
                            )
                            // Grid-Span basierend auf Widget-Größe
                            .gridCellColumns(widget.size.gridColumns)
                            .onDrag {
                                self.draggedWidget = widget
                                return NSItemProvider(object: widget.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: WidgetDropDelegate(
                                    item: widget,
                                    items: $dashboardManager.widgets,
                                    draggedItem: $draggedWidget,
                                    onSave: dashboardManager.saveConfiguration
                                )
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 16) // Abstand zum Footer
                }
            }
            .frame(maxHeight: .infinity) // ScrollView nimmt verfügbaren Platz
            
            // Control Bar - FIXED BOTTOM
            ControlBarView(audioEngine: audioEngine)
                .background(Color(UIColor.systemBackground))
        }
        .sheet(isPresented: $showWidgetPicker) {
            WidgetPickerView(dashboardManager: dashboardManager)
        }
        .onAppear {
            print("[ModularDashboardView] View appeared. Widgets count: \(dashboardManager.widgets.count)")
        }
        .onChange(of: dashboardManager.isEditMode) { _, newValue in
            print("[ModularDashboardView] Edit mode changed: \(newValue)")
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
        draggedItem = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        if draggedItem.id != item.id {
            guard let from = items.firstIndex(where: { $0.id == draggedItem.id }),
                  let to = items.firstIndex(where: { $0.id == item.id }) else { return }
            
            if items[to].id != draggedItem.id {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }
}

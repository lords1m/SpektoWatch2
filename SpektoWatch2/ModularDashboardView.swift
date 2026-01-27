import SwiftUI
import UniformTypeIdentifiers

struct ModularDashboardView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var dashboardManager = DashboardManager()
    @State private var showWidgetPicker = false
    @State private var draggedWidget: WidgetConfiguration?
    
    // Grid layout definition
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            DashboardHeaderView(
                isEditMode: $dashboardManager.isEditMode,
                onAddWidget: { 
                    print("[ModularDashboardView] Add widget button tapped")
                    showWidgetPicker = true 
                }
            )
            
            // Scrollable Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(dashboardManager.widgets) { widget in
                        WidgetCardView(
                            widget: widget,
                            audioEngine: audioEngine,
                            isEditMode: dashboardManager.isEditMode,
                            onDelete: { 
                                print("[ModularDashboardView] Delete requested for widget: \(widget.id)")
                                dashboardManager.removeWidget(id: widget.id) 
                            },
                            onResize: { newSize in 
                                print("[ModularDashboardView] Resize requested for widget: \(widget.id) to \(newSize)")
                                dashboardManager.resizeWidget(id: widget.id, to: newSize) 
                            },
                            onUpdateSettings: { newSettings in
                                dashboardManager.updateWidgetSettings(id: widget.id, settings: newSettings)
                            }
                        )
                        .onDrag {
                            self.draggedWidget = widget
                            return NSItemProvider(object: widget.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: WidgetDropDelegate(item: widget, items: $dashboardManager.widgets, draggedItem: $draggedWidget, onSave: dashboardManager.saveConfiguration))
                    }
                }
                .padding()
            }
            
            // Control Bar
            ControlBarView(audioEngine: audioEngine)
        }
        .sheet(isPresented: $showWidgetPicker) {
            WidgetPickerView(dashboardManager: dashboardManager)
        }
        .onAppear {
            // Ensure audio engine is ready or started if needed
            print("[ModularDashboardView] View appeared. Widgets count: \(dashboardManager.widgets.count)")
        }
        .onChange(of: dashboardManager.isEditMode) { newValue in
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
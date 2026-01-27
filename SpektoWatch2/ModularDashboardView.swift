import SwiftUI

struct ModularDashboardView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var dashboardManager = DashboardManager()
    @State private var showWidgetPicker = false
    
    // Grid layout definition
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            DashboardHeaderView(
                isEditMode: $dashboardManager.isEditMode,
                onAddWidget: { showWidgetPicker = true }
            )
            
            // Scrollable Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(dashboardManager.widgets) { widget in
                        WidgetCardView(
                            widget: widget,
                            audioEngine: audioEngine,
                            isEditMode: dashboardManager.isEditMode,
                            onDelete: { dashboardManager.removeWidget(id: widget.id) },
                            onResize: { newSize in dashboardManager.resizeWidget(id: widget.id, to: newSize) }
                        )
                    }
                    .onMove { indices, newOffset in
                        dashboardManager.moveWidget(from: indices, to: newOffset)
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
        }
    }
}
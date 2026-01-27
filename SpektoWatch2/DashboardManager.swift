import SwiftUI
import Combine

class DashboardManager: ObservableObject {
    @Published var widgets: [WidgetConfiguration] = []
    @Published var isEditMode: Bool = false
    
    private let userDefaultsKey = "DashboardConfiguration_v2"
    
    init() {
        loadConfiguration()
        if widgets.isEmpty {
            // Default setup
            widgets = [
                WidgetConfiguration(type: .spectrogram, size: .large, gridPosition: GridPosition(index: 0)),
                WidgetConfiguration(type: .lafGraph, size: .medium, gridPosition: GridPosition(index: 1)),
                WidgetConfiguration(type: .levelMeter, size: .small, gridPosition: GridPosition(index: 2)),
                WidgetConfiguration(type: .frequencyDisplay, size: .medium, gridPosition: GridPosition(index: 3)),
                WidgetConfiguration(type: .octaveBands, size: .medium, gridPosition: GridPosition(index: 4)),
                WidgetConfiguration(type: .phaseMeter, size: .small, gridPosition: GridPosition(index: 5))
            ]
        }
    }
    
    func addWidget(type: AudioWidgetType, at position: GridPosition? = nil) {
        let size = WidgetConfiguration.defaultSize(for: type)
        let pos = position ?? GridPosition(index: widgets.count)
        let newWidget = WidgetConfiguration(type: type, size: size, gridPosition: pos)
        widgets.append(newWidget)
        saveConfiguration()
    }
    
    func removeWidget(id: UUID) {
        widgets.removeAll { $0.id == id }
        saveConfiguration()
    }
    
    func moveWidget(from source: IndexSet, to destination: Int) {
        widgets.move(fromOffsets: source, toOffset: destination)
        saveConfiguration()
    }
    
    func resizeWidget(id: UUID, to newSize: WidgetSize) {
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].size = newSize
            saveConfiguration()
        }
    }
    
    func saveConfiguration() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(widgets)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Error saving dashboard configuration: \(error)")
        }
    }
    
    func loadConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            let decoder = JSONDecoder()
            widgets = try decoder.decode([WidgetConfiguration].self, from: data)
        } catch {
            print("Error loading dashboard configuration: \(error)")
        }
    }
}
import SwiftUI
import Combine

class DashboardManager: ObservableObject {
    @Published var widgets: [WidgetConfiguration] = []
    @Published var isEditMode: Bool = false
    
    private let userDefaultsKey = "DashboardConfiguration_v2"
    
    init() {
        print("[DashboardManager] Initializing...")
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
            print("[DashboardManager] Created default widgets configuration")
        }
    }
    
    func addWidget(type: AudioWidgetType, at position: GridPosition? = nil) {
        print("[DashboardManager] Adding widget of type: \(type.rawValue)")
        let size = WidgetConfiguration.defaultSize(for: type)
        let pos = position ?? GridPosition(index: widgets.count)
        let newWidget = WidgetConfiguration(type: type, size: size, gridPosition: pos)
        widgets.append(newWidget)
        print("[DashboardManager] Widget added. Total widgets: \(widgets.count)")
        saveConfiguration()
    }
    
    func removeWidget(id: UUID) {
        print("[DashboardManager] Removing widget with ID: \(id)")
        widgets.removeAll { $0.id == id }
        print("[DashboardManager] Widget removed. Total widgets: \(widgets.count)")
        saveConfiguration()
    }
    
    func moveWidget(from source: IndexSet, to destination: Int) {
        print("[DashboardManager] Moving widget from \(source) to \(destination)")
        widgets.move(fromOffsets: source, toOffset: destination)
        saveConfiguration()
    }
    
    func resizeWidget(id: UUID, to newSize: WidgetSize) {
        print("[DashboardManager] Resizing widget \(id) to \(newSize)")
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].size = newSize
            saveConfiguration()
        }
    }
    
    func updateWidgetSettings(id: UUID, settings: [String: String]) {
        print("[DashboardManager] Updating settings for widget \(id)")
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].settings = settings
            saveConfiguration()
        }
    }
    
    func saveConfiguration() {
        print("[DashboardManager] Saving configuration...")
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(widgets)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            print("[DashboardManager] Configuration saved successfully")
        } catch {
            print("Error saving dashboard configuration: \(error)")
        }
    }
    
    func loadConfiguration() {
        print("[DashboardManager] Loading configuration...")
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            let decoder = JSONDecoder()
            widgets = try decoder.decode([WidgetConfiguration].self, from: data)
            print("[DashboardManager] Configuration loaded. Found \(widgets.count) widgets.")
        } catch {
            print("Error loading dashboard configuration: \(error)")
        }
    }
}
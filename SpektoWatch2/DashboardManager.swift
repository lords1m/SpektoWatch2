import SwiftUI
import Combine
import UIKit

class DashboardManager: ObservableObject {
    @Published var widgets: [WidgetConfiguration] = []
    @Published var isEditMode: Bool = false
    
    private let userDefaultsKey = "DashboardConfiguration_v3" // v3 um alte Configs zu ignorieren
    
    init() {
        print("[DashboardManager] Initializing...")
        loadConfiguration()
        if widgets.isEmpty {
            // NUR EIN großes Spektrogramm als Default
            widgets = [
                WidgetConfiguration(type: .spectrogram, size: .full, gridPosition: GridPosition(index: 0))
            ]
            print("[DashboardManager] Created default configuration with ONE large spectrogram")
            saveConfiguration()
        }
    }
    
    func addWidget(type: AudioWidgetType, at position: GridPosition? = nil) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        print("[DashboardManager] Adding widget of type: \(type.rawValue)")
        let size = WidgetConfiguration.defaultSize(for: type)
        let pos = position ?? GridPosition(index: widgets.count)
        let newWidget = WidgetConfiguration(type: type, size: size, gridPosition: pos)
        widgets.append(newWidget)
        print("[DashboardManager] Widget added. Total widgets: \(widgets.count)")
        saveConfiguration()
    }
    
    func removeWidget(id: UUID) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
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
            print("[DashboardManager] Widget resized successfully")
            saveConfiguration()
        } else {
            print("[DashboardManager] ERROR: Widget with ID \(id) not found for resizing")
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
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(widgets)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            print("[DashboardManager] Configuration saved successfully (\(widgets.count) widgets)")
        } catch {
            print("[DashboardManager] Error saving dashboard configuration: \(error)")
        }
    }
    
    func loadConfiguration() {
        print("[DashboardManager] Loading configuration...")
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("[DashboardManager] No saved configuration found")
            return
        }
        do {
            let decoder = JSONDecoder()
            widgets = try decoder.decode([WidgetConfiguration].self, from: data)
            print("[DashboardManager] Configuration loaded successfully. Found \(widgets.count) widgets:")
            for (index, widget) in widgets.enumerated() {
                print("  [\(index)] \(widget.type.rawValue) - \(widget.size.rawValue)")
            }
        } catch {
            print("[DashboardManager] Error loading dashboard configuration: \(error)")
        }
    }
    
    /// Reset zu Standard-Konfiguration
    func resetToDefault() {
        print("[DashboardManager] Resetting to default configuration...")
        widgets = [
            WidgetConfiguration(type: .spectrogram, size: .full, gridPosition: GridPosition(index: 0))
        ]
        saveConfiguration()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

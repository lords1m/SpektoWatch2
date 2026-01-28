import SwiftUI
import Combine
import UIKit
import OSLog

class DashboardManager: ObservableObject {
    @Published var widgets: [WidgetConfiguration] = []
    @Published var isEditMode: Bool = false
    
    private let userDefaultsKey = "DashboardConfiguration_v5" // v5 für Level History
    
    init() {
        Logger.ui.debug("DashboardManager Initializing...")
        loadConfiguration()
        if widgets.isEmpty {
            // NUR EIN großes Spektrogramm als Default
            widgets = [
                WidgetConfiguration(type: .spectrogram, size: WidgetSize(columns: 4, rows: 2.0), gridPosition: GridPosition(index: 0)),
                WidgetConfiguration(type: .levelHistory, size: WidgetSize(columns: 4, rows: 1.0), gridPosition: GridPosition(index: 1))
            ]
            Logger.ui.info("Created default configuration with ONE large spectrogram")
            saveConfiguration()
        }
    }
    
    func addWidget(type: AudioWidgetType, at position: GridPosition? = nil) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        Logger.ui.info("Adding widget of type: \(type.rawValue)")
        let size = WidgetConfiguration.defaultSize(for: type)
        let pos = position ?? GridPosition(index: widgets.count)
        let newWidget = WidgetConfiguration(type: type, size: size, gridPosition: pos)
        widgets.append(newWidget)
        Logger.ui.debug("Widget added. Total widgets: \(self.widgets.count)")
        saveConfiguration()
    }
    
    func removeWidget(id: UUID) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        Logger.ui.info("Removing widget with ID: \(id)")
        widgets.removeAll { $0.id == id }
        Logger.ui.debug("Widget removed. Total widgets: \(self.widgets.count)")
        saveConfiguration()
    }
    
    func moveWidget(from source: IndexSet, to destination: Int) {
        Logger.ui.debug("Moving widget from \(source) to \(destination)")
        widgets.move(fromOffsets: source, toOffset: destination)
        saveConfiguration()
    }
    
    func resizeWidget(id: UUID, to newSize: WidgetSize) {
        Logger.ui.debug("Resizing widget \(id) to \(newSize.columns)x\(newSize.rows)")
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].size = newSize
            Logger.ui.debug("Widget resized successfully")
            saveConfiguration()
        } else {
            Logger.ui.error("Widget with ID \(id) not found for resizing")
        }
    }
    
    func updateWidgetSettings(id: UUID, settings: [String: String]) {
        Logger.ui.debug("Updating settings for widget \(id)")
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].settings = settings
            saveConfiguration()
        }
    }
    
    func saveConfiguration() {
        Logger.ui.debug("Saving configuration...")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(widgets)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            Logger.ui.info("Configuration saved successfully (\(self.widgets.count) widgets)")
        } catch {
            Logger.ui.error("Error saving dashboard configuration: \(error.localizedDescription)")
        }
    }
    
    func loadConfiguration() {
        Logger.ui.debug("Loading configuration...")
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            Logger.ui.info("No saved configuration found")
            return
        }
        do {
            let decoder = JSONDecoder()
            widgets = try decoder.decode([WidgetConfiguration].self, from: data)
            Logger.ui.info("Configuration loaded successfully. Found \(self.widgets.count) widgets")
            for (index, widget) in widgets.enumerated() {
                Logger.ui.debug("  [\(index)] \(widget.type.rawValue) - \(widget.size.columns)x\(widget.size.rows, format: .fixed(precision: 1))")
            }
        } catch {
            Logger.ui.error("Error loading dashboard configuration: \(error.localizedDescription)")
        }
    }
    
    /// Reset zu Standard-Konfiguration
    func resetToDefault() {
        Logger.ui.info("Resetting to default configuration...")
        widgets = [
            WidgetConfiguration(type: .spectrogram, size: WidgetSize(columns: 4, rows: 2.0), gridPosition: GridPosition(index: 0)),
            WidgetConfiguration(type: .levelHistory, size: WidgetSize(columns: 4, rows: 1.0), gridPosition: GridPosition(index: 1))
        ]
        saveConfiguration()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

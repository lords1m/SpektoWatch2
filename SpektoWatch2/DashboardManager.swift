import SwiftUI
import Combine
import UIKit
import OSLog

struct DashboardLayout: Identifiable, Codable {
    let id: UUID
    var name: String
    var widgets: [WidgetConfiguration]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, widgets: [WidgetConfiguration], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.widgets = widgets
        self.createdAt = createdAt
    }
}

private struct DashboardLayoutsState: Codable {
    var layouts: [DashboardLayout]
    var activeLayoutIndex: Int
}

@MainActor
class DashboardManager: ObservableObject {
    @Published var widgets: [WidgetConfiguration] = []
    @Published var layouts: [DashboardLayout] = []
    @Published private(set) var activeLayoutIndex: Int = 0
    @Published var isEditMode: Bool = false

    // Keys live in PersistenceKeys (M13 task-8).
    private let userDefaultsKey = PersistenceKeys.dashboardLegacySnapshot
    private let layoutsUserDefaultsKey = PersistenceKeys.dashboardLayouts
    /// True when saved data existed but could not be decoded; prevents silently overwriting
    /// a corrupt save file with defaults.
    private var configurationLoadFailed = false

    init() {
        Logger.ui.debug("DashboardManager Initializing...")
        loadConfiguration()
        if layouts.isEmpty && !configurationLoadFailed {
            let defaults = Self.defaultWidgets()
            layouts = [DashboardLayout(name: "Layout 1", widgets: defaults)]
            widgets = defaults
            activeLayoutIndex = 0
            Logger.ui.info("Created default dashboard layout")
            saveConfiguration()
        }
    }

    var currentLayoutName: String {
        guard activeLayoutIndex >= 0, activeLayoutIndex < layouts.count else { return "Layout" }
        return layouts[activeLayoutIndex].name
    }

    func widgets(forLayoutAt index: Int) -> [WidgetConfiguration] {
        guard index >= 0, index < layouts.count else { return [] }
        if index == activeLayoutIndex { return widgets }
        return layouts[index].widgets
    }

    func setActiveLayout(index: Int) {
        guard !layouts.isEmpty else { return }
        storeWidgetsToActiveLayout()
        let clamped = max(0, min(index, layouts.count - 1))
        activeLayoutIndex = clamped
        widgets = layouts[clamped].widgets
        saveConfiguration()
    }

    func addEmptyLayout() {
        storeWidgetsToActiveLayout()
        let name = "Layout \(layouts.count + 1)"
        layouts.append(DashboardLayout(name: name, widgets: []))
        activeLayoutIndex = layouts.count - 1
        widgets = []
        saveConfiguration()
    }

    func saveCurrentAsNewLayout() {
        storeWidgetsToActiveLayout()
        let base = currentLayoutName
        let name = uniqueLayoutName(basedOn: "\(base) Kopie")
        layouts.append(DashboardLayout(name: name, widgets: widgets))
        activeLayoutIndex = layouts.count - 1
        saveConfiguration()
    }

    func renameLayout(at index: Int, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, index >= 0, index < layouts.count else { return }
        layouts[index].name = trimmed
        saveConfiguration()
    }

    func deleteLayout(at index: Int) {
        guard layouts.count > 1, index >= 0, index < layouts.count else { return }
        storeWidgetsToActiveLayout()
        layouts.remove(at: index)
        if activeLayoutIndex >= layouts.count {
            activeLayoutIndex = max(0, layouts.count - 1)
        }
        widgets = layouts[activeLayoutIndex].widgets
        saveConfiguration()
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
        guard let index = widgets.firstIndex(where: { $0.id == id }) else {
            Logger.ui.error("Widget with ID \(id) not found for resizing")
            return
        }
        // Clamp to the type's allowed size range (M8 — single source of
        // truth lives in `WidgetConfiguration.sizeRange(for:)`).
        let range = WidgetConfiguration.sizeRange(for: widgets[index].type)
        let safeSize = newSize.clamped(min: range.min, max: range.max)
        Logger.ui.debug("Resizing widget \(id) to \(safeSize.columns)x\(safeSize.rows)")
        widgets[index].size = safeSize
        saveConfiguration()
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
            storeWidgetsToActiveLayout()
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let state = DashboardLayoutsState(layouts: layouts, activeLayoutIndex: activeLayoutIndex)
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: layoutsUserDefaultsKey)

            // legacy snapshot for features reading the old key (e.g. recording metadata snapshot)
            let currentLayoutData = try encoder.encode(widgets)
            UserDefaults.standard.set(currentLayoutData, forKey: userDefaultsKey)
            Logger.ui.info("Configuration saved successfully (\(self.layouts.count) layouts, active=\(self.activeLayoutIndex))")
        } catch {
            Logger.ui.error("Error saving dashboard configuration: \(error.localizedDescription)")
        }
    }

    func loadConfiguration() {
        Logger.ui.debug("Loading configuration...")
        let decoder = JSONDecoder()

        if let layoutsData = UserDefaults.standard.data(forKey: layoutsUserDefaultsKey) {
            do {
                let state = try decoder.decode(DashboardLayoutsState.self, from: layoutsData)
                let hadLegacyOctaveWidgets = state.layouts.contains { layout in
                    layout.widgets.contains(where: { $0.type == .octaveBands })
                }
                layouts = state.layouts.map { layout in
                    var migratedLayout = layout
                    migratedLayout.widgets = Self.normalizeWidgets(layout.widgets)
                    return migratedLayout
                }
                if layouts.isEmpty {
                    layouts = [DashboardLayout(name: "Layout 1", widgets: Self.defaultWidgets())]
                }
                activeLayoutIndex = max(0, min(state.activeLayoutIndex, layouts.count - 1))
                widgets = layouts[activeLayoutIndex].widgets
                if hadLegacyOctaveWidgets {
                    saveConfiguration()
                }
                Logger.ui.info("Loaded dashboard layouts: \(self.layouts.count)")
                return
            } catch {
                Logger.ui.error("Error loading dashboard layouts: \(error.localizedDescription)")
                configurationLoadFailed = true
                return
            }
        }

        // Legacy migration (single layout)
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            Logger.ui.info("No saved configuration found")
            return
        }

        do {
            let decodedWidgets = try decoder.decode([WidgetConfiguration].self, from: data)
            let migratedWidgets = decodedWidgets.isEmpty ? Self.defaultWidgets() : Self.normalizeWidgets(decodedWidgets)
            layouts = [DashboardLayout(name: "Layout 1", widgets: migratedWidgets)]
            activeLayoutIndex = 0
            widgets = migratedWidgets
            Logger.ui.info("Migrated legacy dashboard configuration to multi-layout format")
            saveConfiguration()
        } catch {
            Logger.ui.error("Error loading legacy dashboard configuration: \(error.localizedDescription)")
            configurationLoadFailed = true
        }
    }
    
    /// Reset zu Standard-Konfiguration
    func resetToDefault() {
        Logger.ui.info("Resetting to default configuration...")
        layouts = [DashboardLayout(name: "Layout 1", widgets: Self.defaultWidgets())]
        activeLayoutIndex = 0
        widgets = layouts[0].widgets
        saveConfiguration()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Applies a redesign preset by routing into a dedicated "Preset"
    /// layout (created on first use) — does NOT overwrite the user's
    /// existing custom layouts. If the Preset slot already exists, its
    /// widgets are replaced; otherwise a new slot is appended.
    /// Persists immediately.
    func applyPreset(id: String) {
        let composition = PresetCompositions.widgets(forPresetID: id)
        guard !composition.isEmpty else { return }
        Logger.ui.info("Applying preset '\(id)' (\(composition.count) widgets)")

        storeWidgetsToActiveLayout()

        let presetName = "Preset: \(id)"
        if let existing = layouts.firstIndex(where: { $0.name == presetName }) {
            layouts[existing].widgets = composition
            activeLayoutIndex = existing
        } else {
            layouts.append(DashboardLayout(name: presetName, widgets: composition))
            activeLayoutIndex = layouts.count - 1
        }
        widgets = composition
        saveConfiguration()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func installWidgetSizeScreenshotPreset() {
        Logger.ui.info("Installing widget size screenshot preset...")
        layouts = AudioWidgetType.allCases.map { type in
            DashboardLayout(
                name: "Preset: \(type.rawValue)",
                widgets: Self.sizeCatalogWidgets(for: type)
            )
        }
        activeLayoutIndex = 0
        widgets = layouts.first?.widgets ?? []
        saveConfiguration()

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func storeWidgetsToActiveLayout() {
        guard activeLayoutIndex >= 0, activeLayoutIndex < layouts.count else { return }
        layouts[activeLayoutIndex].widgets = widgets
    }

    private func uniqueLayoutName(basedOn base: String) -> String {
        let existing = Set(layouts.map(\.name))
        if !existing.contains(base) { return base }
        var index = 2
        while existing.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }

    private static func normalizeWidgets(_ widgets: [WidgetConfiguration]) -> [WidgetConfiguration] {
        widgets.compactMap { widget in
            // phaseMeter is deactivated (kept in the enum for legacy decode
            // only). Silently drop any persisted instances so dashboards
            // from older builds load cleanly without the unsupported widget.
            if widget.type == .phaseMeter { return nil }

            var normalized = widget
            if normalized.type == .octaveBands {
                normalized.type = .frequencyDisplay
                if normalized.settings["frequencyBands"] == nil {
                    normalized.settings["frequencyBands"] = "terz"
                }
            }
            return normalized
        }
    }

    private static func defaultWidgets() -> [WidgetConfiguration] {
        [
            WidgetConfiguration(type: .spectrogram, size: WidgetConfiguration.defaultSize(for: .spectrogram), gridPosition: GridPosition(index: 0)),
            WidgetConfiguration(type: .levelHistory, size: WidgetConfiguration.defaultSize(for: .levelHistory), gridPosition: GridPosition(index: 1))
        ]
    }

    private static func sizeCatalogWidgets(for type: AudioWidgetType) -> [WidgetConfiguration] {
        let range = WidgetConfiguration.sizeRange(for: type)
        var widgets: [WidgetConfiguration] = []
        var index = 0

        for rows in range.min.rows...range.max.rows {
            for columns in range.min.columns...range.max.columns {
                let size = WidgetSize(columns: columns, rows: rows)
                widgets.append(
                    WidgetConfiguration(
                        type: type,
                        size: size,
                        gridPosition: GridPosition(index: index)
                    )
                )
                index += 1
            }
        }

        return widgets
    }
}

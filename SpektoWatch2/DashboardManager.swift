import SwiftUI
import Combine
import UIKit
import OSLog

struct DashboardLayout: Identifiable, Codable, Equatable {
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
    /// True once the async load (or "no saved data" branch) has finished. Views
    /// that call `saveConfiguration()` are gated on this flag so the default
    /// placeholder shown during load cannot overwrite a valid saved configuration.
    @Published private(set) var didFinishLoading: Bool = false

    // Keys live in PersistenceKeys (M13 task-8).
    private let userDefaultsKey = PersistenceKeys.dashboardLegacySnapshot
    private let layoutsUserDefaultsKey = PersistenceKeys.dashboardLayouts
    private var configurationLoadFailed = false
    private var isLoading = false

    init() {
        Logger.ui.debug("DashboardManager Initializing...")
        // Show default layout immediately; the saved configuration is loaded
        // asynchronously via startLoading() (called from ModularDashboardView.task)
        // to avoid the 573 ms main-thread hang from JSON decoding in init
        // (M19 task-1).
        let defaults = Self.defaultWidgets()
        layouts = [DashboardLayout(name: "Layout 1", widgets: defaults)]
        widgets = defaults
    }

    // MARK: - Async load

    /// Starts background JSON decoding of the saved dashboard configuration.
    /// Safe to call multiple times — subsequent calls are no-ops once loading
    /// has started.  Must be called on @MainActor (e.g. from a SwiftUI .task).
    func startLoading() {
        guard !didFinishLoading, !isLoading else { return }
        isLoading = true
        Logger.ui.debug("DashboardManager.startLoading() — background decode started")

        // Snapshot UserDefaults bytes on the calling thread (thread-safe, fast).
        let layoutsData = UserDefaults.standard.data(forKey: layoutsUserDefaultsKey)
        let legacyData   = UserDefaults.standard.data(forKey: userDefaultsKey)

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.decodeStoredConfiguration(layoutsData: layoutsData,
                                                        legacyData: legacyData)
            await MainActor.run { [weak self] in
                self?.applyLoadResult(result)
            }
        }
    }

    private enum LoadResult {
        case loaded(layouts: [DashboardLayout], activeIndex: Int, needsMigrationSave: Bool)
        case loadFailed
        case noSavedData
    }

    /// Pure decode — runs off @MainActor inside Task.detached.
    nonisolated private static func decodeStoredConfiguration(
        layoutsData: Data?,
        legacyData: Data?
    ) -> LoadResult {
        let decoder = JSONDecoder()

        if let data = layoutsData {
            do {
                let state = try decoder.decode(DashboardLayoutsState.self, from: data)
                let hadLegacyOctaveWidgets = state.layouts.contains { layout in
                    layout.widgets.contains { $0.type == .octaveBands }
                }
                var loadedLayouts = state.layouts.map { layout -> DashboardLayout in
                    var m = layout
                    m.widgets = normalizeWidgets(layout.widgets)
                    return m
                }
                if loadedLayouts.isEmpty {
                    loadedLayouts = [DashboardLayout(name: "Layout 1", widgets: defaultWidgets())]
                }
                return .loaded(layouts: loadedLayouts,
                               activeIndex: state.activeLayoutIndex,
                               needsMigrationSave: hadLegacyOctaveWidgets)
            } catch {
                Logger.ui.error("Error loading dashboard layouts: \(error.localizedDescription)")
                return .loadFailed
            }
        }

        if let data = legacyData {
            do {
                let decoded = try decoder.decode([WidgetConfiguration].self, from: data)
                let migrated = decoded.isEmpty ? defaultWidgets() : normalizeWidgets(decoded)
                return .loaded(
                    layouts: [DashboardLayout(name: "Layout 1", widgets: migrated)],
                    activeIndex: 0,
                    needsMigrationSave: true
                )
            } catch {
                Logger.ui.error("Error loading legacy dashboard configuration: \(error.localizedDescription)")
                return .loadFailed
            }
        }

        return .noSavedData
    }

    private func applyLoadResult(_ result: LoadResult) {
        isLoading = false
        // Set before saveConfiguration() calls below so the guard inside allows writes.
        didFinishLoading = true

        switch result {
        case .loaded(let loadedLayouts, let activeIndex, let needsMigrationSave):
            layouts = loadedLayouts
            let clamped = max(0, min(activeIndex, loadedLayouts.count - 1))
            activeLayoutIndex = clamped
            widgets = loadedLayouts[clamped].widgets
            if needsMigrationSave { saveConfiguration() }
            Logger.ui.info("DashboardManager loaded \(loadedLayouts.count) layout(s) (active=\(clamped))")
        case .loadFailed:
            configurationLoadFailed = true
            Logger.ui.error("DashboardManager load failed — keeping defaults, not overwriting save file")
        case .noSavedData:
            // Persist the defaults that were set in init().
            saveConfiguration()
            Logger.ui.info("DashboardManager: no saved config — defaults persisted")
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
        guard didFinishLoading else {
            // Load hasn't finished yet — suppress the write so the default
            // placeholder from init() cannot overwrite a valid saved config.
            Logger.ui.debug("saveConfiguration skipped — async load in progress")
            return
        }
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

    nonisolated private static func normalizeWidgets(_ widgets: [WidgetConfiguration]) -> [WidgetConfiguration] {
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

    nonisolated private static func defaultWidgets() -> [WidgetConfiguration] {
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

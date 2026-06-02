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

private struct DashboardLayoutsStateV1: Codable {
    var layouts: [DashboardLayout]
    var activeLayoutIndex: Int
}

@MainActor
class DashboardManager: ObservableObject {
    @Published var presetSlots: [PresetSlot] = []
    @Published var customLayouts: [DashboardLayout] = []
    @Published var navigation: DashboardNavigation = .preset(activePresetID: "overview")
    @Published var widgets: [WidgetConfiguration] = []
    @Published var isEditMode: Bool = false
    @Published private(set) var didFinishLoading: Bool = false

    private let userDefaultsKey = PersistenceKeys.dashboardLegacySnapshot
    private let layoutsV1Key = PersistenceKeys.dashboardLayouts
    private let layoutsV2Key = PersistenceKeys.dashboardLayoutsV2
    private var configurationLoadFailed = false
    private var isLoading = false

    init() {
        Logger.ui.debug("DashboardManager Initializing...")
        let state = DashboardStateFactory.defaultState()
        applyState(state)
    }

    // MARK: - Mode

    var isCustomMode: Bool {
        if case .custom = navigation { return true }
        return false
    }

    var activePresetID: String {
        get {
            if case .preset(let id) = navigation { return id }
            return PresetCatalogue.all.first?.id ?? "overview"
        }
    }

    /// Index into `PresetCatalogue.all` / `presetSlots` for TabView paging.
    var activePresetIndex: Int {
        get {
            DashboardStateFactory.presetIndex(for: activePresetID) ?? 0
        }
    }

    /// Legacy property used by a few tests — preset page index when in preset mode.
    var activeLayoutIndex: Int { activePresetIndex }

    /// Legacy: custom layouts only (DEBUG/tests that enumerate saved pages).
    var layouts: [DashboardLayout] { customLayouts }

    var currentLayoutName: String {
        switch navigation {
        case .preset(let id):
            return PresetCatalogue.all.first { $0.id == id }?.label ?? id
        case .custom(let layoutID):
            return customLayouts.first { $0.id == layoutID }?.name ?? "Layout"
        }
    }

    var headerEyebrowIsCustom: Bool { isCustomMode }

    // MARK: - Async load

    func startLoading() {
        guard !didFinishLoading, !isLoading else { return }
        isLoading = true
        Logger.ui.debug("DashboardManager.startLoading() — background decode started")

        let v2Data = UserDefaults.standard.data(forKey: layoutsV2Key)
        let v1Data = UserDefaults.standard.data(forKey: layoutsV1Key)
        let legacyData = UserDefaults.standard.data(forKey: userDefaultsKey)

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.decodeStoredConfiguration(v2Data: v2Data, v1Data: v1Data, legacyData: legacyData)
            await MainActor.run { [weak self] in
                self?.applyLoadResult(result)
            }
        }
    }

    private enum LoadResult {
        case loadedV2(DashboardStateV2, needsMigrationSave: Bool)
        case loadFailed
        case noSavedData
    }

    nonisolated private static func decodeStoredConfiguration(
        v2Data: Data?,
        v1Data: Data?,
        legacyData: Data?
    ) -> LoadResult {
        let decoder = JSONDecoder()

        if let data = v2Data {
            do {
                var state = try decoder.decode(DashboardStateV2.self, from: data)
                state = reconcileSlots(state)
                let hadLegacyOctave = state.presetSlots.contains { slot in
                    slot.widgets.contains { $0.type == .octaveBands }
                } || state.customLayouts.contains { $0.widgets.contains { $0.type == .octaveBands } }
                return .loadedV2(state, needsMigrationSave: hadLegacyOctave)
            } catch {
                Logger.ui.error("Error loading dashboard v2: \(error.localizedDescription)")
                return .loadFailed
            }
        }

        if let data = v1Data {
            do {
                let v1 = try decoder.decode(DashboardLayoutsStateV1.self, from: data)
                let migrated = DashboardStateMigration.migrateFromV1(
                    DashboardV1Snapshot(layouts: v1.layouts, activeLayoutIndex: v1.activeLayoutIndex)
                )
                return .loadedV2(reconcileSlots(migrated), needsMigrationSave: true)
            } catch {
                Logger.ui.error("Error loading dashboard v1: \(error.localizedDescription)")
                return .loadFailed
            }
        }

        if let data = legacyData {
            do {
                let decoded = try decoder.decode([WidgetConfiguration].self, from: data)
                let migrated = DashboardStateMigration.migrateFromLegacyWidgets(decoded)
                return .loadedV2(reconcileSlots(migrated), needsMigrationSave: true)
            } catch {
                Logger.ui.error("Error loading legacy dashboard: \(error.localizedDescription)")
                return .loadFailed
            }
        }

        return .noSavedData
    }

    /// Ensures slot count/order matches catalogue (e.g. after adding phase preset).
    nonisolated static func reconcileSlots(_ state: DashboardStateV2) -> DashboardStateV2 {
        var result = state
        let byID = Dictionary(uniqueKeysWithValues: result.presetSlots.map { ($0.presetID, $0) })
        result.presetSlots = PresetCatalogue.all.map { preset in
            if let existing = byID[preset.id] {
                return PresetSlot(presetID: preset.id, widgets: normalizeWidgetsPublic(existing.widgets))
            }
            return PresetSlot(presetID: preset.id, widgets: PresetCompositions.widgets(forPresetID: preset.id))
        }
        result.customLayouts = result.customLayouts.map { layout in
            var copy = layout
            copy.widgets = normalizeWidgetsPublic(layout.widgets)
            return copy
        }
        switch result.navigation {
        case .preset(let id):
            result.navigation = .preset(activePresetID: DashboardStateFactory.clampPresetID(id))
        case .custom(let layoutID):
            if !result.customLayouts.contains(where: { $0.id == layoutID }) {
                result.navigation = .preset(activePresetID: "overview")
            }
        }
        return result
    }

    private func applyLoadResult(_ result: LoadResult) {
        isLoading = false
        didFinishLoading = true

        switch result {
        case .loadedV2(let state, let needsMigrationSave):
            applyState(state)
            if needsMigrationSave { saveConfiguration() }
            Logger.ui.info("DashboardManager loaded v2 (\(self.presetSlots.count) presets, \(self.customLayouts.count) custom)")
        case .loadFailed:
            configurationLoadFailed = true
            Logger.ui.error("DashboardManager load failed — keeping defaults")
        case .noSavedData:
            saveConfiguration()
            Logger.ui.info("DashboardManager: no saved config — defaults persisted")
        }
    }

    private func applyState(_ state: DashboardStateV2) {
        presetSlots = state.presetSlots
        customLayouts = state.customLayouts
        navigation = state.navigation
        reloadWidgetsFromNavigation()
    }

    private func reloadWidgetsFromNavigation() {
        switch navigation {
        case .preset(let id):
            if let slot = presetSlots.first(where: { $0.presetID == id }) {
                widgets = slot.widgets
            } else {
                widgets = PresetCompositions.widgets(forPresetID: id)
            }
        case .custom(let layoutID):
            widgets = customLayouts.first { $0.id == layoutID }?.widgets ?? []
        }
    }

    func widgets(forPresetIndex index: Int) -> [WidgetConfiguration] {
        guard index >= 0, index < presetSlots.count else { return [] }
        let slot = presetSlots[index]
        if isCustomMode { return slot.widgets }
        if index == activePresetIndex { return widgets }
        return slot.widgets
    }

    // MARK: - Navigation

    func selectPreset(id: String) {
        let clamped = DashboardStateFactory.clampPresetID(id)
        storeWidgetsToActiveContext()
        navigation = .preset(activePresetID: clamped)
        reloadWidgetsFromNavigation()
        saveConfiguration()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func setActivePresetIndex(_ index: Int) {
        guard index >= 0, index < PresetCatalogue.all.count else { return }
        selectPreset(id: PresetCatalogue.all[index].id)
    }

    /// Alias for preset rail — switches preset page without resetting widgets.
    func applyPreset(id: String) {
        selectPreset(id: id)
    }

    func returnToPresets(presetID: String? = nil) {
        let id = presetID.map { DashboardStateFactory.clampPresetID($0) } ?? activePresetID
        selectPreset(id: id)
    }

    func openCustomLayout(id: UUID) {
        guard let layout = customLayouts.first(where: { $0.id == id }) else { return }
        storeWidgetsToActiveContext()
        navigation = .custom(activeLayoutID: id)
        widgets = layout.widgets
        saveConfiguration()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func resetActivePresetToDefault() {
        guard case .preset(let id) = navigation else { return }
        resetPresetToDefault(id: id)
    }

    func resetPresetToDefault(id: String) {
        let clamped = DashboardStateFactory.clampPresetID(id)
        let composition = PresetCompositions.widgets(forPresetID: clamped)
        guard !composition.isEmpty else { return }
        if let index = presetSlots.firstIndex(where: { $0.presetID == clamped }) {
            presetSlots[index].widgets = composition
        }
        if case .preset(let active) = navigation, active == clamped {
            widgets = composition
        }
        saveConfiguration()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Custom layouts

    func addCustomLayout(empty: Bool = true) {
        storeWidgetsToActiveContext()
        let name = uniqueCustomLayoutName(basedOn: "Layout \(customLayouts.count + 1)")
        let newLayout = DashboardLayout(
            name: name,
            widgets: empty ? [] : widgets
        )
        customLayouts.append(newLayout)
        navigation = .custom(activeLayoutID: newLayout.id)
        widgets = newLayout.widgets
        saveConfiguration()
    }

    func duplicateCurrentAsCustomLayout() {
        storeWidgetsToActiveContext()
        let base = currentLayoutName
        let name = uniqueCustomLayoutName(basedOn: "\(base) Kopie")
        let newLayout = DashboardLayout(name: name, widgets: widgets)
        customLayouts.append(newLayout)
        navigation = .custom(activeLayoutID: newLayout.id)
        saveConfiguration()
    }

    func renameCustomLayout(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = customLayouts.firstIndex(where: { $0.id == id }) else { return }
        customLayouts[index].name = trimmed
        saveConfiguration()
    }

    func deleteCustomLayout(id: UUID) {
        guard let index = customLayouts.firstIndex(where: { $0.id == id }) else { return }
        customLayouts.remove(at: index)
        if case .custom(let activeID) = navigation, activeID == id {
            returnToPresets()
        }
        saveConfiguration()
    }

    // MARK: - Legacy layout APIs (map to custom / preset)

    func setActiveLayout(index: Int) {
        setActivePresetIndex(index)
    }

    func addEmptyLayout() {
        addCustomLayout(empty: true)
    }

    func saveCurrentAsNewLayout() {
        duplicateCurrentAsCustomLayout()
    }

    func renameLayout(at index: Int, name: String) {
        guard index >= 0, index < customLayouts.count else { return }
        renameCustomLayout(id: customLayouts[index].id, name: name)
    }

    func deleteLayout(at index: Int) {
        guard index >= 0, index < customLayouts.count else { return }
        deleteCustomLayout(id: customLayouts[index].id)
    }

    func widgets(forLayoutAt index: Int) -> [WidgetConfiguration] {
        widgets(forPresetIndex: index)
    }

    // MARK: - Widget mutations

    func addWidget(type: AudioWidgetType, at position: GridPosition? = nil) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let size = WidgetConfiguration.defaultSize(for: type)
        let pos = position ?? GridPosition(index: widgets.count)
        widgets.append(WidgetConfiguration(type: type, size: size, gridPosition: pos))
        saveConfiguration()
    }

    func removeWidget(id: UUID) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        widgets.removeAll { $0.id == id }
        saveConfiguration()
    }

    func restoreWidget(_ widget: WidgetConfiguration, at index: Int) {
        let safeIndex = max(0, min(index, widgets.count))
        widgets.insert(widget, at: safeIndex)
        saveConfiguration()
    }

    func moveWidget(from source: IndexSet, to destination: Int) {
        widgets.move(fromOffsets: source, toOffset: destination)
        saveConfiguration()
    }

    func resizeWidget(id: UUID, to newSize: WidgetSize) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        let range = WidgetConfiguration.sizeRange(for: widgets[index].type)
        widgets[index].size = newSize.clamped(min: range.min, max: range.max)
        saveConfiguration()
    }

    func updateWidgetSettings(id: UUID, settings: [String: String]) {
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].settings = settings
            saveConfiguration()
        }
    }

    func saveConfiguration() {
        guard didFinishLoading else {
            Logger.ui.debug("saveConfiguration skipped — async load in progress")
            return
        }
        storeWidgetsToActiveContext()
        do {
            let state = DashboardStateV2(
                presetSlots: presetSlots,
                customLayouts: customLayouts,
                navigation: navigation
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: layoutsV2Key)

            let legacyWidgets = try encoder.encode(widgets)
            UserDefaults.standard.set(legacyWidgets, forKey: userDefaultsKey)
            Logger.ui.info("Configuration saved (v2, \(self.presetSlots.count) presets, \(self.customLayouts.count) custom)")
        } catch {
            Logger.ui.error("Error saving dashboard: \(error.localizedDescription)")
        }
    }

    func resetToDefault() {
        applyState(DashboardStateFactory.defaultState())
        saveConfiguration()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    #if DEBUG
    func installWidgetSizeScreenshotPreset() {
        Logger.ui.info("Installing widget size screenshot preset (custom layouts)...")
        customLayouts = AudioWidgetType.allCases.map { type in
            DashboardLayout(
                name: "Screenshot: \(type.rawValue)",
                widgets: Self.sizeCatalogWidgets(for: type)
            )
        }
        if let first = customLayouts.first {
            navigation = .custom(activeLayoutID: first.id)
            widgets = first.widgets
        }
        saveConfiguration()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    #endif

    private func storeWidgetsToActiveContext() {
        switch navigation {
        case .preset(let id):
            if let index = presetSlots.firstIndex(where: { $0.presetID == id }) {
                presetSlots[index].widgets = widgets
            }
        case .custom(let layoutID):
            if let index = customLayouts.firstIndex(where: { $0.id == layoutID }) {
                customLayouts[index].widgets = widgets
            }
        }
    }

    private func uniqueCustomLayoutName(basedOn base: String) -> String {
        let existing = Set(customLayouts.map(\.name))
        if !existing.contains(base) { return base }
        var index = 2
        while existing.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }

    nonisolated static func normalizeWidgetsPublic(_ widgets: [WidgetConfiguration]) -> [WidgetConfiguration] {
        normalizeWidgets(widgets)
    }

    nonisolated private static func normalizeWidgets(_ widgets: [WidgetConfiguration]) -> [WidgetConfiguration] {
        widgets.compactMap { widget in
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
        PresetCompositions.widgets(forPresetID: "overview")
    }

    private static func sizeCatalogWidgets(for type: AudioWidgetType) -> [WidgetConfiguration] {
        let range = WidgetConfiguration.sizeRange(for: type)
        var result: [WidgetConfiguration] = []
        var index = 0
        for rows in range.min.rows...range.max.rows {
            for columns in range.min.columns...range.max.columns {
                result.append(
                    WidgetConfiguration(
                        type: type,
                        size: WidgetSize(columns: columns, rows: rows),
                        gridPosition: GridPosition(index: index)
                    )
                )
                index += 1
            }
        }
        return result
    }
}

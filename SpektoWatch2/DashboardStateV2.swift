import Foundation

// MARK: - Model C persistence (preset slots + custom layouts)

struct PresetSlot: Codable, Equatable, Identifiable {
    var id: String { presetID }
    let presetID: String
    var widgets: [WidgetConfiguration]

    init(presetID: String, widgets: [WidgetConfiguration]) {
        self.presetID = presetID
        self.widgets = widgets
    }
}

enum DashboardNavigation: Codable, Equatable {
    case preset(activePresetID: String)
    case custom(activeLayoutID: UUID)
}

struct DashboardStateV2: Codable, Equatable {
    var presetSlots: [PresetSlot]
    var customLayouts: [DashboardLayout]
    var navigation: DashboardNavigation
}

enum DashboardStateFactory {
    /// Fresh install: one slot per catalogue entry with default compositions.
    static func defaultState() -> DashboardStateV2 {
        let slots = PresetCatalogue.all.map { preset in
            PresetSlot(
                presetID: preset.id,
                widgets: PresetCompositions.widgets(forPresetID: preset.id)
            )
        }
        return DashboardStateV2(
            presetSlots: slots,
            customLayouts: [],
            navigation: .preset(activePresetID: PresetCatalogue.all.first?.id ?? "overview")
        )
    }

    static func presetIndex(for id: String) -> Int? {
        PresetCatalogue.all.firstIndex { $0.id == id }
    }

    static func clampPresetID(_ id: String) -> String {
        if presetIndex(for: id) != nil { return id }
        return PresetCatalogue.all.first?.id ?? "overview"
    }
}

struct DashboardV1Snapshot {
    var layouts: [DashboardLayout]
    var activeLayoutIndex: Int
}

enum DashboardStateMigration {
    /// v1 multi-layout JSON → v2.
    static func migrateFromV1(_ state: DashboardV1Snapshot) -> DashboardStateV2 {
        var v2 = DashboardStateFactory.defaultState()
        var slotMap = Dictionary(uniqueKeysWithValues: v2.presetSlots.map { ($0.presetID, $0) })
        let prefix = "Preset: "

        for layout in state.layouts {
            let normalized = DashboardManager.normalizeWidgetsPublic(layout.widgets)
            if layout.name.hasPrefix(prefix) {
                let id = String(layout.name.dropFirst(prefix.count))
                if var existing = slotMap[id] {
                    existing.widgets = normalized
                    slotMap[id] = existing
                } else if DashboardStateFactory.presetIndex(for: id) != nil {
                    slotMap[id] = PresetSlot(presetID: id, widgets: normalized)
                } else {
                    v2.customLayouts.append(
                        DashboardLayout(name: layout.name, widgets: normalized, createdAt: layout.createdAt)
                    )
                }
            } else {
                var custom = layout
                custom.widgets = normalized
                v2.customLayouts.append(custom)
            }
        }

        v2.presetSlots = PresetCatalogue.all.map { preset in
            slotMap[preset.id] ?? PresetSlot(
                presetID: preset.id,
                widgets: PresetCompositions.widgets(forPresetID: preset.id)
            )
        }

        let active = state.layouts.indices.contains(state.activeLayoutIndex)
            ? state.layouts[state.activeLayoutIndex]
            : nil

        if let active {
            if active.name.hasPrefix(prefix) {
                let id = DashboardStateFactory.clampPresetID(String(active.name.dropFirst(prefix.count)))
                v2.navigation = .preset(activePresetID: id)
            } else if let match = v2.customLayouts.first(where: { $0.id == active.id }) {
                v2.navigation = .custom(activeLayoutID: match.id)
            } else if let match = v2.customLayouts.first(where: { $0.name == active.name }) {
                v2.navigation = .custom(activeLayoutID: match.id)
            }
        }

        return v2
    }

    static func migrateFromLegacyWidgets(_ widgets: [WidgetConfiguration]) -> DashboardStateV2 {
        var v2 = DashboardStateFactory.defaultState()
        let normalized = DashboardManager.normalizeWidgetsPublic(widgets)
        if let overviewIndex = v2.presetSlots.firstIndex(where: { $0.presetID == "overview" }) {
            v2.presetSlots[overviewIndex].widgets = normalized.isEmpty
                ? v2.presetSlots[overviewIndex].widgets
                : normalized
        }
        v2.navigation = .preset(activePresetID: "overview")
        return v2
    }
}

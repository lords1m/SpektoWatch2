import XCTest
@testable import SpektoWatch2

final class DashboardStateMigrationTests: XCTestCase {

    func testDefaultStateHasAllPresetSlots() {
        let state = DashboardStateFactory.defaultState()
        XCTAssertEqual(state.presetSlots.count, PresetCatalogue.all.count)
        XCTAssertEqual(Set(state.presetSlots.map(\.presetID)), Set(PresetCatalogue.all.map(\.id)))
    }

    func testMigrateV1PresetLayoutIntoSlot() {
        let widgets = [WidgetConfiguration(type: .waterfall, size: WidgetConfiguration.defaultSize(for: .waterfall))]
        let v1 = DashboardLayout(name: "Preset: waterfall", widgets: widgets)
        let migrated = DashboardStateMigration.migrateFromV1(
            DashboardV1Snapshot(layouts: [v1], activeLayoutIndex: 0)
        )
        let slot = migrated.presetSlots.first { $0.presetID == "waterfall" }
        XCTAssertEqual(slot?.widgets.count, 1)
        XCTAssertEqual(slot?.widgets.first?.type, .waterfall)
        if case .preset(let id) = migrated.navigation {
            XCTAssertEqual(id, "waterfall")
        } else {
            XCTFail("Expected preset navigation")
        }
    }

    func testMigrateV1CustomLayout() {
        let custom = DashboardLayout(name: "Mein Messplatz", widgets: [])
        let migrated = DashboardStateMigration.migrateFromV1(
            DashboardV1Snapshot(layouts: [custom], activeLayoutIndex: 0)
        )
        XCTAssertEqual(migrated.customLayouts.count, 1)
        XCTAssertEqual(migrated.customLayouts.first?.name, "Mein Messplatz")
        if case .custom = migrated.navigation {} else {
            XCTFail("Expected custom navigation")
        }
    }

    func testReconcileAddsMissingPhaseSlot() {
        var state = DashboardStateV2(
            presetSlots: PresetCatalogue.all.filter { $0.id != "phase" }.map {
                PresetSlot(presetID: $0.id, widgets: PresetCompositions.widgets(forPresetID: $0.id))
            },
            customLayouts: [],
            navigation: .preset(activePresetID: "overview")
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard let data = try? encoder.encode(state),
              var decoded = try? decoder.decode(DashboardStateV2.self, from: data) else {
            return XCTFail("encode/decode failed")
        }
        decoded = DashboardManager.reconcileSlots(decoded)
        XCTAssertTrue(decoded.presetSlots.contains { $0.presetID == "phase" })
    }
}

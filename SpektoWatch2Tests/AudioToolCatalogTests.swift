import XCTest
@testable import SpektoWatch2

final class AudioToolCatalogTests: XCTestCase {

    func testCatalogMatchesAvailableTypesWithoutDuplicates() {
        let catalogTypes = AudioToolCatalog.tools.map(\.type.rawValue)
        let availableTypes = AudioWidgetType.allCases.map(\.rawValue)

        XCTAssertEqual(catalogTypes, availableTypes)
        XCTAssertEqual(Set(catalogTypes).count, catalogTypes.count)
        XCTAssertTrue(AudioToolCatalog.tools.allSatisfy(\.type.isAvailable))
    }

    func testLegacyAndDeactivatedTypesStayOutOfDiscovery() {
        for type in [AudioWidgetType.waterfall, .octaveBands, .phaseMeter, .masking] {
            XCTAssertNil(AudioToolCatalog.descriptor(for: type), "\(type.rawValue) must not appear in discovery")
        }
    }

    func testEveryToolIsDiscoverableByCategoryAndSupportsBothPresentations() {
        for tool in AudioToolCatalog.tools {
            XCTAssertTrue(
                AudioToolCatalog.tools(in: tool.category, supporting: .liveWidget)
                    .contains { $0.type == tool.type },
                "\(tool.type.rawValue) is missing from its live-widget category"
            )
            XCTAssertTrue(
                AudioToolCatalog.tools(in: tool.category, supporting: .icon)
                    .contains { $0.type == tool.type },
                "\(tool.type.rawValue) is missing from its icon category"
            )
            XCTAssertNotNil(AudioToolCatalog.descriptor(for: tool.type))
        }
    }

    func testFeatureToolsHaveExplicitLaunchDestinations() {
        for tool in AudioToolCatalog.tools {
            switch tool.type {
            case .audioEditor:
                guard case .audioEditor = tool.launchDestination else {
                    return XCTFail("Audio Editor must launch its dedicated feature")
                }
            case .recordings:
                guard case .recordings = tool.launchDestination else {
                    return XCTFail("Recordings must launch their dedicated feature")
                }
            case .settings:
                guard case .settings = tool.launchDestination else {
                    return XCTFail("Settings must launch its dedicated feature")
                }
            default:
                guard case .analysis = tool.launchDestination else {
                    return XCTFail("\(tool.type.rawValue) must launch its analysis view")
                }
            }
        }
    }

    func testCategoriesCoverAllPickerTools() {
        let categorizedTypes = AudioToolCatalog.categories.flatMap { category in
            AudioToolCatalog.tools(in: category, supporting: .liveWidget).map(\.type.rawValue)
        }

        XCTAssertEqual(Set(categorizedTypes), Set(AudioToolCatalog.availableTypes.map(\.rawValue)))
        XCTAssertEqual(categorizedTypes.count, AudioToolCatalog.availableTypes.count)
    }
}

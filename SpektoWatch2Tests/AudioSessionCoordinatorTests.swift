import AVFoundation
import XCTest
@testable import SpektoWatch2

final class AudioSessionCoordinatorTests: XCTestCase {
    private final class FakeAudioSessionDriver: AudioSessionDriving {
        private(set) var configuration: AudioSessionConfiguration
        private(set) var appliedConfigurations: [AudioSessionConfiguration] = []
        private(set) var activationCount = 0
        var failNextActivation = false

        init(configuration: AudioSessionConfiguration) {
            self.configuration = configuration
        }

        func setConfiguration(_ configuration: AudioSessionConfiguration) throws {
            self.configuration = configuration
            appliedConfigurations.append(configuration)
        }

        func activate() throws {
            if failNextActivation {
                failNextActivation = false
                throw ActivationError.failed
            }
            activationCount += 1
        }

        private enum ActivationError: Error {
            case failed
        }
    }

    func testMeasurementCaptureConfigurationRemainsRecordOnly() {
        let configuration = AudioSessionConfiguration.measurementCapture

        XCTAssertEqual(configuration.category, .record)
        XCTAssertEqual(configuration.mode, .measurement)
        XCTAssertTrue(configuration.options.isEmpty)
    }

    func testPlaybackPurposesUseExplicitPolicies() {
        let filePlayback = AudioSessionPlaybackPurpose.filePlayback.configuration
        XCTAssertEqual(filePlayback.category, .playAndRecord)
        XCTAssertEqual(filePlayback.mode, .default)
        XCTAssertTrue(filePlayback.options.contains(.defaultToSpeaker))
        XCTAssertTrue(filePlayback.options.contains(.mixWithOthers))

        let toneGenerator = AudioSessionPlaybackPurpose.toneGenerator.configuration
        XCTAssertEqual(toneGenerator.category, .playAndRecord)
        XCTAssertEqual(toneGenerator.mode, .measurement)
        XCTAssertTrue(toneGenerator.options.contains(.defaultToSpeaker))
        XCTAssertTrue(toneGenerator.options.contains(.mixWithOthers))

        let maskingPreview = AudioSessionPlaybackPurpose.maskingPreview.configuration
        XCTAssertEqual(maskingPreview.category, .playAndRecord)
        XCTAssertEqual(maskingPreview.mode, .measurement)
        XCTAssertTrue(maskingPreview.options.contains(.allowBluetoothHFP))
    }

    func testRepeatedPlaybackAndCaptureTransitionsRestoreMeasurementPolicy() throws {
        let driver = FakeAudioSessionDriver(configuration: .measurementCapture)
        let coordinator = AudioSessionCoordinator(driver: driver)

        try coordinator.activatePlayback(for: .filePlayback)
        try coordinator.activatePlayback(for: .filePlayback)
        try coordinator.activateMeasurementCapture()

        XCTAssertEqual(driver.configuration, .measurementCapture)
        XCTAssertEqual(driver.appliedConfigurations, [
            AudioSessionPlaybackPurpose.filePlayback.configuration,
            .measurementCapture
        ])
        XCTAssertEqual(driver.activationCount, 3)
    }

    func testToneGeneratorPreservesCompatibleMeasurementPlaybackSession() throws {
        let driver = FakeAudioSessionDriver(
            configuration: AudioSessionPlaybackPurpose.toneGenerator.configuration
        )
        let coordinator = AudioSessionCoordinator(driver: driver)

        try coordinator.activatePlayback(for: .toneGenerator)

        XCTAssertTrue(driver.appliedConfigurations.isEmpty)
        XCTAssertEqual(driver.configuration, AudioSessionPlaybackPurpose.toneGenerator.configuration)
        XCTAssertEqual(driver.activationCount, 1)
    }

    func testPlaybackActivationFailureDoesNotPreventCaptureRestoration() {
        let driver = FakeAudioSessionDriver(configuration: .measurementCapture)
        let coordinator = AudioSessionCoordinator(driver: driver)
        driver.failNextActivation = true

        XCTAssertThrowsError(try coordinator.activatePlayback(for: .filePlayback))
        XCTAssertNoThrow(try coordinator.activateMeasurementCapture())
        XCTAssertEqual(driver.configuration, .measurementCapture)
        XCTAssertEqual(driver.activationCount, 1)
    }
}

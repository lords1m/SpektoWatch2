import XCTest
@testable import SpektoWatch2

@MainActor
final class AudioAssetTests: XCTestCase {

    func testLegacyRecordingDefaultsToMeasurementKind() throws {
        let json = #"""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Legacy",
          "audioFileName": "legacy.wav"
        }
        """#.data(using: .utf8)!

        let recording = try JSONDecoder().decode(Recording.self, from: json)

        XCTAssertEqual(recording.assetKind, .measurement)
    }

    func testLegacyImportedAudioDecodesAsAudioFile() throws {
        let json = #"""
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "name": "Imported",
          "description": "Importierte Audiodatei",
          "audioFileName": "imported.wav"
        }
        """#.data(using: .utf8)!

        let recording = try JSONDecoder().decode(Recording.self, from: json)

        XCTAssertEqual(recording.assetKind, .audioFile)
    }

    func testImportedAudioProjectsAsGenericAssetWithoutMeasurementMetadata() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioAssetTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let sourceURL = baseDirectory.appendingPathComponent("import.wav")
        try Data([0, 1, 2, 3]).write(to: sourceURL)
        let manager = RecordingManager(baseDirectory: baseDirectory)

        let imported = try XCTUnwrap(manager.importExternalAudio(
            url: sourceURL,
            title: "Imported audio",
            duration: 1.5,
            sampleRate: 48_000,
            channelCount: 2
        ))
        let asset = try XCTUnwrap(manager.audioAssets.first)

        XCTAssertEqual(imported.assetKind, .audioFile)
        XCTAssertEqual(asset.recordingID, imported.id)
        XCTAssertEqual(asset.displayTitle, "Imported audio")
        XCTAssertEqual(asset.fileURL, manager.url(for: imported))
        XCTAssertEqual(try XCTUnwrap(asset.duration), 1.5)
        XCTAssertNil(asset.measurement)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.fileURL.path))

        let reloadedManager = RecordingManager(baseDirectory: baseDirectory)
        let restored = try XCTUnwrap(reloadedManager.audioAssets.first)
        XCTAssertEqual(restored.recordingID, imported.id)
        XCTAssertNil(restored.measurement)
    }

    func testMeasurementMetadataIsOptionalAndPreservedOnAssetProjection() {
        let recording = Recording(
            name: "Measurement",
            startDate: Date(timeIntervalSince1970: 1),
            duration: 2,
            audioFileName: "measurement.wav",
            measurementDataFileName: "measurement.spekto",
            laeqFast: 62,
            peakLevel: 78,
            minLevel: 31,
            calibrationOffset: 94.5
        )

        let asset = AudioAsset(
            recording: recording,
            fileURL: URL(fileURLWithPath: "/tmp/measurement.wav")
        )

        XCTAssertEqual(asset.measurement?.laeqFast, 62)
        XCTAssertEqual(asset.measurement?.peakLevel, 78)
        XCTAssertEqual(asset.measurement?.calibrationOffset, 94.5)
        XCTAssertEqual(asset.measurement?.measurementDataFileName, "measurement.spekto")
    }
}

import XCTest
@testable import SpektoWatch2

final class RecordingOrphanCleanupTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingOrphanCleanupTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testRemovesUnreferencedAudioAndKeepsCatalogFiles() throws {
        let referenced = UUID().uuidString + ".caf"
        let referencedURL = tempDirectory.appendingPathComponent(referenced)
        FileManager.default.createFile(atPath: referencedURL.path, contents: Data([0x01]))

        let orphanURL = tempDirectory.appendingPathComponent("orphan.caf")
        FileManager.default.createFile(atPath: orphanURL.path, contents: Data([0x02]))

        let metadataURL = tempDirectory.appendingPathComponent("recordings_metadata_v2.json")
        try Data("{}".utf8).write(to: metadataURL)

        let removed = RecordingOrphanCleanup.removeOrphans(
            in: tempDirectory,
            referencedFileNames: [referenced]
        )

        XCTAssertEqual(removed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: referencedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path))
    }
}

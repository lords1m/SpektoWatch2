import XCTest
@testable import SpektoWatch2

/// Regression tests for M22 task-2 (WatchConnectivity transfer pipeline).
/// The watch-only paths (WC-2 outstanding-transfer dedupe, WC-4 cancel,
/// WC-6 failed transfer → `.local`) need a paired device and are covered by
/// the task-8 hardware matrix.
final class M22WatchTransferRegressionTests: XCTestCase {

    private var tempDir: URL!
    private var savedTimeout: TimeInterval = 0

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M22WC-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        savedTimeout = WatchConnectivityManager.stagedTransferTimeout
    }

    override func tearDown() {
        WatchConnectivityManager.stagedTransferTimeout = savedTimeout
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        for key in WatchAppSettingsSync.timestampedKeys {
            UserDefaults.standard.removeObject(forKey: WatchAppSettingsSync.timestampKey(key))
        }
        super.tearDown()
    }

    private func transferMetadata(id: UUID, kind: WatchConnectivityProtocol.RecordingFileKind) throws -> [String: Any] {
        let meta = WatchRecordingMetadata(
            id: id,
            title: "Watch",
            sampleRate: 48_000,
            weighting: "A",
            audioFileName: "\(id.uuidString).caf",
            measurementFileName: "\(id.uuidString).swr"
        )
        return WatchConnectivityProtocol.makeRecordingFileTransferMetadata(
            id: id, kind: kind, metadata: try JSONEncoder().encode(meta))
    }

    // MARK: - WC-1

    func testStagedFileSurvivesInboxDeletionAfterDelegateReturns() throws {
        let manager = WatchConnectivityManager()
        let id = UUID()
        let inbox = tempDir.appendingPathComponent("inbox.caf")
        try Data(repeating: 7, count: 128).write(to: inbox)

        let staged = try XCTUnwrap(manager.stageIncomingRecordingFile(
            at: inbox, metadata: try transferMetadata(id: id, kind: .audio)))
        // WatchConnectivity deletes its inbox file once the delegate returns.
        try? FileManager.default.removeItem(at: inbox)

        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.url.path))
        XCTAssertEqual(try Data(contentsOf: staged.url).count, 128)
        XCTAssertEqual(staged.id, id)
        try? FileManager.default.removeItem(at: staged.url)
    }

    func testMalformedTransferMetadataIsNotStaged() throws {
        let manager = WatchConnectivityManager()
        let inbox = tempDir.appendingPathComponent("junk.caf")
        try Data([1]).write(to: inbox)
        XCTAssertNil(manager.stageIncomingRecordingFile(at: inbox, metadata: ["foo": "bar"]))
    }

    // MARK: - WC-3

    func testLoneAudioFileIngestsAudioOnlyAfterTimeoutWithoutFurtherTraffic() throws {
        WatchConnectivityManager.stagedTransferTimeout = 0.2
        let manager = WatchConnectivityManager()
        let id = UUID()
        let ingested = expectation(description: "audio-only ingest")
        manager.onWatchRecordingReceived = { recording in
            XCTAssertEqual(recording.id, id)
            XCTAssertNil(recording.measurementDataFileName, "no sidecar → audio-only")
            ingested.fulfill()
            return false // no ack / no WCSession traffic in the unit test
        }

        let inbox = tempDir.appendingPathComponent("lone.caf")
        try Data(repeating: 1, count: 64).write(to: inbox)
        let staged = try XCTUnwrap(manager.stageIncomingRecordingFile(
            at: inbox, metadata: try transferMetadata(id: id, kind: .audio)))
        manager.handleStagedRecordingFile(staged)

        wait(for: [ingested], timeout: 3)
        try? FileManager.default.removeItem(at: staged.url)
    }

    // MARK: - WC-5

    func testStalePhoneContextDoesNotOverwriteNewerWatchGain() {
        let defaults = UserDefaults.standard
        let gainKey = PersistenceKeys.Watch.gain
        WatchAppSettingsSync.markLocalChange(gainKey, at: Date(timeIntervalSince1970: 2_000))

        let stale: [String: Any] = [
            gainKey: Float(3.0),
            WatchAppSettingsSync.timestampKey(gainKey): 1_000.0,
        ]
        XCTAssertFalse(WatchAppSettingsSync.shouldApply(gainKey, from: stale, defaults: defaults))

        let legacyNoStamp: [String: Any] = [gainKey: Float(3.0)]
        XCTAssertFalse(WatchAppSettingsSync.shouldApply(gainKey, from: legacyNoStamp, defaults: defaults),
                       "A pre-M22 phone (no timestamp) must not revert a watch-side edit")

        let newer: [String: Any] = [
            gainKey: Float(3.0),
            WatchAppSettingsSync.timestampKey(gainKey): 3_000.0,
        ]
        XCTAssertTrue(WatchAppSettingsSync.shouldApply(gainKey, from: newer, defaults: defaults))
    }

    func testUnchangedKeysKeepTheirPreviousTimestamp() {
        let gainKey = PersistenceKeys.Watch.gain
        let sourceKey = PersistenceKeys.Watch.measurementSourcePreference
        let previous: [String: Any] = [
            gainKey: Float(2.0),
            WatchAppSettingsSync.timestampKey(gainKey): 100.0,
            sourceKey: "iPhone",
            WatchAppSettingsSync.timestampKey(sourceKey): 100.0,
        ]
        let stamped = WatchAppSettingsSync.stampingChangedKeys(
            [gainKey: Float(2.0), sourceKey: "appleWatch"],
            previous: previous,
            now: Date(timeIntervalSince1970: 500)
        )
        XCTAssertEqual(stamped[WatchAppSettingsSync.timestampKey(gainKey)] as? Double, 100)
        XCTAssertEqual(stamped[WatchAppSettingsSync.timestampKey(sourceKey)] as? Double, 500)
    }
}

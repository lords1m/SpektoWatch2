import XCTest
@testable import SpektoWatch2

/// Tests covering the durability / correctness acceptance criteria for
/// M15 task-1-recording-persistence-durability:
///   - soft-delete sidecar survives a simulated process kill
///   - committing a soft-delete clears the sidecar permanently
///   - a corrupt sidecar does not crash the manager on launch
///   - `MeasurementDataWriter` throws on an unwritable URL
///   - `Recording` decode rejects entries without an `id` and the
///     `RecordingManager` load path skips them rather than aborting.
///
/// Tests run against the real Documents/Recordings directory — see
/// AGENT.md M18 backlog for the planned test-isolation work. Each test
/// scopes its assertions to recordings it created itself and cleans
/// them up in tearDown to avoid polluting other tests.
@MainActor
final class RecordingPersistenceDurabilityTests: XCTestCase {

    private var createdRecordingIDs: Set<UUID> = []
    private var extraFilesToClean: [URL] = []
    private var metadataBackup: Data?

    private var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("Recordings", isDirectory: true)
    }

    private var sidecarURL: URL {
        recordingsDirectory.appendingPathComponent("recordings_pending_soft_delete.json")
    }

    private var metadataURL: URL {
        recordingsDirectory.appendingPathComponent("recordings_metadata_v2.json")
    }

    override func setUp() async throws {
        try await super.setUp()
        createdRecordingIDs.removeAll()
        extraFilesToClean.removeAll()
        metadataBackup = nil
        try? FileManager.default.removeItem(at: sidecarURL)
        // Back up real metadata so test writes can't corrupt it.
        metadataBackup = try? Data(contentsOf: metadataURL)
        if metadataBackup != nil {
            try? FileManager.default.removeItem(at: metadataURL)
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: metadataURL)
        if let backup = metadataBackup {
            try? backup.write(to: metadataURL, options: .atomic)
        }
        metadataBackup = nil
        // Drop the test recordings we added so we don't pollute the
        // user's recordings directory or other test cases.
        let manager = RecordingManager()
        let ids = createdRecordingIDs.intersection(Set(manager.recordings.map { $0.id }))
        if !ids.isEmpty {
            manager.deleteRecordings(ids: ids)
        }
        try? FileManager.default.removeItem(at: sidecarURL)
        for url in extraFilesToClean {
            try? FileManager.default.removeItem(at: url)
        }
        createdRecordingIDs.removeAll()
        extraFilesToClean.removeAll()
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Builds a Recording with a placeholder backing audio file so
    /// `addRecording` has something to persist. Returns the stored
    /// Recording after the manager has assigned its final file names.
    @discardableResult
    private func addPlaceholderRecording(named name: String, to manager: RecordingManager) -> Recording {
        let id = UUID()
        // Park a tiny placeholder audio file in the recordings directory
        // so `persistRecordingFile` finds something to move/keep.
        let placeholderURL = recordingsDirectory.appendingPathComponent("\(id.uuidString)-seed.caf")
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: placeholderURL.path, contents: Data([0x00]))

        let recording = Recording(
            id: id,
            name: name,
            startDate: Date(),
            duration: 0.1,
            audioFileName: placeholderURL.path
        )
        manager.addRecording(recording)
        createdRecordingIDs.insert(id)
        return manager.recordings.first(where: { $0.id == id }) ?? recording
    }

    // MARK: - Soft-delete sidecar durability

    func test_softDelete_sidecarSurvivesProcessDeath() {
        var manager: RecordingManager? = RecordingManager()
        let r1 = addPlaceholderRecording(named: "Durability Test 1", to: manager!)
        let r2 = addPlaceholderRecording(named: "Durability Test 2", to: manager!)

        manager!.softDeleteRecordings(ids: [r1.id, r2.id])

        XCTAssertTrue(manager!.hasPendingSoftDelete,
                      "Manager should report a pending soft-delete batch")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path),
                      "Sidecar file must be written before metadata is updated")
        XCTAssertFalse(manager!.recordings.contains(where: { $0.id == r1.id }))
        XCTAssertFalse(manager!.recordings.contains(where: { $0.id == r2.id }))

        // Simulate process death: drop the manager without committing
        // or invoking undo. ARC releases the instance; no deinit-driven
        // commit should run.
        manager = nil

        // Sidecar must still be on disk — the deferred deletion never
        // ran, and we never committed.
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path),
                      "Sidecar should survive the manager being deallocated without commit")

        // Fresh launch: the restore path should rehydrate both rows
        // and remove the sidecar afterwards.
        let revived = RecordingManager()
        XCTAssertTrue(revived.recordings.contains(where: { $0.id == r1.id }),
                      "Recording 1 should be restored after restart")
        XCTAssertTrue(revived.recordings.contains(where: { $0.id == r2.id }),
                      "Recording 2 should be restored after restart")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path),
                       "Sidecar should be removed once its contents are restored")
    }

    func test_softDelete_commitRemovesSidecar() {
        let manager = RecordingManager()
        let r = addPlaceholderRecording(named: "Commit Test", to: manager)

        manager.softDeleteRecordings(ids: [r.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path),
                      "Sidecar should exist immediately after soft-delete")

        manager.commitPendingSoftDeletes()

        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path),
                       "Sidecar should be removed once the deletion is committed")
        XCTAssertFalse(manager.hasPendingSoftDelete,
                       "No pending batch should remain after commit")

        // Fresh manager: the recording must be permanently gone.
        let revived = RecordingManager()
        XCTAssertFalse(revived.recordings.contains(where: { $0.id == r.id }),
                       "Committed soft-delete must not be reversible on next launch")
        // We don't need to clean this id up — it's already deleted.
        createdRecordingIDs.remove(r.id)
    }

    func test_corruptSidecar_loadsCleanly() {
        // Make sure the recordings directory exists before we write to it.
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        let garbage = Data("not valid json at all { [".utf8)
        try? garbage.write(to: sidecarURL, options: .atomic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path),
                      "Precondition: corrupt sidecar must be on disk")

        // Should not crash, should not throw, should leave the manager
        // in a usable state.
        let manager = RecordingManager()
        XCTAssertNotNil(manager)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path),
                       "Corrupt sidecar should be discarded during launch so it doesn't block future loads")
    }

    // MARK: - MeasurementDataWriter throwing header

    func test_measurementDataWriter_initThrowsOnUnwritableURL() {
        // `/dev/null/...` cannot be a valid parent — FileHandle init
        // (and/or createFile) will fail. Any throw from the init is a
        // pass; the contract is "no half-built writer hands you a
        // corrupt file".
        let unwritable = URL(fileURLWithPath: "/dev/null/spekto-unwritable.spekto")

        XCTAssertThrowsError(
            try MeasurementDataWriter(
                fileURL: unwritable,
                metricKeys: ["LAF"],
                sampleRate: 44_100,
                fps: 86.0,
                fftBlockSize: 4096,
                fftBinCount: 0
            ),
            "Writer init must throw rather than silently producing a half-built file"
        )

        // Sanity: nothing parseable was left on disk at the URL.
        if FileManager.default.fileExists(atPath: unwritable.path) {
            extraFilesToClean.append(unwritable)
            XCTAssertNil(try? MeasurementDataReader(fileURL: unwritable),
                         "Any file left behind must not contain a valid header")
        }
    }

    // MARK: - Strict UUID decode

    func test_recording_decodeWithMissingID_throws() {
        // Direct decode: missing `id` must throw on a single Recording.
        let missingIDJSON = Data("""
        {
            "name": "No ID",
            "startDate": "2026-05-24T12:00:00Z",
            "duration": 1.0,
            "audioFileName": "nope.caf",
            "sampleRate": 44100,
            "channelCount": 1,
            "laeqFast": -60,
            "peakLevel": -50,
            "minLevel": -80,
            "photoFileNames": [],
            "tags": [],
            "timeWeighting": "Fast",
            "frequencyWeighting": "A",
            "calibrationOffset": 94,
            "fftBlockSize": 4096
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(Recording.self, from: missingIDJSON),
                             "Decoding a Recording without `id` must throw")

        // End-to-end: write a metadata file with one valid + one
        // broken entry and confirm `RecordingManager` skips only the
        // broken row.
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let validID = UUID()
        let validIDString = validID.uuidString
        let metadataJSON = Data("""
        [
            {
                "id": "\(validIDString)",
                "name": "Good Row",
                "startDate": "2026-05-24T12:00:00Z",
                "duration": 1.0,
                "audioFileName": "good.caf",
                "sampleRate": 44100,
                "channelCount": 1,
                "laeqFast": -60,
                "peakLevel": -50,
                "minLevel": -80,
                "photoFileNames": [],
                "tags": [],
                "timeWeighting": "Fast",
                "frequencyWeighting": "A",
                "calibrationOffset": 94,
                "fftBlockSize": 4096
            },
            {
                "name": "Bad Row (no id)",
                "startDate": "2026-05-24T12:00:00Z",
                "duration": 1.0,
                "audioFileName": "bad.caf",
                "sampleRate": 44100,
                "channelCount": 1,
                "laeqFast": -60,
                "peakLevel": -50,
                "minLevel": -80,
                "photoFileNames": [],
                "tags": [],
                "timeWeighting": "Fast",
                "frequencyWeighting": "A",
                "calibrationOffset": 94,
                "fftBlockSize": 4096
            }
        ]
        """.utf8)
        try? metadataJSON.write(to: metadataURL, options: .atomic)

        let manager = RecordingManager()
        let valid = manager.recordings.filter { $0.id == validID }
        XCTAssertEqual(valid.count, 1,
                       "The well-formed row should load even when a neighbour is corrupt")
        XCTAssertEqual(manager.recordings.count, 1,
                       "The row without `id` should be dropped, not minted a new UUID")
    }
}

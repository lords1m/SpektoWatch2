import XCTest
@testable import SpektoWatch2

/// Regression tests for M22 task-1 (data-loss & persistence, DL-1…DL-14).
/// All file-system tests run in an isolated temp directory.
@MainActor
final class M22DataLossRegressionTests: XCTestCase {

    private var tempBase: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("M22DL-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempBase { try? FileManager.default.removeItem(at: tempBase) }
        tempBase = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private var recordingsDir: URL { tempBase.appendingPathComponent("Recordings", isDirectory: true) }

    private static let metricKeys = ["LAF", "LAeq"]

    private func makeWriter(_ url: URL, version: UInt16, fps: Float = 10) throws -> MeasurementDataWriter {
        try MeasurementDataWriter(
            fileURL: url,
            metricKeys: Self.metricKeys,
            sampleRate: 48_000,
            fps: fps,
            fftBlockSize: 4096,
            fftBinCount: 0,
            fileFormatVersion: version
        )
    }

    private func writeFrame(_ writer: MeasurementDataWriter, t: Float, value: Float = 60) throws {
        let bands = [Float](repeating: 40, count: MeasurementDataFormat.thirdOctaveBandCount)
        try writer.writeFrame(
            timestamp: t,
            metricValues: [value, value],
            broadbandLevel: value,
            thirdOctaveZ: bands,
            thirdOctaveA: bands,
            thirdOctaveC: bands,
            fullFFT: []
        )
    }

    private func patch(_ url: URL, offset: UInt64, bytes: [UInt8]) throws {
        let handle = try FileHandle(forUpdating: url)
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: Data(bytes))
        try handle.close()
    }

    // MARK: - DL-2 sidecar vs orphan sweep

    private struct SidecarFixture: Encodable {
        let timestamp: Date
        let recordings: [Recording]
    }

    func testSoftDeletedFilesSurviveRelaunchOrphanSweep() throws {
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let audioName = "\(UUID().uuidString).caf"
        let audioURL = recordingsDir.appendingPathComponent(audioName)
        try Data([1, 2, 3]).write(to: audioURL)
        let recording = Recording(name: "Soft", startDate: Date(), duration: 1, audioFileName: audioName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([Recording]()).write(to: recordingsDir.appendingPathComponent("recordings_metadata_v2.json"))
        try encoder.encode(SidecarFixture(timestamp: Date(), recordings: [recording]))
            .write(to: recordingsDir.appendingPathComponent("recordings_pending_soft_delete.json"))

        let manager = RecordingManager(baseDirectory: tempBase)

        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path),
                      "Orphan sweep must not delete files referenced by the soft-delete sidecar")
        XCTAssertTrue(manager.recordings.contains { $0.id == recording.id },
                      "Sidecar recording must be restored")
    }

    // MARK: - DL-3 ack only on persist

    func testIngestWatchRecordingFailsWhenAudioMissing() {
        let manager = RecordingManager(baseDirectory: tempBase)
        let recording = Recording(
            name: "Missing",
            startDate: Date(),
            duration: 1,
            audioFileName: tempBase.appendingPathComponent("does-not-exist.caf").path
        )
        XCTAssertFalse(manager.ingestWatchRecording(recording))
        XCTAssertFalse(manager.recordings.contains { $0.id == recording.id })
    }

    func testIngestWatchRecordingSucceedsWithAudio() throws {
        let manager = RecordingManager(baseDirectory: tempBase)
        let audio = tempBase.appendingPathComponent("watch.caf")
        try Data([0, 1]).write(to: audio)
        let recording = Recording(name: "Watch", startDate: Date(), duration: 1, audioFileName: audio.path)
        XCTAssertTrue(manager.ingestWatchRecording(recording))
        XCTAssertTrue(manager.ingestWatchRecording(recording), "Idempotent by id")
    }

    // MARK: - DL-4 crash-safe .spekto

    func testUnfinalizedV2FileRecoversFramesFromFileSize() throws {
        let url = tempBase.appendingPathComponent("crash.spekto")
        let writer = try makeWriter(url, version: MeasurementDataFormat.version2)
        for i in 0..<7 { try writeFrame(writer, t: Float(i) * 0.1) }
        try writer.close()
        // Simulate a crash before close(): header frame count never patched.
        try patch(url, offset: UInt64(MeasurementDataFormat.frameCountOffset), bytes: [UInt8](repeating: 0, count: 8))

        let reader = try MeasurementDataReader(fileURL: url)
        XCTAssertEqual(reader.frameCount, 7)
        XCTAssertTrue(reader.isRecovered)
        XCTAssertEqual(try reader.readFrame(at: 6).timestamp, 0.6, accuracy: 1e-5)
    }

    func testUnfinalizedV3FileRecoversFramesAndIgnoresPartialFrame() throws {
        let url = tempBase.appendingPathComponent("crash3.spekto")
        let writer = try makeWriter(url, version: MeasurementDataFormat.version3)
        for i in 0..<5 { try writeFrame(writer, t: Float(i) * 0.1) }
        try writer.close()
        let finalized = try MeasurementDataReader(fileURL: url)
        let headerSize = UInt64(finalized.header.headerSize)
        let frameSize = UInt64(finalized.frameSize)

        // Strip the trailer, leave half a frame dangling, clear CRC/seek/count.
        let handle = try FileHandle(forUpdating: url)
        try handle.truncate(atOffset: headerSize + 5 * frameSize + frameSize / 2)
        try handle.close()
        try patch(url, offset: UInt64(MeasurementDataFormat.frameCountOffset), bytes: [UInt8](repeating: 0, count: 8))
        try patch(url, offset: UInt64(MeasurementDataFormat.v3HeaderCRCOffset), bytes: [UInt8](repeating: 0, count: 4))
        try patch(url, offset: UInt64(MeasurementDataFormat.v3SeekIndexOffsetField), bytes: [UInt8](repeating: 0, count: 8))

        let reader = try MeasurementDataReader(fileURL: url)
        XCTAssertEqual(reader.frameCount, 5)
        XCTAssertTrue(reader.isRecovered)
    }

    // MARK: - DL-6 untrusted counts

    func testHugeFrameCountThrowsInsteadOfTrapping() throws {
        let url = tempBase.appendingPathComponent("huge.spekto")
        let writer = try makeWriter(url, version: MeasurementDataFormat.version2)
        for i in 0..<3 { try writeFrame(writer, t: Float(i)) }
        try writer.close()
        try patch(url, offset: UInt64(MeasurementDataFormat.frameCountOffset), bytes: [UInt8](repeating: 0xFF, count: 8))
        XCTAssertThrowsError(try MeasurementDataReader(fileURL: url))
    }

    func testSeekIndexWithOversizedCountIsRejected() {
        var data = Data()
        data.appendUInt32LE(MeasurementDataFormat.seekIndexMagic)
        data.appendUInt64LE(UInt64.max / 2)
        data.appendUInt64LE(64)
        XCTAssertNil(MeasurementDataV3Support.decodeSeekIndex(from: data))
    }

    // MARK: - DL-8 dashboard lossy decode

    func testUnknownWidgetTypeDropsOnlyThatWidget() throws {
        let good = WidgetConfiguration(type: .spectrogram, size: WidgetSize(columns: 2, rows: 2))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode([good, good])) as! [[String: Any]]
        json[1]["type"] = "Hologramm-Widget-aus-der-Zukunft"
        let slot: [String: Any] = ["presetID": "overview", "widgets": json]
        let data = try JSONSerialization.data(withJSONObject: slot)

        let decoded = try JSONDecoder().decode(PresetSlot.self, from: data)
        XCTAssertEqual(decoded.widgets.count, 1)
        XCTAssertEqual(decoded.widgets.first?.type, .spectrogram)
    }

    func testLegacyCaseNameWidgetTypeDecodes() throws {
        let data = Data("\"waterfall\"".utf8)
        XCTAssertEqual(try JSONDecoder().decode(AudioWidgetType.self, from: data), .waterfall)
    }

    func testCorruptDashboardBackupIsWritten() {
        let url = DashboardManager.backupCorruptConfiguration(Data("{oops".utf8), directory: tempBase)
        XCTAssertNotNil(url)
        if let url { XCTAssertEqual(try? Data(contentsOf: url), Data("{oops".utf8)) }
    }

    // MARK: - DL-9 masking profiles

    func testCorruptMaskingProfilesAreBackedUpAndNotOverwritten() throws {
        let dir = tempBase.appendingPathComponent("Masking", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("profiles.json")
        let corrupt = Data("[{\"broken\": true".utf8)
        try corrupt.write(to: file)

        let manager = MaskingProfileManager(directory: dir)
        XCTAssertTrue(manager.loadFailed)
        manager.delete(offsets: IndexSet()) // would persist() the empty list

        XCTAssertEqual(try Data(contentsOf: file), corrupt, "profiles.json must stay untouched")
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("profiles.corrupt-") }
        XCTAssertEqual(backups.count, 1)
    }

    // MARK: - DL-10 calibration override

    func testCalibrationOverrideIsNotPersisted() {
        let defaults = UserDefaults.standard
        let engine = AudioEngine(filterManager: BandstopFilterManager(), connectivityManager: WatchConnectivityManager())
        let original = engine.calibrationOffset
        defer { engine.calibrationOffset = original }

        engine.calibrationOffset = 91.5
        engine.setCalibrationOverride(120)
        XCTAssertEqual(engine.effectiveCalibrationOffset, 120)
        XCTAssertEqual(engine.calibrationOffset, 91.5)
        XCTAssertEqual(CalibrationProvider.resolveStartupOffset(defaults: defaults), 91.5, accuracy: 0.001)
        engine.setCalibrationOverride(nil)
        XCTAssertEqual(engine.effectiveCalibrationOffset, 91.5)
    }

    // MARK: - DL-11 JSON NaN

    func testJSONExportWritesNullForNonFiniteValues() throws {
        let url = tempBase.appendingPathComponent("nan.spekto")
        let writer = try makeWriter(url, version: MeasurementDataFormat.version3)
        try writeFrame(writer, t: 0, value: .nan)
        try writeFrame(writer, t: 0.1, value: .infinity)
        try writer.close()

        let reader = try MeasurementDataReader(fileURL: url)
        let out = tempBase.appendingPathComponent("out.json")
        let recording = Recording(name: "NaN", startDate: Date(), duration: 0.2, audioFileName: "x.caf")
        XCTAssertNoThrow(try JSONMeasurementExporter().export(recording: recording, reader: reader, to: out))
        let text = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(text.contains("null"))
        XCTAssertEqual(ExportValueSanitizer.csv(.nan), "")
    }

    // MARK: - DL-12 timestamp-based frame lookup

    func testFrameLookupUsesStoredTimestampsWhenFramesWereDropped() throws {
        let url = tempBase.appendingPathComponent("gaps.spekto")
        let writer = try makeWriter(url, version: MeasurementDataFormat.version3, fps: 10)
        // Frames 0.3 and 0.4 were dropped under back-pressure.
        for t: Float in [0.0, 0.1, 0.2, 0.5, 0.6, 0.7] { try writeFrame(writer, t: t) }
        try writer.close()

        let reader = try MeasurementDataReader(fileURL: url)
        XCTAssertEqual(reader.frameIndex(forTime: 0.55), 3)
        XCTAssertEqual(reader.frameIndex(forTime: 0.0), 0)
        XCTAssertEqual(reader.frameIndex(forTime: 99), 5)
        XCTAssertEqual(reader.frameIndex(forTime: 0.35), 2)
    }

    // MARK: - DL-13 unaligned float copy

    func testCopyFloatsFromUnalignedOffset() {
        var data = Data([0xAB]) // 1-byte prefix → floats start unaligned
        for value: Float in [1.5, -2.25, 1000] {
            var bits = value.bitPattern.littleEndian
            data.append(Data(bytes: &bits, count: 4))
        }
        XCTAssertEqual(SpectrogramData.copyFloats(from: data, byteOffset: 1, count: 3), [1.5, -2.25, 1000])
        XCTAssertEqual(SpectrogramData.copyFloats(from: data, byteOffset: 1, count: 4), [0, 0, 0, 0],
                       "Out-of-range reads return zeros instead of reading past the buffer")
    }
}

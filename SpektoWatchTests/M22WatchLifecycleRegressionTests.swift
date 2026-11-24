import XCTest
import AVFoundation
@testable import SpektoWatch_Watch_App

/// Regression tests for M22 task-3 (watch lifecycle & configuration).
/// Background runtime, force-quit recovery on device and complication
/// refresh without the phone are hardware items in task-8.
final class M22WatchLifecycleRegressionTests: XCTestCase {

    private var tempBase: URL!

    override func setUp() {
        super.setUp()
        tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("M22WL-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempBase { try? FileManager.default.removeItem(at: tempBase) }
        super.tearDown()
    }

    // MARK: - WL-1 / WL-4 runtime-session invalidation policy

    func testInvalidationFromStaleSessionIsIgnored() {
        XCTAssertEqual(
            WatchAudioEngine.runtimeInvalidationAction(isCurrentSession: false, didStart: true, hasError: false, isRecording: true),
            .ignore
        )
    }

    func testStartFailureKeepsRecording() {
        XCTAssertEqual(
            WatchAudioEngine.runtimeInvalidationAction(isCurrentSession: true, didStart: false, hasError: true, isRecording: true),
            .keepRecordingWithWarning
        )
    }

    func testExpiryOfStartedSessionStopsAndReleases() {
        XCTAssertEqual(
            WatchAudioEngine.runtimeInvalidationAction(isCurrentSession: true, didStart: true, hasError: false, isRecording: true),
            .stopAndRelease
        )
    }

    // MARK: - WL-2 crash-safe catalog

    private func writeAudio(to url: URL, seconds: Double = 0.5) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)
    }

    func testInProgressEntryIsRecoveredOnLaunchNotDeleted() throws {
        let id = UUID()
        let store1 = WatchRecordingStore(baseDirectory: tempBase)
        let audio = store1.directory.appendingPathComponent("\(id.uuidString).caf")
        try writeAudio(to: audio)
        store1.beginRecording(WatchRecordingMetadata(
            id: id,
            title: "Aufnahme",
            sampleRate: 44_100,
            weighting: "A",
            audioFileName: audio.lastPathComponent,
            measurementFileName: "\(id.uuidString).swr"
        ))
        // Simulated crash: no finalize/register. Relaunch:
        let store2 = WatchRecordingStore(baseDirectory: tempBase)
        let recovered = try XCTUnwrap(store2.recordings.first { $0.id == id })
        XCTAssertNil(recovered.isInProgress)
        XCTAssertEqual(recovered.syncState, .local)
        XCTAssertGreaterThan(recovered.duration, 0.4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }

    func testUncataloguedReadableAudioIsRecataloguedAndJunkRemoved() throws {
        let store = WatchRecordingStore(baseDirectory: tempBase)
        let id = UUID()
        let audio = store.directory.appendingPathComponent("\(id.uuidString).caf")
        try writeAudio(to: audio)
        let junk = store.directory.appendingPathComponent("\(UUID().uuidString).caf")
        try Data([0, 1, 2]).write(to: junk)

        let relaunched = WatchRecordingStore(baseDirectory: tempBase)
        XCTAssertTrue(relaunched.recordings.contains { $0.id == id })
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: junk.path))
    }

    func testInProgressEntriesAreHiddenFromFinishedList() {
        let store = WatchRecordingStore(baseDirectory: tempBase)
        store.beginRecording(WatchRecordingMetadata(
            title: "x", sampleRate: 44_100, weighting: "A",
            audioFileName: "a.caf", measurementFileName: "a.swr"))
        XCTAssertEqual(store.recordings.count, 1)
        XCTAssertTrue(store.finishedRecordings.isEmpty)
    }

    // MARK: - WL-7 level graph range

    func testLevelDisplayRangeMapsSPL() {
        XCTAssertEqual(LevelDisplayRange.normalized(20), 0)
        XCTAssertEqual(LevelDisplayRange.normalized(120), 1)
        XCTAssertEqual(LevelDisplayRange.normalized(70), 0.5, accuracy: 1e-6)
        XCTAssertEqual(LevelDisplayRange.normalized(-60), 0, "dBFS-style values clamp instead of flat-lining at the top")
        XCTAssertEqual(LevelDisplayRange.normalized(.nan), 0)
    }

    func testTimeWindowUsesTimestamps() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(DisplayTimeWindow.seconds(oldest: t0, newest: t0.addingTimeInterval(24)), 24)
        XCTAssertEqual(DisplayTimeWindow.seconds(oldest: nil, newest: t0), 0)
    }

    func testRingBufferOldestNewest() {
        var ring = RingBuffer<Int>(capacity: 3)
        XCTAssertNil(ring.oldest)
        [1, 2, 3, 4].forEach { ring.append($0) }
        XCTAssertEqual(ring.oldest, 2)
        XCTAssertEqual(ring.newest, 4)
    }
}

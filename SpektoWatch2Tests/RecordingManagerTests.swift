import XCTest
@testable import SpektoWatch2

/// Tests für RecordingManager - Testet Datei-I/O, Metadaten-Verwaltung und Recording-Lifecycle
@MainActor
final class RecordingManagerTests: XCTestCase {
    
    var recordingManager: RecordingManager!
    var filterManager: BandstopFilterManager!
    var connectivityManager: WatchConnectivityManager!
    var audioEngine: AudioEngine!
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        recordingManager = RecordingManager(baseDirectory: tempDir)
        filterManager = BandstopFilterManager()
        connectivityManager = WatchConnectivityManager()
        audioEngine = AudioEngine(filterManager: filterManager, connectivityManager: connectivityManager)
    }

    override func tearDown() async throws {
        audioEngine = nil
        connectivityManager = nil
        filterManager = nil
        recordingManager = nil
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDir = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    /// Testet dass RecordingManager korrekt initialisiert wird
    func testInitialization() {
        XCTAssertNotNil(recordingManager, "RecordingManager should initialize")
        XCTAssertFalse(recordingManager.isRecording, "Should not be recording initially")
        XCTAssertEqual(recordingManager.currentRecordingDuration, 0, "Duration should be 0")
    }
    
    /// Testet Recordings-Directory Erstellung
    func testRecordingsDirectoryCreated() {
        // Start und stop recording um directory zu erstellen
        _ = recordingManager.startRecording(audioEngine: audioEngine)
        
        let expectation = XCTestExpectation(description: "Stop recording")
        recordingManager.stopRecording(audioEngine: audioEngine) { _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        let recordingsPath = tempDir.appendingPathComponent("Recordings")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingsPath.path),
                     "Recordings directory should be created")
    }
    
    // MARK: - Recording Lifecycle Tests
    
    /// Testet Start einer Recording
    func testStartRecording() {
        let success = recordingManager.startRecording(audioEngine: audioEngine)
        
        XCTAssertTrue(success, "Recording should start successfully")
        XCTAssertTrue(recordingManager.isRecording, "Should be recording after start")
        
        // Cleanup
        let expectation = XCTestExpectation(description: "Stop")
        recordingManager.stopRecording(audioEngine: audioEngine) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 2.0)
    }
    
    /// Testet dass zweites Start fehlschlägt während Recording läuft
    func testStartRecordingWhileRecording() {
        _ = recordingManager.startRecording(audioEngine: audioEngine)
        
        let secondStart = recordingManager.startRecording(audioEngine: audioEngine)
        XCTAssertFalse(secondStart, "Second start should fail while recording")
        
        // Cleanup
        let expectation = XCTestExpectation(description: "Stop")
        recordingManager.stopRecording(audioEngine: audioEngine) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 2.0)
    }
    
    /// Testet Stop einer Recording
    func testStopRecording() {
        _ = recordingManager.startRecording(audioEngine: audioEngine)
        
        let expectation = XCTestExpectation(description: "Stop recording")
        var audioURL: URL?
        
        recordingManager.stopRecording(audioEngine: audioEngine) { url in
            audioURL = url
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertFalse(recordingManager.isRecording, "Should not be recording after stop")
        XCTAssertNotNil(audioURL, "Should return audio URL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL!.path),
                     "Audio file should exist")
    }
    
    /// Testet Stop ohne laufende Recording
    func testStopRecordingWithoutStart() {
        let expectation = XCTestExpectation(description: "Stop without start")
        var result: URL?
        
        recordingManager.stopRecording(audioEngine: audioEngine) { url in
            result = url
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertNil(result, "Should return nil when stopping without recording")
    }
    
    /// Testet Recording-Duration-Timer
    func testRecordingDurationTimer() {
        _ = recordingManager.startRecording(audioEngine: audioEngine)
        
        // Warte 0.5 Sekunden
        let durationExpectation = XCTestExpectation(description: "Duration increases")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertGreaterThan(self.recordingManager.currentRecordingDuration, 0.3,
                               "Duration should increase over time")
            durationExpectation.fulfill()
        }
        
        wait(for: [durationExpectation], timeout: 1.0)
        
        // Cleanup
        let stopExpectation = XCTestExpectation(description: "Stop")
        recordingManager.stopRecording(audioEngine: audioEngine) { _ in stopExpectation.fulfill() }
        wait(for: [stopExpectation], timeout: 2.0)
    }
    
    // MARK: - Metadata Tests
    
    /// Testet Speicherung von Recording mit Metadaten
    func testSaveRecordingWithMetadata() throws {
        _ = recordingManager.startRecording(audioEngine: audioEngine)
        
        let stopExpectation = XCTestExpectation(description: "Stop")
        var audioURL: URL?
        
        recordingManager.stopRecording(audioEngine: audioEngine) { url in
            audioURL = url
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 2.0)
        
        guard let url = audioURL else {
            XCTFail("No audio URL")
            return
        }
        
        let testName = "Test Recording"
        let testDescription = "Test Description"
        let initialCount = recordingManager.recordings.count
        
        let stats = audioEngine.getRecordingStatistics()
        let recording = Recording(
            name: testName,
            description: testDescription,
            startDate: Date(),
            duration: recordingManager.currentRecordingDuration,
            audioFileName: url.path,
            laeqFast: stats.laeqFast,
            peakLevel: stats.peak,
            minLevel: stats.min,
            timeWeighting: audioEngine.timeWeighting.displayName,
            frequencyWeighting: audioEngine.frequencyWeighting.rawValue
        )
        recordingManager.addRecording(recording)
        
        XCTAssertEqual(recordingManager.recordings.count, initialCount + 1,
                      "Should add one recording")
        
        let saved = recordingManager.recordings.first!
        XCTAssertEqual(saved.name, testName, "Name should match")
        XCTAssertEqual(saved.description, testDescription, "Description should match")
        XCTAssertGreaterThan(saved.duration, 0, "Duration should be positive")
        XCTAssertEqual(saved.sampleRate, 44100.0, "Sample rate should be 44100")
    }
    
    /// Testet Default-Name wenn leer
    func testSaveRecordingWithEmptyName() throws {
        _ = recordingManager.startRecording(audioEngine: audioEngine)
        
        let stopExpectation = XCTestExpectation(description: "Stop")
        var audioURL: URL?
        
        recordingManager.stopRecording(audioEngine: audioEngine) { url in
            audioURL = url
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 2.0)
        
        guard let url = audioURL else {
            XCTFail("No audio URL")
            return
        }
        
        let stats = audioEngine.getRecordingStatistics()
        let recording = Recording(
            name: "",
            startDate: Date(),
            duration: recordingManager.currentRecordingDuration,
            audioFileName: url.path,
            laeqFast: stats.laeqFast,
            peakLevel: stats.peak,
            minLevel: stats.min
        )
        recordingManager.addRecording(recording)
        
        let saved = recordingManager.recordings.first!
        // Default name is set during addRecording if empty
        XCTAssertFalse(saved.name.isEmpty, "Should have a name")
    }
    
    // MARK: - CRUD Tests
    
    /// Testet Löschen einer Recording
    func testDeleteRecording() throws {
        // Create recording
        _ = recordingManager.startRecording(audioEngine: audioEngine)
        
        let stopExpectation = XCTestExpectation(description: "Stop")
        var audioURL: URL?
        recordingManager.stopRecording(audioEngine: audioEngine) { url in
            audioURL = url
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 2.0)
        
        guard let url = audioURL else {
            XCTFail("No audio URL")
            return
        }
        
        let stats = audioEngine.getRecordingStatistics()
        let recording = Recording(
            name: "To Delete",
            startDate: Date(),
            duration: recordingManager.currentRecordingDuration,
            audioFileName: url.path,
            laeqFast: stats.laeqFast,
            peakLevel: stats.peak,
            minLevel: stats.min
        )
        recordingManager.addRecording(recording)
        
        let savedRecording = recordingManager.recordings.first!
        let audioFilePath = recordingManager.url(for: savedRecording).path
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioFilePath),
                     "Audio file should exist before deletion")
        
        recordingManager.deleteRecording(at: IndexSet(integer: 0))
        
        XCTAssertFalse(recordingManager.recordings.contains(where: { $0.id == savedRecording.id }),
                      "Recording should be removed from list")
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFilePath),
                      "Audio file should be deleted")
    }
    
    /// Testet URL-Getter
    func testURLForRecording() throws {
        _ = recordingManager.startRecording(audioEngine: audioEngine)
        
        let stopExpectation = XCTestExpectation(description: "Stop")
        var audioURL: URL?
        recordingManager.stopRecording(audioEngine: audioEngine) { url in
            audioURL = url
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 2.0)
        
        guard let url = audioURL else {
            XCTFail("No audio URL")
            return
        }
        
        let stats = audioEngine.getRecordingStatistics()
        let recording = Recording(
            name: "URL Test",
            startDate: Date(),
            duration: recordingManager.currentRecordingDuration,
            audioFileName: url.path,
            laeqFast: stats.laeqFast,
            peakLevel: stats.peak,
            minLevel: stats.min
        )
        recordingManager.addRecording(recording)
        
        let savedRecording = recordingManager.recordings.first!
        let retrievedURL = recordingManager.url(for: savedRecording)
        
        XCTAssertEqual(retrievedURL.lastPathComponent, savedRecording.audioFileName,
                      "URL should match audio filename")
        XCTAssertTrue(FileManager.default.fileExists(atPath: retrievedURL.path),
                     "File should exist at URL")
    }
    
    // MARK: - Statistics Tests
    
    /// Testet dass Recording-Statistiken erfasst werden
    func testRecordingStatisticsCapture() throws {
        // Simuliere Audio-Daten
        let samples = (0..<4096).map { sin(Float($0) * 0.1) * 0.5 }
        
        for _ in 0..<10 {
            audioEngine.processExternalAudio(samples)
        }
        
        _ = recordingManager.startRecording(audioEngine: audioEngine)
        
        let stopExpectation = XCTestExpectation(description: "Stop")
        var audioURL: URL?
        recordingManager.stopRecording(audioEngine: audioEngine) { url in
            audioURL = url
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 2.0)
        
        guard let url = audioURL else {
            XCTFail("No audio URL")
            return
        }
        
        let stats = audioEngine.getRecordingStatistics()
        let recording = Recording(
            name: "Stats Test",
            startDate: Date(),
            duration: recordingManager.currentRecordingDuration,
            audioFileName: url.path,
            laeqFast: stats.laeqFast,
            peakLevel: stats.peak,
            minLevel: stats.min
        )
        recordingManager.addRecording(recording)
        
        let savedRecording = recordingManager.recordings.first!
        
        // Statistiken sollten erfasst sein
        XCTAssertNotEqual(savedRecording.laeqFast, 0, "LAeq should be captured")
        XCTAssertNotEqual(savedRecording.peakLevel, 0, "Peak should be captured")
    }
    
    // MARK: - Persistence Tests
    
    /// Testet Laden von Recordings beim Start
    func testLoadRecordingsOnInit() throws {
        // Create recording
        _ = recordingManager.startRecording(audioEngine: audioEngine)
        
        let stopExpectation = XCTestExpectation(description: "Stop")
        var audioURL: URL?
        recordingManager.stopRecording(audioEngine: audioEngine) { url in
            audioURL = url
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 2.0)
        
        guard let url = audioURL else {
            XCTFail("No audio URL")
            return
        }
        
        let stats = audioEngine.getRecordingStatistics()
        let recording = Recording(
            name: "Persistence Test",
            startDate: Date(),
            duration: recordingManager.currentRecordingDuration,
            audioFileName: url.path,
            laeqFast: stats.laeqFast,
            peakLevel: stats.peak,
            minLevel: stats.min
        )
        recordingManager.addRecording(recording)
        
        let recordingID = recordingManager.recordings.first!.id
        
        let newManager = RecordingManager(baseDirectory: tempDir)
        XCTAssertTrue(newManager.recordings.contains(where: { $0.id == recordingID }),
                     "Recordings should persist across manager instances")
    }
    
    // MARK: - Edge Cases
    
    /// Testet Verhalten mit vielen Recordings
    func testManyRecordings() throws {
        // Erstelle mehrere kleine Recordings
        for i in 0..<5 {
            _ = recordingManager.startRecording(audioEngine: audioEngine)
            
            let stopExpectation = XCTestExpectation(description: "Stop \(i)")
            var audioURL: URL?
            recordingManager.stopRecording(audioEngine: audioEngine) { url in
                audioURL = url
                stopExpectation.fulfill()
            }
            wait(for: [stopExpectation], timeout: 2.0)
            
            if let url = audioURL {
                let stats = audioEngine.getRecordingStatistics()
                let recording = Recording(
                    name: "Recording \(i)",
                    startDate: Date(),
                    duration: recordingManager.currentRecordingDuration,
                    audioFileName: url.path,
                    laeqFast: stats.laeqFast,
                    peakLevel: stats.peak,
                    minLevel: stats.min
                )
                recordingManager.addRecording(recording)
            }
        }
        
        XCTAssertEqual(recordingManager.recordings.count, 5,
                      "Should have 5 recordings")
        
        // Überprüfe Reihenfolge (neueste zuerst)
        XCTAssertEqual(recordingManager.recordings[0].name, "Recording 4")
        XCTAssertEqual(recordingManager.recordings[4].name, "Recording 0")
    }
}

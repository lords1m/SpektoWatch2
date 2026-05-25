#if canImport(UIKit)
import XCTest
@testable import SpektoWatch2
import AVFoundation
import CoreLocation
import PDFKit

@MainActor
final class PDFReportGeneratorTests: XCTestCase {
    
    var pdfGenerator: PDFReportGenerator!
    var recordingManager: RecordingManager!
    var audioEngine: AudioEngine!
    var filterManager: BandstopFilterManager!
    var connectivityManager: WatchConnectivityManager!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        pdfGenerator = PDFReportGenerator()
        filterManager = BandstopFilterManager()
        // Create a new instance for testing
        connectivityManager = WatchConnectivityManager()
        audioEngine = AudioEngine(filterManager: filterManager, connectivityManager: connectivityManager)
        
        // Create unique temp directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        recordingManager = RecordingManager()
    }
    
    override func tearDown() async throws {
        pdfGenerator = nil
        audioEngine = nil
        
        // Clean up temp directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        recordingManager = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Basic PDF Generation Tests
    
    func testGenerateBasicPDFReport() throws {
        let recording = createTestRecording()
        recordingManager.addRecording(recording)

        guard let savedRecording = recordingManager.recordings.first(where: { $0.id == recording.id }) else {
            XCTFail("Should have saved recording")
            return
        }

        let pdfURL = try pdfGenerator.generateReport(for: savedRecording, recordingManager: recordingManager)

        XCTAssertTrue(FileManager.default.fileExists(atPath: pdfURL.path), "PDF file should exist")
        XCTAssertTrue(pdfURL.path.contains("report_"), "PDF should have report_ prefix")
        XCTAssertTrue(pdfURL.pathExtension == "pdf", "File should be PDF")
    }
    
    func testGeneratedPDFIsValid() throws {
        let recording = createTestRecording()
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        // Verify PDF can be loaded
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            XCTFail("Should be able to load PDF document")
            return
        }
        
        // Verify PDF has at least 2 pages (cover + spectrogram page)
        XCTAssertGreaterThanOrEqual(pdfDocument.pageCount, 2, "PDF should have at least 2 pages")
    }
    
    func testPDFContainsExpectedPageCount() throws {
        let recording = createTestRecording()
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            XCTFail("Should load PDF")
            return
        }
        
        // Without photos: 2 pages (summary + spectrogram/bands)
        XCTAssertEqual(pdfDocument.pageCount, 2, "PDF without photos should have 2 pages")
    }
    
    func testPDFWithPhotosHasAdditionalPages() throws {
        let recording = createTestRecordingWithPhoto()
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            XCTFail("Should load PDF")
            return
        }
        
        // With 1 photo: 3 pages (summary + spectrogram/bands + photo)
        XCTAssertEqual(pdfDocument.pageCount, 3, "PDF with 1 photo should have 3 pages")
    }
    
    // MARK: - Content Validation Tests
    
    func testPDFContainsRecordingName() throws {
        let recording = createTestRecording(name: "Test Measurement 123")
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let firstPage = pdfDocument.page(at: 0) else {
            XCTFail("Should load PDF with first page")
            return
        }
        
        let pageText = firstPage.string ?? ""
        XCTAssertTrue(pageText.contains("Test Measurement 123"), "PDF should contain recording name")
    }
    
    func testPDFContainsHeader() throws {
        let recording = createTestRecording()
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let firstPage = pdfDocument.page(at: 0) else {
            XCTFail("Should load PDF")
            return
        }
        
        let pageText = firstPage.string ?? ""
        XCTAssertTrue(pageText.contains("SpektoWatch Messbericht"), "PDF should contain header")
    }
    
    func testPDFContainsSummaryTable() throws {
        let recording = createTestRecording(laeq: 65.5, peakLevel: 85.2)
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let firstPage = pdfDocument.page(at: 0) else {
            XCTFail("Should load PDF")
            return
        }
        
        let pageText = firstPage.string ?? ""
        XCTAssertTrue(pageText.contains("Zusammenfassung"), "PDF should contain summary section")
        XCTAssertTrue(pageText.contains("LAeq"), "PDF should contain LAeq metric")
    }
    
    func testPDFContainsFooter() throws {
        let recording = createTestRecording()
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let firstPage = pdfDocument.page(at: 0) else {
            XCTFail("Should load PDF")
            return
        }
        
        let pageText = firstPage.string ?? ""
        XCTAssertTrue(pageText.contains("Erstellt mit SpektoWatch"), "PDF should contain footer")
        XCTAssertTrue(pageText.contains("Seite"), "PDF should contain page number")
    }
    
    func testPDFSecondPageContainsSpectrogram() throws {
        let recording = createTestRecording()
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let secondPage = pdfDocument.page(at: 1) else {
            XCTFail("Should load PDF with second page")
            return
        }
        
        let pageText = secondPage.string ?? ""
        XCTAssertTrue(pageText.contains("Gesamt-Spektrogramm"), "Second page should contain spectrogram section")
    }
    
    func testPDFSecondPageContainsBandAnalysis() throws {
        let recording = createTestRecording()
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let secondPage = pdfDocument.page(at: 1) else {
            XCTFail("Should load PDF")
            return
        }
        
        let pageText = secondPage.string ?? ""
        XCTAssertTrue(pageText.contains("Terzbandanalyse"), "Second page should contain third-octave band analysis")
        XCTAssertTrue(pageText.contains("Z/A/C"), "Should mention Z, A, C weightings")
    }
    
    func testPDFContainsConfiguration() throws {
        let recording = createTestRecording(fftBlockSize: 8192, calibrationOffset: 5.5)
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let secondPage = pdfDocument.page(at: 1) else {
            XCTFail("Should load PDF")
            return
        }
        
        let pageText = secondPage.string ?? ""
        XCTAssertTrue(pageText.contains("Konfiguration"), "Should contain configuration section")
        XCTAssertTrue(pageText.contains("8192"), "Should contain FFT block size")
    }
    
    // MARK: - Edge Cases and Error Handling
    
    func testGeneratePDFWithMinimalRecording() throws {
        // Create minimal recording with no measurement data
        var recording = createTestRecording()
        recording.laeqFast = -120.0
        recording.peakLevel = -120.0
        recording.minLevel = -120.0
        
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: pdfURL.path), "Should generate PDF even with minimal data")
        
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            XCTFail("Should load PDF")
            return
        }
        
        XCTAssertGreaterThanOrEqual(pdfDocument.pageCount, 2, "Should have at least 2 pages")
    }
    
    func testGeneratePDFWithNoMeasurementFile() throws {
        let recording = createTestRecording()
        
        // Ensure no measurement file exists (default behavior)
        let measurementURL = recordingManager.measurementURL(for: recording)
        if let url = measurementURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        // Should still generate PDF with fallback values
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: pdfURL.path), "Should generate PDF without measurement file")
    }
    
    func testGeneratePDFWithLocation() throws {
        let location = CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050)
        let recording = createTestRecording(location: location)
        
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let firstPage = pdfDocument.page(at: 0) else {
            XCTFail("Should load PDF")
            return
        }
        
        let pageText = firstPage.string ?? ""
        XCTAssertTrue(pageText.contains("52.5"), "Should contain latitude")
        XCTAssertTrue(pageText.contains("13.4"), "Should contain longitude")
    }
    
    func testGeneratePDFWithDescription() throws {
        let recording = createTestRecording(description: "Traffic noise measurement at intersection")
        
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let secondPage = pdfDocument.page(at: 1) else {
            XCTFail("Should load PDF")
            return
        }
        
        let pageText = secondPage.string ?? ""
        XCTAssertTrue(pageText.contains("Traffic noise measurement"), "Should contain description")
    }
    
    func testGeneratePDFWithMultiplePhotos() throws {
        let recording = createTestRecordingWithMultiplePhotos(count: 3)
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            XCTFail("Should load PDF")
            return
        }
        
        // With 3 photos: 5 pages (summary + spectrogram/bands + 3 photo pages)
        XCTAssertEqual(pdfDocument.pageCount, 5, "PDF with 3 photos should have 5 pages")
    }
    
    func testPDFGeneratedInTemporaryDirectory() throws {
        let recording = createTestRecording()
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        let tempDir = FileManager.default.temporaryDirectory.path
        XCTAssertTrue(pdfURL.path.contains(tempDir), "PDF should be generated in temporary directory")
    }
    
    func testPDFFilenameContainsRecordingID() throws {
        let recording = createTestRecording()
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        let filename = pdfURL.lastPathComponent
        XCTAssertTrue(filename.contains(recording.id.uuidString), "PDF filename should contain recording ID")
    }
    
    // MARK: - Required Baseline Content Tests

    func testPDFContainsMicrophoneDisclaimer() throws {
        let recording = createTestRecording()
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)

        guard let pdfDocument = PDFDocument(url: pdfURL),
              let firstPage = pdfDocument.page(at: 0) else {
            XCTFail("Should load PDF with first page")
            return
        }

        let pageText = firstPage.string ?? ""
        XCTAssertTrue(pageText.contains("Näherungswerte"), "PDF should state measurements are approximate values")
        XCTAssertTrue(pageText.contains("iPhone") || pageText.contains("Apple Watch"), "PDF should reference built-in microphone sources")
        XCTAssertTrue(pageText.contains("compliance") || pageText.contains("Nachweise"), "PDF should state measurements are not compliance-grade")
    }

    func testPDFCalibrationStateForZeroOffset() throws {
        let recording = createTestRecording(calibrationOffset: 0.0)
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)

        guard let pdfDocument = PDFDocument(url: pdfURL),
              let secondPage = pdfDocument.page(at: 1) else {
            XCTFail("Should load PDF with second page")
            return
        }

        let pageText = secondPage.string ?? ""
        XCTAssertTrue(pageText.contains("kein Offset") || pageText.contains("nicht kalibriert"),
                      "PDF should explain zero calibration offset means no calibration was applied")
    }

    func testPDFCalibrationStateForNonZeroOffset() throws {
        let recording = createTestRecording(calibrationOffset: 3.5)
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)

        guard let pdfDocument = PDFDocument(url: pdfURL),
              let secondPage = pdfDocument.page(at: 1) else {
            XCTFail("Should load PDF with second page")
            return
        }

        let pageText = secondPage.string ?? ""
        XCTAssertTrue(pageText.contains("3.5"), "PDF should show calibration offset value")
        XCTAssertTrue(pageText.contains("angewendet"), "PDF should indicate offset was applied")
    }

    func testPDFGenerationCancellationThrowsQuickly() async throws {
        let recording = createTestRecording()
        let audioURL = recordingManager.url(for: recording)
        let measurementURL = try createTestMeasurementFile(frameCount: 10_000)

        let task = Task.detached {
            try PDFReportGenerator().generateReport(
                for: recording,
                audioURL: audioURL,
                measurementURL: measurementURL,
                photoURLs: []
            )
        }

        let start = Date()
        task.cancel()
        await Task.yield()

        do {
            _ = try await task.value
            XCTFail("PDF generation should throw CancellationError after cancellation.")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // PE-2: a cancelled / failed PDF export must not leave the partially
    // written report sitting in temporaryDirectory.
    func testPDFGenerationCleansUpTempFileOnCancellation() async throws {
        let recording = createTestRecording()
        let audioURL = recordingManager.url(for: recording)
        let measurementURL = try createTestMeasurementFile(frameCount: 5000)
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("report_\(recording.id.uuidString).pdf")
        try? FileManager.default.removeItem(at: expectedURL)

        let task = Task.detached {
            try PDFReportGenerator().generateReport(
                for: recording,
                audioURL: audioURL,
                measurementURL: measurementURL,
                photoURLs: []
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled PDF generation should throw.")
        } catch {
            // Expected
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: expectedURL.path),
            "Cancelled PDF export should not leave a temp file behind."
        )
    }

    // MARK: - Performance Tests
    
    func testPDFGenerationPerformance() throws {
        let recording = createTestRecording()
        
        measure {
            do {
                let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
                try? FileManager.default.removeItem(at: pdfURL)
            } catch {
                XCTFail("PDF generation failed: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestRecording(
        name: String = "Test Recording",
        laeq: Float = 65.0,
        peakLevel: Float = 85.0,
        minLevel: Float = 45.0,
        fftBlockSize: Int = 4096,
        calibrationOffset: Float = 0.0,
        location: CLLocationCoordinate2D? = nil,
        description: String = ""
    ) -> Recording {
        // Create audio file
        let audioFileName = "\(UUID().uuidString).m4a"
        let audioURL = tempDirectory.appendingPathComponent(audioFileName)
        createDummyAudioFile(at: audioURL)
        
        var recording = Recording(
            id: UUID(),
            name: name,
            startDate: Date(),
            duration: 10.0,
            audioFileName: audioURL.path,
            laeqFast: laeq,
            peakLevel: peakLevel,
            minLevel: minLevel,
            timeWeighting: "Fast",
            frequencyWeighting: "A",
            calibrationOffset: calibrationOffset,
            fftBlockSize: fftBlockSize
        )
        
        if let location = location {
            recording.location = location
        }
        
        recording.description = description
        
        // Add recording to manager using addRecording
        recordingManager.addRecording(recording)
        
        // Get the updated recording from the manager (it may have been modified)
        return recordingManager.recordings.first ?? recording
    }
    
    private func createTestRecordingWithPhoto() -> Recording {
        var recording = createTestRecording()
        
        // Create dummy photo file
        let baseURL = recordingManager.url(for: recording).deletingLastPathComponent()
        let photoName = "photo_\(UUID().uuidString).jpg"
        let photoURL = baseURL.appendingPathComponent(photoName)
        
        createDummyImage(at: photoURL)
        
        recording.photoFileNames = [photoName]
        
        // Update recording in manager
        recordingManager.updateRecording(recording)
        
        return recordingManager.recordings.first(where: { $0.id == recording.id }) ?? recording
    }
    
    private func createTestRecordingWithMultiplePhotos(count: Int) -> Recording {
        var recording = createTestRecording()
        
        let baseURL = recordingManager.url(for: recording).deletingLastPathComponent()
        var photoNames: [String] = []
        
        for _ in 0..<count {
            let photoName = "photo_\(UUID().uuidString).jpg"
            let photoURL = baseURL.appendingPathComponent(photoName)
            createDummyImage(at: photoURL)
            photoNames.append(photoName)
        }
        
        recording.photoFileNames = photoNames
        
        // Update recording in manager
        recordingManager.updateRecording(recording)
        
        return recordingManager.recordings.first(where: { $0.id == recording.id }) ?? recording
    }
    
    private func createDummyAudioFile(at url: URL) {
        // Write an empty placeholder — the PDF generator only checks the URL
        // exists; it doesn't decode the audio content in tests.
        try? Data().write(to: url)
    }
    
    private func createDummyImage(at url: URL) {
        // Create 100x100 white image
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.white.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        if let image = image, let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: url)
        } else {
            // Fallback
            try? Data().write(to: url)
        }
    }

    private func createTestMeasurementFile(frameCount: Int) throws -> URL {
        let tempURL = tempDirectory.appendingPathComponent("test_measurement_\(UUID().uuidString).spekto")
        let writer = try MeasurementDataWriter(
            fileURL: tempURL,
            metricKeys: ["LAeq", "LAFmax", "LAFmin"],
            sampleRate: 44100,
            fps: 10,
            fftBlockSize: 4096,
            fftBinCount: 0,
            maxPendingFrames: max(32, frameCount + 1)
        )

        let thirdOctaves = Array(repeating: Float(60.0), count: MeasurementDataFormat.thirdOctaveBandCount)
        for index in 0..<frameCount {
            try writer.writeFrame(
                timestamp: Float(index) * 0.1,
                metricValues: [65.0, 85.0, 45.0],
                broadbandLevel: 65.0,
                thirdOctaveZ: thirdOctaves,
                thirdOctaveA: thirdOctaves,
                thirdOctaveC: thirdOctaves,
                fullFFT: []
            )
        }

        try writer.close()
        return tempURL
    }

    // MARK: - M15 task-6: Energy-correct dB averaging
    //
    // Time-averaging dB values in the log domain understates the true
    // Leq for any signal with dynamic range. These tests pin the
    // post-fix energy-mean convention so the bug can't silently come
    // back via a refactor.

    func testEnergyAverageDB_asymmetricFixtureMatchesEnergyMeanNotArithmetic() {
        // dB1 = -20, dB2 = -80
        // Arithmetic mean: (-20 + -80) / 2 = -50 dB  (the bug)
        // Energy mean:    10·log10((10^-2 + 10^-8) / 2)
        //              =  10·log10(0.005000005)
        //              ≈ -23.01 dB
        let avg = PDFReportGenerator.energyAverageDB([-20, -80])
        XCTAssertEqual(avg, -23.01, accuracy: 0.05,
                       "Energy average of -20 dB / -80 dB must round to ~-23 dB, got \(avg)")
        XCTAssertGreaterThan(avg, -50,
                             "Energy average must exceed the arithmetic mean (-50 dB) for an asymmetric fixture")
    }

    func testEnergyAverageDB_equalValuesAreIdempotent() {
        // Identical dB values: energy mean equals arithmetic mean.
        XCTAssertEqual(PDFReportGenerator.energyAverageDB([-60, -60, -60]), -60, accuracy: 1e-4)
        XCTAssertEqual(PDFReportGenerator.energyAverageDB([0, 0]), 0, accuracy: 1e-4)
    }

    func testEnergyAverageDB_emptyInputReturnsFloor() {
        XCTAssertEqual(PDFReportGenerator.energyAverageDB([], floorDB: -120), -120)
    }

    func testEnergyAverageDB_allFloorFramesStayAtFloor() {
        // Three -120 dB sentinel frames: 10^-12 each, mean 10^-12,
        // 10·log10(10^-12) = -120 dB — exactly the floor.
        let avg = PDFReportGenerator.energyAverageDB([-120, -120, -120], floorDB: -120)
        XCTAssertEqual(avg, -120, accuracy: 1e-3)
    }

    func testEnergyMeanDB_zeroDividerReturnsFloor() {
        XCTAssertEqual(PDFReportGenerator.energyMeanDB(sum: 1.0, divider: 0, floorDB: -120), -120)
    }

    func testEnergyMeanDB_zeroSumReturnsFloor() {
        XCTAssertEqual(PDFReportGenerator.energyMeanDB(sum: 0, divider: 5, floorDB: -120), -120)
    }
}
#endif

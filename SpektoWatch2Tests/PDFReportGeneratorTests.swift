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
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        pdfGenerator = PDFReportGenerator()
        audioEngine = AudioEngine(fftBlockSize: 4096)
        
        // Create unique temp directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        recordingManager = RecordingManager(baseDirectory: tempDirectory)
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
        // Start and stop recording to create valid data
        let started = recordingManager.startRecording(audioEngine: audioEngine)
        XCTAssertTrue(started, "Recording should start")
        
        // Wait briefly for recording
        Thread.sleep(forTimeInterval: 0.5)
        
        let expectation = XCTestExpectation(description: "Stop recording")
        var stoppedRecording: Recording?
        recordingManager.stopRecording(audioEngine: audioEngine) { recording in
            stoppedRecording = recording
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
        
        guard let recording = stoppedRecording else {
            XCTFail("Should have stopped recording")
            return
        }
        
        // Generate PDF
        let pdfURL = try pdfGenerator.generateReport(for: recording, recordingManager: recordingManager)
        
        // Verify PDF exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: pdfURL.path), "PDF file should exist")
        
        // Verify PDF is in temp directory
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
        let audioURL = recordingManager.baseDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        createDummyAudioFile(at: audioURL)
        
        var recording = Recording(
            id: UUID(),
            name: name,
            date: Date(),
            duration: 10.0,
            laeqFast: laeq,
            peakLevel: peakLevel,
            minLevel: minLevel,
            fftBlockSize: fftBlockSize,
            calibrationOffset: calibrationOffset,
            timeWeighting: "Fast",
            frequencyWeighting: "A"
        )
        
        if let location = location {
            recording.location = location
        }
        
        recording.description = description
        
        // Save recording to manager
        try? recordingManager.saveRecording(recording, audioURL: audioURL, measurementData: nil, statistics: MeasurementStatistics.placeholder)
        
        return recording
    }
    
    private func createTestRecordingWithPhoto() -> Recording {
        var recording = createTestRecording()
        
        // Create dummy photo file
        let baseURL = recordingManager.url(for: recording).deletingLastPathComponent()
        let photoName = "photo_\(UUID().uuidString).jpg"
        let photoURL = baseURL.appendingPathComponent(photoName)
        
        createDummyImage(at: photoURL)
        
        recording.photoFileNames = [photoName]
        try? recordingManager.saveRecording(recording, audioURL: recordingManager.url(for: recording), measurementData: nil, statistics: MeasurementStatistics.placeholder)
        
        return recording
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
        try? recordingManager.saveRecording(recording, audioURL: recordingManager.url(for: recording), measurementData: nil, statistics: MeasurementStatistics.placeholder)
        
        return recording
    }
    
    private func createDummyAudioFile(at url: URL) {
        // Create minimal valid m4a file
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000
        ]
        
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            Thread.sleep(forTimeInterval: 0.1)
            recorder.stop()
        } catch {
            // Fallback: create empty file
            try? Data().write(to: url)
        }
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
}
#endif

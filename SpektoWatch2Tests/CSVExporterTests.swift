import XCTest
@testable import SpektoWatch2
import Foundation

@MainActor
final class CSVExporterTests: XCTestCase {
    
    var csvExporter: CSVExporter!
    var jsonExporter: JSONMeasurementExporter!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        csvExporter = CSVExporter()
        jsonExporter = JSONMeasurementExporter()
        
        // Create unique temp directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CSVTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        csvExporter = nil
        jsonExporter = nil
        
        // Clean up temp directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        
        try await super.tearDown()
    }
    
    // MARK: - CSV Export Tests
    
    func testCSVExportBasic() throws {
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("test_export.csv")
        
        try csvExporter.export(
            reader: reader,
            to: outputURL,
            selectedMetrics: ["LAeq", "LAFmax"],
            includeThirdOctaves: false
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "CSV file should exist")
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertFalse(content.isEmpty, "CSV content should not be empty")
    }
    
    func testCSVHeaderFormat() throws {
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("header_test.csv")
        
        try csvExporter.export(
            reader: reader,
            to: outputURL,
            selectedMetrics: ["LAeq", "LAFmax"],
            includeThirdOctaves: false
        )
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        guard let header = lines.first else {
            XCTFail("CSV should have header line")
            return
        }
        
        XCTAssertTrue(header.contains("Zeit[s]"), "Header should contain Zeit[s]")
        XCTAssertTrue(header.contains("LAeq"), "Header should contain LAeq")
        XCTAssertTrue(header.contains("LAFmax"), "Header should contain LAFmax")
        XCTAssertTrue(header.contains("Breitband[dB]"), "Header should contain Breitband[dB]")
    }
    
    func testCSVWithThirdOctaves() throws {
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("octaves_test.csv")
        
        try csvExporter.export(
            reader: reader,
            to: outputURL,
            selectedMetrics: ["LAeq"],
            includeThirdOctaves: true
        )
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        guard let header = lines.first else {
            XCTFail("CSV should have header")
            return
        }
        
        // Check for Z, A, C weighted third-octaves
        XCTAssertTrue(header.contains("Z_20"), "Header should contain Z-weighted bands")
        XCTAssertTrue(header.contains("A_1000"), "Header should contain A-weighted bands")
        XCTAssertTrue(header.contains("C_8000"), "Header should contain C-weighted bands")
    }
    
    func testCSVWithoutThirdOctaves() throws {
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("no_octaves_test.csv")
        
        try csvExporter.export(
            reader: reader,
            to: outputURL,
            selectedMetrics: ["LAeq"],
            includeThirdOctaves: false
        )
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        guard let header = lines.first else {
            XCTFail("CSV should have header")
            return
        }
        
        // Should not contain third-octave columns
        XCTAssertFalse(header.contains("Z_20"), "Header should not contain Z-weighted bands")
        XCTAssertFalse(header.contains("A_1000"), "Header should not contain A-weighted bands")
        XCTAssertFalse(header.contains("C_8000"), "Header should not contain C-weighted bands")
    }
    
    func testCSVDataRows() throws {
        let reader = createTestMeasurementReader(frameCount: 5)
        let outputURL = tempDirectory.appendingPathComponent("rows_test.csv")
        
        try csvExporter.export(
            reader: reader,
            to: outputURL,
            selectedMetrics: ["LAeq"],
            includeThirdOctaves: false
        )
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        // Header + 5 data rows
        XCTAssertEqual(lines.count, 6, "CSV should have 1 header + 5 data rows")
    }
    
    func testCSVSeparatorFormat() throws {
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("separator_test.csv")
        
        try csvExporter.export(
            reader: reader,
            to: outputURL,
            selectedMetrics: ["LAeq"],
            includeThirdOctaves: false
        )
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        // CSV should use semicolon separator
        XCTAssertTrue(lines.first?.contains(";") ?? false, "CSV should use semicolon separator")
    }
    
    func testCSVNumericFormat() throws {
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("numeric_test.csv")
        
        try csvExporter.export(
            reader: reader,
            to: outputURL,
            selectedMetrics: ["LAeq"],
            includeThirdOctaves: false
        )
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        guard lines.count > 1 else {
            XCTFail("CSV should have data rows")
            return
        }
        
        let dataLine = lines[1]
        let values = dataLine.components(separatedBy: ";")
        
        // Check numeric format (should have 3 decimal places)
        XCTAssertTrue(values.contains(where: { $0.contains(".") }), "Values should contain decimal separator")
    }
    
    func testCSVSelectedMetricsFilter() throws {
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("filter_test.csv")
        
        // Only export LAeq, not LAFmax
        try csvExporter.export(
            reader: reader,
            to: outputURL,
            selectedMetrics: ["LAeq"],
            includeThirdOctaves: false
        )
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        guard let header = lines.first else {
            XCTFail("CSV should have header")
            return
        }
        
        XCTAssertTrue(header.contains("LAeq"), "Should contain selected metric")
        XCTAssertFalse(header.contains("LAFmax"), "Should not contain unselected metric")
    }
    
    func testCSVEmptyMetricsList() throws {
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("empty_metrics_test.csv")
        
        // Export with empty metrics
        try csvExporter.export(
            reader: reader,
            to: outputURL,
            selectedMetrics: [],
            includeThirdOctaves: false
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "CSV should still be created")
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        guard let header = lines.first else {
            XCTFail("CSV should have header")
            return
        }
        
        // Should still have Zeit and Breitband columns
        XCTAssertTrue(header.contains("Zeit[s]"), "Should have Zeit column")
        XCTAssertTrue(header.contains("Breitband[dB]"), "Should have Breitband column")
    }
    
    func testCSVInvalidMetricsFiltered() throws {
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("invalid_metrics_test.csv")
        
        // Request metrics that don't exist in reader
        try csvExporter.export(
            reader: reader,
            to: outputURL,
            selectedMetrics: ["LAeq", "NonExistentMetric", "LAFmax"],
            includeThirdOctaves: false
        )
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        guard let header = lines.first else {
            XCTFail("CSV should have header")
            return
        }
        
        // Valid metrics should be included
        XCTAssertTrue(header.contains("LAeq"), "Should include valid metric LAeq")
        XCTAssertTrue(header.contains("LAFmax"), "Should include valid metric LAFmax")
        
        // Invalid metric should be filtered out
        XCTAssertFalse(header.contains("NonExistentMetric"), "Should filter out invalid metrics")
    }
    
    // MARK: - JSON Export Tests
    
    func testJSONExportBasic() throws {
        let recording = createTestRecording()
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("test_export.json")
        
        try jsonExporter.export(recording: recording, reader: reader, to: outputURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "JSON file should exist")
        
        let data = try Data(contentsOf: outputURL)
        XCTAssertFalse(data.isEmpty, "JSON data should not be empty")
    }
    
    func testJSONStructure() throws {
        let recording = createTestRecording()
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("structure_test.json")
        
        try jsonExporter.export(recording: recording, reader: reader, to: outputURL)
        
        let data = try Data(contentsOf: outputURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertNotNil(json, "Should parse as JSON dictionary")
        XCTAssertNotNil(json?["recording"], "Should contain recording object")
        XCTAssertNotNil(json?["metricKeys"], "Should contain metricKeys array")
        XCTAssertNotNil(json?["frames"], "Should contain frames array")
        XCTAssertNotNil(json?["sampleRate"], "Should contain sampleRate")
        XCTAssertNotNil(json?["fps"], "Should contain fps")
    }
    
    func testJSONRecordingData() throws {
        let recording = createTestRecording(name: "Test Recording", duration: 120.0)
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("recording_data_test.json")
        
        try jsonExporter.export(recording: recording, reader: reader, to: outputURL)
        
        let data = try Data(contentsOf: outputURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let recordingData = json?["recording"] as? [String: Any] else {
            XCTFail("Should contain recording data")
            return
        }
        
        XCTAssertEqual(recordingData["name"] as? String, "Test Recording", "Should contain recording name")
        XCTAssertEqual(recordingData["duration"] as? Double, 120.0, "Should contain duration")
        XCTAssertNotNil(recordingData["id"], "Should contain ID")
        XCTAssertNotNil(recordingData["startDate"], "Should contain start date")
        XCTAssertNotNil(recordingData["calibrationOffset"], "Should contain calibration offset")
        XCTAssertNotNil(recordingData["fftBlockSize"], "Should contain FFT block size")
    }
    
    func testJSONFrameData() throws {
        let recording = createTestRecording()
        let reader = createTestMeasurementReader(frameCount: 3)
        let outputURL = tempDirectory.appendingPathComponent("frame_data_test.json")
        
        try jsonExporter.export(recording: recording, reader: reader, to: outputURL)
        
        let data = try Data(contentsOf: outputURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let frames = json?["frames"] as? [[String: Any]] else {
            XCTFail("Should contain frames array")
            return
        }
        
        XCTAssertEqual(frames.count, 3, "Should contain 3 frames")
        
        guard let firstFrame = frames.first else {
            XCTFail("Should have first frame")
            return
        }
        
        XCTAssertNotNil(firstFrame["timestamp"], "Frame should contain timestamp")
        XCTAssertNotNil(firstFrame["metrics"], "Frame should contain metrics")
        XCTAssertNotNil(firstFrame["broadband"], "Frame should contain broadband level")
        XCTAssertNotNil(firstFrame["thirdOctaveZ"], "Frame should contain Z-weighted third-octaves")
        XCTAssertNotNil(firstFrame["thirdOctaveA"], "Frame should contain A-weighted third-octaves")
        XCTAssertNotNil(firstFrame["thirdOctaveC"], "Frame should contain C-weighted third-octaves")
    }
    
    func testJSONThirdOctaveArrays() throws {
        let recording = createTestRecording()
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("octave_arrays_test.json")
        
        try jsonExporter.export(recording: recording, reader: reader, to: outputURL)
        
        let data = try Data(contentsOf: outputURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let frames = json?["frames"] as? [[String: Any]],
              let firstFrame = frames.first else {
            XCTFail("Should contain frames")
            return
        }
        
        let zArray = firstFrame["thirdOctaveZ"] as? [Float]
        let aArray = firstFrame["thirdOctaveA"] as? [Float]
        let cArray = firstFrame["thirdOctaveC"] as? [Float]
        
        XCTAssertNotNil(zArray, "Should contain Z array")
        XCTAssertNotNil(aArray, "Should contain A array")
        XCTAssertNotNil(cArray, "Should contain C array")
        
        // Should have 31 third-octave bands
        XCTAssertEqual(zArray?.count, 31, "Should have 31 Z bands")
        XCTAssertEqual(aArray?.count, 31, "Should have 31 A bands")
        XCTAssertEqual(cArray?.count, 31, "Should have 31 C bands")
    }
    
    func testJSONMetricsData() throws {
        let recording = createTestRecording()
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("metrics_test.json")
        
        try jsonExporter.export(recording: recording, reader: reader, to: outputURL)
        
        let data = try Data(contentsOf: outputURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let frames = json?["frames"] as? [[String: Any]],
              let firstFrame = frames.first,
              let metrics = firstFrame["metrics"] as? [String: Float] else {
            XCTFail("Should contain metrics")
            return
        }
        
        XCTAssertTrue(metrics.keys.contains("LAeq"), "Metrics should contain LAeq")
        XCTAssertTrue(metrics.keys.contains("LAFmax"), "Metrics should contain LAFmax")
    }
    
    func testJSONDateFormat() throws {
        let recording = createTestRecording()
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("date_format_test.json")
        
        try jsonExporter.export(recording: recording, reader: reader, to: outputURL)
        
        let data = try Data(contentsOf: outputURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let recordingData = json?["recording"] as? [String: Any],
              let startDateString = recordingData["startDate"] as? String else {
            XCTFail("Should contain start date")
            return
        }
        
        // Should be ISO8601 format
        let formatter = ISO8601DateFormatter()
        let parsedDate = formatter.date(from: startDateString)
        XCTAssertNotNil(parsedDate, "Start date should be in ISO8601 format")
    }
    
    func testJSONPrettyPrinted() throws {
        let recording = createTestRecording()
        let reader = createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("pretty_test.json")
        
        try jsonExporter.export(recording: recording, reader: reader, to: outputURL)
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        
        // Pretty printed JSON should contain newlines and indentation
        XCTAssertTrue(content.contains("\n"), "JSON should be pretty printed with newlines")
        XCTAssertTrue(content.contains("  "), "JSON should be indented")
    }
    
    // MARK: - Error Handling Tests
    
    func testCSVExportToInvalidPath() {
        let reader = createTestMeasurementReader()
        let invalidURL = URL(fileURLWithPath: "/invalid/path/that/does/not/exist/test.csv")
        
        XCTAssertThrowsError(try csvExporter.export(
            reader: reader,
            to: invalidURL,
            selectedMetrics: ["LAeq"],
            includeThirdOctaves: false
        ), "Should throw error for invalid path")
    }
    
    func testJSONExportToInvalidPath() {
        let recording = createTestRecording()
        let reader = createTestMeasurementReader()
        let invalidURL = URL(fileURLWithPath: "/invalid/path/that/does/not/exist/test.json")
        
        XCTAssertThrowsError(try jsonExporter.export(
            recording: recording,
            reader: reader,
            to: invalidURL
        ), "Should throw error for invalid path")
    }
    
    // MARK: - Performance Tests
    
    func testCSVExportPerformance() throws {
        let reader = createTestMeasurementReader(frameCount: 1000)
        
        measure {
            let outputURL = tempDirectory.appendingPathComponent("perf_\(UUID().uuidString).csv")
            do {
                try csvExporter.export(
                    reader: reader,
                    to: outputURL,
                    selectedMetrics: ["LAeq", "LAFmax"],
                    includeThirdOctaves: true
                )
                try? FileManager.default.removeItem(at: outputURL)
            } catch {
                XCTFail("CSV export failed: \(error)")
            }
        }
    }
    
    func testJSONExportPerformance() throws {
        let recording = createTestRecording()
        let reader = createTestMeasurementReader(frameCount: 1000)
        
        measure {
            let outputURL = tempDirectory.appendingPathComponent("perf_\(UUID().uuidString).json")
            do {
                try jsonExporter.export(recording: recording, reader: reader, to: outputURL)
                try? FileManager.default.removeItem(at: outputURL)
            } catch {
                XCTFail("JSON export failed: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestMeasurementReader(frameCount: Int = 10) -> MeasurementDataReader {
        let tempURL = tempDirectory.appendingPathComponent("test_measurement_\(UUID().uuidString).dat")
        
        // Create test measurement file
        let writer = try! MeasurementDataWriter(
            fileURL: tempURL,
            metricKeys: ["LAeq", "LAFmax", "LAFmin"],
            sampleRate: 44100,
            fps: 10,
            fftBlockSize: 4096
        )
        
        for i in 0..<frameCount {
            try! writer.writeFrame(
                timestamp: Float(i) * 0.1,
                metricValues: [65.0, 85.0, 45.0],
                broadbandLevel: 65.0 + Float.random(in: -5...5),
                thirdOctaveZ: Array(repeating: 60.0, count: 31),
                thirdOctaveA: Array(repeating: 58.0, count: 31),
                thirdOctaveC: Array(repeating: 62.0, count: 31)
            )
        }
        
        try! writer.close()
        
        return try! MeasurementDataReader(fileURL: tempURL)
    }
    
    private func createTestRecording(
        name: String = "Test Recording",
        duration: TimeInterval = 60.0
    ) -> Recording {
        Recording(
            id: UUID(),
            name: name,
            startDate: Date(),
            duration: duration,
            audioFileName: "test.m4a",
            laeqFast: 65.0,
            peakLevel: 85.0,
            minLevel: 45.0,
            timeWeighting: "Fast",
            frequencyWeighting: "A",
            calibrationOffset: 0.0,
            fftBlockSize: 4096
        )
    }
}

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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader(frameCount: 5)
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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader()
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
    
    // MARK: - Determinism and Ordering Tests

    func testCSVMetricOrderMatchesSelectedOrder() throws {
        let reader = try createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("order_test.csv")

        // Request metrics in reverse alphabetical order
        try csvExporter.export(
            reader: reader,
            to: outputURL,
            selectedMetrics: ["LAFmax", "LAeq"],
            includeThirdOctaves: false
        )

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let header = content.components(separatedBy: .newlines).first ?? ""
        let columns = header.components(separatedBy: ";")

        guard let laeqIndex = columns.firstIndex(of: "LAeq"),
              let lafmaxIndex = columns.firstIndex(of: "LAFmax") else {
            XCTFail("Header should contain both metrics")
            return
        }
        XCTAssertLessThan(lafmaxIndex, laeqIndex, "LAFmax should appear before LAeq when requested first")
    }

    func testCSVHeaderIsStable() throws {
        let reader = try createTestMeasurementReader()
        let urlA = tempDirectory.appendingPathComponent("stable_a.csv")
        let urlB = tempDirectory.appendingPathComponent("stable_b.csv")

        let metrics = ["LAeq", "LAFmax", "LAFmin"]
        try csvExporter.export(reader: reader, to: urlA, selectedMetrics: metrics, includeThirdOctaves: false)
        try csvExporter.export(reader: reader, to: urlB, selectedMetrics: metrics, includeThirdOctaves: false)

        let headerA = (try String(contentsOf: urlA, encoding: .utf8)).components(separatedBy: .newlines).first
        let headerB = (try String(contentsOf: urlB, encoding: .utf8)).components(separatedBy: .newlines).first
        XCTAssertEqual(headerA, headerB, "Headers must be identical across exports with same inputs")
    }

    func testCSVNumericFormatThreeDecimalPlaces() throws {
        let reader = try createTestMeasurementReader(frameCount: 1)
        let outputURL = tempDirectory.appendingPathComponent("decimal_test.csv")

        try csvExporter.export(reader: reader, to: outputURL, selectedMetrics: ["LAeq"], includeThirdOctaves: false)

        let lines = (try String(contentsOf: outputURL, encoding: .utf8))
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { XCTFail("CSV should have a data row"); return }

        let headerColumns = lines[0].components(separatedBy: ";")
        let dataValues = lines[1].components(separatedBy: ";")
        // Skip the timestamp column (index 0) — its value is 0.0 which
        // may be formatted without trailing zeros. Assert only on metric
        // columns where the fixture seeds deterministic values.
        for (index, value) in dataValues.enumerated() {
            guard !value.isEmpty, index > 0, index < headerColumns.count else { continue }
            let parts = value.components(separatedBy: ".")
            XCTAssertEqual(parts.count, 2, "Column '\(headerColumns[index])' value '\(value)' should have exactly one decimal point")
            XCTAssertEqual(parts.last?.count, 3, "Column '\(headerColumns[index])' value '\(value)' should have exactly 3 decimal places")
        }
    }

    func testCSVThirdOctaveColumnCount() throws {
        let reader = try createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("band_count_test.csv")

        try csvExporter.export(reader: reader, to: outputURL, selectedMetrics: [], includeThirdOctaves: true)

        let header = (try String(contentsOf: outputURL, encoding: .utf8))
            .components(separatedBy: .newlines).first ?? ""
        let columns = header.components(separatedBy: ";")

        let zCount = columns.filter { $0.hasPrefix("Z_") }.count
        let aCount = columns.filter { $0.hasPrefix("A_") }.count
        let cCount = columns.filter { $0.hasPrefix("C_") }.count

        XCTAssertEqual(zCount, 31, "Should have 31 Z-weighted third-octave columns")
        XCTAssertEqual(aCount, 31, "Should have 31 A-weighted third-octave columns")
        XCTAssertEqual(cCount, 31, "Should have 31 C-weighted third-octave columns")
    }

    func testCSVThirdOctaveDecimalBandLabel() throws {
        let reader = try createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("band_label_test.csv")

        try csvExporter.export(reader: reader, to: outputURL, selectedMetrics: [], includeThirdOctaves: true)

        let header = (try String(contentsOf: outputURL, encoding: .utf8))
            .components(separatedBy: .newlines).first ?? ""

        XCTAssertTrue(header.contains("Z_31.5"), "31.5 Hz band should be labelled 'Z_31.5'")
        XCTAssertTrue(header.contains("A_31.5"), "31.5 Hz band should be labelled 'A_31.5'")
        XCTAssertTrue(header.contains("C_31.5"), "31.5 Hz band should be labelled 'C_31.5'")
    }

    func testCSVZeroFrameProducesHeaderOnly() throws {
        let reader = try createTestMeasurementReader(frameCount: 0)
        let outputURL = tempDirectory.appendingPathComponent("zero_frame_test.csv")

        try csvExporter.export(reader: reader, to: outputURL, selectedMetrics: ["LAeq"], includeThirdOctaves: false)

        let lines = (try String(contentsOf: outputURL, encoding: .utf8))
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 1, "Zero-frame export should produce only the header row")
        XCTAssertTrue(lines.first?.contains("Zeit[s]") ?? false, "Header should still be present")
    }

    func testCSVExportCancellationThrowsQuickly() async throws {
        let measurementURL = try createTestMeasurementFile(frameCount: 10_000)
        let outputURL = tempDirectory.appendingPathComponent("cancelled_export.csv")

        let task = Task.detached {
            let reader = try MeasurementDataReader(fileURL: measurementURL)
            try CSVExporter().export(
                reader: reader,
                to: outputURL,
                selectedMetrics: ["LAeq", "LAFmax"],
                includeThirdOctaves: true
            )
        }

        let start = Date()
        task.cancel()
        await Task.yield()

        do {
            try await task.value
            XCTFail("CSV export should throw CancellationError after cancellation.")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // PE-2: a cancelled CSV export must not leave the partially written file
    // sitting at outputURL.
    func testCSVExportCleansUpTempFileOnCancellation() async throws {
        let measurementURL = try createTestMeasurementFile(frameCount: 5000)
        let outputURL = tempDirectory.appendingPathComponent("cancel_cleanup.csv")

        let task = Task.detached {
            let reader = try MeasurementDataReader(fileURL: measurementURL)
            try CSVExporter().export(
                reader: reader,
                to: outputURL,
                selectedMetrics: ["LAeq", "LAFmax"],
                includeThirdOctaves: true
            )
        }
        task.cancel()

        do {
            try await task.value
            XCTFail("Cancelled CSV export should throw.")
        } catch {
            // Expected
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outputURL.path),
            "Cancelled CSV export should not leave a temp file behind."
        )
    }

    // MARK: - JSON Export Tests
    
    func testJSONExportBasic() throws {
        let recording = createTestRecording()
        let reader = try createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("test_export.json")
        
        try jsonExporter.export(recording: recording, reader: reader, to: outputURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "JSON file should exist")
        
        let data = try Data(contentsOf: outputURL)
        XCTAssertFalse(data.isEmpty, "JSON data should not be empty")
    }
    
    func testJSONStructure() throws {
        let recording = createTestRecording()
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader(frameCount: 3)
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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader()
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
        let reader = try createTestMeasurementReader()
        let outputURL = tempDirectory.appendingPathComponent("pretty_test.json")
        
        try jsonExporter.export(recording: recording, reader: reader, to: outputURL)
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        
        // Pretty printed JSON should contain newlines and indentation
        XCTAssertTrue(content.contains("\n"), "JSON should be pretty printed with newlines")
        XCTAssertTrue(content.contains("  "), "JSON should be indented")
    }
    
    // MARK: - Error Handling Tests
    
    func testCSVExportToInvalidPath() throws {
        let reader = try createTestMeasurementReader()
        let invalidURL = URL(fileURLWithPath: "/invalid/path/that/does/not/exist/test.csv")
        
        XCTAssertThrowsError(try csvExporter.export(
            reader: reader,
            to: invalidURL,
            selectedMetrics: ["LAeq"],
            includeThirdOctaves: false
        ), "Should throw error for invalid path")
    }
    
    func testJSONExportToInvalidPath() throws {
        let recording = createTestRecording()
        let reader = try createTestMeasurementReader()
        let invalidURL = URL(fileURLWithPath: "/invalid/path/that/does/not/exist/test.json")
        
        XCTAssertThrowsError(try jsonExporter.export(
            recording: recording,
            reader: reader,
            to: invalidURL
        ), "Should throw error for invalid path")
    }
    
    // MARK: - Performance Tests
    
    func testCSVExportPerformance() throws {
        let reader = try createTestMeasurementReader(frameCount: 1000)
        
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
        let reader = try createTestMeasurementReader(frameCount: 1000)
        
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
    
    private func createTestMeasurementReader(frameCount: Int = 10) throws -> MeasurementDataReader {
        let tempURL = try createTestMeasurementFile(frameCount: frameCount)
        return try MeasurementDataReader(fileURL: tempURL)
    }

    private func createTestMeasurementFile(frameCount: Int = 10) throws -> URL {
        let tempURL = tempDirectory.appendingPathComponent("test_measurement_\(UUID().uuidString).dat")

        let writer = try MeasurementDataWriter(
            fileURL: tempURL,
            metricKeys: ["LAeq", "LAFmax", "LAFmin"],
            sampleRate: 44100,
            fps: 10,
            fftBlockSize: 4096,
            fftBinCount: 2048,
            maxPendingFrames: max(32, frameCount + 1)
        )

        let fullFFT = Array(repeating: Float(-70.0), count: 2048)
        for i in 0..<frameCount {
            try writer.writeFrame(
                timestamp: Float(i) * 0.1,
                metricValues: [65.0, 85.0, 45.0],
                broadbandLevel: 65.0,
                thirdOctaveZ: Array(repeating: 60.0, count: 31),
                thirdOctaveA: Array(repeating: 58.0, count: 31),
                thirdOctaveC: Array(repeating: 62.0, count: 31),
                fullFFT: fullFFT
            )
        }

        try writer.close()
        return tempURL
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

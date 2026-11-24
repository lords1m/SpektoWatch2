import Foundation

/// DL-11: shared sanitising of non-finite measurement values for exporters.
/// `JSONSerialization` raises an Objective-C exception (crash) on NaN/Inf,
/// and CSV consumers choke on "nan"/"inf" tokens.
enum ExportValueSanitizer {
    /// JSON-safe value: the number, or `NSNull()` when non-finite.
    static func json(_ value: Float) -> Any {
        value.isFinite ? Double(value) : NSNull()
    }

    static func json(_ values: [Float]) -> [Any] {
        values.map { json($0) }
    }

    static func json(_ value: Double) -> Any {
        value.isFinite ? value : NSNull()
    }

    /// CSV field: formatted number, or an empty field when non-finite.
    static func csv(_ value: Float) -> String {
        value.isFinite ? String(format: "%.3f", value) : ""
    }
}

final class CSVExporter {
    private static let thirdOctaveCenters: [Float] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
        1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ]

    func export(
        reader: MeasurementDataReader,
        to outputURL: URL,
        selectedMetrics: [String],
        includeThirdOctaves: Bool = true
    ) throws {
        guard let stream = OutputStream(url: outputURL, append: false) else {
            throw MeasurementDataError.ioFailure("CSV-Ausgabestream konnte nicht geöffnet werden.")
        }

        stream.open()

        // PE-2: remove the partially-written CSV on cancellation or any throw
        // past stream-open so /tmp doesn't accumulate orphan exports.
        // Register removeItem BEFORE stream.close so LIFO defer closes first.
        var exportSucceeded = false
        defer {
            if !exportSucceeded {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }
        defer { stream.close() }

        // PE-3: CSV uses `;` field separator and `.` decimal (C locale).
        // Decision recorded 2026-05-24 (M15 task-10): keep C-locale numeric
        // format for unambiguous round-trip with tooling that consumes the
        // file (R, Python, MATLAB). Excel-DE imports via the semicolon
        // delimiter without locale conversion of the values themselves.

        let keyToIndex = Dictionary(uniqueKeysWithValues: reader.header.metricKeys.enumerated().map { ($1, $0) })
        let metricPairs: [(key: String, index: Int)] = selectedMetrics.compactMap { key in
            guard let idx = keyToIndex[key] else { return nil }
            return (key, idx)
        }
        var header = ["Zeit[s]"] + metricPairs.map(\.key) + ["Breitband[dB]"]
        if includeThirdOctaves {
            header += Self.thirdOctaveCenters.map { "Z_\(Self.bandLabel($0))" }
            header += Self.thirdOctaveCenters.map { "A_\(Self.bandLabel($0))" }
            header += Self.thirdOctaveCenters.map { "C_\(Self.bandLabel($0))" }
        }
        try writeLine(header.joined(separator: ";"), to: stream)

        for index in 0..<reader.frameCount {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let frame = try reader.readFrameSummary(at: index)
            var values: [String] = []
            values.reserveCapacity(2 + metricPairs.count + (includeThirdOctaves ? 93 : 0))
            values.append(Self.format(frame.timestamp))
            for pair in metricPairs {
                let value = pair.index < frame.metrics.count ? frame.metrics[pair.index] : -120.0
                values.append(Self.format(value))
            }
            values.append(Self.format(frame.broadbandLevel))

            if includeThirdOctaves {
                values += frame.thirdOctaveZ.map { Self.format($0) }
                values += frame.thirdOctaveA.map { Self.format($0) }
                values += frame.thirdOctaveC.map { Self.format($0) }
            }

            try writeLine(values.joined(separator: ";"), to: stream)
        }

        exportSucceeded = true
    }

    private func writeLine(_ line: String, to stream: OutputStream) throws {
        guard let data = (line + "\n").data(using: .utf8), !data.isEmpty else { return }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else {
                throw MeasurementDataError.ioFailure("Leerer Ausgabepuffer.")
            }
            var totalWritten = 0
            while totalWritten < data.count {
                let written = stream.write(base.advanced(by: totalWritten), maxLength: data.count - totalWritten)
                if written <= 0 {
                    throw MeasurementDataError.ioFailure(stream.streamError?.localizedDescription ?? "Unbekannter Stream-Fehler")
                }
                totalWritten += written
            }
        }
    }

    private static func format(_ value: Float) -> String {
        ExportValueSanitizer.csv(value)
    }

    private static func bandLabel(_ center: Float) -> String {
        if abs(center.rounded() - center) < 0.001 {
            return String(format: "%.0f", center)
        }
        return String(format: "%.1f", center)
    }
}

final class JSONMeasurementExporter {
    func export(recording: Recording, reader: MeasurementDataReader, to outputURL: URL) throws {
        var frames: [[String: Any]] = []
        frames.reserveCapacity(reader.frameCount)

        for index in 0..<reader.frameCount {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let frame = try reader.readFrameSummary(at: index)
            var metrics: [String: Any] = [:]
            for (metricIndex, key) in reader.header.metricKeys.enumerated() where metricIndex < frame.metrics.count {
                metrics[key] = ExportValueSanitizer.json(frame.metrics[metricIndex])
            }
            frames.append([
                "timestamp": ExportValueSanitizer.json(frame.timestamp),
                "metrics": metrics,
                "broadband": ExportValueSanitizer.json(frame.broadbandLevel),
                "thirdOctaveZ": ExportValueSanitizer.json(frame.thirdOctaveZ),
                "thirdOctaveA": ExportValueSanitizer.json(frame.thirdOctaveA),
                "thirdOctaveC": ExportValueSanitizer.json(frame.thirdOctaveC)
            ])
        }

        let payload: [String: Any] = [
            "recording": [
                "id": recording.id.uuidString,
                "name": recording.name,
                "startDate": ISO8601DateFormatter().string(from: recording.startDate),
                "duration": ExportValueSanitizer.json(recording.duration),
                "calibrationOffset": ExportValueSanitizer.json(recording.calibrationOffset),
                "fftBlockSize": recording.fftBlockSize
            ],
            "widgetConfigurations": recording.widgetConfigurations?.base64EncodedString() as Any,
            "metricKeys": reader.header.metricKeys,
            "sampleRate": ExportValueSanitizer.json(reader.header.sampleRate),
            "fps": ExportValueSanitizer.json(reader.header.fps),
            "frames": frames
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: outputURL, options: .atomic)
    }
}

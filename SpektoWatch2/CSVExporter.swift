import Foundation

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
        defer { stream.close() }

        // PE-2: remove the partially-written CSV on cancellation or any throw
        // past stream-open so /tmp doesn't accumulate orphan exports.
        var exportSucceeded = false
        defer {
            if !exportSucceeded {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        // PE-3: CSV uses `;` field separator and `.` decimal (C locale).
        // Decision recorded 2026-05-24 (M15 task-10): keep C-locale numeric
        // format for unambiguous round-trip with tooling that consumes the
        // file (R, Python, MATLAB). Excel-DE imports via the semicolon
        // delimiter without locale conversion of the values themselves.

        let metrics = selectedMetrics.filter { reader.header.metricKeys.contains($0) }
        var header = ["Zeit[s]"] + metrics + ["Breitband[dB]"]
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
            let frame = try reader.readFrame(at: index)
            var values: [String] = [Self.format(frame.timestamp)]
            for key in metrics {
                let value = frame.value(forMetric: key, using: reader.header.metricKeys) ?? -120.0
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
        guard let data = (line + "\n").data(using: .utf8) else { return }
        let result = data.withUnsafeBytes { bytes in
            guard let ptr = bytes.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return stream.write(ptr, maxLength: data.count)
        }
        if result < 0 {
            throw MeasurementDataError.ioFailure(stream.streamError?.localizedDescription ?? "Unbekannter Stream-Fehler")
        }
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.3f", value)
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
            let frame = try reader.readFrame(at: index)
            var metrics: [String: Float] = [:]
            for (metricIndex, key) in reader.header.metricKeys.enumerated() where metricIndex < frame.metrics.count {
                metrics[key] = frame.metrics[metricIndex]
            }
            frames.append([
                "timestamp": frame.timestamp,
                "metrics": metrics,
                "broadband": frame.broadbandLevel,
                "thirdOctaveZ": frame.thirdOctaveZ,
                "thirdOctaveA": frame.thirdOctaveA,
                "thirdOctaveC": frame.thirdOctaveC
            ])
        }

        let payload: [String: Any] = [
            "recording": [
                "id": recording.id.uuidString,
                "name": recording.name,
                "startDate": ISO8601DateFormatter().string(from: recording.startDate),
                "duration": recording.duration,
                "calibrationOffset": recording.calibrationOffset,
                "fftBlockSize": recording.fftBlockSize
            ],
            "widgetConfigurations": recording.widgetConfigurations?.base64EncodedString() as Any,
            "metricKeys": reader.header.metricKeys,
            "sampleRate": reader.header.sampleRate,
            "fps": reader.header.fps,
            "frames": frames
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: outputURL, options: .atomic)
    }
}

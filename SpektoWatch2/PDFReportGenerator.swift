#if canImport(UIKit)
import UIKit
import AVFoundation
import CoreLocation

final class PDFReportGenerator {
    private let spectrogramRenderer = SpectrogramImageRenderer()

    /// Convenience wrapper that resolves all URLs from `recordingManager` on the
    /// main actor, then hands them off to the non-isolated core renderer. This
    /// keeps existing call sites (production + tests) working unchanged while
    /// satisfying Swift 6 strict-concurrency: `RecordingManager` is
    /// `@MainActor`, but `PDFReportGenerator` itself doesn't need to be.
    @MainActor
    func generateReport(
        for recording: Recording,
        recordingManager: RecordingManager
    ) throws -> URL {
        let audioURL = recordingManager.url(for: recording)
        let measurementURL = recordingManager.measurementURL(for: recording)
        let photoURLs = recording.photoFileNames.map { recordingManager.getPhotoURL(fileName: $0) }
        return try generateReport(
            for: recording,
            audioURL: audioURL,
            measurementURL: measurementURL,
            photoURLs: photoURLs
        )
    }

    /// Core renderer. Takes pre-resolved file URLs so it has no dependency on
    /// any actor-isolated type and can be invoked from background contexts.
    func generateReport(
        for recording: Recording,
        audioURL: URL,
        measurementURL: URL?,
        photoURLs: [URL]
    ) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("report_\(recording.id.uuidString).pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @72dpi

        let measurementReader: MeasurementDataReader? = {
            guard let url = measurementURL,
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try? MeasurementDataReader(fileURL: url)
        }()
        let lineValues = try loadBroadbandValues(reader: measurementReader)
        let bands = try loadAverageThirdOctaves(reader: measurementReader)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: outputURL) { context in
            context.beginPage()
            let cg = context.cgContext
            drawHeader(in: cg, rect: pageRect, recording: recording)
            drawSummaryTable(in: cg, origin: CGPoint(x: 40, y: 100), recording: recording, reader: measurementReader)

            cg.saveGState()
            let lineRect = CGRect(x: 40, y: 250, width: pageRect.width - 80, height: 140)
            drawSectionTitle("Pegelverlauf", at: CGPoint(x: lineRect.minX, y: lineRect.minY - 18), in: cg)
            drawChartBackground(in: cg, rect: lineRect)
            ChartRenderer.drawLineChart(in: cg, rect: lineRect.insetBy(dx: 8, dy: 10), values: lineValues)
            cg.restoreGState()

            drawMicrophoneDisclaimer(in: cg, rect: CGRect(x: 40, y: 410, width: pageRect.width - 80, height: 90))
            drawFooter(in: cg, rect: pageRect, page: 1)

            context.beginPage()
            let page2 = context.cgContext
            drawSectionTitle("Gesamt-Spektrogramm", at: CGPoint(x: 40, y: 40), in: page2)
            if let image = try? spectrogramRenderer.renderSpectrogramImage(audioURL: audioURL) {
                let rect = CGRect(x: 40, y: 60, width: pageRect.width - 80, height: 250)
                image.draw(in: rect)
                page2.setStrokeColor(UIColor.secondaryLabel.cgColor)
                page2.stroke(rect)
            } else {
                drawPlaceholder(in: page2, rect: CGRect(x: 40, y: 60, width: pageRect.width - 80, height: 250), text: "Spektrogramm konnte nicht berechnet werden")
            }

            drawSectionTitle("Terzbandanalyse (Z/A/C)", at: CGPoint(x: 40, y: 340), in: page2)
            let zRect = CGRect(x: 40, y: 360, width: pageRect.width - 80, height: 95)
            let aRect = CGRect(x: 40, y: 470, width: pageRect.width - 80, height: 95)
            let cRect = CGRect(x: 40, y: 580, width: pageRect.width - 80, height: 95)
            drawBandChart(label: "Z", values: bands.z, rect: zRect, color: .systemBlue, in: page2)
            drawBandChart(label: "A", values: bands.a, rect: aRect, color: .systemGreen, in: page2)
            drawBandChart(label: "C", values: bands.c, rect: cRect, color: .systemOrange, in: page2)

            drawConfiguration(
                recording: recording,
                rect: CGRect(x: 40, y: 690, width: pageRect.width - 80, height: 110),
                in: page2
            )
            drawFooter(in: page2, rect: pageRect, page: 2)

            if !photoURLs.isEmpty {
                var pageIndex = 3
                for photoURL in photoURLs {
                    guard let image = UIImage(contentsOfFile: photoURL.path) else { continue }
                    context.beginPage()
                    let cg = context.cgContext
                    drawSectionTitle("Angehängtes Foto", at: CGPoint(x: 40, y: 40), in: cg)
                    let maxRect = CGRect(x: 40, y: 70, width: pageRect.width - 80, height: pageRect.height - 140)
                    let fitted = AVMakeRect(aspectRatio: image.size, insideRect: maxRect)
                    image.draw(in: fitted)
                    drawFooter(in: cg, rect: pageRect, page: pageIndex)
                    pageIndex += 1
                }
            }
        }

        return outputURL
    }

    private func drawHeader(in context: CGContext, rect: CGRect, recording: Recording) {
        let title = "SpektoWatch Messbericht"
        drawText(title, rect: CGRect(x: 40, y: 28, width: rect.width - 80, height: 28), font: .boldSystemFont(ofSize: 22))
        let metadata = [
            "Messung: \(recording.name)",
            "Datum: \(recording.formattedDate)",
            "Dauer: \(recording.formattedDuration)",
            "Ort: \(recording.location.map { "\($0.latitude), \($0.longitude)" } ?? "n/a")"
        ].joined(separator: "\n")
        drawText(metadata, rect: CGRect(x: 40, y: 56, width: rect.width - 80, height: 64), font: .systemFont(ofSize: 11))
        context.setStrokeColor(UIColor.separator.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: 40, y: 126))
        context.addLine(to: CGPoint(x: rect.width - 40, y: 126))
        context.strokePath()
    }

    private func drawSummaryTable(
        in context: CGContext,
        origin: CGPoint,
        recording: Recording,
        reader: MeasurementDataReader?
    ) {
        var values: [String: Float] = [
            "LAeq": recording.laeqFast,
            "LAFmin": recording.minLevel,
            "LAFmax": recording.peakLevel,
            "LCpeak": recording.peakLevel
        ]
        if let reader, reader.frameCount > 0, let last = try? reader.readFrame(at: reader.frameCount - 1) {
            for (idx, key) in reader.header.metricKeys.enumerated() where idx < last.metrics.count {
                values[key] = last.metrics[idx]
            }
        }

        let keys = ["LAeq", "LAFmin", "LAFmax", "LAF5", "LAF95", "LCpeak"]
        drawSectionTitle("Zusammenfassung", at: CGPoint(x: origin.x, y: origin.y - 20), in: context)

        let tableRect = CGRect(x: origin.x, y: origin.y, width: 250, height: 20 * CGFloat(keys.count + 1))
        context.setStrokeColor(UIColor.separator.cgColor)
        context.stroke(tableRect)
        for i in 0...keys.count {
            let y = tableRect.minY + CGFloat(i) * 20
            context.move(to: CGPoint(x: tableRect.minX, y: y))
            context.addLine(to: CGPoint(x: tableRect.maxX, y: y))
        }
        context.move(to: CGPoint(x: tableRect.minX + 130, y: tableRect.minY))
        context.addLine(to: CGPoint(x: tableRect.minX + 130, y: tableRect.maxY))
        context.strokePath()

        for (row, key) in keys.enumerated() {
            drawText(key, rect: CGRect(x: tableRect.minX + 6, y: tableRect.minY + 20 * CGFloat(row) + 4, width: 120, height: 16), font: .systemFont(ofSize: 10))
            let value = values[key] ?? -120
            drawText(String(format: "%.1f dB", value), rect: CGRect(x: tableRect.minX + 136, y: tableRect.minY + 20 * CGFloat(row) + 4, width: 100, height: 16), font: .systemFont(ofSize: 10))
        }
    }

    private func drawConfiguration(recording: Recording, rect: CGRect, in context: CGContext) {
        drawSectionTitle("Konfiguration", at: CGPoint(x: rect.minX, y: rect.minY - 18), in: context)
        let lines = [
            "FFT-Blockgröße: \(recording.fftBlockSize)",
            calibrationStateText(recording.calibrationOffset),
            "Zeitbewertung: \(recording.timeWeighting)",
            "Frequenzbewertung: \(recording.frequencyWeighting)",
            "Beschreibung: \(recording.description.isEmpty ? "-" : recording.description)"
        ].joined(separator: "\n")
        drawText(lines, rect: rect, font: .systemFont(ofSize: 10))
    }

    private func calibrationStateText(_ offset: Float) -> String {
        if offset == 0.0 {
            return "Kalibrierung: 0.0 dB – kein Offset angewendet (nicht kalibriert)"
        }
        return String(format: "Kalibrierung: %.1f dB – manueller Offset angewendet", offset)
    }

    private func drawMicrophoneDisclaimer(in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.08).cgColor)
        context.fill(rect)
        context.setStrokeColor(UIColor.systemOrange.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(0.75)
        context.stroke(rect)
        context.restoreGState()

        let title = "Hinweis zur Messgenauigkeit"
        drawText(title, rect: CGRect(x: rect.minX + 8, y: rect.minY + 6, width: rect.width - 16, height: 14), font: .boldSystemFont(ofSize: 9))

        let body = "Messungen mit integrierten iPhone- oder Apple Watch-Mikrofonen sind Näherungswerte. " +
            "Sie sind nicht für behördliche Lärmschutzgutachten oder compliance-relevante Nachweise geeignet."
        drawText(body, rect: CGRect(x: rect.minX + 8, y: rect.minY + 22, width: rect.width - 16, height: rect.height - 30), font: .systemFont(ofSize: 9))
    }

    private func drawBandChart(label: String, values: [Float], rect: CGRect, color: UIColor, in context: CGContext) {
        drawText(label, rect: CGRect(x: rect.minX, y: rect.minY - 14, width: 20, height: 12), font: .boldSystemFont(ofSize: 10))
        drawChartBackground(in: context, rect: rect)
        ChartRenderer.drawBarChart(in: context, rect: rect.insetBy(dx: 4, dy: 6), values: values, minValue: -100, maxValue: 20, fillColor: color)
    }

    private func drawSectionTitle(_ title: String, at point: CGPoint, in context: CGContext) {
        context.saveGState()
        drawText(title, rect: CGRect(x: point.x, y: point.y, width: 500, height: 18), font: .boldSystemFont(ofSize: 13))
        context.restoreGState()
    }

    private func drawChartBackground(in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setFillColor(UIColor.secondarySystemBackground.cgColor)
        context.fill(rect)
        context.setStrokeColor(UIColor.separator.cgColor)
        context.stroke(rect)
        context.restoreGState()
    }

    private func drawPlaceholder(in context: CGContext, rect: CGRect, text: String) {
        context.setFillColor(UIColor.secondarySystemBackground.cgColor)
        context.fill(rect)
        context.setStrokeColor(UIColor.separator.cgColor)
        context.stroke(rect)
        drawText(text, rect: rect.insetBy(dx: 12, dy: 12), font: .italicSystemFont(ofSize: 12))
    }

    private func drawFooter(in context: CGContext, rect: CGRect, page: Int) {
        drawText("Erstellt mit SpektoWatch", rect: CGRect(x: 40, y: rect.height - 28, width: 220, height: 16), font: .systemFont(ofSize: 9))
        drawText("Seite \(page)", rect: CGRect(x: rect.width - 120, y: rect.height - 28, width: 80, height: 16), font: .systemFont(ofSize: 9), alignment: .right)
    }

    private func drawText(_ text: String, rect: CGRect, font: UIFont, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ]
        text.draw(in: rect, withAttributes: attributes)
    }

    private func loadBroadbandValues(reader: MeasurementDataReader?) throws -> [Float] {
        guard let reader, reader.frameCount > 0 else { return [recordingFallbackValue] }
        var values: [Float] = []
        values.reserveCapacity(reader.frameCount)
        for index in 0..<reader.frameCount {
            values.append(try reader.readFrame(at: index).broadbandLevel)
        }
        return values
    }

    private var recordingFallbackValue: Float { -120.0 }

    private func loadAverageThirdOctaves(reader: MeasurementDataReader?) throws -> (z: [Float], a: [Float], c: [Float]) {
        let count = MeasurementDataFormat.thirdOctaveBandCount
        guard let reader, reader.frameCount > 0 else {
            let empty = [Float](repeating: -120.0, count: count)
            return (empty, empty, empty)
        }

        var z = [Float](repeating: 0, count: count)
        var a = [Float](repeating: 0, count: count)
        var c = [Float](repeating: 0, count: count)

        for index in 0..<reader.frameCount {
            let frame = try reader.readFrame(at: index)
            for i in 0..<count {
                z[i] += frame.thirdOctaveZ[i]
                a[i] += frame.thirdOctaveA[i]
                c[i] += frame.thirdOctaveC[i]
            }
        }

        let divider = Float(reader.frameCount)
        for i in 0..<count {
            z[i] /= divider
            a[i] /= divider
            c[i] /= divider
        }
        return (z, a, c)
    }

}
#endif

//
//  PDFReportSnapshotTests.swift
//  SpektoWatch2Tests
//
//  Example snapshot tests using the Xcode Cloud-friendly `ciAssertSnapshot`
//  helper. Tests are stubbed (`XCTSkipUnless canImport(SnapshotTesting)`)
//  until swift-snapshot-testing is wired into the test target.
//
//  See SnapshotTestSupport.swift for setup instructions and folder layout.
//
//  Why PDFReportGenerator first:
//  -----------------------------
//  - Deterministic output (no GPU, no Metal, no on-device fonts beyond
//    system stack).
//  - Catches both layout and copy regressions in a single artifact.
//  - Two complementary strategies on one fixture: rasterized first-page
//    image (`.image`) AND a textual document outline (`.lines`). Image
//    snapshots catch visual regressions; line snapshots catch wording
//    changes without pixel sensitivity.

import XCTest
import CoreLocation
#if canImport(UIKit)
import UIKit
import PDFKit
#endif
@testable import SpektoWatch2

#if canImport(SnapshotTesting)
import SnapshotTesting
#endif

final class PDFReportSnapshotTests: XCTestCase {

    override func setUpWithError() throws {
        #if !canImport(SnapshotTesting)
        throw XCTSkip("SnapshotTesting package not yet added to SpektoWatch2Tests. " +
                      "See SnapshotTestSupport.swift for setup instructions.")
        #endif
    }

    /// Smoke: render a known recording into PDF, snapshot the first page as
    /// a rasterized image with a permissive perceptual precision floor.
    @MainActor
    func testPDFReport_firstPageImage_matchesBaseline() throws {
        #if canImport(SnapshotTesting) && canImport(UIKit)
        let fixture = makeDeterministicReportFixture()
        let pdfData = try renderPDF(from: fixture)
        let pageImage = try rasterizeFirstPage(of: pdfData, scale: 2.0)

        ciAssertSnapshot(
            of: pageImage,
            as: .image(precision: 0.99, perceptualPrecision: 0.98)
        )
        #endif
    }

    /// Wording / structure snapshot — catches copy regressions and field
    /// reordering without being sensitive to font rendering.
    @MainActor
    func testPDFReport_documentOutline_matchesBaseline() throws {
        #if canImport(SnapshotTesting) && canImport(UIKit)
        let fixture = makeDeterministicReportFixture()
        let pdfData = try renderPDF(from: fixture)
        let outline = try extractTextOutline(from: pdfData)

        ciAssertSnapshot(of: outline, as: .lines)
        #endif
    }

    // MARK: - Fixture helpers
    //
    // These intentionally read from a checked-in fixture, never `Date()`,
    // never `Locale.current`, never random IDs. Snapshot tests die on any
    // non-determinism.

    /// Frozen `Recording` whose audio + measurement files intentionally do
    /// not exist on disk. `PDFReportGenerator` falls through to its built-in
    /// placeholder paths for spectrogram + bandcharts, which is exactly what
    /// we want: a deterministic render that exercises layout, header, copy,
    /// and the summary table without depending on AVAudioFile output.
    private func makeDeterministicReportFixture() -> Recording {
        // 2026-01-01T00:00:00Z, in seconds since 2001 reference date.
        let frozenStart = Date(timeIntervalSinceReferenceDate: 788_918_400)
        let frozenID = UUID(uuidString: "00000000-0000-0000-0000-00000000F1FF")!
        return Recording(
            id: frozenID,
            name: "Snapshot Fixture",
            description: "Deterministic fixture for PDF snapshot tests.",
            startDate: frozenStart,
            duration: 125,
            audioFileName: "snapshot-fixture-missing.m4a",
            measurementDataFileName: nil,
            sampleRate: 48_000,
            channelCount: 1,
            laeqFast: 62.5,
            peakLevel: 88.1,
            minLevel: 31.4,
            location: CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050),
            photoFileNames: [],
            tags: ["snapshot", "fixture"],
            timeWeighting: "Fast",
            frequencyWeighting: "A",
            widgetConfigurations: nil,
            markers: nil,
            calibrationOffset: 94.0,
            fftBlockSize: 4096
        )
    }

    @MainActor
    private func renderPDF(from fixture: Recording) throws -> Data {
        #if canImport(UIKit)
        let manager = RecordingManager()
        let generator = PDFReportGenerator()
        let url = try generator.generateReport(for: fixture, recordingManager: manager)
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
        #else
        throw XCTSkip("PDF rendering requires UIKit.")
        #endif
    }

    #if canImport(UIKit)
    private func rasterizeFirstPage(of data: Data, scale: CGFloat) throws -> UIImage {
        guard let document = PDFDocument(data: data),
              let page = document.page(at: 0) else {
            throw NSError(domain: "PDFReportSnapshotTests",
                          code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "PDF has no first page"])
        }
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox)
    }

    private func extractTextOutline(from data: Data) throws -> [String] {
        guard let document = PDFDocument(data: data) else {
            throw NSError(domain: "PDFReportSnapshotTests",
                          code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not open PDF"])
        }
        var lines: [String] = []
        for index in 0..<document.pageCount {
            guard let pageText = document.page(at: index)?.string else { continue }
            for raw in pageText.split(whereSeparator: { $0.isNewline }) {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { lines.append(trimmed) }
            }
            lines.append("---page-break---")
        }
        return lines
    }
    #endif
}

#if !canImport(UIKit)
// PDF rasterization helpers above assume UIKit (iOS test target). If the
// snapshot suite is ever ported to a non-UIKit target, swap UIImage for
// NSImage and PDFDocument's macOS APIs.
#endif

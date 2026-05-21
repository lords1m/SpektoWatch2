# Task 2: PDF Report Fixture

Status: in_progress
Created: 2026-05-20
Milestone: `milestone-7-xcode-cloud-snapshot-testing`
Depends on: task-1

## Progress (2026-05-20)

All four `fatalError` stubs in `SpektoWatch2Tests/PDFReportSnapshotTests.swift`
are replaced with real implementations:

- ✅ `makeDeterministicReportFixture()` returns a frozen `Recording` with
  `id = 00000000-0000-0000-0000-00000000F1FF`,
  `startDate = Date(timeIntervalSinceReferenceDate: 788_918_400)` (=
  2026-01-01T00:00:00Z), nil `measurementDataFileName`, and a nonexistent
  `audioFileName`. The generator then falls through to its built-in
  placeholders for spectrogram and band charts — exactly the deterministic
  baseline we want for layout + copy snapshots without depending on
  AVAudioFile output.
- ✅ `renderPDF(from:)` routes through
  `PDFReportGenerator().generateReport(for:recordingManager:)` (the same
  entry point M6 task-2 consolidated through `RecordingManager`). Writes
  to the generator's temp URL, reads bytes back, deletes the temp file.
  Test method now `@MainActor` because `generateReport` is `@MainActor`.
- ✅ `rasterizeFirstPage(of:scale:)` uses
  `PDFDocument(data:) → page(at: 0)?.thumbnail(of:for:)` at a fixed size
  derived from the page's `mediaBox` × scale.
- ✅ `extractTextOutline(from:)` walks pages, splits on newlines, trims
  whitespace, drops empties, and inserts `---page-break---` between pages.

Determinism caveats:

- `Recording.formattedDate` uses `Locale(identifier: "de_DE")` but reads
  `TimeZone.current`. The test plan now pins `TZ=UTC`, so the rendered
  `Datum:` line will be stable on Xcode Cloud (which uses UTC by default
  anyway, but explicit pin is safer for developer machines).
- `PDFReportGenerator` does not call `Date()` or `DateFormatter` directly
  (grepped); the only date path is `recording.formattedDate` and
  `recording.formattedDuration`, both of which are pure functions of the
  pinned `startDate` / `duration` once timezone is fixed.
- `RecordingManager()` ctor calls `loadRecordings()` from
  `~/Documents/Recordings` — that side-effect doesn't reach the
  rendered PDF (the only `RecordingManager` API the generator uses are
  `url(for:)`, `measurementURL(for:)`, and `getPhotoURL(fileName:)`,
  all pure path concatenation).

Outstanding (validation gates):

- ⏳ Triple-invocation determinism check (acceptance bullets 2–4) cannot
  be run locally — simulator is broken per AGENT.md. Will be confirmed
  on the first Xcode Cloud run in task 3.
- ⏳ If a PDF metadata `CreationDate` field is embedded by UIKit's
  `UIGraphicsPDFRenderer`, the `.lines` snapshot will be stable
  (`PDFDocument.page(at:).string` does not surface metadata) but the
  `.image` snapshot will be stable too (metadata is not rendered into
  pixels). Both strategies should be deterministic once timezone is
  pinned — to be confirmed empirically on Xcode Cloud.

## Objective

Replace the four `fatalError` stubs in `PDFReportSnapshotTests.swift` with
fully deterministic fixture helpers. Snapshot tests die instantly on any
non-determinism (timestamps, locale, random IDs, file ordering, font
fallback), so this task is mostly about freezing every input.

## Scope

1. `makeDeterministicReportFixture()`
   - Build a frozen `RecordingMetadata` (or whatever shape
     `PDFReportGenerator` consumes — match exactly what the production
     export path passes from `RecordingManager`).
   - All timestamps: `Date(timeIntervalSince1970: 1767225600)` (= 2026-01-01
     00:00 UTC) or other fixed epochs.
   - Locale: pass `Locale(identifier: "en_US_POSIX")` everywhere the
     fixture or report formatter touches locale.
   - Time zone: `TimeZone(identifier: "UTC")!`.
   - Measurement samples: inline arrays in the test file. No reading from
     disk. No `Date()`. No `UUID()`. If the report includes a recording UUID,
     hard-code `UUID(uuidString: "00000000-0000-0000-0000-000000000001")!`.

2. `renderPDF(from:)`
   - Call the same `PDFReportGenerator` entry point that
     `RecordingManager` uses for production exports (per M6 task-2
     consolidation). Do not re-implement the rendering path — that
     defeats the purpose of the snapshot.
   - Return `Data`. If the generator writes to a URL, write to a temp
     directory and read the bytes back.

3. `rasterizeFirstPage(of:scale:)`
   - `PDFDocument(data: data)?.page(at: 0)?.thumbnail(of:, for: .mediaBox)`
     at a fixed `CGSize` (e.g. 612 × 792 × scale). Do not use
     `UIScreen.main.scale` — pin the scale.
   - Return `UIImage`.

4. `extractTextOutline(from:)`
   - Walk `PDFDocument` pages, collect `page.string ?? ""` per page,
     `components(separatedBy: .newlines)`, trim each line, drop empties.
   - Return `[String]`. Stable across font rendering changes.

## Acceptance

- All four helpers are implemented; no `fatalError` remains.
- Calling `makeDeterministicReportFixture()` twice in the same process
  returns equivalent values (deep equality if the type is `Equatable`;
  otherwise verify by encoding to JSON and comparing strings).
- `renderPDF(from:)` returns the same byte count on three back-to-back
  invocations (PDF byte equality is too strict because of metadata
  timestamps inside the PDF — count is a useful weaker check).
- `extractTextOutline(from:)` returns the same `[String]` on three
  back-to-back invocations.
- Test methods still call `ciAssertSnapshot(...)` — no other assertion
  framework is mixed in.

## Non-Goals

- Recording baselines (task 3).
- Additional snapshot subjects beyond PDF.
- Refactoring `PDFReportGenerator` itself. If it has non-determinism (e.g.
  embedded `CreationDate` in the PDF metadata), document it in the task
  notes and let the image / lines snapshots ignore it — do not modify
  production code in this milestone.

## Notes

- If `PDFReportGenerator` internally calls `Date()` for a "report
  generated at" field, the rasterized snapshot will diff on every run.
  Two options: (a) parameterize the generator with an injected `Date`
  (preferred, small surface), or (b) crop the timestamp region out of
  the rasterized image before snapshotting. Choose (a) if the generator
  already takes a context object; (b) if the change would ripple.
- Watch out for `NSAttributedString` font fallback — if the PDF uses a
  font that isn't on every Apple-silicon simulator image, rendering
  drifts. Stick to system fonts.

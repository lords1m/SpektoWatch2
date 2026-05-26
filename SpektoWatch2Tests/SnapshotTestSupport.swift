//
//  SnapshotTestSupport.swift
//  SpektoWatch2Tests
//
//  Bundled-resources snapshot-testing pattern for Xcode Cloud.
//
//  Why this file exists:
//  ---------------------
//  swift-snapshot-testing resolves the snapshot directory from `#filePath`,
//  a StaticString baked in at compile time. Xcode Cloud builds tests on one
//  machine and runs them on another — that compile-time path does not exist
//  on the test runner, so `assertSnapshot` either fails to find baselines
//  or silently records new ones every run.
//
//  Fix: ship the snapshots inside the .xctest bundle as resources. At runtime
//  we point swift-snapshot-testing at the bundled location instead of the
//  baked-in source path.
//
//  Folder convention (must match exactly):
//  ---------------------------------------
//      SpektoWatch2Tests/
//        __Snapshots__/                <-- add as Folder Reference (blue) in
//          MyClassNameTests/           <-- Xcode, with `Create folder references`,
//            testFoo.1.png             <-- target membership = SpektoWatch2Tests
//          OtherClassNameTests/
//            testBar.1.png
//
//  Do NOT add `__Snapshots__` itself as a target resource; add the
//  per-class folders inside it as folder references. Names must match the
//  test class name exactly (case-sensitive). This is the Jaanus pattern.
//
//  Xcode setup (one-time, manual):
//  -------------------------------
//  1. File > Add Package Dependencies... >
//     https://github.com/pointfreeco/swift-snapshot-testing  (>= 1.17.4)
//     Add product `SnapshotTesting` to the `SpektoWatch2Tests` target.
//  2. Create `SpektoWatch2Tests/__Snapshots__/<TestClassName>/` directories
//     for each snapshot test class. Drag them into the test target as
//     folder references (blue folders).
//  3. In the test plan, pin a single device + OS (e.g. iPhone 15 / iOS 17.5)
//     and a single locale/region/appearance/dynamic-type. Snapshot tests
//     are pixel-sensitive to all of these.
//  4. Snapshots run in Xcode Cloud only (per AGENT.md, the local simulator
//     is broken — do not run xcodebuild test locally).
//
//  Recording mode:
//  ---------------
//  Pass `record: true` per-call to record new baselines, or set the env var
//  `RECORD_SNAPSHOTS=YES` on the Xcode Cloud workflow to re-record
//  everything. Never let record mode reach main.

#if canImport(SnapshotTesting)
import SnapshotTesting
import XCTest
import Foundation

/// Drop-in replacement for `assertSnapshot` that finds baselines inside the
/// .xctest bundle when running on a CI machine that doesn't have the source
/// tree mounted (Xcode Cloud).
///
/// Falls through to the standard behaviour locally so the regular record /
/// review workflow keeps working.
public func ciAssertSnapshot<Value, Format>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, Format>,
    named name: String? = nil,
    record recording: Bool? = nil,
    timeout: TimeInterval = 5,
    testClass: AnyClass,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) {
    let recordMode = recording ?? isRecordModeEnabled()
    let directory = snapshotDirectory(for: testClass, sourceFile: file, recordMode: recordMode)

    let failure = verifySnapshot(
        of: try value(),
        as: snapshotting,
        named: name,
        record: recordMode ? .all : nil,
        snapshotDirectory: directory,
        timeout: timeout,
        file: file,
        testName: testName
    )

    if let message = failure {
        XCTFail(message, file: file, line: line)
    }
}

/// XCTestCase convenience — picks up `testClass` automatically.
public extension XCTestCase {
    func ciAssertSnapshot<Value, Format>(
        of value: @autoclosure () throws -> Value,
        as snapshotting: Snapshotting<Value, Format>,
        named name: String? = nil,
        record recording: Bool? = nil,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let recordMode = recording ?? isRecordModeEnabled()
        let directory = snapshotDirectory(for: type(of: self), sourceFile: file, recordMode: recordMode)

        let failure = verifySnapshot(
            of: try value(),
            as: snapshotting,
            named: name,
            record: recordMode ? .all : nil,
            snapshotDirectory: directory,
            timeout: timeout,
            file: file,
            testName: testName
        )

        if let message = failure {
            XCTFail(message, file: file, line: line)
        }
    }
}

public func ciSnapshotBaselinesAvailable(for testClass: AnyClass) -> Bool {
    bundledSnapshotDirectoryWithBaselines(for: testClass) != nil
}

// MARK: - Path resolution

/// Resolves the snapshot directory:
///   1. If a folder named `<TestClassName>` exists inside the test bundle's
///      `__Snapshots__/`, use that (Xcode Cloud path).
///   2. Otherwise fall back to `<source file dir>/__Snapshots__/<TestClassName>`
///      so local record / review continues to work normally.
private func snapshotDirectory(
    for testClass: AnyClass,
    sourceFile: StaticString,
    recordMode: Bool
) -> String {
    let className = String(describing: testClass)
        .components(separatedBy: ".")
        .last ?? String(describing: testClass)

    let sourceDirectory = sourceSnapshotDirectory(for: className, sourceFile: sourceFile)
    if recordMode {
        return sourceDirectory
    }

    if let bundled = bundledSnapshotDirectoryWithBaselines(for: testClass) {
        return bundled.path
    }

    return sourceDirectory
}

private func bundledSnapshotDirectoryWithBaselines(for testClass: AnyClass) -> URL? {
    let className = String(describing: testClass)
        .components(separatedBy: ".")
        .last ?? String(describing: testClass)

    guard let resourceURL = Bundle(for: testClass).resourceURL else {
        return nil
    }

    let bundled = resourceURL
        .appendingPathComponent("__Snapshots__", isDirectory: true)
        .appendingPathComponent(className, isDirectory: true)

    return directoryContainsSnapshotBaselines(bundled) ? bundled : nil
}

private func sourceSnapshotDirectory(for className: String, sourceFile: StaticString) -> String {
    let sourceURL = URL(fileURLWithPath: "\(sourceFile)", isDirectory: false)
    return sourceURL
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__", isDirectory: true)
        .appendingPathComponent(className, isDirectory: true)
        .path
}

private func directoryContainsSnapshotBaselines(_ url: URL) -> Bool {
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return false
    }

    return contents.contains { item in
        guard (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return false
        }
        return item.lastPathComponent != "README.txt"
    }
}

private func isRecordModeEnabled() -> Bool {
    let env = ProcessInfo.processInfo.environment
    let value = env["RECORD_SNAPSHOTS"]?.lowercased()
    return value == "yes" || value == "true" || value == "1"
}

#else
#warning("""
SnapshotTesting is not available. Add the swift-snapshot-testing package to \
SpektoWatch2Tests (File > Add Package Dependencies...) to enable snapshot tests.
""")
#endif

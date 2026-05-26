import XCTest

extension XCTestCase {

    /// Captures a screenshot, attaches it to the test result with `keepAlways`
    /// lifetime, and writes a PNG sidecar to the system temp directory so
    /// `capture-screenshots.py` can pick it up later.
    ///
    /// The attachment name encodes device + iOS version so multi-device Xcode
    /// Cloud matrix runs produce distinguishable artifacts.
    func capture(
        _ screenshotName: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        settle()

        let screenshot = XCUIScreen.main.screenshot()
        let qualifiedName = "\(deviceTag())-\(screenshotName)"

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = qualifiedName
        attachment.lifetime = .keepAlways
        add(attachment)

        // Sidecar PNG for capture-screenshots.py extraction.
        let testClass = String(describing: type(of: self))
        let testName = self.name
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITestScreenshots", isDirectory: true)
            .appendingPathComponent(sanitizeFilename(testClass), isDirectory: true)
            .appendingPathComponent(sanitizeFilename(testName), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(sanitizeFilename(qualifiedName)).png")
        try? screenshot.pngRepresentation.write(to: fileURL)
    }

    /// Waits for in-flight animations / async state updates to settle.
    func settle(_ duration: TimeInterval = 0.7) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }

    /// Sanitises a string so it is safe to use as a filename component.
    func sanitizeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return value.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : Character("_") }
            .reduce("") { $0 + String($1) }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .isEmpty ? "screenshot"
            : value.unicodeScalars
                .map { allowed.contains($0) ? Character($0) : Character("_") }
                .reduce("") { $0 + String($1) }
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    // MARK: - Private

    private func deviceTag() -> String {
        let env = ProcessInfo.processInfo.environment
        let device = env["SIMULATOR_DEVICE_NAME"]
            ?? env["DEVICE_NAME"]
            ?? "Device"
        let os = env["SIMULATOR_RUNTIME_VERSION"]
            ?? env["OS_VERSION"]
            ?? ""
        return os.isEmpty ? device : "\(device)-iOS\(os)"
    }
}

// MARK: - Failure screenshot

extension XCTestCase {

    /// Override to automatically capture a screenshot on test failure so every
    /// failed run ships with its visual context in the xcresult bundle.
    open override func tearDown() {
        if let run = testRun, !run.hasSucceeded {
            XCTContext.runActivity(named: "Failure screenshot") { _ in
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "FAILURE-\(name)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        super.tearDown()
    }
}

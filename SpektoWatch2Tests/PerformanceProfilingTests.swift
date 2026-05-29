import XCTest
import MetalKit
import Combine
import SwiftUI
import UIKit
import os
@testable @preconcurrency import SpektoWatch2

// MARK: - Pipeline Overview
//
// [Audio Tap 512 samples] → [SampleBuffer] → (fftSize samples accumulated)
//      → [1] FFTProcessor.performFFT
//      → [2] FFTProcessor.convertToDB
//      → [3] FrequencyWeightingProcessor.applyWeighting
//      → [4] SpectrogramProcessor.process  (bandstop, octave, binning, smoothing)
//      → [AudioEngine emits SpectrogramData via spectrogramSubject]
//      → [5] HighEndSpectrogramAdapter.updateWithFFTMagnitudes (mapping + texture write)
//      → [Metal draw (async GPU)]
//
// FPS Budget at Fast scroll (hopSize=512, 44100 Hz): 44100/512 ≈ 86 Hz → ~11.6 ms/frame

@MainActor
final class PerformanceProfilingTests: XCTestCase {

    private let iterations: Int = {
        if let raw = ProcessInfo.processInfo.environment["SPEKTO_PERF_ITERS"],
           let value = Int(raw),
           value > 0 {
            return value
        }
        return 500
    }()
    private let sampleRate: Double = 44100.0
    private let shouldPrintReport: Bool = {
        ProcessInfo.processInfo.environment["SPEKTO_PERF_REPORT"] == "1"
    }()
    private final class DisplayLinkFrameCounter: NSObject {
        var frames: Int = 0
        @objc func step() { frames += 1 }
    }

    // Static singletons: never deallocated → avoids os_signpost TaskLocal deinit crash.
    private static let sharedFilterMgr  = BandstopFilterManager()
    private static let sharedSpectProc  = SpectrogramProcessor(bandstopFilterManager: sharedFilterMgr)

    // MARK: - Stage 1: FFT

    /// Misst FFT-Laufzeit bei verschiedenen Blockgrößen.
    /// Regression: 8192-FFT muss unter 5 ms bleiben.
    func testStage1_FFTPerformance() {
        let configs: [(size: Int, label: String)] = [
            (1024,  "1024 "),
            (2048,  "2048 "),
            (4096,  "4096 "),
            (8192,  "8192 "),
            (16384, "16384"),
        ]

        report("\n┌────────────────────────────────────────────────┐")
        report("│  STAGE 1: FFT Computation (Accelerate vDSP)   │")
        report("├─────────────┬────────────┬──────────┬─────────┤")
        report("│  Block Size │  Mean (µs) │ Mean(ms) │ Max FPS │")
        report("├─────────────┼────────────┼──────────┼─────────┤")

        for cfg in configs {
            let proc = FFTProcessor(fftSize: cfg.size, sampleRate: sampleRate)
            let samples = makeSineWave(frequency: 1000, count: cfg.size)
            let (meanUs, fps) = bench(n: iterations) { _ = proc.performFFT(on: samples) }
            let line = "│  \(cfg.label)        │\(fmt9(meanUs))  │\(fmt7ms(meanUs)) │\(fmt6fps(fps)) │"
            report(line)
        }
        report("└─────────────┴────────────┴──────────┴─────────┘")

        // Regression
        let refProc = FFTProcessor(fftSize: 8192, sampleRate: sampleRate)
        let refSamples = makeSineWave(frequency: 440, count: 8192)
        let (meanUs, _) = bench(n: iterations) { _ = refProc.performFFT(on: refSamples) }
        XCTAssertLessThan(meanUs / 1000.0, 5.0,
            "FFT(8192) regression: \(String(format: "%.2f", meanUs/1000.0)) ms > 5 ms budget")
    }

    // MARK: - Stage 2: dB Conversion

    /// Misst vDSP-basierte dB-Konvertierung.
    func testStage2_DBConversion() {
        let configs: [(bins: Int, label: String)] = [
            (512,  "512  "), (1024, "1024 "), (2048, "2048 "), (4096, "4096 "),
        ]

        report("\n┌──────────────────────────────────────────────────┐")
        report("│  STAGE 2: dB Conversion (vDSP_vdbcon)           │")
        report("├──────────┬────────────┬────────────┬────────────┤")
        report("│  Bins    │  Mean (µs) │  Mean (ms) │    Max FPS │")
        report("├──────────┼────────────┼────────────┼────────────┤")

        for cfg in configs {
            let proc = FFTProcessor(fftSize: cfg.bins * 2, sampleRate: sampleRate)
            let mags = [Float](repeating: 0.5, count: cfg.bins)
            let (meanUs, fps) = bench(n: iterations) { _ = proc.convertToDB(mags) }
            report("│  \(cfg.label)   │\(fmt9(meanUs))  │\(fmt8ms4(meanUs)) │\(fmt9fps(fps)) │")
        }
        report("└──────────┴────────────┴────────────┴────────────┘")
    }

    // MARK: - Stage 3: Frequency Weighting

    /// Vergleicht A-, C- und Z-Bewertungsfilter bei 8192 Bins.
    func testStage3_FrequencyWeighting() {
        let fftSize = 8192
        let proc = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate)
        let weightProc = FrequencyWeightingProcessor(fftSize: fftSize, sampleRate: sampleRate)
        let mags = proc.performFFT(on: makeSineWave(frequency: 1000, count: fftSize))
        let dbMags = proc.convertToDB(mags)
        let freqs = proc.frequencies

        report("\n┌───────────────────────────────────────────────────┐")
        report("│  STAGE 3: Frequency Weighting (8192 bins)         │")
        report("├────────────┬────────────┬────────────┬────────────┤")
        report("│  Weighting │  Mean (µs) │  Mean (ms) │    Max FPS │")
        report("├────────────┼────────────┼────────────┼────────────┤")

        for weighting in FrequencyWeighting.allCases {
            let (meanUs, fps) = bench(n: iterations) {
                _ = weightProc.applyWeighting(to: dbMags, frequencies: freqs, weighting: weighting)
            }
            let wLabel = weighting.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
            report("│  \(wLabel)  │\(fmt9(meanUs))  │\(fmt8ms4(meanUs)) │\(fmt9fps(fps)) │")
        }
        report("└────────────┴────────────┴────────────┴────────────┘")
    }

    // MARK: - Stage 4: SpectrogramProcessor

    /// Zeigt wie viel Zeit SpectrogramProcessor insgesamt und mit/ohne Binning braucht.
    func testStage4_SpectrogramProcessorBreakdown() {
        let fftSize = 8192
        let fftProc = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate)
        let mags = fftProc.performFFT(on: makeSineWave(frequency: 1000, count: fftSize))
        let dbMags = fftProc.convertToDB(mags)
        let freqs = fftProc.frequencies
        let sr = sampleRate
        let n = iterations

        // Use shared static instance – never deallocated, so os_signpost TaskLocal deinit
        // crash cannot occur regardless of @MainActor context.
        let processor = Self.sharedSpectProc
        var fullUs: Double = 0; var fullFPS: Double = 0
        var noBinUs: Double = 0; var noBinFPS: Double = 0

        processor.binningFactor = 2
        (fullUs, fullFPS) = bench(n: n) {
            _ = processor.process(frequencies: freqs, dbMagnitudes: dbMags, sampleRate: sr, smoothingTrack: .z)
        }
        processor.binningFactor = 1
        (noBinUs, noBinFPS) = bench(n: n) {
            _ = processor.process(frequencies: freqs, dbMagnitudes: dbMags, sampleRate: sr, smoothingTrack: .z)
        }

        let binCost = max(0.0, fullUs - noBinUs)
        let binPct  = fullUs > 0 ? 100.0 * binCost / fullUs : 0

        report("\n┌─────────────────────────────────────────────────────┐")
        report("│  STAGE 4: SpectrogramProcessor (8192 bins in)       │")
        report("├──────────────────────┬────────────┬─────────────────┤")
        report("│  Configuration       │  Mean (µs) │  Max FPS        │")
        report("├──────────────────────┼────────────┼─────────────────┤")
        report("│  Full (binFactor=2)  │\(fmt9(fullUs))  │\(fmt9fps(fullFPS))       │")
        report("│  No binning          │\(fmt9(noBinUs))  │\(fmt9fps(noBinFPS))       │")
        report("│  Binning overhead    │\(fmt9(binCost))  │  \(String(format: "%.0f", binPct))% share           │")
        report("└──────────────────────┴────────────┴─────────────────┘")

        XCTAssertLessThan(fullUs / 1000.0, 8.0,
            "SpectrogramProcessor regression: \(String(format: "%.2f", fullUs/1000.0)) ms > 8 ms budget")
    }

    // MARK: - Stage 5: HighEndSpectrogramAdapter CPU Work

    /// Misst Mapping-Cache-Aufbau und gecachte Texture-Writes (CPU-Seite).
    /// Metal-Rendering (GPU draw) wird in Tests nicht ausgeführt.
    func testStage5_AdapterCPUWork() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal nicht verfügbar (Simulator ohne Metal-Support)")
        }

        let adapter = HighEndSpectrogramAdapter(
            frame: CGRect(x: 0, y: 0, width: 400, height: 600),
            device: device
        )

        let fftProc = FFTProcessor(fftSize: 8192, sampleRate: sampleRate)
        let mags = fftProc.performFFT(on: makeSineWave(frequency: 1000, count: 8192))
        let dbMags = fftProc.convertToDB(mags)
        let now = Date()

        // Erster Aufruf: baut Mapping-Cache auf (2048 Bins mit log-Mathematik)
        let buildStart = CFAbsoluteTimeGetCurrent()
        adapter.updateWithFFTMagnitudes(dbMags, sampleRate: sampleRate, timestamp: now)
        let buildUs = (CFAbsoluteTimeGetCurrent() - buildStart) * 1_000_000.0

        // Folgeaufrufe: Cache gecacht, nur Texture-Column-Write
        let (cachedUs, cachedFPS) = bench(n: iterations) {
            adapter.updateWithFFTMagnitudes(dbMags, sampleRate: sampleRate, timestamp: now)
        }

        report("\n┌──────────────────────────────────────────────────────────┐")
        report("│  STAGE 5: HighEndSpectrogramAdapter CPU (2048 freq bins) │")
        report("├───────────────────────────────────────┬──────────────────┤")
        report("│  Operation                            │  Time            │")
        report("├───────────────────────────────────────┼──────────────────┤")
        report(String(format: "│  First call (cache build + write)     │  %8.1f µs     │", buildUs))
        report(String(format: "│  Cached calls (write only, mean)      │  %8.1f µs     │", cachedUs))
        report(String(format: "│  Max FPS (cached path)                │  %8.0f FPS    │", cachedFPS))
        report("└───────────────────────────────────────┴──────────────────┘")

        XCTAssertLessThan(cachedUs / 1000.0, 3.0,
            "Adapter CPU regression: \(String(format: "%.2f", cachedUs/1000.0)) ms > 3 ms budget")
    }

    // MARK: - FPS Budget: Published Frames

    /// Misst tatsächlich von AudioEngine emittierte High-rate-FPS bei verschiedenen Scroll-Geschwindigkeiten.
    func testFPSBudget_DifferentScrollSpeeds() {
        struct Cfg {
            let speed: ScrollSpeed; let minFPS: Double; let label: String
        }
        let configs: [Cfg] = [
            Cfg(speed: .fast,     minFPS: 60, label: "Fast    (hopSize=512,  ~86 FPS target)"),
            Cfg(speed: .normal,   minFPS: 30, label: "Normal  (hopSize=1024, ~43 FPS target)"),
            Cfg(speed: .slow,     minFPS: 15, label: "Slow    (hopSize=2048, ~21 FPS target)"),
            Cfg(speed: .verySlow, minFPS:  8, label: "VsSlow  (hopSize=4096, ~10 FPS target)"),
        ]

        report("\n┌────────────────────────────────────────────────────────────────┐")
        report("│  FPS BUDGET: High-rate SpectrogramData Frames Per Second      │")
        report("├──────────────────────────────────────────┬─────────────────────┤")
        report("│  Config                                  │  Measured / Min FPS │")
        report("├──────────────────────────────────────────┼─────────────────────┤")

        for cfg in configs {
            let filterMgr = BandstopFilterManager()
            let connMgr = WatchConnectivityManager()
            let engine = AudioEngine(filterManager: filterMgr, connectivityManager: connMgr)
            engine.scrollSpeed = cfg.speed

            let hopSize = cfg.speed.rawValue
            let fftSize = engine.currentBlockSize.rawValue
            let chunk = makeSineWave(frequency: 440, count: hopSize)

            var publishedFrames = 0
            let lock = NSLock()
            let cancellable = engine.spectrogramSubject
                .sink { _ in
                    lock.lock(); publishedFrames += 1; lock.unlock()
                }
            defer { cancellable.cancel() }

            // Warmup: FFT-Buffer füllen
            let warmupChunks = Int(ceil(Double(fftSize) / Double(hopSize))) + 4
            for _ in 0..<warmupChunks { engine.processExternalAudio(chunk) }
            drainMainQueue()
            lock.lock(); publishedFrames = 0; lock.unlock()

            // Messen: Die Chunks werden synthetisch ohne Echtzeit-Wartezeit eingespeist.
            // Daher muss die Cadence gegen simulierte Audiozeit bewertet werden, nicht
            // gegen CPU-Wall-Clock-Zeit des Test-Runners.
            let measuredChunks = 200
            for _ in 0..<measuredChunks { engine.processExternalAudio(chunk) }
            drainMainQueue()

            lock.lock(); let frames = publishedFrames; lock.unlock()
            let simulatedDuration = Double(measuredChunks * hopSize) / sampleRate
            let fps = frames > 0 ? Double(frames) / max(simulatedDuration, 0.001) : 0.0

            let label = cfg.label.padding(toLength: 40, withPad: " ", startingAt: 0)
            report(String(format: "│  %@  │  %6.1f / %4.0f FPS    │", label, fps, cfg.minFPS))

            XCTAssertGreaterThanOrEqual(fps, cfg.minFPS,
                "FPS regression [\(cfg.label)]: \(String(format: "%.1f", fps)) FPS < \(cfg.minFPS) FPS minimum")
        }
        report("└──────────────────────────────────────────┴─────────────────────┘")
    }

    // MARK: - FPS Budget: Widgets

    /// Misst die effektive Render-Cadence eines echten SwiftUI-Widget-Stacks (Canvas-basiert).
    /// Dieser Test ist ein Regression-Guard für sichtbares Dashboard-Rendering unter Live-Updates.
    func testWidgetRenderFPSBudget() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("FPS measurement is not meaningful on the simulator; run on device")
        #endif
        let filterMgr = BandstopFilterManager()
        let connMgr = WatchConnectivityManager()
        let engine = AudioEngine(filterManager: filterMgr, connectivityManager: connMgr)

        let historySettings: [String: String] = [
            WidgetSettings.useWidgetOverridesKey: "1",
            "historyMetric": "LAF",
            "timeSpan": "5",
            "freqWeighting": "A",
            "timeWeighting": "Fast"
        ]
        let spectrumSettings: [String: String] = [
            WidgetSettings.useWidgetOverridesKey: "1",
            "freqWeighting": "A",
            "frequencyBands": "terz"
        ]

        let rootView = VStack(spacing: 8) {
            LevelHistoryWidget(audioEngine: engine, settings: historySettings)
                .frame(width: 360, height: 150)
            FrequencySpectrumWidget(audioEngine: engine, settings: spectrumSettings)
                .frame(width: 360, height: 150)
        }
        .frame(width: 390, height: 330)

        let host = UIHostingController(rootView: rootView)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 390))
        window.rootViewController = host
        window.makeKeyAndVisible()

        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let binCount = 1024
        let frequencies: [Float] = (0..<binCount).map { Float($0) * 22050.0 / Float(max(1, binCount - 1)) }
        let levelKeys = ["LAF", "LAS", "LCF", "LCS", "LZF", "LZS", "LAeq", "LAFmin", "LAFmax", "LAF5", "LAF95", "LAFT5", "LAFTeq", "LCpeak"]

        let phaseLock = OSAllocatedUnfairLock(initialState: Float(0))
        let updateTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            let phase = phaseLock.withLock { p -> Float in
                p += 0.045
                return p
            }
            var magnitudes = [Float](repeating: -90.0, count: binCount)
            for i in 0..<binCount {
                let x = Float(i) / Float(binCount)
                let harmonic = sinf((x * 28.0 + phase) * .pi)
                let envelope = expf(-x * 3.5)
                magnitudes[i] = -90.0 + envelope * (harmonic * 35.0 + 40.0)
            }

            let broadband = 65.0 + sinf(phase * 0.8) * 4.0
            var levels: [String: Float] = [:]
            for (index, key) in levelKeys.enumerated() {
                levels[key] = broadband + Float(index % 4) - 1.5
            }

            engine.live.currentSpectrogramData = SpectrogramData(
                frequencies: frequencies,
                magnitudes: magnitudes,
                magnitudesA: magnitudes,
                magnitudesC: magnitudes,
                broadbandLevel: broadband,
                levels: levels,
                sampleRate: 44100.0
            )
        }
        RunLoop.main.add(updateTimer, forMode: .common)
        defer { updateTimer.invalidate() }

        let frameCounter = DisplayLinkFrameCounter()
        let displayLink = CADisplayLink(target: frameCounter, selector: #selector(DisplayLinkFrameCounter.step))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        } else {
            displayLink.preferredFramesPerSecond = 60
        }
        displayLink.add(to: .main, forMode: .common)
        defer { displayLink.invalidate() }

        let duration: TimeInterval = 2.0
        let done = expectation(description: "Collect widget render frames")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            done.fulfill()
        }
        wait(for: [done], timeout: duration + 1.0)

        let fps = Double(frameCounter.frames) / duration
        let displayMax = Double(UIScreen.main.maximumFramesPerSecond)
        let minFPS = max(30.0, min(60.0, displayMax * 0.75))
        XCTAssertGreaterThanOrEqual(
            fps,
            minFPS,
            "Widget render FPS regression: measured \(String(format: "%.1f", fps)) FPS, expected >= \(minFPS) FPS"
        )
    }

    // MARK: - Bottleneck Summary

    /// Kombinierter ASCII-Bericht aller CPU-Stufen mit Bottleneck-Kennzeichnung.
    func testBottleneckSummary() {
        let fftSize = 8192
        let fftProc    = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate)
        let weightProc = FrequencyWeightingProcessor(fftSize: fftSize, sampleRate: sampleRate)

        let samples = makeSineWave(frequency: 1000, count: fftSize)

        let (fftUs, _)    = bench(n: 300) { _ = fftProc.performFFT(on: samples) }
        let mags          = fftProc.performFFT(on: samples)
        let (dbUs, _)     = bench(n: 300) { _ = fftProc.convertToDB(mags) }
        let dbMags        = fftProc.convertToDB(mags)
        let freqs         = fftProc.frequencies
        let (weightUs, _) = bench(n: 300) {
            _ = weightProc.applyWeighting(to: dbMags, frequencies: freqs, weighting: .a)
        }

        // Shared static instance avoids os_signpost TaskLocal deinit crash.
        var procUs: Double = 0
        (procUs, _) = bench(n: 300) {
            _ = Self.sharedSpectProc.process(frequencies: freqs, dbMagnitudes: dbMags, sampleRate: sampleRate, smoothingTrack: .z)
        }

        let cpuTotal  = fftUs + dbUs + weightUs + procUs
        let budgetUs  = 1_000_000.0 / 86.0  // 86 FPS ≈ 11628 µs
        let usagePct  = 100.0 * cpuTotal / budgetUs

        func row(_ name: String, _ us: Double) -> String {
            let pct   = cpuTotal > 0 ? us / cpuTotal : 0
            let bars  = min(16, Int(pct * 16))
            let bar   = String(repeating: "█", count: bars) + String(repeating: "░", count: 16 - bars)
            let flag  = pct > 0.4 ? "⚠" : " "
            let namePadded = name.padding(toLength: 10, withPad: " ", startingAt: 0)
            return String(format: "║  %@ ║ %8.1f µs ║ %7.2f ms ║ %5.1f%% ", namePadded, us, us / 1000.0, pct * 100)
                + bar + " " + flag + "║"
        }

        report("""

        ╔══════════════════════════════════════════════════════════════════╗
        ║      PIPELINE BOTTLENECK SUMMARY  (FFT=8192, Fast / 86 FPS)     ║
        ╠════════════╦══════════════╦═══════════╦══════════════════════════╣
        ║  Stage     ║   µs/frame   ║  ms/frame ║  Share  Breakdown     ⚠ ║
        ╠════════════╬══════════════╬═══════════╬══════════════════════════╣
        \(row("1  FFT",     fftUs))
        \(row("2  dB conv", dbUs))
        \(row("3  Wght A",  weightUs))
        \(row("4  Proc",    procUs))
        ╠════════════╬══════════════╬═══════════╬══════════════════════════╣
        ║  CPU Total ║\(String(format: " %8.1f µs ║ %7.2f ms ║ %5.1f%% of 86-FPS budget        ║", cpuTotal, cpuTotal/1000.0, usagePct))
        ╚════════════╩══════════════╩═══════════╩══════════════════════════╝
        Note: Metal texture write + GPU draw NOT measured (run on-device with Instruments).
        """)

        XCTAssertLessThan(cpuTotal / 1000.0, 8.0,
            "CPU total exceeds 8 ms budget: \(String(format: "%.2f", cpuTotal/1000.0)) ms. " +
            "Check stage with highest ⚠ flag above.")
    }

    // MARK: - Helpers

    private func makeSineWave(frequency: Float, count: Int) -> [Float] {
        (0..<count).map { sin(2 * .pi * frequency * Float($0) / Float(sampleRate)) * 0.5 }
    }

    /// Führt `block` n mal aus (mit Warmup) und gibt (µs/frame, max FPS) zurück.
    @discardableResult
    private func bench(n: Int, block: () -> Void) -> (meanUs: Double, maxFPS: Double) {
        for _ in 0..<min(10, n / 5) { block() }
        let t0 = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<n { block() }
        let t1 = DispatchTime.now().uptimeNanoseconds
        let meanUs = Double(t1 - t0) / 1_000.0 / Double(n)
        return (meanUs, meanUs > 0 ? 1_000_000.0 / meanUs : .infinity)
    }

    private func drainMainQueue() {
        let exp = expectation(description: "mainQueue")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 3.0)
    }

    private func report(_ message: String) {
        if shouldPrintReport {
            print(message)
        }
    }

    // MARK: - Formatters (avoid %s crash with Swift strings)

    private func fmt9(_ us: Double) -> String { String(format: " %8.1f ", us) }
    private func fmt6fps(_ fps: Double) -> String { String(format: " %5.0f  ", fps) }
    private func fmt9fps(_ fps: Double) -> String { String(format: " %7.0f  ", fps) }
    private func fmt7ms(_ us: Double) -> String { String(format: " %6.2f ", us / 1000.0) }
    private func fmt8ms4(_ us: Double) -> String { String(format: " %7.4f ", us / 1000.0) }
}

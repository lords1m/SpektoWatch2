import XCTest
import MetalKit
@testable import SpektoWatch2

final class PerformanceMetricsTests: XCTestCase {
    private let iterations: Int = {
        if let raw = ProcessInfo.processInfo.environment["SPEKTO_PERF_METRIC_ITERS"],
           let value = Int(raw),
           value > 0 {
            return value
        }
        return 10
    }()

    private let innerLoops: Int = {
        if let raw = ProcessInfo.processInfo.environment["SPEKTO_PERF_METRIC_LOOPS"],
           let value = Int(raw),
           value > 0 {
            return value
        }
        return 50
    }()

    private let sampleRate: Double = 44100.0

    private func metrics() -> [XCTMetric] {
        var list: [XCTMetric] = [XCTClockMetric()]
        if #available(iOS 13.0, *) {
            list.append(XCTCPUMetric())
            list.append(XCTMemoryMetric())
        }
        return list
    }

    private func options() -> XCTMeasureOptions {
        let opts = XCTMeasureOptions()
        opts.iterationCount = iterations
        return opts
    }

    private func loop(_ block: () -> Void) {
        for _ in 0..<innerLoops { block() }
    }

    func testFFT_Metrics() {
        let fftSize = 8192
        let proc = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate)
        let samples = makeSineWave(frequency: 1000, count: fftSize)

        measure(metrics: metrics(), options: options()) {
            loop {
                _ = proc.performFFT(on: samples)
            }
        }
    }

    func testSpectrogramProcessor_Metrics() {
        let fftSize = 8192
        let fftProc = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate)
        let mags = fftProc.performFFT(on: makeSineWave(frequency: 1000, count: fftSize))
        let dbMags = fftProc.convertToDB(mags)
        let freqs = fftProc.frequencies
        let processor = SpectrogramProcessor(bandstopFilterManager: BandstopFilterManager())

        measure(metrics: metrics(), options: options()) {
            loop {
                _ = processor.process(frequencies: freqs, dbMagnitudes: dbMags, sampleRate: sampleRate, smoothingTrack: .z)
            }
        }
    }

    func testAdapterCachedUpdate_Metrics() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal not available on this host")
        }

        let adapter = HighEndSpectrogramAdapter(
            frame: CGRect(x: 0, y: 0, width: 400, height: 600),
            device: device
        )

        let fftSize = 8192
        let fftProc = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate)
        let mags = fftProc.performFFT(on: makeSineWave(frequency: 1000, count: fftSize))
        let dbMags = fftProc.convertToDB(mags)
        let now = Date()

        // Warm cache
        adapter.updateWithFFTMagnitudes(dbMags, sampleRate: sampleRate, timestamp: now)

        measure(metrics: metrics(), options: options()) {
            loop {
                adapter.updateWithFFTMagnitudes(dbMags, sampleRate: sampleRate, timestamp: now)
            }
        }
    }

    func testAudioEngineExternalProcessing_Metrics() {
        let engine = AudioEngine(filterManager: BandstopFilterManager(), connectivityManager: WatchConnectivityManager())
        engine.scrollSpeed = .fast
        let hopSize = engine.scrollSpeed.rawValue
        let samples = makeSineWave(frequency: 440, count: hopSize)

        measure(metrics: metrics(), options: options()) {
            loop {
                engine.processExternalAudio(samples)
            }
        }
    }

    private func makeSineWave(frequency: Float, count: Int) -> [Float] {
        (0..<count).map { sin(2 * .pi * frequency * Float($0) / Float(sampleRate)) * 0.5 }
    }
}

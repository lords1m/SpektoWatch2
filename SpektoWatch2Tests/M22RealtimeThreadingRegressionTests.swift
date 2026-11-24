import XCTest
import AVFoundation
@testable import SpektoWatch2

/// Regression tests for M22 task-5 (real-time & threading safety).
/// Run the `SpektoWatch2Tests` plan configuration with Thread Sanitizer to get
/// the full value of the concurrency tests; Instruments checks for render-
/// thread allocations / lock waits are in task-8.
final class M22RealtimeThreadingRegressionTests: XCTestCase {

    // MARK: - RealtimeSlotQueue

    func testSlotQueueProcessesInOrderAndDrains() {
        let processed = OSAllocatedUnfairLock<[Int]>(initialState: [])
        let queue = RealtimeSlotQueue(capacity: 8, name: "test.slots") { slot in
            processed.withLock { $0.append(slot) }
        }
        var expected: [Int] = []
        for _ in 0..<200 {
            guard let slot = queue.acquireFreeSlot() else { continue }
            expected.append(slot)
            queue.enqueue(slot)
        }
        queue.drainAndStop()
        XCTAssertEqual(processed.withLock { $0 }, expected)
        XCTAssertNil(queue.acquireFreeSlot(), "Closed queue hands out no slots")
    }

    func testSlotQueueCountsDropsWhenFull() {
        let gate = DispatchSemaphore(value: 0)
        let queue = RealtimeSlotQueue(capacity: 2, name: "test.slots.full") { _ in gate.wait() }
        let a = queue.acquireFreeSlot()
        let b = queue.acquireFreeSlot()
        XCTAssertNotNil(a); XCTAssertNotNil(b)
        XCTAssertNil(queue.acquireFreeSlot())
        XCTAssertEqual(queue.droppedCount, 1)
        queue.enqueue(a!); queue.enqueue(b!)
        gate.signal(); gate.signal()
        queue.drainAndStop()
    }

    // MARK: - Measurement writer on the slot queue

    func testMeasurementWriterWritesAllFramesFromBackgroundThreads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString).spekto")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try MeasurementDataWriter(
            fileURL: url, metricKeys: ["LAF"], sampleRate: 48_000, fps: 50,
            fftBlockSize: 1024, fftBinCount: 0, maxPendingFrames: 512
        )
        let bands = [Float](repeating: 30, count: MeasurementDataFormat.thirdOctaveBandCount)
        let frames = 300
        let done = expectation(description: "frames")
        DispatchQueue.global(qos: .userInteractive).async {
            for i in 0..<frames {
                try? writer.writeFrame(timestamp: Float(i) / 50, metricValues: [50],
                                       broadbandLevel: 50, thirdOctaveZ: bands,
                                       thirdOctaveA: bands, thirdOctaveC: bands, fullFFT: [])
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        try writer.close()
        let reader = try MeasurementDataReader(fileURL: url)
        XCTAssertEqual(UInt64(reader.frameCount) + writer.droppedFrameCount, UInt64(frames))
        XCTAssertGreaterThan(reader.frameCount, 0)
    }

    // MARK: - RT-1 pipeline reconfiguration under load

    func testFFTReconfigurationWhileProcessingDoesNotCrash() {
        let engine = AudioEngine(filterManager: BandstopFilterManager(), connectivityManager: WatchConnectivityManager())
        let stop = OSAllocatedUnfairLock<Bool>(initialState: false)
        let finished = expectation(description: "producer finished")
        let samples = (0..<1024).map { Float(sin(Double($0) * 0.05)) * 0.1 }

        DispatchQueue.global(qos: .userInteractive).async {
            while !stop.withLock({ $0 }) {
                engine.processExternalAudio(samples, sampleRate: 44_100)
            }
            finished.fulfill()
        }

        let sizes: [FFTBlockSize] = [.size4096, .size2048, .size8192, .size1024]
        for i in 0..<40 {
            engine.setBlockSize(sizes[i % sizes.count])
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        stop.withLock { $0 = true }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(engine.currentBlockSize, sizes[39 % sizes.count])
    }
}

import Foundation
import os

/// M22 RT-5: hand-off of preallocated buffer *slots* from the audio render
/// thread to a dedicated worker thread without allocating, taking a blocking
/// lock, logging, or dispatching blocks on the render thread.
///
/// - `acquireFreeSlot()` / `enqueue(_:)` are render-thread safe: an
///   `OSAllocatedUnfairLock` around fixed-capacity, preallocated storage plus
///   one `DispatchSemaphore.signal()`.
/// - The worker thread runs `handler(slot)` for each enqueued slot in FIFO
///   order and then returns the slot to the free pool.
/// - `drainAndStop()` processes everything still queued and joins the worker.
final class RealtimeSlotQueue {
    private struct State {
        var queue: [Int]
        var head = 0
        var count = 0
        var free: [Int]
        var closing = false
        var dropped: UInt64 = 0
    }

    let capacity: Int
    private let state: OSAllocatedUnfairLock<State>
    private let available = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private var worker: Thread?
    private let stopLock = NSLock()
    private var stopped = false

    /// - Parameters:
    ///   - capacity: number of slots (`0..<capacity`), all initially free.
    ///   - handler: runs on the worker thread for each enqueued slot.
    init(capacity: Int, name: String, handler: @escaping (Int) -> Void) {
        let cap = max(1, capacity)
        self.capacity = cap
        var free = [Int]()
        free.reserveCapacity(cap)
        for i in stride(from: cap - 1, through: 0, by: -1) { free.append(i) }
        state = OSAllocatedUnfairLock(initialState: State(
            queue: [Int](repeating: 0, count: cap),
            free: free
        ))
        let available = self.available
        let finished = self.finished
        let state = self.state
        let thread = Thread {
            while true {
                available.wait()
                let next: Int? = state.withLockUnchecked { s in
                    guard s.count > 0 else { return nil }
                    let slot = s.queue[s.head]
                    s.head = (s.head + 1) % s.queue.count
                    s.count -= 1
                    return slot
                }
                if let slot = next {
                    handler(slot)
                    state.withLockUnchecked { $0.free.append(slot) }
                    continue
                }
                if state.withLockUnchecked({ $0.closing }) { break }
            }
            finished.signal()
        }
        thread.name = name
        thread.qualityOfService = .utility
        worker = thread
        thread.start()
    }

    deinit {
        drainAndStop()
    }

    /// Render-thread safe. `nil` when every slot is in flight (caller drops
    /// the frame and the drop is counted).
    func acquireFreeSlot() -> Int? {
        state.withLockUnchecked { s in
            guard !s.closing, let slot = s.free.popLast() else {
                s.dropped &+= 1
                return nil
            }
            return slot
        }
    }

    /// Returns a slot acquired with `acquireFreeSlot()` without processing it.
    func returnUnusedSlot(_ slot: Int) {
        state.withLockUnchecked { $0.free.append(slot) }
    }

    /// Render-thread safe. Queues `slot` for the worker.
    func enqueue(_ slot: Int) {
        state.withLockUnchecked { s in
            let tail = (s.head + s.count) % s.queue.count
            s.queue[tail] = slot
            s.count += 1
        }
        available.signal()
    }

    /// Frames dropped because no slot was free (read off the render thread).
    var droppedCount: UInt64 { state.withLock { $0.dropped } }

    /// Processes everything still queued, then stops the worker. Idempotent.
    /// Called from the worker thread itself (e.g. a `deinit` triggered by the
    /// handler) it only requests the stop instead of deadlocking.
    func drainAndStop() {
        stopLock.lock()
        guard !stopped else { stopLock.unlock(); return }
        stopped = true
        stopLock.unlock()

        state.withLock { $0.closing = true }
        available.signal()
        if Thread.current !== worker {
            finished.wait()
        }
        worker = nil
    }
}

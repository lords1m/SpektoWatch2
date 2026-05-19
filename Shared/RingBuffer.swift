import Foundation

/// Fixed-capacity FIFO buffer with O(1) append-and-drop-oldest.
///
/// The watch spectrogram views previously held `[[Float]]` and called
/// `removeFirst()` once per audio frame to keep the window size bounded —
/// that's O(n) per frame because Swift's `Array.removeFirst()` shifts the
/// remaining elements. At ~22 Hz with `maxFrames = 60` and 1024-element
/// magnitude arrays, the cost added up to a real fraction of the watch's
/// main-thread budget.
///
/// `RingBuffer` overwrites the oldest slot in place on `append` once the
/// capacity is full. `inOrder` returns the contents oldest-first so the
/// existing rendering loops keep working without restructuring.
public struct RingBuffer<Element> {
    public let capacity: Int

    /// Backing storage. Grows up to `capacity` then stays fixed.
    private var storage: [Element] = []
    /// Index of the OLDEST element once `storage.count == capacity`.
    /// Below capacity, `head` is unused (oldest element is `storage[0]`).
    private var head: Int = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be positive")
        self.capacity = capacity
        self.storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    /// Append a new element. If the buffer is full, the oldest element is
    /// dropped in O(1).
    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Returns the contents oldest-first. The result is a freshly allocated
    /// `[Element]` snapshot so callers can iterate without worrying about
    /// concurrent mutation.
    public func inOrder() -> [Element] {
        guard !storage.isEmpty else { return [] }
        if storage.count < capacity {
            return storage
        }
        var out: [Element] = []
        out.reserveCapacity(capacity)
        for i in 0..<capacity {
            out.append(storage[(head + i) % capacity])
        }
        return out
    }

    /// Clears the buffer. Keeps the reserved storage capacity.
    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }
}

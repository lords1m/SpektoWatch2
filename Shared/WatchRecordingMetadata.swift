import Foundation

/// Sync state of a standalone watch recording relative to the phone.
/// Drives the catalog UI ([[task-4-recordings-ui]]) and the opportunistic
/// transfer in [[task-5-sync-back]].
public enum WatchRecordingSyncState: String, Codable, Sendable {
    /// Captured on the watch, not yet transferred to the phone.
    case local
    /// A `transferFile` is in flight.
    case syncing
    /// Confirmed ingested by the phone (idempotent dedupe key is the recording id).
    case synced
}

/// Durable metadata for one standalone watch recording. Persisted in the
/// on-watch catalog and reused verbatim by the phone-side ingest so the same
/// `id` provides exactly-once dedupe across the WatchConnectivity boundary.
public struct WatchRecordingMetadata: Codable, Identifiable, Sendable, Equatable {
    /// Stable identity. Also the basename of the audio + `.swr` files on disk
    /// and the idempotency key for sync-back.
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var duration: TimeInterval
    public var sampleRate: Double
    /// Frequency weighting in effect at capture ("Z"/"A"/"C").
    public var weighting: String
    public var audioFileName: String
    public var measurementFileName: String
    public var syncState: WatchRecordingSyncState
    /// Session-aggregate metrics captured at finalize (the last `.swr` frame's
    /// time-integrated LAeq and running LCpeak). `nil` if no frame was written.
    public var laeq: Float?
    public var lcPeak: Float?

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        sampleRate: Double,
        weighting: String,
        audioFileName: String,
        measurementFileName: String,
        syncState: WatchRecordingSyncState = .local,
        laeq: Float? = nil,
        lcPeak: Float? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.sampleRate = sampleRate
        self.weighting = weighting
        self.audioFileName = audioFileName
        self.measurementFileName = measurementFileName
        self.syncState = syncState
        self.laeq = laeq
        self.lcPeak = lcPeak
    }
}

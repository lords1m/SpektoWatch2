import Foundation
import WatchConnectivity
import Combine
import OSLog
#if os(watchOS)
import WidgetKit
#endif

public class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    #if os(watchOS)
    // Keys live in `Shared/AppGroup.swift` to avoid drift with the widget
    // extension reader.
    private static let complicationWidgetKinds = [
        "SpektoWatchLevelCircular",
        "SpektoWatchLevelRectangular",
        "SpektoWatchLevelInline",
        "SpektoWatchLevelCorner"
    ]
    #endif
    
    @Published public var isReachable = false
    @Published public var spectrogramData: SpectrogramData?
    @Published public var selectedMicrophoneSource: MicrophoneSource = .iPhone
    @Published public var watchDashboardConfig: WatchDashboardConfig?
    @Published public var frequencyWeighting: String = "A"
    #if os(watchOS)
    private var lastComplicationReload = Date.distantPast
    #endif
    
    // MARK: - Queue Definitionen
    private struct QueuedMessage {
        let id = UUID()
        let message: [String: Any]
        var retries: Int
        let timestamp: Date
    }
    
    private var messageQueue: [QueuedMessage] = []
    private let maxRetries = 3
    private var isProcessingQueue = false

    // MARK: - Spectrogram Send Throttling
    //
    // FFT frames arrive at ~21 Hz (44100 / 2048). Sending each one via
    // `sendMessageData` immediately would saturate the WCSession outbound
    // queue, drop frames silently (no errorHandler was wired), and waste
    // radio/battery. Coalesce into a single most-recent frame per adaptive
    // interval (thermal-aware) and flush on a dedicated queue.
    //
    // The watch-side `Shared/WatchConnectivityManager` has the symmetric
    // logic for sends originating from the watch.
    private let spectrogramSendQueue = DispatchQueue(label: "com.spektowatch.ios-spectrogram-send", qos: .utility)
    private var pendingSpectrogramData: SpectrogramData?
    private var isSpectrogramSendScheduled = false
    private var lastSpectrogramSendTime: TimeInterval = 0
    private var hasLoggedSpectrogramUnreachability = false

    #if os(iOS)
    // MARK: - Standalone recording sync-back (M21 task-5)
    //
    /// Phone-side ingest hook. Returns true once the recording is in the iOS
    /// store (newly added OR already present — idempotent), which gates the
    /// "synced" acknowledgement back to the watch. Wired in `AppServices`.
    var onWatchRecordingReceived: ((Recording) -> Bool)?

    /// Serializes staging-directory mutation for incoming `transferFile`s. WC
    /// delivers `didReceive file:` on a background queue; both files of a
    /// recording must be correlated by id before ingest.
    private let transferIngestQueue = DispatchQueue(label: "com.spektowatch.watch-recording-ingest")
    private var stagedTransferMetadata: [UUID: WatchRecordingMetadata] = [:]

    private var transferStagingDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WatchSyncStaging", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    #endif

    public override init() {
        super.init()
        // Ensure public access for Watch App
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // MARK: - WCSessionDelegate
    
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            self.processQueue()
        }
        #if os(watchOS)
        if activationState == .activated {
            syncPendingRecordings()
        }
        #endif
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            if self.isReachable {
                self.processQueue()
            }
        }
        #if os(watchOS)
        if session.isReachable {
            syncPendingRecordings()
        }
        #endif
    }

    /// Incoming standalone recording file (iOS) / ingest acknowledgement (watch).
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        #if os(iOS)
        transferIngestQueue.async { [weak self] in
            self?.handleIncomingRecordingFile(file)
        }
        #endif
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        #if os(watchOS)
        if let id = WatchConnectivityProtocol.syncedRecordingId(fromUserInfo: userInfo) {
            DispatchQueue.main.async {
                WatchRecordingStore.shared.setSyncState(.synced, for: id)
            }
        }
        #endif
    }
    
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
    
    // MARK: - Empfang
    
    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard !messageData.isEmpty else { return }
        if case .spectrogram(let specData) = WatchConnectivityProtocol.decodeBinaryPayload(messageData) {
            DispatchQueue.main.async {
                self.spectrogramData = specData
                #if os(watchOS)
                self.updateComplicationState(from: specData)
                #endif
            }
        }
    }

    #if os(watchOS)
    private static let complicationReloadMinimumInterval: TimeInterval = 60

    private func updateComplicationState(from data: SpectrogramData) {
        let now = Date()
        guard now.timeIntervalSince(lastComplicationReload) >= Self.complicationReloadMinimumInterval else { return }
        // Assign before the reload so a near-simultaneous second call cannot
        // race past the throttle check.
        lastComplicationReload = now

        let shared = AppGroup.defaults
        shared.set(data.levels["LAF"] ?? data.broadbandLevel, forKey: ComplicationSharedKeys.level)
        shared.set(frequencyWeighting, forKey: ComplicationSharedKeys.weighting)

        Self.complicationWidgetKinds.forEach {
            WidgetCenter.shared.reloadTimelines(ofKind: $0)
        }
    }
    #endif
    
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            guard let type = WatchConnectivityProtocol.messageType(from: message) else {
                if let typeRaw = message[WatchConnectivityProtocol.Key.type] as? String {
                    Logger.connectivity.info("Ignored unknown message type: \(typeRaw)")
                }
                return
            }
            switch type {
            case .microphoneSource:
                if let source = WatchConnectivityProtocol.microphoneSource(from: message) {
                    self.selectedMicrophoneSource = source
                }
            case .startRecording:
                let source = WatchConnectivityProtocol.recordingSource(from: message)
                if let source {
                    self.selectedMicrophoneSource = source
                }
                NotificationCenter.default.post(name: .startRecordingCommand, object: source)
            case .stopRecording:
                let source = WatchConnectivityProtocol.recordingSource(from: message)
                NotificationCenter.default.post(name: .stopRecordingCommand, object: source)
            case .frequencyWeighting:
                if let weighting = WatchConnectivityProtocol.frequencyWeighting(from: message) {
                    self.frequencyWeighting = weighting
                }
            case .watchDashboardConfig:
                if let configString = WatchConnectivityProtocol.dashboardConfigString(from: message),
                   let configData = configString.data(using: .utf8),
                   let config = WatchDashboardConfig.decode(from: configData) {
                    self.watchDashboardConfig = config
                    config.save()
                }
            case .gain:
                if let gain = WatchConnectivityProtocol.gain(from: message) {
                    NotificationCenter.default.post(name: .gainOrBandwidthChangedNotification, object: gain)
                }
            case .appStateUpdate:
                // iOS-side receives no appStateUpdate today (envelope
                // flows iOS → watch only). Reserved for the watch's
                // future ability to push state back. Decode-and-drop
                // to keep the protocol future-proof.
                _ = WatchConnectivityProtocol.appStateUpdate(from: message)
            case .recordingFileTransfer, .recordingSynced:
                // These are delivered via transferFile / transferUserInfo,
                // not sendMessage — handled in session(_:didReceive:) and
                // session(_:didReceiveUserInfo:). No action needed here.
                break
            }
        }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            if let weighting = applicationContext["frequencyWeighting"] as? String {
                self.frequencyWeighting = weighting
            }
            if let configString = applicationContext[PersistenceKeys.watchDashboardConfig] as? String,
               let configData = configString.data(using: .utf8),
               let config = WatchDashboardConfig.decode(from: configData) {
                self.watchDashboardConfig = config
                config.save()
            }
        }
    }
    
    // MARK: - Senden (Public API)
    
    public func sendSpectrogramData(_ data: SpectrogramData) {
        // Coalesce: keep only the most recent frame. The audio thread can call
        // this at FFT framerate without saturating WCSession.
        spectrogramSendQueue.async {
            self.pendingSpectrogramData = data
            self.scheduleSpectrogramSendIfNeeded()
        }
    }

    private func scheduleSpectrogramSendIfNeeded() {
        guard !isSpectrogramSendScheduled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let sendInterval = adaptiveSpectrogramSendInterval()
        let earliestSend = lastSpectrogramSendTime + sendInterval
        let delay = max(0, earliestSend - now)

        isSpectrogramSendScheduled = true
        spectrogramSendQueue.asyncAfter(deadline: .now() + delay) {
            self.flushPendingSpectrogramData()
        }
    }

    private func flushPendingSpectrogramData() {
        guard let dataToSend = pendingSpectrogramData else {
            isSpectrogramSendScheduled = false
            return
        }

        pendingSpectrogramData = nil
        isSpectrogramSendScheduled = false
        lastSpectrogramSendTime = ProcessInfo.processInfo.systemUptime

        guard WCSession.default.isReachable else {
            if !hasLoggedSpectrogramUnreachability {
                Logger.connectivity.info("Watch not reachable; dropping spectrogram frame.")
                hasLoggedSpectrogramUnreachability = true
            }
            return
        }
        hasLoggedSpectrogramUnreachability = false

        let packet = WatchConnectivityProtocol.makeSpectrogramPacket(dataToSend)
        WCSession.default.sendMessageData(packet, replyHandler: nil) { error in
            Logger.connectivity.error("Error sending spectrogram data: \(error.localizedDescription)")
        }
    }

    private func adaptiveSpectrogramSendInterval() -> TimeInterval {
        let processInfo = ProcessInfo.processInfo
        if processInfo.isLowPowerModeEnabled {
            return WatchConnectivityProtocol.lowPowerSpectrogramSendInterval
        }
        switch processInfo.thermalState {
        case .serious: return WatchConnectivityProtocol.seriousThermalSpectrogramSendInterval
        case .critical: return WatchConnectivityProtocol.criticalThermalSpectrogramSendInterval
        case .fair: return WatchConnectivityProtocol.fairThermalSpectrogramSendInterval
        default: return WatchConnectivityProtocol.normalSpectrogramSendInterval
        }
    }
    
    public func sendGainValue(_ gain: Float) {
        sendWithRetry(WatchConnectivityProtocol.makeGainMessage(gain))
    }
    
    public func sendMicrophoneSourceSelection(_ source: MicrophoneSource) {
        sendWithRetry(WatchConnectivityProtocol.makeMicrophoneSourceMessage(source))
    }

    public func sendFrequencyWeightingSelection(_ weighting: String) {
        sendWithRetry(WatchConnectivityProtocol.makeFrequencyWeightingMessage(weighting))
        do {
            try WCSession.default.updateApplicationContext(["frequencyWeighting": weighting])
        } catch {
            // Ignore context errors
        }
    }
    
    public func requestRecordingStart(source: MicrophoneSource? = nil) {
        sendWithRetry(WatchConnectivityProtocol.makeRecordingStartMessage(source: source))
    }
    
    public func requestRecordingStop(source: MicrophoneSource? = nil) {
        sendWithRetry(WatchConnectivityProtocol.makeRecordingStopMessage(source: source))
    }

    public func requestWearableRecordingStart() {
        selectedMicrophoneSource = .appleWatch
        sendMicrophoneSourceSelection(.appleWatch)
        requestRecordingStart(source: .appleWatch)
    }

    public func requestWearableRecordingStop() {
        requestRecordingStop(source: .appleWatch)
    }

    public func sendWatchDashboardConfig(_ config: WatchDashboardConfig) {
        guard let configData = config.encode(),
              let configString = String(data: configData, encoding: .utf8) else {
            return
        }
        sendWithRetry(WatchConnectivityProtocol.makeWatchDashboardConfigMessage(configString))

        // Also send via application context for background delivery
        do {
            try WCSession.default.updateApplicationContext([PersistenceKeys.watchDashboardConfig: configString])
        } catch {
            // Ignore context errors
        }
    }

    // MARK: - Queue Logic
    
    private func sendWithRetry(_ message: [String: Any]) {
        // Callers can arrive on any thread; all messageQueue / isProcessingQueue
        // mutations must happen on main to stay consistent with the reply/error
        // handlers (which already dispatch to main) and the reachability callbacks.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let queued = QueuedMessage(message: message, retries: 0, timestamp: Date())
            self.messageQueue.append(queued)
            self.processQueue()
        }
    }

    private func processQueue() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isProcessingQueue, !messageQueue.isEmpty else { return }
        
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            return // Warten auf Reachability Change
        }
        
        isProcessingQueue = true
        let currentMessage = messageQueue[0]
        
        WCSession.default.sendMessage(currentMessage.message, replyHandler: { _ in
            DispatchQueue.main.async {
                if !self.messageQueue.isEmpty { self.messageQueue.removeFirst() }
                self.isProcessingQueue = false
                self.processQueue()
            }
        }, errorHandler: { error in
            DispatchQueue.main.async {
                self.handleMessageError(currentMessage, error: error)
            }
        })
    }
    
    private func handleMessageError(_ message: QueuedMessage, error: Error) {
        dispatchPrecondition(condition: .onQueue(.main))
        var updatedMessage = message
        updatedMessage.retries += 1
        
        if updatedMessage.retries <= maxRetries {
            if !messageQueue.isEmpty {
                messageQueue[0] = updatedMessage
            }
            
            // Exponential Backoff: 0.5s, 1.0s, 2.0s
            let delay = 0.5 * pow(2.0, Double(updatedMessage.retries - 1))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.isProcessingQueue = false
                self.processQueue()
            }
        } else {
            Logger.connectivity.error("Message dropped after \(self.maxRetries) retries: \(error.localizedDescription)")
            if !messageQueue.isEmpty {
                messageQueue.removeFirst()
            }
            isProcessingQueue = false
            processQueue()
        }
    }

    // MARK: - Standalone recording sync-back (M21 task-5)

    #if os(watchOS)
    /// Opportunistically push not-yet-synced standalone recordings to the phone
    /// via `transferFile` (OS-queued — delivered when the phone is reachable;
    /// NOT a live stream). Re-entrant-safe: only `.local`/`.syncing` entries are
    /// transferred, and the phone dedupes by recording id so a retried transfer
    /// never creates a duplicate. Marks each entry `.syncing` until the phone's
    /// ack flips it to `.synced`.
    func syncPendingRecordings() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        DispatchQueue.main.async {
            let store = WatchRecordingStore.shared
            let fm = FileManager.default
            for rec in store.recordings where rec.syncState != .synced {
                let audioURL = store.audioURL(for: rec)
                guard fm.fileExists(atPath: audioURL.path) else { continue }
                guard let metaData = try? JSONEncoder().encode(rec) else { continue }

                store.setSyncState(.syncing, for: rec.id)
                session.transferFile(audioURL, metadata: WatchConnectivityProtocol.makeRecordingFileTransferMetadata(
                    id: rec.id, kind: .audio, metadata: metaData))

                let measurementURL = store.measurementURL(for: rec)
                if fm.fileExists(atPath: measurementURL.path) {
                    session.transferFile(measurementURL, metadata: WatchConnectivityProtocol.makeRecordingFileTransferMetadata(
                        id: rec.id, kind: .measurement, metadata: metaData))
                }
            }
        }
    }
    #endif

    #if os(iOS)
    /// Copies one incoming recording file out of WC's temporary location into a
    /// staging dir keyed by recording id, then ingests once both audio + `.swr`
    /// are present. Runs on `transferIngestQueue`. `file.fileURL` is only valid
    /// until the delegate returns, so the copy is synchronous.
    private func handleIncomingRecordingFile(_ file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        guard let id = WatchConnectivityProtocol.recordingId(fromTransfer: metadata),
              let kind = WatchConnectivityProtocol.recordingFileKind(fromTransfer: metadata),
              let recordingMeta = WatchConnectivityProtocol.recordingMetadata(fromTransfer: metadata) else {
            Logger.connectivity.error("Dropping recording file with malformed metadata")
            return
        }

        let fm = FileManager.default
        let ext = kind == .audio ? "caf" : "swr"
        let destination = transferStagingDirectory.appendingPathComponent("\(id.uuidString).\(ext)")
        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: destination)
        }
        do {
            try fm.copyItem(at: file.fileURL, to: destination)
        } catch {
            Logger.connectivity.error("Failed to stage incoming recording file: \(error.localizedDescription)")
            return
        }

        stagedTransferMetadata[id] = recordingMeta

        let audioURL = transferStagingDirectory.appendingPathComponent("\(id.uuidString).caf")
        let measurementURL = transferStagingDirectory.appendingPathComponent("\(id.uuidString).swr")
        guard fm.fileExists(atPath: audioURL.path), fm.fileExists(atPath: measurementURL.path) else {
            return // wait for the other file
        }

        stagedTransferMetadata[id] = nil
        ingestStagedRecording(recordingMeta, audioURL: audioURL, measurementURL: measurementURL)
    }

    private func ingestStagedRecording(_ meta: WatchRecordingMetadata, audioURL: URL, measurementURL: URL) {
        // `addRecording` consumes absolute paths and moves the files into the
        // iOS recordings store, renaming the sidecar to `.spekto` (same binary
        // MeasurementDataFormat as `.swr`). Build the iOS Recording from the
        // shared metadata; the id is preserved so dedupe is stable.
        let recording = Recording(
            id: meta.id,
            name: meta.title,
            startDate: meta.createdAt,
            duration: meta.duration,
            audioFileName: audioURL.path,
            measurementDataFileName: measurementURL.path,
            sampleRate: meta.sampleRate,
            laeqFast: meta.laeq ?? -120.0,
            peakLevel: meta.lcPeak ?? -120.0,
            frequencyWeighting: meta.weighting
        )

        DispatchQueue.main.async {
            let ingested = self.onWatchRecordingReceived?(recording) ?? false
            guard ingested else { return }
            // Confirm via transferUserInfo (queued + guaranteed) so the watch
            // flips the catalog entry to `.synced` even if not reachable now.
            WCSession.default.transferUserInfo(
                WatchConnectivityProtocol.makeRecordingSyncedUserInfo(id: meta.id))
        }
    }
    #endif
}

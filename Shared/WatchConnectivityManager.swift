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
    /// Protocol version reported by the paired device (0 = legacy build).
    @Published public private(set) var peerProtocolVersion: UInt16 = WatchConnectivityProtocol.legacyProtocolVersion
    #if os(watchOS)
    @Published public private(set) var phoneAppState: WatchAppState?
    @Published public private(set) var lastPhoneSpectrogramReceivedAt: Date?
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

    #if os(watchOS)
    /// WC-2 debounce for `syncPendingRecordings`.
    static let syncDebounceInterval: TimeInterval = 2
    private var pendingSyncWorkItem: DispatchWorkItem?
    /// File kinds whose `transferFile` completed without error in this
    /// process, per recording id (main thread). Prevents resending while the
    /// phone's ack is still in flight.
    private var deliveredTransferKinds: [UUID: Set<WatchConnectivityProtocol.RecordingFileKind>] = [:]
    #endif

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
    private var stagedTransferFirstSeenAt: [UUID: Date] = [:]
    /// WC-3: per-id audio-only fallback, armed when the first file of a pair
    /// is staged and cancelled when its partner arrives.
    private var stagedTransferFallbacks: [UUID: DispatchWorkItem] = [:]
    static var stagedTransferTimeout: TimeInterval = 120
    /// Staged files older than this (no in-memory pairing state after a
    /// relaunch) are purged; the watch resends anything not acknowledged.
    private static let stagedFileMaxAge: TimeInterval = 24 * 60 * 60

    /// A file moved out of WatchConnectivity's temporary inbox.
    struct StagedRecordingFile {
        let id: UUID
        let kind: WatchConnectivityProtocol.RecordingFileKind
        let metadata: WatchRecordingMetadata
        let url: URL
    }

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
            if activationState == .activated {
                self.publishLocalProtocolVersion()
            }
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
                self.publishLocalProtocolVersion()
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
        // WC-1: `file.fileURL` is only valid until this delegate returns, so
        // the move into the staging directory must happen synchronously here.
        // Only the bookkeeping hops to the ingest queue.
        guard let staged = stageIncomingRecordingFile(at: file.fileURL, metadata: file.metadata ?? [:]) else { return }
        transferIngestQueue.async { [weak self] in
            self?.handleStagedRecordingFile(staged)
        }
        #endif
    }

    /// WC-6: transfer finished (watch side). A failed transfer returns the
    /// catalog entry to `.local` so the next sync retries it instead of
    /// leaving it stuck in `.syncing`.
    public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        #if os(watchOS)
        let metadata = fileTransfer.file.metadata ?? [:]
        guard let id = WatchConnectivityProtocol.recordingId(fromTransfer: metadata) else { return }
        let kind = WatchConnectivityProtocol.recordingFileKind(fromTransfer: metadata)
        DispatchQueue.main.async {
            if let error {
                Logger.connectivity.error("Recording transfer \(id.uuidString) failed: \(error.localizedDescription)")
                self.deliveredTransferKinds[id] = nil
                if WatchRecordingStore.shared.recordings.first(where: { $0.id == id })?.syncState == .syncing {
                    WatchRecordingStore.shared.setSyncState(.local, for: id)
                }
            } else if let kind {
                self.deliveredTransferKinds[id, default: []].insert(kind)
            }
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
                self.lastPhoneSpectrogramReceivedAt = Date()
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
            if message[WatchConnectivityProtocol.Key.protocolVersion] != nil {
                self.peerProtocolVersion = WatchConnectivityProtocol.protocolVersion(from: message)
            }
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
            case .watchMeterLayoutConfig:
                if let configString = WatchConnectivityProtocol.dashboardConfigString(from: message),
                   let configData = configString.data(using: .utf8),
                   let config = WatchMeterLayoutConfig.decode(from: configData) {
                    WatchAppSettingsSync.applyMeterLayoutConfig(config)
                }
            case .watchMeasurementSourcePreference:
                if let preference = WatchConnectivityProtocol.measurementSourcePreference(from: message) {
                    WatchAppSettingsSync.applyMeasurementSourcePreference(preference)
                }
            case .gain:
                if let gain = WatchConnectivityProtocol.gain(from: message) {
                    NotificationCenter.default.post(name: .gainOrBandwidthChangedNotification, object: gain)
                }
            case .appStateUpdate:
                #if os(watchOS)
                if let state = WatchConnectivityProtocol.appStateUpdate(from: message) {
                    self.phoneAppState = state
                }
                #else
                _ = WatchConnectivityProtocol.appStateUpdate(from: message)
                #endif
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
            self.peerProtocolVersion = WatchConnectivityProtocol.peerProtocolVersion(from: applicationContext)
            if let weighting = applicationContext["frequencyWeighting"] as? String {
                self.frequencyWeighting = weighting
            }
            if let configString = applicationContext[PersistenceKeys.watchDashboardConfig] as? String,
               let configData = configString.data(using: .utf8),
               let config = WatchDashboardConfig.decode(from: configData) {
                self.watchDashboardConfig = config
                config.save()
            }
            WatchAppSettingsSync.applyApplicationContext(applicationContext)
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
        mergeAndUpdateApplicationContext(["frequencyWeighting": weighting])
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
        mergeAndUpdateApplicationContext([PersistenceKeys.watchDashboardConfig: configString])
    }

    /// Pushes the spectrogram quality preset to the watch via application context.
    public func sendSpectrogramResolution(_ resolution: SpectrogramResolution) {
        WatchAppSettingsSync.applySpectrogramResolution(resolution)
        mergeAndUpdateApplicationContext([PersistenceKeys.spectrogramResolution: resolution.rawValue])
    }

    /// Pushes all watch-app settings the phone can edit (meter layout, live source, gain).
    public func sendWatchAppSettings(
        meterLayout: WatchMeterLayoutConfig,
        measurementSource: WatchMeasurementSourcePreference,
        gain: Float,
        spectrogramResolution: SpectrogramResolution = .current
    ) {
        meterLayout.save()
        UserDefaults.standard.set(measurementSource.rawValue, forKey: PersistenceKeys.Watch.measurementSourcePreference)
        UserDefaults.standard.set(measurementSource == .appleWatch, forKey: PersistenceKeys.Watch.standaloneEnabled)
        UserDefaults.standard.set(gain, forKey: PersistenceKeys.Watch.gain)
        WatchAppSettingsSync.applySpectrogramResolution(spectrogramResolution)

        if let configData = meterLayout.encode(),
           let configString = String(data: configData, encoding: .utf8) {
            sendWithRetry(WatchConnectivityProtocol.makeWatchMeterLayoutConfigMessage(configString))
        }
        sendWithRetry(WatchConnectivityProtocol.makeWatchMeasurementSourcePreferenceMessage(measurementSource))
        sendWithRetry(WatchConnectivityProtocol.makeGainMessage(gain))

        var context: [String: Any] = ["frequencyWeighting": frequencyWeighting]
        if let configData = meterLayout.encode(),
           let configString = String(data: configData, encoding: .utf8) {
            context[PersistenceKeys.Watch.meterLayoutConfig] = configString
        }
        context[PersistenceKeys.Watch.measurementSourcePreference] = measurementSource.rawValue
        context[PersistenceKeys.Watch.gain] = gain
        context[PersistenceKeys.spectrogramResolution] = spectrogramResolution.rawValue
        mergeAndUpdateApplicationContext(context)
    }

    /// Publishes our protocol version via application context so the peer can
    /// gate features without waiting for a live `sendMessage`.
    private func publishLocalProtocolVersion() {
        mergeAndUpdateApplicationContext([:])
    }

    private func mergeAndUpdateApplicationContext(_ updates: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            var context = session.applicationContext
            // WC-5: stamp only keys whose value actually changed.
            let stamped = WatchAppSettingsSync.stampingChangedKeys(updates, previous: context)
            for (key, value) in stamped {
                context[key] = value
            }
            try session.updateApplicationContext(WatchConnectivityProtocol.mergingProtocolVersion(into: context))
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
        let currentMessage = messageQueue.removeFirst()

        // Fire-and-forget control plane: receivers handle `didReceiveMessage`
        // without reply handlers, so queue progression cannot depend on reply.
        WCSession.default.sendMessage(currentMessage.message, replyHandler: nil, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.handleMessageError(currentMessage, error: error)
            }
        })
        isProcessingQueue = false
        processQueue()
    }
    
    private func handleMessageError(_ message: QueuedMessage, error: Error) {
        dispatchPrecondition(condition: .onQueue(.main))
        var updatedMessage = message
        updatedMessage.retries += 1
        
        if updatedMessage.retries <= maxRetries {
            // Requeue and keep chronological order even if multiple in-flight messages fail.
            messageQueue.append(updatedMessage)
            messageQueue.sort { $0.timestamp < $1.timestamp }
            isProcessingQueue = true

            // Exponential Backoff: 0.5s, 1.0s, 2.0s
            let delay = 0.5 * pow(2.0, Double(updatedMessage.retries - 1))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.isProcessingQueue = false
                self?.processQueue()
            }
        } else {
            Logger.connectivity.error("Message dropped after \(self.maxRetries) retries: \(error.localizedDescription)")
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
    /// WC-2: activation + reachability callbacks arrive in bursts; coalesce
    /// them into one sync pass per `syncDebounceInterval`.
    func syncPendingRecordings() {
        DispatchQueue.main.async {
            self.pendingSyncWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.pendingSyncWorkItem = nil
                self?.performSyncPendingRecordings()
            }
            self.pendingSyncWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.syncDebounceInterval, execute: work)
        }
    }

    /// Recording ids with a `transferFile` still queued/in flight.
    static func outstandingTransferIds(_ transfers: [WCSessionFileTransfer]) -> Set<UUID> {
        Set(transfers.compactMap { WatchConnectivityProtocol.recordingId(fromTransfer: $0.file.metadata ?? [:]) })
    }

    private func performSyncPendingRecordings() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // WC-2: never re-queue a recording whose transfer is still
        // outstanding (or already delivered in this process and awaiting the
        // phone's ack) — each resend is a multi-MB duplicate.
        let outstanding = Self.outstandingTransferIds(session.outstandingFileTransfers)
        let store = WatchRecordingStore.shared
        let fm = FileManager.default
        for rec in store.recordings where rec.syncState == .local || rec.syncState == .syncing {
            if outstanding.contains(rec.id) { continue }
            let audioURL = store.audioURL(for: rec)
            guard fm.fileExists(atPath: audioURL.path) else { continue }
            let measurementURL = store.measurementURL(for: rec)
            let hasMeasurement = fm.fileExists(atPath: measurementURL.path)
            let delivered = deliveredTransferKinds[rec.id] ?? []
            let needsAudio = !delivered.contains(.audio)
            let needsMeasurement = hasMeasurement && !delivered.contains(.measurement)
            guard needsAudio || needsMeasurement else { continue }
            guard let metaData = try? JSONEncoder().encode(rec) else { continue }

            store.setSyncState(.syncing, for: rec.id)
            if needsAudio {
                session.transferFile(audioURL, metadata: WatchConnectivityProtocol.makeRecordingFileTransferMetadata(
                    id: rec.id, kind: .audio, metadata: metaData))
            }
            if needsMeasurement {
                session.transferFile(measurementURL, metadata: WatchConnectivityProtocol.makeRecordingFileTransferMetadata(
                    id: rec.id, kind: .measurement, metadata: metaData))
            }
        }
    }

    #endif

    #if os(iOS)
    /// WC-1: synchronously moves one incoming recording file out of
    /// WatchConnectivity's inbox into `WatchSyncStaging/<id>.<ext>`. Must be
    /// called inside `session(_:didReceive:)` (the inbox URL is invalid once
    /// the delegate returns). Returns `nil` for malformed metadata or I/O
    /// failure (the watch keeps the entry un-acked and retries).
    func stageIncomingRecordingFile(at sourceURL: URL, metadata: [String: Any]) -> StagedRecordingFile? {
        guard let id = WatchConnectivityProtocol.recordingId(fromTransfer: metadata),
              let kind = WatchConnectivityProtocol.recordingFileKind(fromTransfer: metadata),
              let recordingMeta = WatchConnectivityProtocol.recordingMetadata(fromTransfer: metadata) else {
            Logger.connectivity.error("Dropping recording file with malformed metadata")
            return nil
        }

        let fm = FileManager.default
        let ext = kind == .audio ? "caf" : "swr"
        let destination = transferStagingDirectory.appendingPathComponent("\(id.uuidString).\(ext)")
        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: destination)
        }
        do {
            try fm.moveItem(at: sourceURL, to: destination)
        } catch {
            do {
                try fm.copyItem(at: sourceURL, to: destination)
            } catch {
                Logger.connectivity.error("Failed to stage incoming recording file: \(error.localizedDescription)")
                return nil
            }
        }
        return StagedRecordingFile(id: id, kind: kind, metadata: recordingMeta, url: destination)
    }

    /// Pairs staged audio + `.swr` by recording id and ingests once both are
    /// present. Runs on `transferIngestQueue`.
    func handleStagedRecordingFile(_ staged: StagedRecordingFile) {
        purgeAgedStagingFilesIfNeeded()

        let id = staged.id
        let fm = FileManager.default
        stagedTransferMetadata[id] = staged.metadata
        stagedTransferFirstSeenAt[id] = stagedTransferFirstSeenAt[id] ?? Date()

        let audioURL = transferStagingDirectory.appendingPathComponent("\(id.uuidString).caf")
        let measurementURL = transferStagingDirectory.appendingPathComponent("\(id.uuidString).swr")
        guard fm.fileExists(atPath: audioURL.path), fm.fileExists(atPath: measurementURL.path) else {
            // WC-3: wait for the partner, but arm a per-id fallback so a lone
            // audio file is ingested even if no further transfer ever arrives.
            armStagedTransferFallback(for: id)
            return
        }

        clearStagedTransferState(for: id)
        ingestStagedRecording(staged.metadata, audioURL: audioURL, measurementURL: measurementURL)
    }

    private func armStagedTransferFallback(for id: UUID) {
        guard stagedTransferFallbacks[id] == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.runStagedTransferFallback(for: id)
        }
        stagedTransferFallbacks[id] = work
        transferIngestQueue.asyncAfter(deadline: .now() + Self.stagedTransferTimeout, execute: work)
    }

    private func clearStagedTransferState(for id: UUID) {
        stagedTransferMetadata[id] = nil
        stagedTransferFirstSeenAt[id] = nil
        stagedTransferFallbacks[id]?.cancel()
        stagedTransferFallbacks[id] = nil
    }

    /// Audio-only ingest (or purge) for an id whose partner never arrived.
    private func runStagedTransferFallback(for id: UUID) {
        let fm = FileManager.default
        let meta = stagedTransferMetadata[id]
        clearStagedTransferState(for: id)
        let audioURL = transferStagingDirectory.appendingPathComponent("\(id.uuidString).caf")
        let measurementURL = transferStagingDirectory.appendingPathComponent("\(id.uuidString).swr")
        if let meta, fm.fileExists(atPath: audioURL.path) {
            let optionalMeasurement = fm.fileExists(atPath: measurementURL.path) ? measurementURL : nil
            Logger.connectivity.warning("Staged watch transfer \(id.uuidString) timed out waiting for sidecar — ingesting audio-only")
            ingestStagedRecording(meta, audioURL: audioURL, measurementURL: optionalMeasurement)
        } else {
            if fm.fileExists(atPath: audioURL.path) { try? fm.removeItem(at: audioURL) }
            if fm.fileExists(atPath: measurementURL.path) { try? fm.removeItem(at: measurementURL) }
            Logger.connectivity.error("Purged stale staged watch transfer for recording \(id.uuidString)")
        }
    }

    /// Removes staging files that have no in-memory pairing state and are
    /// older than `stagedFileMaxAge` (leftovers from a previous process).
    private func purgeAgedStagingFilesIfNeeded() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: transferStagingDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let now = Date()
        for url in entries {
            let name = url.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: name), stagedTransferMetadata[id] != nil { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            if now.timeIntervalSince(modified) > Self.stagedFileMaxAge {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func ingestStagedRecording(_ meta: WatchRecordingMetadata, audioURL: URL, measurementURL: URL?) {
        // `addRecording` consumes absolute paths and moves the files into the
        // iOS recordings store, renaming the sidecar to `.spekto` (same binary
        // MeasurementDataFormat as `.swr`). Build the iOS Recording from the
        // shared metadata; the id is preserved so dedupe is stable.
        let duration = RecordingManager.resolvedRecordingDuration(
            audioURL: audioURL,
            measurementURL: measurementURL,
            fallback: meta.duration
        )
        let spectralAvailable = measurementURL.map {
            MeasurementSpectralAvailability.hasUsableSpectralData(fileURL: $0)
        } ?? false
        let recording = Recording(
            id: meta.id,
            name: meta.title,
            startDate: meta.createdAt,
            duration: duration,
            audioFileName: audioURL.path,
            measurementDataFileName: measurementURL?.path,
            sampleRate: meta.sampleRate,
            laeqFast: meta.laeq ?? -120.0,
            peakLevel: meta.lcPeak ?? -120.0,
            minLevel: meta.minLevel ?? -120.0,
            timeWeighting: meta.timeWeighting ?? "Fast",
            frequencyWeighting: meta.weighting,
            calibrationOffset: meta.calibrationOffset ?? 100.0,
            fftBlockSize: meta.fftBlockSize ?? 2048,
            spectralDataAvailable: spectralAvailable
        )

        DispatchQueue.main.async {
            let ingested = self.onWatchRecordingReceived?(recording) ?? false
            guard ingested else {
                // DL-3: not persisted → no ack; staged files stay so a resend
                // (or the next fallback) can retry.
                return
            }
            // WC-2: on success `addRecording` moved the files; when the id was
            // already present (duplicate resend) they are still staged —
            // remove them so duplicates don't leak.
            let fm = FileManager.default
            if fm.fileExists(atPath: audioURL.path) { try? fm.removeItem(at: audioURL) }
            if let measurementURL, fm.fileExists(atPath: measurementURL.path) {
                try? fm.removeItem(at: measurementURL)
            }
            // Confirm via transferUserInfo (queued + guaranteed) so the watch
            // flips the catalog entry to `.synced` even if not reachable now.
            WCSession.default.transferUserInfo(
                WatchConnectivityProtocol.makeRecordingSyncedUserInfo(id: meta.id))
        }
    }
    #endif
}

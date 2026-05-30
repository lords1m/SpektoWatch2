import Foundation
import WatchConnectivity
import Combine
import os.signpost
#if os(watchOS)
import WidgetKit
#endif

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    private static let performanceLog = OSLog(subsystem: "com.spektowatch", category: "performance.connectivity")
    #if os(watchOS)
    // Complication keys are defined once in `Shared/AppGroup.swift` so the
    // widget-extension reader and this writer cannot drift.
    private static let complicationWidgetKinds = [
        "SpektoWatchLevelCircular",
        "SpektoWatchLevelRectangular",
        "SpektoWatchLevelInline",
        "SpektoWatchLevelCorner"
    ]
    #endif
    private let sendQueue = DispatchQueue(label: "com.spektowatch.watch-send", qos: .utility)
    private var pendingSpectrogramData: SpectrogramData?
    private var isSpectrogramSendScheduled = false
    private var lastSpectrogramSendTime: TimeInterval = 0
    #if os(watchOS)
    private var lastComplicationReload = Date.distantPast
    #endif

    @Published var spectrogramData: SpectrogramData?
    @Published var isReachable = false
    @Published var selectedMicrophoneSource: MicrophoneSource = .iPhone
    @Published var watchDashboardConfig: WatchDashboardConfig?
    @Published var frequencyWeighting: String = "A"

    var onMicrophoneSourceChanged: ((MicrophoneSource) -> Void)?
    private var hasLoggedUnreachability = false

    #if os(iOS)
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

    private override init() {
        super.init()

        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func sendSpectrogramData(_ data: SpectrogramData) {
        sendQueue.async {
            self.pendingSpectrogramData = data
            self.scheduleSpectrogramSendIfNeeded()
        }
    }

    func sendMicrophoneSourceSelection(_ source: MicrophoneSource) {
        guard WCSession.default.isReachable else {
            print("Watch not reachable")
            return
        }

        let message = WatchConnectivityProtocol.makeMicrophoneSourceMessage(source)
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Error sending microphone source: \(error.localizedDescription)")
        }
    }

    func requestRecordingStart(source: MicrophoneSource? = nil) {
        print("[WCM] Requesting Start")
        guard WCSession.default.isReachable else {
            print("[WCM] Error: Not reachable")
            return
        }
        let message = WatchConnectivityProtocol.makeRecordingStartMessage(source: source)
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Error sending start command: \(error.localizedDescription)")
        }
    }

    func requestRecordingStop(source: MicrophoneSource? = nil) {
        print("[WCM] Requesting Stop")
        guard WCSession.default.isReachable else {
            print("[WCM] Error: Not reachable")
            return
        }
        let message = WatchConnectivityProtocol.makeRecordingStopMessage(source: source)
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Error sending stop command: \(error.localizedDescription)")
        }
    }

    func requestWearableRecordingStart() {
        selectedMicrophoneSource = .appleWatch
        sendMicrophoneSourceSelection(.appleWatch)
        requestRecordingStart(source: .appleWatch)
    }

    func requestWearableRecordingStop() {
        requestRecordingStop(source: .appleWatch)
    }

    func sendGainValue(_ gain: Float) {
        guard WCSession.default.isReachable else { return }
        let message = WatchConnectivityProtocol.makeGainMessage(gain)
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Error sending gain: \(error.localizedDescription)")
        }
    }

    // MARK: - Watch Dashboard Configuration

    func sendWatchDashboardConfig(_ config: WatchDashboardConfig) {
        guard WCSession.default.isReachable else {
            print("[WCM] Watch not reachable for dashboard config")
            // Try to send via application context for background delivery
            sendWatchDashboardConfigViaContext(config)
            return
        }

        guard let configData = config.encode(),
              let configString = String(data: configData, encoding: .utf8) else {
            print("[WCM] Error encoding dashboard config")
            return
        }

        let message = WatchConnectivityProtocol.makeWatchDashboardConfigMessage(configString)
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("[WCM] Error sending dashboard config: \(error.localizedDescription)")
            // Fallback to application context
            self.sendWatchDashboardConfigViaContext(config)
        }
    }

    private func sendWatchDashboardConfigViaContext(_ config: WatchDashboardConfig) {
        guard let configData = config.encode(),
              let configString = String(data: configData, encoding: .utf8) else {
            return
        }

        do {
            try WCSession.default.updateApplicationContext([PersistenceKeys.watchDashboardConfig: configString])
            print("[WCM] Dashboard config sent via application context")
        } catch {
            print("[WCM] Error sending dashboard config via context: \(error.localizedDescription)")
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
            print("[WCM] Dropping recording file with malformed metadata")
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
            print("[WCM] Failed to stage incoming recording file: \(error)")
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

    private func scheduleSpectrogramSendIfNeeded() {
        guard !isSpectrogramSendScheduled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let sendInterval = adaptiveSpectrogramSendInterval()
        let earliestSend = lastSpectrogramSendTime + sendInterval
        let delay = max(0, earliestSend - now)

        isSpectrogramSendScheduled = true
        sendQueue.asyncAfter(deadline: .now() + delay) {
            self.flushPendingSpectrogramData()
        }
    }

    private func flushPendingSpectrogramData() {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "WatchSendSpectrogram", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "WatchSendSpectrogram", signpostID: signpostID) }

        guard let dataToSend = pendingSpectrogramData else {
            isSpectrogramSendScheduled = false
            return
        }

        pendingSpectrogramData = nil
        isSpectrogramSendScheduled = false
        lastSpectrogramSendTime = ProcessInfo.processInfo.systemUptime

        guard WCSession.default.isReachable else {
            if !hasLoggedUnreachability {
                print("Watch not reachable")
                hasLoggedUnreachability = true
            }
            // Note: the "if pendingSpectrogramData != nil { reschedule }"
            // branches that previously lived here and after `sendMessageData`
            // were dead code. `pendingSpectrogramData` was set to nil three
            // lines above and `sendQueue` is serial, so no other writer can
            // mutate it between then and here.
            return
        }
        hasLoggedUnreachability = false

        let packet = WatchConnectivityProtocol.makeSpectrogramPacket(dataToSend)
        WCSession.default.sendMessageData(packet, replyHandler: nil) { error in
            print("Error sending spectrogram data: \(error.localizedDescription)")
        }
    }

    private func adaptiveSpectrogramSendInterval() -> TimeInterval {
        let processInfo = ProcessInfo.processInfo
        if processInfo.isLowPowerModeEnabled {
            return WatchConnectivityProtocol.lowPowerSpectrogramSendInterval
        }

        switch processInfo.thermalState {
        case .serious:
            return WatchConnectivityProtocol.seriousThermalSpectrogramSendInterval
        case .critical:
            return WatchConnectivityProtocol.criticalThermalSpectrogramSendInterval
        case .fair:
            return WatchConnectivityProtocol.fairThermalSpectrogramSendInterval
        default:
            return WatchConnectivityProtocol.normalSpectrogramSendInterval
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
        #if os(watchOS)
        if activationState == .activated {
            syncPendingRecordings()
        }
        #endif
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "WatchDidReceiveMessage", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "WatchDidReceiveMessage", signpostID: signpostID) }

        guard let type = WatchConnectivityProtocol.messageType(from: message) else {
            // Unknown message type — log so a missing decoder doesn't go
            // unnoticed during cross-version skew.
            if let typeRaw = message[WatchConnectivityProtocol.Key.type] as? String {
                print("[WCM] Ignored unknown message type: \(typeRaw)")
            }
            return
        }

        switch type {
        case .startRecording:
            let source = WatchConnectivityProtocol.recordingSource(from: message)
            // WCSession delivers `didReceiveMessage` on a background queue.
            // All state mutation AND the NotificationCenter post must hop to
            // main so observers (e.g. WatchAudioEngine.handleStartRecording)
            // touch AVAudioEngine and `@Published` state on the main thread.
            DispatchQueue.main.async {
                if let source {
                    self.selectedMicrophoneSource = source
                    self.onMicrophoneSourceChanged?(source)
                }
                NotificationCenter.default.post(name: .startRecordingCommand, object: source)
            }
        case .stopRecording:
            let source = WatchConnectivityProtocol.recordingSource(from: message)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .stopRecordingCommand, object: source)
            }
        case .gain:
            if let gain = WatchConnectivityProtocol.gain(from: message) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .gainOrBandwidthChangedNotification, object: gain)
                }
            }
        case .microphoneSource:
            if let source = WatchConnectivityProtocol.microphoneSource(from: message) {
                DispatchQueue.main.async {
                    self.selectedMicrophoneSource = source
                    self.onMicrophoneSourceChanged?(source)
                }
            }
        case .watchDashboardConfig:
            if let configString = WatchConnectivityProtocol.dashboardConfigString(from: message),
               let configData = configString.data(using: .utf8),
               let config = WatchDashboardConfig.decode(from: configData) {
                DispatchQueue.main.async {
                    self.watchDashboardConfig = config
                    config.save()
                    NotificationCenter.default.post(name: .watchDashboardConfigChanged, object: config)
                    print("[WCM] Received watch dashboard config with \(config.widgets.count) widgets")
                }
            }
        case .frequencyWeighting:
            if let weighting = WatchConnectivityProtocol.frequencyWeighting(from: message) {
                DispatchQueue.main.async {
                    self.frequencyWeighting = weighting
                }
            }
        case .appStateUpdate:
            // Phase 2 (M13 task-7) wires consumption — watch faces
            // read accent/theme from this envelope to replace
            // hardcoded phosphor. For now: decode-and-drop so the
            // exhaustive switch compiles and the envelope can be
            // round-tripped end-to-end on hardware without
            // user-visible effect.
            _ = WatchConnectivityProtocol.appStateUpdate(from: message)
        }
    }

    /// Handles binary-encoded spectrogram (0x01) data from iOS.
    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
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
    /// Minimum interval between WidgetKit timeline reloads.
    ///
    /// watchOS enforces a hard daily budget on complication refreshes
    /// (~50 reloads/day, per WidgetKit docs). The previous 1-second cadence
    /// could exhaust the budget in under a minute of continuous measurement,
    /// after which the system silently stops updating the complication.
    /// 60 s keeps live values fresh enough for an at-a-glance level indicator
    /// while staying comfortably inside the system budget for an all-day
    /// session (60 reloads/hour vs ~50 reloads/day allowed without
    /// throttling — Apple coalesces beyond a soft hourly limit too).
    private static let complicationReloadMinimumInterval: TimeInterval = 60

    private func updateComplicationState(from data: SpectrogramData) {
        let now = Date()
        guard now.timeIntervalSince(lastComplicationReload) >= Self.complicationReloadMinimumInterval else { return }

        // Update `lastComplicationReload` BEFORE issuing the reload so a second
        // call arriving within the same tick cannot race past the throttle
        // check. Previously this was assigned after the WidgetCenter call,
        // making the guard a TOCTOU window.
        lastComplicationReload = now

        // Route through the App Group suite so the widget extension's process
        // can read these. Previously this wrote to `UserDefaults.standard`,
        // which the extension never sees — meaning live data never reached
        // the complication.
        let shared = AppGroup.defaults
        shared.set(data.levels["LAF"] ?? data.broadbandLevel, forKey: ComplicationSharedKeys.level)
        shared.set(frequencyWeighting, forKey: ComplicationSharedKeys.weighting)

        Self.complicationWidgetKinds.forEach {
            WidgetCenter.shared.reloadTimelines(ofKind: $0)
        }
    }
    #endif

    // Handle application context for background config delivery
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let weighting = applicationContext["frequencyWeighting"] as? String {
            DispatchQueue.main.async {
                self.frequencyWeighting = weighting
            }
        }
        if let configString = applicationContext[PersistenceKeys.watchDashboardConfig] as? String,
           let configData = configString.data(using: .utf8),
           let config = WatchDashboardConfig.decode(from: configData) {
            DispatchQueue.main.async {
                self.watchDashboardConfig = config
                config.save()
                NotificationCenter.default.post(name: .watchDashboardConfigChanged, object: config)
                print("[WCM] Received watch dashboard config via context")
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            print("[WCM] Reachability: \(session.isReachable)")
            self.isReachable = session.isReachable
        }
        #if os(watchOS)
        if session.isReachable {
            syncPendingRecordings()
        }
        #endif
    }

    /// Incoming standalone recording file (iOS) / ingest acknowledgement (watch).
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        #if os(iOS)
        transferIngestQueue.async { [weak self] in
            self?.handleIncomingRecordingFile(file)
        }
        #endif
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        #if os(watchOS)
        if let id = WatchConnectivityProtocol.syncedRecordingId(fromUserInfo: userInfo) {
            DispatchQueue.main.async {
                WatchRecordingStore.shared.setSyncState(.synced, for: id)
            }
        }
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}

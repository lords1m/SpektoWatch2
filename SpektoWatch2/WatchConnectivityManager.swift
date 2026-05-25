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
    }
    
    public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            if self.isReachable {
                self.processQueue()
            }
        }
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
}

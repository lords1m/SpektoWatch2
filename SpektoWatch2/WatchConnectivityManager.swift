import Foundation
import WatchConnectivity
import Combine
import OSLog

public class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    
    @Published public var isReachable = false
    @Published public var spectrogramData: SpectrogramData?
    @Published public var selectedMicrophoneSource: MicrophoneSource = .iPhone
    @Published public var watchDashboardConfig: WatchDashboardConfig?
    @Published public var frequencyWeighting: String = "A"
    
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
            DispatchQueue.main.async { self.spectrogramData = specData }
        }
    }
    
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            if let type = WatchConnectivityProtocol.messageType(from: message) {
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
                }
            }
        }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            if let weighting = applicationContext["frequencyWeighting"] as? String {
                self.frequencyWeighting = weighting
            }
            if let configString = applicationContext["watchDashboardConfig"] as? String,
               let configData = configString.data(using: .utf8),
               let config = WatchDashboardConfig.decode(from: configData) {
                self.watchDashboardConfig = config
                config.save()
            }
        }
    }
    
    // MARK: - Senden (Public API)
    
    public func sendSpectrogramData(_ data: SpectrogramData) {
        // Echtzeit-Daten senden wir direkt (Fire & Forget), keine Queue
        guard WCSession.default.isReachable else { return }
        let packet = WatchConnectivityProtocol.makeSpectrogramPacket(data)
        WCSession.default.sendMessageData(packet, replyHandler: nil, errorHandler: nil)
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
            try WCSession.default.updateApplicationContext(["watchDashboardConfig": configString])
        } catch {
            // Ignore context errors
        }
    }

    // MARK: - Queue Logic
    
    private func sendWithRetry(_ message: [String: Any]) {
        let queued = QueuedMessage(message: message, retries: 0, timestamp: Date())
        messageQueue.append(queued)
        processQueue()
    }
    
    private func processQueue() {
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

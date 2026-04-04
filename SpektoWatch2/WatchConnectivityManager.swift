import Foundation
import WatchConnectivity
import Combine
import OSLog

public class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    
    @Published public var isReachable = false
    @Published public var spectrogramData: SpectrogramData?
    @Published public var audioData: AudioData?
    @Published public var selectedMicrophoneSource: MicrophoneSource = .iPhone
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
        let type = messageData[0]
        // dropFirst() liefert einen Slice mit Start-Index 1, nicht 0.
        // copyBytes(to:from:) in fromBinaryData() verwendet absolute Indices → OOB-Crash.
        // Data(...) kopiert den Buffer und setzt die Indices auf 0 zurück.
        let payload = Data(messageData.dropFirst())
        
        if type == 0x01 {
            if let specData = SpectrogramData.fromBinaryData(payload) {
                DispatchQueue.main.async { self.spectrogramData = specData }
            }
        } else if type == 0x02 {
            if let audioData = AudioData.fromBinaryData(payload) {
                DispatchQueue.main.async {
                    self.audioData = audioData
                }
            }
        }
    }
    
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            if let type = message["type"] as? String {
                switch type {
                case "microphoneSource":
                    if let sourceRaw = message["source"] as? String,
                       let source = MicrophoneSource(rawValue: sourceRaw) {
                        self.selectedMicrophoneSource = source
                    }
                case "startRecording":
                    NotificationCenter.default.post(name: .startRecordingCommand, object: nil)
                case "stopRecording":
                    NotificationCenter.default.post(name: .stopRecordingCommand, object: nil)
                case "frequencyWeighting":
                    if let weighting = message["value"] as? String {
                        self.frequencyWeighting = weighting
                    }
                default:
                    break
                }
            }
        }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            if let weighting = applicationContext["frequencyWeighting"] as? String {
                self.frequencyWeighting = weighting
            }
        }
    }
    
    // MARK: - Senden (Public API)
    
    public func sendSpectrogramData(_ data: SpectrogramData) {
        // Echtzeit-Daten senden wir direkt (Fire & Forget), keine Queue
        guard WCSession.default.isReachable else { return }
        var packet = Data([0x01]) // Header 0x01 for Spectrogram
        packet.append(data.toBinaryData())
        WCSession.default.sendMessageData(packet, replyHandler: nil, errorHandler: nil)
    }
    
    public func sendAudioData(_ data: AudioData) {
        guard WCSession.default.isReachable else { return }
        var packet = Data([0x02]) // Header 0x02 for Audio
        packet.append(data.toBinaryData())
        WCSession.default.sendMessageData(packet, replyHandler: nil, errorHandler: nil)
    }
    
    public func sendGainValue(_ gain: Float) {
        sendWithRetry(["type": "gain", "value": gain])
    }
    
    public func sendMicrophoneSourceSelection(_ source: MicrophoneSource) {
        sendWithRetry(["type": "microphoneSource", "source": source.rawValue])
    }

    public func sendFrequencyWeightingSelection(_ weighting: String) {
        sendWithRetry(["type": "frequencyWeighting", "value": weighting])
        do {
            try WCSession.default.updateApplicationContext(["frequencyWeighting": weighting])
        } catch {
            // Ignore context errors
        }
    }
    
    public func requestRecordingStart() {
        sendWithRetry(["type": "startRecording"])
    }
    
    public func requestRecordingStop() {
        sendWithRetry(["type": "stopRecording"])
    }

    public func sendWatchDashboardConfig(_ config: WatchDashboardConfig) {
        guard let configData = config.encode(),
              let configString = String(data: configData, encoding: .utf8) else {
            return
        }
        sendWithRetry(["type": "watchDashboardConfig", "config": configString])

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

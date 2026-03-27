import Foundation
import WatchConnectivity
import Combine
import os.signpost

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    private static let performanceLog = OSLog(subsystem: "com.spektowatch", category: "performance.connectivity")
    private let sendQueue = DispatchQueue(label: "com.spektowatch.watch-send", qos: .utility)
    private let spectrogramEncoder = JSONEncoder()
    private var pendingSpectrogramData: SpectrogramData?
    private var isSpectrogramSendScheduled = false
    private var lastSpectrogramSendTime: TimeInterval = 0

    @Published var spectrogramData: SpectrogramData?
    @Published var audioData: AudioData?
    @Published var isReachable = false
    @Published var selectedMicrophoneSource: MicrophoneSource = .iPhone
    @Published var watchDashboardConfig: WatchDashboardConfig?

    var onMicrophoneSourceChanged: ((MicrophoneSource) -> Void)?
    private var hasLoggedUnreachability = false

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

    func sendAudioData(_ data: AudioData) {
        guard WCSession.default.isReachable else {
            print("iPhone not reachable")
            return
        }

        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(data)

            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let message = ["audioData": jsonString]
                WCSession.default.sendMessage(message, replyHandler: nil) { error in
                    print("Error sending audio data: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error encoding audio data: \(error)")
        }
    }

    func sendMicrophoneSourceSelection(_ source: MicrophoneSource) {
        guard WCSession.default.isReachable else {
            print("Watch not reachable")
            return
        }

        let message: [String: Any] = ["type": "microphoneSource", "source": source.rawValue]
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Error sending microphone source: \(error.localizedDescription)")
        }
    }

    func requestRecordingStart() {
        print("[WCM] Requesting Start")
        guard WCSession.default.isReachable else {
            print("[WCM] Error: Not reachable")
            return
        }
        // Key "type" matches what the iOS-side WatchConnectivityManager expects.
        let message: [String: Any] = ["type": "startRecording"]
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Error sending start command: \(error.localizedDescription)")
        }
    }

    func requestRecordingStop() {
        print("[WCM] Requesting Stop")
        guard WCSession.default.isReachable else {
            print("[WCM] Error: Not reachable")
            return
        }
        let message: [String: Any] = ["type": "stopRecording"]
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Error sending stop command: \(error.localizedDescription)")
        }
    }

    func sendGainValue(_ gain: Float) {
        guard WCSession.default.isReachable else { return }
        let message: [String: Any] = ["type": "gain", "value": gain]
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

        let message = ["watchDashboardConfig": configString]
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
            try WCSession.default.updateApplicationContext(["watchDashboardConfig": configString])
            print("[WCM] Dashboard config sent via application context")
        } catch {
            print("[WCM] Error sending dashboard config via context: \(error.localizedDescription)")
        }
    }

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
            if pendingSpectrogramData != nil {
                scheduleSpectrogramSendIfNeeded()
            }
            return
        }
        hasLoggedUnreachability = false

        do {
            let jsonData = try spectrogramEncoder.encode(dataToSend)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let message = ["spectrogramData": jsonString]
                WCSession.default.sendMessage(message, replyHandler: nil) { error in
                    print("Error sending message: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error encoding spectrogram data: \(error)")
        }

        if pendingSpectrogramData != nil {
            scheduleSpectrogramSendIfNeeded()
        }
    }

    private func adaptiveSpectrogramSendInterval() -> TimeInterval {
        let processInfo = ProcessInfo.processInfo
        if processInfo.isLowPowerModeEnabled {
            return 0.25
        }

        switch processInfo.thermalState {
        case .serious:
            return 0.33
        case .critical:
            return 0.5
        case .fair:
            return 0.2
        default:
            return 0.1
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "WatchDidReceiveMessage", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "WatchDidReceiveMessage", signpostID: signpostID) }

        // The iOS-side uses a ["type": "..."] envelope for all control messages.
        if let type = message["type"] as? String {
            switch type {
            case "startRecording":
                NotificationCenter.default.post(name: .startRecordingCommand, object: nil)
            case "stopRecording":
                NotificationCenter.default.post(name: .stopRecordingCommand, object: nil)
            case "gain":
                if let gain = message["value"] as? Float {
                    NotificationCenter.default.post(name: .gainOrBandwidthChangedNotification, object: gain)
                }
            case "microphoneSource":
                if let sourceString = message["source"] as? String,
                   let source = MicrophoneSource(rawValue: sourceString) {
                    DispatchQueue.main.async {
                        self.selectedMicrophoneSource = source
                        self.onMicrophoneSourceChanged?(source)
                    }
                }
            case "watchDashboardConfig":
                if let configString = message["config"] as? String,
                   let configData = configString.data(using: .utf8),
                   let config = WatchDashboardConfig.decode(from: configData) {
                    DispatchQueue.main.async {
                        self.watchDashboardConfig = config
                        NotificationCenter.default.post(name: .watchDashboardConfigChanged, object: config)
                        print("[WCM] Received watch dashboard config with \(config.widgets.count) widgets")
                    }
                }
            default:
                print("[WCM] Unknown message type: \(type)")
            }
        }
    }

    /// Handles binary-encoded spectrogram (0x01) and audio (0x02) data from iOS.
    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard !messageData.isEmpty else { return }
        let type = messageData[0]
        let payload = messageData.dropFirst()

        if type == 0x01 {
            if let specData = SpectrogramData.fromBinaryData(payload) {
                DispatchQueue.main.async { self.spectrogramData = specData }
            }
        } else if type == 0x02 {
            if let audioData = AudioData.fromBinaryData(payload) {
                DispatchQueue.main.async { self.audioData = audioData }
            }
        }
    }

    // Handle application context for background config delivery
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let configString = applicationContext["watchDashboardConfig"] as? String,
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
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}

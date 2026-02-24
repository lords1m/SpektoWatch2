import Foundation
import WatchConnectivity
import Combine
import os.signpost

extension Notification.Name {
    static let startRecordingCommand = Notification.Name("startRecordingCommand")
    static let stopRecordingCommand = Notification.Name("stopRecordingCommand")
    static let gainOrBandwidthChangedNotification = Notification.Name("gainOrBandwidthChangedNotification")
}

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

        let message = ["microphoneSource": source.rawValue]
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

        let message = ["command": "startRecording"]
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

        let message = ["command": "stopRecording"]
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Error sending stop command: \(error.localizedDescription)")
        }
    }

    func sendGainValue(_ gain: Float) {
        let message = ["gain": gain]
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

        if let jsonString = message["spectrogramData"] as? String,
           let jsonData = jsonString.data(using: .utf8) {
            do {
                let decoder = JSONDecoder()
                let data = try decoder.decode(SpectrogramData.self, from: jsonData)

                DispatchQueue.main.async {
                    self.spectrogramData = data
                }
            } catch {
                print("Error decoding spectrogram data: \(error)")
            }
        } else if let jsonString = message["audioData"] as? String,
                  let jsonData = jsonString.data(using: .utf8) {
            do {
                let decoder = JSONDecoder()
                let data = try decoder.decode(AudioData.self, from: jsonData)

                DispatchQueue.main.async {
                    self.audioData = data
                }
            } catch {
                print("Error decoding audio data: \(error)")
            }
        } else if let sourceString = message["microphoneSource"] as? String,
                  let source = MicrophoneSource(rawValue: sourceString) {
            DispatchQueue.main.async {
                self.selectedMicrophoneSource = source
                self.onMicrophoneSourceChanged?(source)
            }
        } else if let command = message["command"] as? String {
            print("[WCM] Received command '\(command)'")
            if command == "startRecording" {
                NotificationCenter.default.post(name: .startRecordingCommand, object: nil)
            } else if command == "stopRecording" {
                NotificationCenter.default.post(name: .stopRecordingCommand, object: nil)
            }
        } else if let gain = message["gain"] as? Float {
            NotificationCenter.default.post(name: .gainOrBandwidthChangedNotification, object: gain)
        } else if let configString = message["watchDashboardConfig"] as? String,
                  let configData = configString.data(using: .utf8),
                  let config = WatchDashboardConfig.decode(from: configData) {
            DispatchQueue.main.async {
                self.watchDashboardConfig = config
                NotificationCenter.default.post(name: .watchDashboardConfigChanged, object: config)
                print("[WCM] Received watch dashboard config with \(config.widgets.count) widgets")
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

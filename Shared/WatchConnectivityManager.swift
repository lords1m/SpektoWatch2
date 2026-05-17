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
    private static let complicationLevelKey = "spw.complication.level"
    private static let complicationWeightingKey = "spw.complication.weighting"
    private static let complicationWidgetKinds = [
        "SpektoWatchLevelCircular",
        "SpektoWatchLevelRectangular",
        "SpektoWatchLevelInline"
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

        let packet = WatchConnectivityProtocol.makeSpectrogramPacket(dataToSend)
        WCSession.default.sendMessageData(packet, replyHandler: nil) { error in
            print("Error sending spectrogram data: \(error.localizedDescription)")
        }

        if pendingSpectrogramData != nil {
            scheduleSpectrogramSendIfNeeded()
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
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "WatchDidReceiveMessage", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "WatchDidReceiveMessage", signpostID: signpostID) }

        if let type = WatchConnectivityProtocol.messageType(from: message) {
            switch type {
            case .startRecording:
                let source = WatchConnectivityProtocol.recordingSource(from: message)
                if let source {
                    DispatchQueue.main.async {
                        self.selectedMicrophoneSource = source
                        self.onMicrophoneSourceChanged?(source)
                    }
                }
                NotificationCenter.default.post(name: .startRecordingCommand, object: source)
            case .stopRecording:
                let source = WatchConnectivityProtocol.recordingSource(from: message)
                NotificationCenter.default.post(name: .stopRecordingCommand, object: source)
            case .gain:
                if let gain = WatchConnectivityProtocol.gain(from: message) {
                    NotificationCenter.default.post(name: .gainOrBandwidthChangedNotification, object: gain)
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
            }
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
    private func updateComplicationState(from data: SpectrogramData) {
        let now = Date()
        guard now.timeIntervalSince(lastComplicationReload) >= 1 else { return }

        UserDefaults.standard.set(data.levels["LAF"] ?? data.broadbandLevel, forKey: Self.complicationLevelKey)
        UserDefaults.standard.set(frequencyWeighting, forKey: Self.complicationWeightingKey)

        lastComplicationReload = now
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

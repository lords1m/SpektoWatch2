import Foundation
import WatchConnectivity
import Combine

extension Notification.Name {
    static let startRecordingCommand = Notification.Name("startRecordingCommand")
    static let stopRecordingCommand = Notification.Name("stopRecordingCommand")
}

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var spectrogramData: SpectrogramData?
    @Published var audioData: AudioData?
    @Published var isReachable = false
    @Published var selectedMicrophoneSource: MicrophoneSource = .iPhone

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
        guard WCSession.default.isReachable else {
            if !hasLoggedUnreachability {
                print("Watch not reachable")
                hasLoggedUnreachability = true
            }
            return
        }
        hasLoggedUnreachability = false

        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(data)

            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let message = ["spectrogramData": jsonString]
                WCSession.default.sendMessage(message, replyHandler: nil) { error in
                    print("Error sending message: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error encoding spectrogram data: \(error)")
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
        guard WCSession.default.isReachable else {
            print("Watch not reachable")
            return
        }

        let message = ["command": "startRecording"]
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Error sending start command: \(error.localizedDescription)")
        }
    }

    func requestRecordingStop() {
        guard WCSession.default.isReachable else {
            print("Watch not reachable")
            return
        }

        let message = ["command": "stopRecording"]
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Error sending stop command: \(error.localizedDescription)")
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
            if command == "startRecording" {
                NotificationCenter.default.post(name: .startRecordingCommand, object: nil)
            } else if command == "stopRecording" {
                NotificationCenter.default.post(name: .stopRecordingCommand, object: nil)
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
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

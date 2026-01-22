import Foundation
import AVFoundation
import WatchKit
import Combine

class WatchAudioEngine: NSObject, ObservableObject {
    private var audioEngine: AVAudioEngine
    private let bufferSize: AVAudioFrameCount = 4096
    private let sampleRate: Double = 44100.0

    @Published var isRecording = false

    override init() {
        audioEngine = AVAudioEngine()
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStartRecording),
            name: .startRecordingCommand,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStopRecording),
            name: .stopRecordingCommand,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleStartRecording() {
        startRecording()
    }

    @objc private func handleStopRecording() {
        stopRecording()
    }

    func startRecording() {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)

            try audioEngine.start()

            DispatchQueue.main.async {
                self.isRecording = true
            }
        } catch {
            print("Watch audio engine start error: \(error)")
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        let audioData = AudioData(samples: samples, sampleRate: sampleRate)
        WatchConnectivityManager.shared.sendAudioData(audioData)
    }
}

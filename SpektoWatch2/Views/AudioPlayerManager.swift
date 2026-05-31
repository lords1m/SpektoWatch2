import AVFoundation
import Combine
import Foundation

/// Lightweight audio-file player used by `RecordingDetailView`'s
/// playback section. Wraps an `AVAudioEngine` + `AVAudioPlayerNode`
/// so the detail view can scrub, seek, and tap-out samples for the
/// visualization pipeline.
///
/// Extracted from `RecordingDetailView.swift` as part of M13 task-2.
/// Owns no shared state with the detail view — the extraction is
/// purely mechanical.
final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var isLoaded = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var scrubTime: TimeInterval = 0

    /// Forwards decoded playback samples together with the sample rate of the
    /// tap buffer. The rate is taken from the buffer's own format (the engine
    /// mixer rate), which can differ from the recording's file sample rate, so
    /// downstream frequency analysis must use this value rather than assuming
    /// the recording rate.
    var onAudioSamples: (([Float], Double) -> Void)?

    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var updateTimer: Timer?
    private var seekFrame: AVAudioFramePosition = 0
    private var sampleRate: Double = 44100.0
    private var wasPlayingBeforeScrub = false
    private let processingQueue = DispatchQueue(label: "com.spektowatch.audioprocessing", qos: .userInteractive)

    override init() {
        super.init()
        setupEngine()
    }

    deinit {
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func setupEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self, self.isPlaying, let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            let bufferSampleRate = buffer.format.sampleRate
            self.processingQueue.async {
                self.onAudioSamples?(samples, bufferSampleRate)
            }
        }
    }

    /// Loads an audio file for playback. Returns `true` on success. On failure
    /// the caller is expected to surface the error to the user — previously this
    /// only logged, so a missing/corrupt file left the play button silently dead.
    @discardableResult
    func loadAudio(url: URL) -> Bool {
        do {
            audioFile = try AVAudioFile(forReading: url)
            if let file = audioFile {
                sampleRate = file.processingFormat.sampleRate
                duration = Double(file.length) / sampleRate
            }
            isLoaded = true
            return true
        } catch {
            print("[AudioPlayerManager] ERROR loading audio: \(error.localizedDescription)")
            isLoaded = false
            return false
        }
    }

    func play() {
        guard let file = audioFile, !isPlaying else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AudioPlayerManager] Session error: \(error)")
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("[AudioPlayerManager] Engine start failed: \(error)")
                return
            }
        }

        let remainingFrames = AVAudioFrameCount(file.length - seekFrame)
        if remainingFrames > 0 {
            playerNode.scheduleSegment(file, startingFrame: seekFrame, frameCount: remainingFrames, at: nil) { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isPlaying else { return }
                    self.stop()
                }
            }
        }

        playerNode.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopTimer()
        seekFrame = AVAudioFramePosition(currentTime * sampleRate)
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        isPlaying = false
        currentTime = 0
        seekFrame = 0
        stopTimer()
    }

    func beginScrubbing() {
        wasPlayingBeforeScrub = isPlaying
        if isPlaying {
            playerNode.pause()
            stopTimer()
        }
    }

    func endScrubbing() {
        if wasPlayingBeforeScrub {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying
        if wasPlaying {
            playerNode.stop()
            isPlaying = false
            stopTimer()
        }

        currentTime = time
        scrubTime = time
        seekFrame = AVAudioFramePosition(time * sampleRate)

        if wasPlaying {
            play()
        }
    }

    func seek(by offset: TimeInterval) {
        let newTime = currentTime + offset
        seek(to: max(0, min(newTime, duration)))
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            if let nodeTime = self.playerNode.lastRenderTime,
               let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) {
                let currentFrame = self.seekFrame + playerTime.sampleTime
                self.currentTime = Double(currentFrame) / self.sampleRate
            } else if self.currentTime < self.duration {
                self.currentTime += 0.03
            }
        }
        // Add to .common modes so the playhead keeps advancing while the user
        // scrolls the detail view (UITracking run-loop mode). With the default
        // scheduledTimer the timer pauses during scrolling and playback time freezes.
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}

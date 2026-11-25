import AVFoundation
import Combine
import Foundation
import os

/// Lightweight audio-file player used by `RecordingDetailView`'s
/// playback section. Wraps an `AVAudioEngine` + `AVAudioPlayerNode`
/// so the detail view can scrub, seek, and tap-out samples for the
/// visualization pipeline.
///
/// Extracted from `RecordingDetailView.swift` as part of M13 task-2.
/// Owns no shared state with the detail view — the extraction is
/// purely mechanical.
final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false {
        didSet {
            tapStateLock.withLock { $0.isPlaying = isPlaying }
        }
    }
    @Published var isLoaded = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var scrubTime: TimeInterval = 0

    /// Forwards decoded playback samples together with the sample rate of the
    /// tap buffer. The rate is taken from the buffer's own format (the engine
    /// mixer rate), which can differ from the recording's file sample rate, so
    /// downstream frequency analysis must use this value rather than assuming
    /// the recording rate.
    var onAudioSamples: (([Float], Double) -> Void)? {
        get { tapStateLock.withLock { $0.onAudioSamples } }
        set { tapStateLock.withLock { $0.onAudioSamples = newValue } }
    }

    private struct TapState {
        var isPlaying = false
        var onAudioSamples: (([Float], Double) -> Void)?
    }

    private let tapStateLock = OSAllocatedUnfairLock<TapState>(initialState: TapState())
    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var updateTimer: Timer?
    private var seekFrame: AVAudioFramePosition = 0
    private var sampleRate: Double = 44100.0
    private var wasPlayingBeforeScrub = false
    /// True after `pause()` / scrub-hold while scheduled buffers are still valid.
    private var canResumeAfterPause = false
    /// Monotonic counter invalidated on every stop/seek/play so a stale
    /// `scheduleSegment` completion from a prior segment cannot stop playback.
    private var playbackGeneration: UInt64 = 0
    private let processingQueue = DispatchQueue(label: "com.spektowatch.audioprocessing", qos: .userInteractive)

    override init() {
        super.init()
        setupEngine()
    }

    deinit {
        stopTimer()
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func setupEngine() {
        engine.attach(playerNode)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            let playing = self.tapStateLock.withLockUnchecked { $0.isPlaying }
            guard playing, let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            let bufferSampleRate = buffer.format.sampleRate
            self.processingQueue.async { [weak self] in
                guard let self else { return }
                let callback = self.tapStateLock.withLock { $0.onAudioSamples }
                callback?(samples, bufferSampleRate)
            }
        }
    }

    /// Loads an audio file for playback. Returns `true` on success. On failure
    /// the caller is expected to surface the error to the user — previously this
    /// only logged, so a missing/corrupt file left the play button silently dead.
    @discardableResult
    func loadAudio(url: URL) -> Bool {
        stop()
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0 else {
                print("[AudioPlayerManager] ERROR: audio file has zero frames: \(url.lastPathComponent)")
                audioFile = nil
                isLoaded = false
                duration = 0
                return false
            }
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            duration = Double(file.length) / sampleRate
            seekFrame = 0
            currentTime = 0
            scrubTime = 0
            reconnectPlayer(to: file.processingFormat)
            isLoaded = duration > 0
            return isLoaded
        } catch {
            print("[AudioPlayerManager] ERROR loading audio: \(error.localizedDescription)")
            audioFile = nil
            isLoaded = false
            return false
        }
    }

    func play() {
        guard let file = audioFile, !isPlaying else { return }

        activatePlaybackSession()

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("[AudioPlayerManager] Engine start failed: \(error)")
                return
            }
        }

        if canResumeAfterPause {
            canResumeAfterPause = false
            playerNode.play()
            isPlaying = true
            startTimer()
            return
        }

        playbackGeneration &+= 1
        let expectedGeneration = playbackGeneration

        playerNode.stop()
        var startFrame = max(0, min(seekFrame, file.length))
        var remainingFrames = AVAudioFrameCount(max(0, file.length - startFrame))

        // At EOF, restart from the beginning instead of doing nothing.
        if remainingFrames == 0, file.length > 0 {
            startFrame = 0
            seekFrame = 0
            currentTime = 0
            scrubTime = 0
            remainingFrames = AVAudioFrameCount(file.length)
        }

        guard remainingFrames > 0 else {
            isLoaded = false
            return
        }

        seekFrame = startFrame
        reconnectPlayer(to: file.processingFormat)

        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: remainingFrames, at: nil) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isPlaying, self.playbackGeneration == expectedGeneration else { return }
                self.stop()
            }
        }

        playerNode.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        guard isPlaying else { return }
        playerNode.pause()
        isPlaying = false
        stopTimer()
        seekFrame = AVAudioFramePosition(currentTime * sampleRate)
        canResumeAfterPause = true
    }

    func stop() {
        playbackGeneration &+= 1
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
        isPlaying = false
        canResumeAfterPause = false
        currentTime = 0
        scrubTime = 0
        seekFrame = 0
        stopTimer()
    }

    func beginScrubbing() {
        wasPlayingBeforeScrub = isPlaying
        if isPlaying {
            playerNode.pause()
            stopTimer()
            seekFrame = AVAudioFramePosition(currentTime * sampleRate)
            canResumeAfterPause = true
            isPlaying = false
        }
    }

    func endScrubbing() {
        if wasPlayingBeforeScrub {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, duration))
        let wasPlaying = isPlaying
        playbackGeneration &+= 1
        if wasPlaying || canResumeAfterPause {
            playerNode.stop()
            isPlaying = false
            stopTimer()
        }
        canResumeAfterPause = false

        currentTime = clampedTime
        scrubTime = clampedTime
        seekFrame = AVAudioFramePosition(clampedTime * sampleRate)

        if wasPlaying {
            play()
        }
    }

    func seek(by offset: TimeInterval) {
        let newTime = currentTime + offset
        seek(to: max(0, min(newTime, duration)))
    }

    // MARK: - Private

    /// After live measurement the session is often `.record` / `.measurement`.
    /// Use a category that can actually route to the speaker, matching the
    /// tone-generator and masking players.
    private func activatePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            let needsConfig = (session.category != .playAndRecord && session.category != .playback)
                || session.mode == .measurement
                || (session.category == .playAndRecord && !session.categoryOptions.contains(.defaultToSpeaker))
            if needsConfig {
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker, .mixWithOthers]
                )
            }
            try session.setActive(true)
        } catch {
            print("[AudioPlayerManager] Session error: \(error)")
        }
    }

    private func reconnectPlayer(to format: AVAudioFormat) {
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
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

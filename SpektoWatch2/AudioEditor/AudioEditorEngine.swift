import AsyncAlgorithms
import AVFoundation
import Foundation
import Observation
import os

@Observable
@MainActor
final class AudioEditorEngine {
    private(set) var isLoaded = false
    private(set) var isPlaying = false
    var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var isBypassed = false {
        didSet { applyEQParameters() }
    }
    var isLoopingSelection = false
    var loopRange: AudioTimeRange?

    private struct ScheduledSegment {
        let sourceStartFrame: AVAudioFramePosition
        let frameCount: AVAudioFrameCount
        let editedStartTime: TimeInterval
        let editedEndTime: TimeInterval
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private let eqNode = AVAudioUnitEQ(numberOfBands: AudioUnitEQConfigurator.bandCount)

    @ObservationIgnored private var audioFile: AVAudioFile?
    @ObservationIgnored private var fileSampleRate: Double = 44100.0
    @ObservationIgnored private var fileLength: AVAudioFramePosition = 0
    @ObservationIgnored private var recipe = AudioEditRecipe(sourceDuration: 0)

    @ObservationIgnored nonisolated(unsafe) private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var playbackGeneration: UInt64 = 0
    @ObservationIgnored private var activePlaybackStartEditedTime: TimeInterval = 0
    @ObservationIgnored private var activeLoopRange: AudioTimeRange?
    @ObservationIgnored private var wasPlayingBeforeScrub = false

    @ObservationIgnored private weak var suspendedLiveEngine: AudioEngine?
    @ObservationIgnored private var didSuspendLiveEngine = false

    @ObservationIgnored nonisolated(unsafe) private var configurationObserver: NSObjectProtocol?

    /// Only attaches nodes. The graph is wired in `load(url:recipe:)`,
    /// after the session allows output: wiring it here (while live capture
    /// still holds a record-only session) bound the mixer to an output with
    /// no channels, so playback never started or stayed silent.
    init() {
        engine.attach(playerNode)
        engine.attach(eqNode)
    }

    deinit {
        updateTask?.cancel()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        engine.stop()
    }

    func suspendLiveCaptureIfNeeded(audioEngine: AudioEngine?) {
        guard let audioEngine, !didSuspendLiveEngine else { return }
        if audioEngine.engineStatus == .running && !audioEngine.recording.isRecordingToFile {
            audioEngine.stopLiveMode()
            suspendedLiveEngine = audioEngine
            didSuspendLiveEngine = true
        }
    }

    func restoreLiveCaptureIfNeeded() {
        stop()
        if didSuspendLiveEngine, let engine = suspendedLiveEngine {
            engine.startLiveMode()
        }
        suspendedLiveEngine = nil
        didSuspendLiveEngine = false
    }

    func load(url: URL, recipe: AudioEditRecipe) throws {
        stop()
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.processingFormat.sampleRate > 0 else {
            audioFile = nil
            isLoaded = false
            duration = 0
            return
        }
        audioFile = file
        fileSampleRate = file.processingFormat.sampleRate
        fileLength = file.length
        self.recipe = recipe
        duration = recipe.effectiveDuration
        currentTime = 0
        activatePlaybackSession()
        reconnectGraph(to: file.processingFormat)
        applyEQParameters()
        observeConfigurationChanges()
        isLoaded = true
    }

    func updateRecipe(_ newRecipe: AudioEditRecipe) {
        let rangesChanged = newRecipe.keptRanges != recipe.keptRanges
        recipe = newRecipe
        duration = newRecipe.effectiveDuration
        if currentTime > duration {
            currentTime = max(0, duration)
        }
        applyEQParameters()

        if rangesChanged && isPlaying {
            let resumeAt = min(currentTime, max(0, duration - 0.02))
            seek(to: resumeAt)
        }
    }

    func play() {
        guard let file = audioFile, !isPlaying, duration > 0 else { return }
        activatePlaybackSession()

        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                // The route may have changed since load: rewire and retry once.
                reconnectGraph(to: file.processingFormat)
                do {
                    engine.prepare()
                    try engine.start()
                } catch {
                    Logger.audioEngine.error("AudioEditorEngine start failed: \(error.localizedDescription)")
                    return
                }
            }
        }

        if currentTime >= duration - 0.02 {
            currentTime = 0
        }

        schedulePlayback(fromEditedTime: currentTime, file: file)
        playerNode.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        guard isPlaying else { return }
        playbackGeneration &+= 1
        let capturedTime = computeCurrentEditedTime()
        playerNode.stop()
        isPlaying = false
        stopTimer()
        currentTime = max(0, min(capturedTime, duration))
    }

    func stop() {
        playbackGeneration &+= 1
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
        isPlaying = false
        stopTimer()
        currentTime = 0
    }

    func beginScrubbing() {
        wasPlayingBeforeScrub = isPlaying
        if isPlaying {
            pause()
        }
    }

    func endScrubbing() {
        if wasPlayingBeforeScrub {
            wasPlayingBeforeScrub = false
            play()
        }
    }

    func seek(to editedTime: TimeInterval) {
        let clamped = max(0, min(editedTime, duration))
        let wasPlaying = isPlaying
        playbackGeneration &+= 1
        if wasPlaying {
            playerNode.stop()
            isPlaying = false
            stopTimer()
        }
        currentTime = clamped
        if wasPlaying {
            play()
        }
    }

    func seek(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    // MARK: - Private

    private func applyEQParameters() {
        // Gain is the EQ's globalGain (set above); the mixer stays at unity
        // so preview and export match and gain isn't applied twice.
        AudioUnitEQConfigurator.configure(eqNode: eqNode, recipe: recipe, bypassed: isBypassed)
        engine.mainMixerNode.outputVolume = 1.0
    }

    /// Wires player → EQ → mixer → output for the file's format, with the
    /// mixer → output link re-derived from the current hardware route.
    private func reconnectGraph(to format: AVAudioFormat) {
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eqNode)
        engine.disconnectNodeOutput(engine.mainMixerNode)
        engine.connect(playerNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
    }

    /// The engine stops itself when the route or session changes (headphones,
    /// live capture reconfiguring the session). Rewire it and keep the
    /// playhead so the next play works.
    private func observeConfigurationChanges() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let file = self.audioFile else { return }
                let wasPlaying = self.isPlaying
                if wasPlaying { self.pause() }
                self.reconnectGraph(to: file.processingFormat)
                if wasPlaying { self.play() }
            }
        }
    }

    private func schedulePlayback(fromEditedTime startEdited: TimeInterval, file: AVAudioFile) {
        playbackGeneration &+= 1
        let expectedGen = playbackGeneration
        playerNode.stop()

        let loopBounds: AudioTimeRange? = {
            guard isLoopingSelection, let lr = loopRange, lr.duration > 0.05 else { return nil }
            let clampedStart = max(0, min(lr.start, duration - 0.05))
            let clampedEnd = max(clampedStart + 0.05, min(lr.end, duration))
            return AudioTimeRange(start: clampedStart, end: clampedEnd)
        }()
        activeLoopRange = loopBounds

        let effectiveStart: TimeInterval
        let effectiveEnd: TimeInterval
        if let loopBounds {
            if startEdited < loopBounds.start || startEdited >= loopBounds.end - 0.02 {
                effectiveStart = loopBounds.start
            } else {
                effectiveStart = startEdited
            }
            effectiveEnd = loopBounds.end
        } else {
            effectiveStart = max(0, min(startEdited, duration))
            effectiveEnd = duration
        }

        currentTime = effectiveStart
        activePlaybackStartEditedTime = effectiveStart

        let segments = buildScheduledSegments(fromEdited: effectiveStart, toEdited: effectiveEnd)
        guard !segments.isEmpty else {
            isPlaying = false
            return
        }

        for (index, seg) in segments.enumerated() {
            let isLast = (index == segments.count - 1)
            playerNode.scheduleSegment(
                file,
                startingFrame: seg.sourceStartFrame,
                frameCount: seg.frameCount,
                at: nil
            ) { [weak self] in
                guard isLast else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.isPlaying, self.playbackGeneration == expectedGen else { return }
                    if let activeLoop = self.activeLoopRange, self.isLoopingSelection, let file = self.audioFile {
                        self.schedulePlayback(fromEditedTime: activeLoop.start, file: file)
                        self.playerNode.play()
                    } else {
                        self.stop()
                    }
                }
            }
        }
    }

    private func buildScheduledSegments(fromEdited: TimeInterval, toEdited: TimeInterval) -> [ScheduledSegment] {
        var result: [ScheduledSegment] = []
        var cursor: TimeInterval = 0

        for range in recipe.keptRanges {
            let segStartEdited = cursor
            let segEndEdited = cursor + range.duration
            cursor = segEndEdited

            let overlapStart = max(fromEdited, segStartEdited)
            let overlapEnd = min(toEdited, segEndEdited)
            guard overlapEnd - overlapStart > 0.002 else { continue }

            let srcStartSec = range.start + (overlapStart - segStartEdited)
            let srcEndSec = range.start + (overlapEnd - segStartEdited)
            let startFrame = max(0, min(fileLength - 1, AVAudioFramePosition(srcStartSec * fileSampleRate)))
            let endFrame = max(startFrame + 1, min(fileLength, AVAudioFramePosition(srcEndSec * fileSampleRate)))
            let frameCount = AVAudioFrameCount(max(1, endFrame - startFrame))

            result.append(ScheduledSegment(
                sourceStartFrame: startFrame,
                frameCount: frameCount,
                editedStartTime: overlapStart,
                editedEndTime: overlapEnd
            ))
        }
        return result
    }

    private func computeCurrentEditedTime() -> TimeInterval {
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
           playerTime.sampleRate > 0 {
            let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
            let candidate = activePlaybackStartEditedTime + max(0, elapsed)
            if let activeLoop = activeLoopRange {
                return min(candidate, activeLoop.end)
            }
            return min(candidate, duration)
        }
        return min(duration, currentTime + 0.03)
    }

    private func startTimer() {
        stopTimer()
        updateTask = Task { @MainActor [weak self] in
            for await _ in AsyncTimerSequence.repeating(every: .milliseconds(30), clock: .continuous) {
                guard !Task.isCancelled, let self, self.isPlaying else { break }
                self.currentTime = self.computeCurrentEditedTime()
            }
        }
    }

    private func stopTimer() {
        updateTask?.cancel()
        updateTask = nil
    }

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
            // Best effort
        }
    }
}

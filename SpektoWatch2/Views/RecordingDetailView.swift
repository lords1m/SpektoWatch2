import SwiftUI
import AVFoundation
import Combine
import Accelerate

struct RecordingDetailView: View {
    @Environment(\.dismiss) var dismiss
    let recording: AudioRecording

    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var vizAudioEngine = AudioEngine(
        filterManager: BandstopFilterManager(),
        connectivityManager: WatchConnectivityManager()
    )
    @State private var showEditSheet = false
    @State private var showShareSheet = false
    @State private var isDraggingSlider = false
    @State private var spectrogramHistory: [[Float]] = []
    @State private var isLoadingSpectrogram = false
    @State private var useScrollableSpectrogram = true  // Toggle für den neuen Modus
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Card
                    headerCard
                    
                    // Audio Player
                    audioPlayerCard
                    
                    // Statistics
                    statisticsCard
                    
                    // Metadata
                    metadataCard
                    
                    // Description
                    if !recording.description.isEmpty {
                        descriptionCard
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(recording.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showShareSheet = true }) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: { showEditSheet = true }) {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            let url = recording.url
            audioPlayer.loadAudio(url: url)
            audioPlayer.onAudioSamples = { samples in
                vizAudioEngine.processExternalAudio(samples)
            }

            // Berechne Spektrogramm-Historie für scrollbare Ansicht
            if useScrollableSpectrogram {
                loadSpectrogramHistory(from: url)
            }
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text(recording.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(recording.formattedDate)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Audio Player Card

    private var audioPlayerCard: some View {
        VStack(spacing: 16) {
            // Spectrogram Visualization - Scrollbar oder Live
            if useScrollableSpectrogram && !spectrogramHistory.isEmpty {
                // Scrollbares Spektrogramm mit Playhead
                ScrollableSpectrogramView(
                    currentTime: Binding(
                        get: { isDraggingSlider ? audioPlayer.scrubTime : audioPlayer.currentTime },
                        set: { _ in }
                    ),
                    duration: audioPlayer.duration,
                    magnitudeHistory: spectrogramHistory,
                    colormapType: 0,
                    onSeek: { time in
                        audioPlayer.scrubTime = time
                        audioPlayer.seek(to: time)
                    }
                )
                .frame(height: 200)
                .background(Color.black)
                .cornerRadius(12)
            } else if isLoadingSpectrogram {
                // Loading indicator
                ZStack {
                    Color.black
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Spektrogramm wird berechnet...")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                    }
                }
                .frame(height: 200)
                .cornerRadius(12)
            } else {
                // Live Spektrogramm (Fallback)
                HighEndSpectrogramAdapterWithAxes(audioEngine: vizAudioEngine, timeSpan: .seconds5, scrollSpeed: .fast)
                    .frame(height: 200)
                    .background(Color.black)
                    .cornerRadius(12)
            }

            // Playback Controls
            HStack(spacing: 20) {
                // Backward Button
                Button(action: { audioPlayer.seek(by: -5) }) {
                    Image(systemName: "gobackward.5")
                        .font(.title2)
                }
                .disabled(!audioPlayer.isLoaded)

                // Play/Pause Button
                Button(action: {
                    if audioPlayer.isPlaying {
                        audioPlayer.pause()
                    } else {
                        audioPlayer.play()
                    }
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                }
                .disabled(!audioPlayer.isLoaded)

                // Forward Button
                Button(action: { audioPlayer.seek(by: 5) }) {
                    Image(systemName: "goforward.5")
                        .font(.title2)
                }
                .disabled(!audioPlayer.isLoaded)
            }
            .foregroundColor(.blue)

            // Progress Bar
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { isDraggingSlider ? audioPlayer.scrubTime : audioPlayer.currentTime },
                        set: {
                            audioPlayer.scrubTime = $0
                            audioPlayer.seek(to: $0)
                        }
                    ),
                    in: 0...max(audioPlayer.duration, 0.1),
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if editing { audioPlayer.beginScrubbing() } else { audioPlayer.endScrubbing() }
                    }
                )
                .disabled(!audioPlayer.isLoaded)

                HStack {
                    Text(formatTime(isDraggingSlider ? audioPlayer.scrubTime : audioPlayer.currentTime))
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(audioPlayer.duration))
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Statistics Card
    
    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistik")
                .font(.headline)
            
            Divider()
            
            StatRow(icon: "waveform.path", title: "LA eq,Fast", value: String(format: "%.1f dB", recording.laeqFast))
            StatRow(icon: "arrow.up.circle", title: "Maximum", value: String(format: "%.1f dB", recording.peakLevel))
            StatRow(icon: "arrow.down.circle", title: "Minimum", value: String(format: "%.1f dB", recording.minLevel))
            StatRow(icon: "clock", title: "Dauer", value: recording.formattedDuration)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Metadata Card
    
    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Konfiguration")
                .font(.headline)
            
            Divider()
            
            StatRow(icon: "gauge", title: "Zeitbewertung", value: recording.timeWeighting)
            StatRow(icon: "slider.horizontal.3", title: "Frequenzbewertung", value: recording.frequencyWeighting)
            StatRow(icon: "music.note", title: "Samplerate", value: "\(Int(recording.sampleRate)) Hz")
            StatRow(icon: "speaker.wave.2", title: "Kanäle", value: "\(recording.channelCount)")
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Description Card
    
    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Beschreibung")
                .font(.headline)
            
            Divider()
            
            Text(recording.description)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Functions

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Spectrogram Loading

    private func loadSpectrogramHistory(from url: URL) {
        isLoadingSpectrogram = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let audioFile = try AVAudioFile(forReading: url)
                let format = audioFile.processingFormat
                let sampleRate = format.sampleRate
                let frameCount = AVAudioFrameCount(audioFile.length)

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    DispatchQueue.main.async { isLoadingSpectrogram = false }
                    return
                }

                try audioFile.read(into: buffer)

                guard let channelData = buffer.floatChannelData else {
                    DispatchQueue.main.async { isLoadingSpectrogram = false }
                    return
                }

                // Extract samples from first channel
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(frameCount)))

                // Compute spectrogram
                let history = computeSpectrogramHistory(samples: samples, sampleRate: sampleRate)

                DispatchQueue.main.async {
                    self.spectrogramHistory = history
                    self.isLoadingSpectrogram = false
                }
            } catch {
                print("[RecordingDetailView] Error loading audio for spectrogram: \(error)")
                DispatchQueue.main.async {
                    self.isLoadingSpectrogram = false
                }
            }
        }
    }

    private func computeSpectrogramHistory(samples: [Float], sampleRate: Double) -> [[Float]] {
        let fftSize = 4096
        let hopSize = 512
        let frequencyBins = 512
        let splToDbfsOffset: Float = 120.0

        guard samples.count > fftSize else { return [] }

        var history: [[Float]] = []

        // FFT Setup
        guard let fftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD) else { return [] }
        defer { vDSP_DFT_DestroySetup(fftSetup) }

        // Hann Window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var offset = 0
        while offset + fftSize <= samples.count {
            // Extract window
            let windowSamples = Array(samples[offset..<(offset + fftSize)])

            // Apply window
            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(windowSamples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

            // Prepare for zrop (interleaved input)
            var realIn = [Float](repeating: 0, count: fftSize / 2)
            var imagIn = [Float](repeating: 0, count: fftSize / 2)
            for i in 0..<(fftSize / 2) {
                realIn[i] = windowed[2 * i]
                imagIn[i] = windowed[2 * i + 1]
            }

            var realOut = [Float](repeating: 0, count: fftSize / 2)
            var imagOut = [Float](repeating: 0, count: fftSize / 2)

            vDSP_DFT_Execute(fftSetup, realIn, imagIn, &realOut, &imagOut)

            // Compute magnitude
            var magnitudes = [Float](repeating: 0, count: fftSize / 2)
            realOut.withUnsafeMutableBufferPointer { realPtr in
                imagOut.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                }
            }

            // Convert to dB SPL and resample to frequencyBins
            var column = [Float](repeating: -120.0, count: frequencyBins)
            for i in 0..<frequencyBins {
                let srcIndex = Int(Float(i) / Float(frequencyBins) * Float(magnitudes.count))
                let mag = magnitudes[min(srcIndex, magnitudes.count - 1)]
                let db = 20.0 * log10(mag + 1e-10) + splToDbfsOffset
                column[i] = db
            }

            history.append(column)
            offset += hopSize
        }

        return history
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Audio Player Manager

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var isLoaded = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var scrubTime: TimeInterval = 0
    
    var onAudioSamples: (([Float]) -> Void)?
    
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
    
    private func setupEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        
        // Install tap for visualization
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self = self, self.isPlaying else { return }
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            
            // WICHTIG: Nicht auf Main Thread dispatchen!
            // AudioEngine.processExternalAudio ist thread-safe und dispatched UI-Updates selbst.
            self.processingQueue.async {
                self.onAudioSamples?(samples)
            }
        }
    }
    
    func loadAudio(url: URL) {
        do {
            audioFile = try AVAudioFile(forReading: url)
            if let file = audioFile {
                sampleRate = file.processingFormat.sampleRate
                duration = Double(file.length) / sampleRate
            }
            isLoaded = true
            print("[AudioPlayerManager] Audio loaded: \(url.lastPathComponent)")
        } catch {
            print("[AudioPlayerManager] ERROR loading audio: \(error.localizedDescription)")
        }
    }
    
    func play() {
        guard let file = audioFile, !isPlaying else { return }
        
        // Configure Audio Session for Playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AudioPlayerManager] Session error: \(error)")
        }
        
        if !engine.isRunning {
            try? engine.start()
        }
        
        // Schedule remaining frames
        let remainingFrames = AVAudioFrameCount(file.length - seekFrame)
        if remainingFrames > 0 {
            playerNode.scheduleSegment(file, startingFrame: seekFrame, frameCount: remainingFrames, at: nil) {
                DispatchQueue.main.async {
                    if self.isPlaying {
                        self.stop() // Auto-stop at end
                    }
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
        
        // Store current position roughly
        // Note: Precise pausing with AVAudioEngine requires more complex node time calculation
        // For this simple player, we rely on the timer's last value
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
        // Nur seeken, wenn wir nicht gerade aktiv abspielen (wird durch beginScrubbing pausiert)
        // oder wenn wir programmgesteuert springen
        if isPlaying {
            playerNode.stop()
        }
        
        currentTime = time
        scrubTime = time
        seekFrame = AVAudioFramePosition(time * sampleRate)
        
        if isPlaying {
            play()
        }
    }
    
    func seek(by offset: TimeInterval) {
        let newTime = currentTime + offset
        seek(to: max(0, min(newTime, duration)))
    }
    
    private func startTimer() {
        stopTimer()
        // Schnellerer Timer für flüssigere UI (0.03s = ~30fps)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            
            // Präzisere Zeitberechnung basierend auf Node Time
            if let nodeTime = self.playerNode.lastRenderTime,
               let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) {
                let currentFrame = self.seekFrame + playerTime.sampleTime
                self.currentTime = Double(currentFrame) / self.sampleRate
            } else {
                // Fallback
                if self.currentTime < self.duration {
                    self.currentTime += 0.03
                }
            }
        }
    }
    
    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Handled in scheduleSegment completion
    }
}

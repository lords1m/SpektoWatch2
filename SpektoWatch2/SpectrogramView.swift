import SwiftUI

struct SpectrogramView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var spectrogramFrames: [SpectrogramFrame] = []
    @State private var isRecording = false
    @State private var selectedMicrophoneSource: MicrophoneSource = .iPhone
    @State private var lastUpdateTime: Date = .distantPast
    @State private var gainBoost: Double = 5.0  // Default gain for 1-10x range
    @State private var useMetalRenderer = true  // Toggle between Metal and Canvas

    let maxFrames = 600  // Many frames for smooth flow
    let updateThrottleInterval: TimeInterval = 1.0 / 30.0 // Max 30 FPS

    var body: some View {
        VStack(spacing: 0) {
            Text("Live Spektrogramm")
                .font(.title)
                .padding(.top)

            VStack(alignment: .leading, spacing: 4) {
                Text("Source")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                Picker("", selection: $selectedMicrophoneSource) {
                    ForEach(MicrophoneSource.allCases, id: \.self) { source in
                        Image(systemName: source == .iPhone ? "iphone" : "applewatch")
                            .tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedMicrophoneSource) { newSource in
                    handleMicrophoneSourceChange(newSource)
                }
                
                // Renderer Toggle
                HStack {
                    Text("Renderer:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $useMetalRenderer) {
                        Text("Metal").tag(true)
                        Text("Canvas").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                .padding(.top, 2)
                
                // Gain control
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verstärkung: \(Int(gainBoost))x")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("1x")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Slider(value: $gainBoost, in: 1...10, step: 1)
                            .onChange(of: gainBoost) { newGain in
                                audioEngine.setGainBoost(Float(newGain))
                            }

                        Text("10x")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ZStack {
                if spectrogramFrames.isEmpty {
                    Text("Tippe auf Start, um zu beginnen")
                        .foregroundColor(.gray)
                } else {
                    if useMetalRenderer {
                        // Use OPTIMIZED Metal renderer with bugfixes
                        // (Bilinear interpolation, noise gate, gamma correction, log compression)
                        HighEndSpectrogramAdapterWithAxes(audioEngine: audioEngine)
                    } else {
                        // Use Canvas renderer (original implementation)
                        SpectrogramCanvasWithAxes(frames: spectrogramFrames, maxFrames: maxFrames)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .padding(.top, 8)

            HStack {
                Image(systemName: connectivityManager.isReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(connectivityManager.isReachable ? .green : .red)
                Text(connectivityManager.isReachable ? "Watch verbunden" : "Watch nicht verbunden")
                    .foregroundColor(connectivityManager.isReachable ? .green : .red)
                    .font(.caption)
            }
            .padding(.vertical, 8)

            Button(action: toggleRecording) {
                HStack {
                    Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.title2)
                    Text(isRecording ? "Stop" : "Start")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(width: 200, height: 50)
                .background(isRecording ? Color.red : Color.green)
                .cornerRadius(25)
            }
            .padding(.bottom)
        }
        .onReceive(audioEngine.$currentSpectrogramData) { data in
            if let data = data, selectedMicrophoneSource == .iPhone {
                updateSpectrogramFrames(data)
            }
        }
        .onReceive(connectivityManager.$spectrogramData) { data in
            if let data = data, selectedMicrophoneSource == .appleWatch {
                updateSpectrogramFrames(data)
            }
        }
        .onAppear {
            // Set initial gain boost
            audioEngine.setGainBoost(Float(gainBoost))
        }
    }

    private func handleMicrophoneSourceChange(_ newSource: MicrophoneSource) {
        connectivityManager.selectedMicrophoneSource = newSource
        connectivityManager.sendMicrophoneSourceSelection(newSource)

        if isRecording {
            audioEngine.stopRecording()
            spectrogramFrames.removeAll()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if newSource == .iPhone {
                    audioEngine.startRecording()
                } else {
                    connectivityManager.requestRecordingStart()
                }
            }
        }
    }

    private func toggleRecording() {
        isRecording.toggle()

        if isRecording {
            if selectedMicrophoneSource == .iPhone {
                audioEngine.startRecording()
            } else {
                connectivityManager.requestRecordingStart()
            }
        } else {
            if selectedMicrophoneSource == .iPhone {
                audioEngine.stopRecording()
            } else {
                connectivityManager.requestRecordingStop()
            }
        }
    }

    private func updateSpectrogramFrames(_ data: SpectrogramData) {
        // Throttle updates to avoid overwhelming the UI
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= updateThrottleInterval else {
            return
        }
        lastUpdateTime = now

        let frame = SpectrogramFrame(magnitudes: data.magnitudes, timestamp: data.timestamp)

        spectrogramFrames.append(frame)

        if spectrogramFrames.count > maxFrames {
            spectrogramFrames.removeFirst()
        }
    }
}

struct SpectrogramCanvasWithAxes: View {
    let frames: [SpectrogramFrame]
    let maxFrames: Int

    let axisWidth: CGFloat = 50
    let axisHeight: CGFloat = 30

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Y-Achse (Frequenz)
                VStack(spacing: 0) {
                    ForEach(0..<5) { i in
                        Spacer()
                        Text(frequencyLabel(index: i))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .frame(width: axisWidth)
                    }
                    Spacer()
                    Text("100 Hz")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .frame(width: axisWidth)
                        .padding(.bottom, axisHeight)
                }

                VStack(spacing: 0) {
                    // Spektrogramm
                    SpectrogramCanvas(frames: frames)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // X-Achse (Zeit)
                    HStack(spacing: 0) {
                        Text(timeLabel(isStart: true))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(timeLabel(isStart: false))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(height: axisHeight)
                }
            }
        }
    }

    private func frequencyLabel(index: Int) -> String {
        // Display range: 100 Hz to 8000 Hz (8 kHz)
        let minFreq = 100.0
        let maxFreq = 8000.0
        
        // index 0 is at the top (highest frequency), index 5 is at the bottom (lowest frequency)
        let freq = maxFreq - (maxFreq - minFreq) * Double(index) / 5.0
        
        if freq >= 1000 {
            return String(format: "%.1f kHz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }

    private func timeLabel(isStart: Bool) -> String {
        guard !frames.isEmpty else { return "Now" }

        // RTL: Now is on the right, old data on the left
        if isStart {
            // Left side: oldest data
            let oldestFrame = frames.first!
            let elapsed = Date().timeIntervalSince(oldestFrame.timestamp)
            return String(format: "-%.0fs", elapsed)
        } else {
            // Right side: current time
            return "Now"
        }
    }
}

struct SpectrogramCanvas: View {
    let frames: [SpectrogramFrame]

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard !frames.isEmpty else { return }
                
                let frameWidth = size.width / CGFloat(frames.count)
                
                // Only display frequencies from 100 Hz to 8000 Hz for better visibility
                let totalBins = frames.first?.magnitudes.count ?? 1
                let sampleRate: Double = 44100.0
                let frequencyPerBin = sampleRate / Double(totalBins * 2)
                
                let minFrequency: Double = 100.0  // 100 Hz
                let maxFrequency: Double = 8000.0 // 8 kHz
                
                let minBin = Int(minFrequency / frequencyPerBin)
                let maxBin = min(Int(maxFrequency / frequencyPerBin), totalBins - 1)
                let displayBins = maxBin - minBin

                for (frameIndex, frame) in frames.enumerated() {
                    let x = CGFloat(frameIndex) * frameWidth

                    for displayIndex in 0..<displayBins {
                        let binIndex = minBin + displayIndex
                        guard binIndex < frame.magnitudes.count else { continue }
                        
                        let magnitude = frame.magnitudes[binIndex]
                        let normalizedMagnitude = magnitude
                        
                        // FIXED: High frequencies at TOP (y=0), low frequencies at BOTTOM (y=size.height)
                        // We need to invert the display so higher bin indices (higher frequencies) appear at the top
                        let y = size.height - (CGFloat(displayIndex + 1) * size.height / CGFloat(displayBins))
                        let height = size.height / CGFloat(displayBins)

                        // Enhanced color mapping for better visibility
                        let color: Color
                        if normalizedMagnitude < 0.05 {
                            // Very low: pure black (noise floor)
                            color = Color.black
                        } else if normalizedMagnitude < 0.2 {
                            // Low: dark blue
                            let t = (Double(normalizedMagnitude) - 0.05) / 0.15
                            color = Color(red: 0, green: 0, blue: 0.3 + t * 0.7)
                        } else if normalizedMagnitude < 0.4 {
                            // Medium-low: blue to cyan
                            let t = (Double(normalizedMagnitude) - 0.2) / 0.2
                            color = Color(red: 0, green: t, blue: 1.0)
                        } else if normalizedMagnitude < 0.6 {
                            // Medium: cyan to green
                            let t = (Double(normalizedMagnitude) - 0.4) / 0.2
                            color = Color(red: 0, green: 1.0, blue: 1.0 - t)
                        } else if normalizedMagnitude < 0.8 {
                            // Medium-high: green to yellow
                            let t = (Double(normalizedMagnitude) - 0.6) / 0.2
                            color = Color(red: t, green: 1.0, blue: 0)
                        } else {
                            // Very high: yellow to red
                            let t = (Double(normalizedMagnitude) - 0.8) / 0.2
                            color = Color(red: 1.0, green: 1.0 - t, blue: 0)
                        }

                        context.fill(
                            Path(CGRect(x: x, y: y, width: frameWidth, height: height)),
                            with: .color(color)
                        )
                    }
                }
            }
        }
    }
}

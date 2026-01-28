import SwiftUI

struct WatchSpectrogramView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @EnvironmentObject var audioEngine: WatchAudioEngine
    @State private var frames: [[Float]] = []
    @State private var zoomLevel: Double = 1.0
    @State private var debugCounter: Int = 0
    @FocusState private var isFocused: Bool
    
    // Konfiguration für Watch-Display
    private let maxFrames = 60    // Optimiert für Watch-Display (ca. 6 Sek)
    private let displayBins = 40  // Ausreichend für kleines Display
    
    // dB Range (angepasst an iOS App für Konsistenz)
    private let minDB: Float = -60.0 // Angepasst: -40.0 war zu hoch für -55dB Signale
    private let maxDB: Float = -10.0 // Zurück auf -10.0 für bessere Helligkeit
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
        ZStack {
            HStack(spacing: 0) {
                // Frequenz-Achse
                VStack(alignment: .trailing) {
                    Text(formatFreq(22050.0 * zoomLevel))
                    Spacer()
                    Text(formatFreq(11025.0 * zoomLevel))
                    Spacer()
                    Text("0")
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.gray)
                .frame(width: 30, alignment: .trailing)
                .padding(.vertical, 4)
                .padding(.trailing, 2)

            // Horizontales Spektrogramm Canvas (Zeit: X-Achse, Frequenz: Y-Achse)
            Canvas { context, size in
                let width = size.width
                let height = size.height
                
                // Jede Spalte ist ein Zeit-Frame (Breite)
                let colWidth = width / CGFloat(maxFrames)
                // Jede Zeile ist ein Frequenz-Bin (Höhe)
                let rowHeight = height / CGFloat(displayBins)
                
                for (i, magnitudes) in frames.enumerated() {
                    // Zeit läuft von links nach rechts
                    // i=0 ist der älteste Frame im Buffer, i=count-1 der neueste
                    let x = CGFloat(i) * colWidth
                    
                    // On-the-fly Downsampling basierend auf Zoom-Level
                    let effectiveCount = Int(Double(magnitudes.count) * zoomLevel)
                    let chunkSize = max(1, effectiveCount / displayBins)
                    
                    for f in 0..<displayBins {
                        let start = f * chunkSize
                        let end = min(start + chunkSize, effectiveCount)
                        // Max-Pooling
                        let mag = (start < end && start < magnitudes.count) ? (magnitudes[start..<min(end, magnitudes.count)].max() ?? minDB) : minDB
                        
                        // dB Normalisierung (-100 bis -10 dB)
                        let normalized = (mag - minDB) / (maxDB - minDB)
                        
                        if normalized > 0.05 { // Noise Gate
                            let color = spectrogramColor(Double(normalized))
                            // Frequenz auf Y-Achse (Tiefe Frequenzen unten)
                            let y = height - CGFloat(f + 1) * rowHeight
                            
                            let rect = CGRect(x: x, y: y, width: colWidth + 0.5, height: rowHeight + 0.5)
                            context.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            }
            .drawingGroup() // Metal-Rendering aktivieren
            .background(Color.black)
            .cornerRadius(4)
            }
            .edgesIgnoringSafeArea(.bottom)
            
            // Status & Steuerung
            VStack {
                Spacer()
                HStack {
                Circle()
                    .fill(connectivityManager.isReachable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Spacer()
                
                // Aufnahme-Steuerung (Lokal auf der Watch)
                Button(action: {
                    print("[WatchView] Play Tapped")
                    audioEngine.startRecording()
                }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                }
                .frame(width: 30, height: 30)
                .background(Color.green.opacity(0.3))
                .clipShape(Circle())
                
                Button(action: {
                    print("[WatchView] Stop Tapped")
                    audioEngine.stopRecording()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                }
                .frame(width: 30, height: 30)
                .background(Color.red.opacity(0.3))
                .clipShape(Circle())
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
            }
        }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .scrollDisabled(true)
            .focusable()
            .focused($isFocused)
            .digitalCrownRotation($zoomLevel, from: 0.1, through: 1.0, by: 0.05, sensitivity: .medium, isContinuous: false)
            .onAppear { isFocused = true }
        }
        // 1. Lokale Daten (Priorität wenn Watch aufnimmt)
        .onReceive(audioEngine.$currentSpectrogramData) { data in
            guard audioEngine.isRecording, let data = data else { return }
            processSpectrogramData(data)
        }
        // 2. Remote Daten (Wenn iPhone aufnimmt)
        .onReceive(connectivityManager.$spectrogramData) { data in
            guard !audioEngine.isRecording, let data = data else { return }
            processSpectrogramData(data)
        }
    }
    
    private func processSpectrogramData(_ data: SpectrogramData) {
            // DEBUG: Log received data on Watch
            debugCounter += 1
            if debugCounter % 60 == 0 {
                let minVal = data.magnitudes.min() ?? 0
                let maxVal = data.magnitudes.max() ?? 0
                let avgVal = data.magnitudes.reduce(0, +) / Float(data.magnitudes.count)
                
                print("[WatchView] Input Range: [\(String(format: "%.1f", minVal)), \(String(format: "%.1f", maxVal))] dB, Avg: \(String(format: "%.1f", avgVal)) dB")
                print("[WatchView] Config minDB: \(minDB), maxDB: \(maxDB)")
                
                // Check Normalisierung
                let normalizedMax = (maxVal - minDB) / (maxDB - minDB)
                print("[WatchView] Norm Max Normalized: \(String(format: "%.2f", normalizedMax)) (Should be < 1.0)")
                
                // Farb-Diagnose
                if normalizedMax <= 0.0 { print("[WatchView] Color: Black (Silence)") }
                else if normalizedMax < 0.3 { print("[WatchView] Color: Dark Blue (Noise Floor)") }
                else if normalizedMax < 0.5 { print("[WatchView] Color: Blue -> Cyan") }
                else { print("[WatchView] Color: Cyan -> Green -> Red") }
            }
            
            // Speichere Rohdaten für dynamischen Zoom
            frames.append(data.magnitudes)
            if frames.count > maxFrames {
                frames.removeFirst()
            }
    }
    
    private func spectrogramColor(_ value: Double) -> Color {
        // Turbo-ähnliche Colormap mit Fade-to-Black für sauberen Hintergrund
        if value <= 0.0 { return .black }
        
        // 0.0 - 0.2: Schwarz -> Dunkelblau (Noise Floor verstecken)
        if value < 0.2 {
            return Color(red: 0, green: 0, blue: value * 2.5)
        }
        // 0.2 - 0.5: Blau -> Cyan
        else if value < 0.5 {
            let t = (value - 0.2) / 0.3
            return Color(red: 0, green: t, blue: 1.0)
        }
        // 0.5 - 1.0: Cyan -> Grün -> Gelb -> Rot
        else {
            // Vereinfachter Verlauf für den Rest
            let t = (value - 0.5) / 0.5
            return Color(red: t, green: 1.0 - t * 0.5, blue: 1.0 - t)
        }
    }
    
    private func formatFreq(_ freq: Double) -> String {
        if freq >= 1000 {
            return String(format: "%.0fk", freq / 1000)
        } else {
            return String(format: "%.0f", freq)
        }
    }
}
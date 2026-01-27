import SwiftUI

/// Modell für einen Bandsperre-Filter
struct BandstopFilter: Identifiable, Codable, Equatable {
    let id: UUID
    var isEnabled: Bool
    var lowFrequency: Float   // Untere Grenzfrequenz (Hz)
    var highFrequency: Float  // Obere Grenzfrequenz (Hz)
    var name: String
    var color: String         // Hex-Farbe für Visualisierung
    
    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        lowFrequency: Float = 50.0,
        highFrequency: Float = 60.0,
        name: String = "Netzbrummen",
        color: String = "#FF6B6B"
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.lowFrequency = lowFrequency
        self.highFrequency = highFrequency
        self.name = name
        self.color = color
    }
    
    var bandwidth: Float {
        highFrequency - lowFrequency
    }
    
    var centerFrequency: Float {
        (lowFrequency + highFrequency) / 2.0
    }
    
    var formattedRange: String {
        if lowFrequency >= 1000 {
            return String(format: "%.1f - %.1f kHz", lowFrequency/1000, highFrequency/1000)
        } else {
            return String(format: "%.0f - %.0f Hz", lowFrequency, highFrequency)
        }
    }
}

// MARK: - Range Slider Component

struct FrequencyRangeSlider: View {
    @Binding var lowValue: Float
    @Binding var highValue: Float
    let range: ClosedRange<Float>
    let useLogScale: Bool
    
    @State private var isDraggingLow = false
    @State private var isDraggingHigh = false
    @State private var isDraggingRange = false
    @State private var dragStartLow: Float = 0
    @State private var dragStartHigh: Float = 0
    
    private let thumbSize: CGFloat = 32
    private let trackHeight: CGFloat = 10
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - thumbSize
            
            ZStack(alignment: .leading) {
                // Background Track - HELLER FÜR BESSERE SICHTBARKEIT
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)
                
                // Selected Range (Bandsperre-Bereich) - DEUTLICH SICHTBAR
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.8), Color.orange.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(4, CGFloat(highPosition(width: width) - lowPosition(width: width))),
                        height: trackHeight
                    )
                    .offset(x: thumbSize / 2 + CGFloat(lowPosition(width: width)))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDraggingRange {
                                    isDraggingRange = true
                                    dragStartLow = lowValue
                                    dragStartHigh = highValue
                                }
                                
                                let deltaPixels = value.translation.width
                                let lowPos = frequencyToPosition(dragStartLow, width: width)
                                let highPos = frequencyToPosition(dragStartHigh, width: width)
                                
                                let newLowPos = lowPos + Float(deltaPixels)
                                let newHighPos = highPos + Float(deltaPixels)
                                
                                if newLowPos >= 0 && newHighPos <= Float(width) {
                                    lowValue = positionToFrequency(newLowPos, width: width)
                                    highValue = positionToFrequency(newHighPos, width: width)
                                }
                            }
                            .onEnded { _ in
                                isDraggingRange = false
                            }
                    )
                
                // Low Frequency Thumb - GRÖßER & BESSER SICHTBAR
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .overlay(
                        Text("L")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .scaleEffect(isDraggingLow ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3), value: isDraggingLow)
                    .offset(x: CGFloat(lowPosition(width: width)))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingLow = true
                                let position = Float(value.location.x)
                                let newValue = positionToFrequency(position, width: width)
                                lowValue = max(range.lowerBound, min(newValue, highValue - 1))
                            }
                            .onEnded { _ in
                                isDraggingLow = false
                            }
                    )
                
                // High Frequency Thumb - GRÖßER & BESSER SICHTBAR
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .overlay(
                        Text("H")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .scaleEffect(isDraggingHigh ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3), value: isDraggingHigh)
                    .offset(x: CGFloat(highPosition(width: width)))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingHigh = true
                                let position = Float(value.location.x)
                                let newValue = positionToFrequency(position, width: width)
                                highValue = max(lowValue + 1, min(newValue, range.upperBound))
                            }
                            .onEnded { _ in
                                isDraggingHigh = false
                            }
                    )
            }
        }
        .frame(height: thumbSize + 16)
    }
    
    // LOGARITHMISCHE SKALIERUNG
    private func frequencyToPosition(_ frequency: Float, width: CGFloat) -> Float {
        if useLogScale {
            let minLog = log10(range.lowerBound)
            let maxLog = log10(range.upperBound)
            let freqLog = log10(max(range.lowerBound, min(range.upperBound, frequency)))
            let normalized = (freqLog - minLog) / (maxLog - minLog)
            return Float(width) * normalized
        } else {
            let normalized = (frequency - range.lowerBound) / (range.upperBound - range.lowerBound)
            return Float(width) * normalized
        }
    }
    
    private func positionToFrequency(_ position: Float, width: CGFloat) -> Float {
        let normalized = position / Float(width)
        
        if useLogScale {
            let minLog = log10(range.lowerBound)
            let maxLog = log10(range.upperBound)
            let freqLog = minLog + normalized * (maxLog - minLog)
            return pow(10, freqLog)
        } else {
            return range.lowerBound + normalized * (range.upperBound - range.lowerBound)
        }
    }
    
    private func lowPosition(width: CGFloat) -> Float {
        frequencyToPosition(lowValue, width: width)
    }
    
    private func highPosition(width: CGFloat) -> Float {
        frequencyToPosition(highValue, width: width)
    }
}

// MARK: - Bandstop Filter Edit View

struct BandstopFilterEditView: View {
    @Binding var filter: BandstopFilter
    let onDelete: () -> Void
    
    @State private var showAdvanced = false
    
    // Preset-Werte für schnelle Auswahl
    private let presets: [(name: String, low: Float, high: Float)] = [
        ("Netzbrummen 50Hz", 48, 52),
        ("Netzbrummen 60Hz", 58, 62),
        ("Oberwellen 100Hz", 98, 102),
        ("Oberwellen 150Hz", 148, 152),
        ("Tiefpass < 100Hz", 20, 100),
        ("Hochpass > 8kHz", 8000, 20000),
        ("Sprachbereich", 300, 3400),
        ("Subwoofer", 20, 80),
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            // Header mit Toggle und Delete
            HStack {
                Toggle(isOn: $filter.isEnabled) {
                    TextField("Name", text: $filter.name)
                        .font(.headline)
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
            
            // Frequenzbereich-Anzeige
            HStack {
                VStack(alignment: .leading) {
                    Text("Untere Grenze")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatFrequency(filter.lowFrequency))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .monospacedDigit()
                }
                
                Spacer()
                
                VStack {
                    Text("Bandbreite")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatFrequency(filter.bandwidth))
                        .font(.caption)
                        .foregroundColor(.orange)
                        .monospacedDigit()
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Obere Grenze")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatFrequency(filter.highFrequency))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                        .monospacedDigit()
                }
            }
            
            // Dual Range Slider mit LOG-SCALE
            FrequencyRangeSlider(
                lowValue: $filter.lowFrequency,
                highValue: $filter.highFrequency,
                range: 20...20000,
                useLogScale: true
            )
            .padding(.vertical, 8)
            
            // Feineinstellung mit Steppern
            HStack(spacing: 20) {
                // Low Frequency Stepper
                HStack {
                    Button(action: { filter.lowFrequency = max(20, filter.lowFrequency - stepSize(for: filter.lowFrequency)) }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: { filter.lowFrequency = min(filter.highFrequency - 1, filter.lowFrequency + stepSize(for: filter.lowFrequency)) }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                // High Frequency Stepper
                HStack {
                    Button(action: { filter.highFrequency = max(filter.lowFrequency + 1, filter.highFrequency - stepSize(for: filter.highFrequency)) }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    
                    Button(action: { filter.highFrequency = min(20000, filter.highFrequency + stepSize(for: filter.highFrequency)) }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Presets
            DisclosureGroup("Schnellauswahl", isExpanded: $showAdvanced) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(presets, id: \.name) { preset in
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                filter.lowFrequency = preset.low
                                filter.highFrequency = preset.high
                                filter.name = preset.name
                            }
                        }) {
                            Text(preset.name)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .opacity(filter.isEnabled ? 1.0 : 0.6)
    }
    
    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.2f kHz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }
    
    private func stepSize(for frequency: Float) -> Float {
        // Logarithmische Schritte: kleiner bei niedrigen Frequenzen
        if frequency < 100 {
            return 1
        } else if frequency < 1000 {
            return 10
        } else if frequency < 10000 {
            return 100
        } else {
            return 500
        }
    }
}

// MARK: - Main Bandstop Filter Settings View

struct BandstopFilterSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var filters: [BandstopFilter]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Info-Header
                    HStack {
                        Image(systemName: "waveform.path.badge.minus")
                            .font(.title2)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading) {
                            Text("Bandsperre-Filter")
                                .font(.headline)
                            Text("Frequenzbereiche von der Analyse ausschließen")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    
                    // Filter Liste
                    ForEach($filters) { $filter in
                        BandstopFilterEditView(
                            filter: $filter,
                            onDelete: {
                                withAnimation {
                                    filters.removeAll { $0.id == filter.id }
                                }
                            }
                        )
                    }
                    
                    // Add Button
                    Button(action: addNewFilter) {
                        Label("Bandsperre hinzufügen", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                    }
                    
                    // Visualisierung
                    if !filters.isEmpty {
                        BandstopVisualizationView(filters: filters.filter { $0.isEnabled })
                            .frame(height: 100)
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Bandsperre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func addNewFilter() {
        let newFilter = BandstopFilter(
            name: "Filter \(filters.count + 1)",
            color: ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7"].randomElement() ?? "#FF6B6B"
        )
        withAnimation {
            filters.append(newFilter)
        }
    }
}

// MARK: - Visualization

struct BandstopVisualizationView: View {
    let filters: [BandstopFilter]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Frequency axis background
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                
                // Bandstop regions
                ForEach(filters) { filter in
                    let startX = logPosition(for: filter.lowFrequency, width: geometry.size.width)
                    let endX = logPosition(for: filter.highFrequency, width: geometry.size.width)
                    
                    Rectangle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: max(2, endX - startX))
                        .position(x: (startX + endX) / 2, y: geometry.size.height / 2)
                    
                    // Label
                    Text(filter.name)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .position(x: (startX + endX) / 2, y: 15)
                }
                
                // Frequency Labels
                ForEach([20, 100, 1000, 10000, 20000], id: \.self) { freq in
                    let x = logPosition(for: Float(freq), width: geometry.size.width)
                    
                    VStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 1, height: geometry.size.height - 20)
                        
                        Text(freq >= 1000 ? "\(freq/1000)k" : "\(freq)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .position(x: x, y: geometry.size.height / 2)
                }
            }
        }
    }
    
    private func logPosition(for frequency: Float, width: CGFloat) -> CGFloat {
        let minLog = log10(20.0)
        let maxLog = log10(20000.0)
        let freqLog = log10(max(20, min(20000, frequency)))
        let normalized = (freqLog - minLog) / (maxLog - minLog)
        return CGFloat(normalized) * width
    }
}

// MARK: - Preview

struct BandstopFilterSettingsView_Previews: PreviewProvider {
    @State static var filters = [
        BandstopFilter(lowFrequency: 48, highFrequency: 52, name: "Netzbrummen 50Hz"),
        BandstopFilter(lowFrequency: 98, highFrequency: 102, name: "Oberwelle 100Hz")
    ]
    
    static var previews: some View {
        BandstopFilterSettingsView(filters: $filters)
    }
}

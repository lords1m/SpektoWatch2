import Foundation

/// Unified model for bandstop filters used across the app
struct BandstopFilter: Identifiable, Codable, Equatable {
    let id: UUID
    var isEnabled: Bool
    var lowFrequency: Float   // Lower cutoff frequency (Hz)
    var highFrequency: Float  // Upper cutoff frequency (Hz)
    var name: String
    var color: String         // Hex color for visualization
    
    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        lowFrequency: Float,
        highFrequency: Float,
        name: String = "Custom Filter",
        color: String = "#FF6B6B"
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.lowFrequency = lowFrequency
        self.highFrequency = highFrequency
        self.name = name
        self.color = color
    }
    
    // MARK: - Computed Properties
    
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
    
    // MARK: - Validation
    
    enum ValidationError: LocalizedError {
        case frequenciesReversed
        case outOfBounds(nyquist: Float)
        case negativeFrequency
        case bandwidthTooNarrow
        
        var errorDescription: String? {
            switch self {
            case .frequenciesReversed:
                return "Untere Frequenz muss kleiner als obere Frequenz sein"
            case .outOfBounds(let nyquist):
                return "Frequenzen müssen zwischen 20 Hz und \(Int(nyquist)) Hz liegen"
            case .negativeFrequency:
                return "Frequenzen dürfen nicht negativ sein"
            case .bandwidthTooNarrow:
                return "Bandbreite muss mindestens 2 Hz betragen"
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .frequenciesReversed:
                return "Tauschen Sie die Werte von unterer und oberer Frequenz"
            case .outOfBounds:
                return "Wählen Sie Frequenzen im hörbaren Bereich"
            case .negativeFrequency:
                return "Verwenden Sie positive Frequenzwerte"
            case .bandwidthTooNarrow:
                return "Erhöhen Sie den Abstand zwischen unterer und oberer Frequenz"
            }
        }
    }
    
    /// Validates the filter against physical and technical limits
    func validate(nyquist: Float = 22050.0) throws {
        // Check 1: Negative frequencies
        guard lowFrequency >= 0, highFrequency >= 0 else {
            throw ValidationError.negativeFrequency
        }
        
        // Check 2: Order
        guard lowFrequency < highFrequency else {
            throw ValidationError.frequenciesReversed
        }
        
        // Check 3: Bandwidth
        guard (highFrequency - lowFrequency) >= 2.0 else {
            throw ValidationError.bandwidthTooNarrow
        }
        
        // Check 4: Range
        guard lowFrequency >= 20.0, highFrequency <= nyquist else {
            throw ValidationError.outOfBounds(nyquist: nyquist)
        }
    }
    
    /// Auto-corrects invalid values
    mutating func autoCorrect(nyquist: Float = 22050.0) {
        // Clamp to positive range
        lowFrequency = max(20.0, lowFrequency)
        highFrequency = max(lowFrequency + 2.0, highFrequency)
        
        // Clamp to Nyquist
        highFrequency = min(nyquist, highFrequency)
        lowFrequency = min(highFrequency - 2.0, lowFrequency)
        
        // If still reversed, swap
        if lowFrequency > highFrequency {
            swap(&lowFrequency, &highFrequency)
        }
    }
}

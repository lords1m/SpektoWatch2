import Foundation
import Combine

/// Konfiguration für die erweiterte FFT-Analyse
/// Ermöglicht Studenten, FFT-Parameter zu ändern und deren Auswirkungen zu beobachten
class FFTConfiguration: ObservableObject {

    // MARK: - Published Properties

    /// Aktuelle Fensterfunktion
    @Published var windowFunction: WindowFunction = .blackmanHarris {
        didSet {
            UserDefaults.standard.set(windowFunction.rawValue, forKey: "fft_windowFunction")
        }
    }

    /// Aktuelle FFT-Blockgröße
    @Published var blockSize: FFTBlockSize = .size2048 {
        didSet {
            UserDefaults.standard.set(blockSize.rawValue, forKey: "fft_blockSize")
        }
    }

    /// Overlap-Prozentsatz (0-87.5%)
    @Published var overlapPercent: Float = 87.5 {
        didSet {
            UserDefaults.standard.set(overlapPercent, forKey: "fft_overlapPercent")
        }
    }

    /// Zeigt Erklärungen im UI an
    @Published var showExplanations: Bool = true {
        didSet {
            UserDefaults.standard.set(showExplanations, forKey: "fft_showExplanations")
        }
    }

    // MARK: - Computed Properties

    /// Frequenzauflösung in Hz
    var frequencyResolution: Float {
        return 44100.0 / Float(blockSize.rawValue)
    }

    /// Zeitauflösung in Millisekunden
    var timeResolutionMs: Float {
        return Float(blockSize.rawValue) / 44100.0 * 1000.0
    }

    /// Hop-Größe basierend auf Overlap
    var hopSize: Int {
        let overlap = min(max(overlapPercent, 0), 87.5) / 100.0
        return max(1, Int(Float(blockSize.rawValue) * (1.0 - overlap)))
    }

    /// Anzahl der Frequenzbins
    var binCount: Int {
        return blockSize.rawValue / 2
    }

    // MARK: - Initialization

    init() {
        loadSavedSettings()
    }

    private func loadSavedSettings() {
        if let windowRaw = UserDefaults.standard.string(forKey: "fft_windowFunction"),
           let window = WindowFunction(rawValue: windowRaw) {
            windowFunction = window
        }

        let blockRaw = UserDefaults.standard.integer(forKey: "fft_blockSize")
        if blockRaw > 0, let block = FFTBlockSize(rawValue: blockRaw) {
            blockSize = block
        }

        if UserDefaults.standard.object(forKey: "fft_overlapPercent") != nil {
            overlapPercent = UserDefaults.standard.float(forKey: "fft_overlapPercent")
        }
        overlapPercent = min(max(overlapPercent, 0), 87.5)

        showExplanations = UserDefaults.standard.object(forKey: "fft_showExplanations") as? Bool ?? true
    }

    // MARK: - Educational Helpers

    /// Heisenberg-Unsicherheit: Produkt aus Zeit- und Frequenzauflösung
    var heisenbergProduct: Float {
        return frequencyResolution * timeResolutionMs
    }

    /// Beschreibung der aktuellen Zeit-Frequenz-Auflösung
    var resolutionDescription: String {
        let freqRes = String(format: "%.1f", frequencyResolution)
        let timeRes = String(format: "%.0f", timeResolutionMs)
        return "Δf = \(freqRes) Hz, Δt = \(timeRes) ms"
    }

}

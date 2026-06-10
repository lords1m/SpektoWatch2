import Foundation
import Combine

/// Konfiguration für die erweiterte FFT-Analyse
/// Ermöglicht Studenten, FFT-Parameter zu ändern und deren Auswirkungen zu beobachten
@MainActor
class FFTConfiguration: ObservableObject {

    // MARK: - Published Properties

    // Keys live in PersistenceKeys.FFT (M13 task-8).

    /// Aktuelle Fensterfunktion
    @Published var windowFunction: WindowFunction = .blackmanHarris {
        didSet {
            UserDefaults.standard.set(windowFunction.rawValue, forKey: PersistenceKeys.FFT.windowFunction)
        }
    }

    /// Aktuelle FFT-Blockgröße
    @Published var blockSize: FFTBlockSize = .size4096 {
        didSet {
            UserDefaults.standard.set(blockSize.rawValue, forKey: PersistenceKeys.FFT.blockSize)
        }
    }

    /// Overlap-Prozentsatz (0–75 %)
    @Published var overlapPercent: Float = 75.0 {
        didSet {
            UserDefaults.standard.set(overlapPercent, forKey: PersistenceKeys.FFT.overlapPercent)
        }
    }

    /// Zeigt Erklärungen im UI an
    @Published var showExplanations: Bool = true {
        didSet {
            UserDefaults.standard.set(showExplanations, forKey: PersistenceKeys.FFT.showExplanations)
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
        let overlap = min(max(overlapPercent, 0), 75.0) / 100.0
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
        let defaults = UserDefaults.standard
        let configVersion = defaults.integer(forKey: PersistenceKeys.FFT.configVersion)
        if configVersion < PersistenceKeys.FFT.currentVersion {
            // v3: bump default block size to 4096 for sharper frequency
            // resolution (≈10.7 Hz/bin vs. 21.5 Hz/bin at 2048).
            defaults.set(FFTBlockSize.size4096.rawValue, forKey: PersistenceKeys.FFT.blockSize)
            defaults.set(PersistenceKeys.FFT.currentVersion, forKey: PersistenceKeys.FFT.configVersion)
        }

        if let windowRaw = defaults.string(forKey: PersistenceKeys.FFT.windowFunction),
           let window = WindowFunction(rawValue: windowRaw) {
            windowFunction = window
        }

        let blockRaw = defaults.integer(forKey: PersistenceKeys.FFT.blockSize)
        if blockRaw > 0, let block = FFTBlockSize(rawValue: blockRaw) {
            blockSize = block
        }

        if defaults.object(forKey: PersistenceKeys.FFT.overlapPercent) != nil {
            overlapPercent = defaults.float(forKey: PersistenceKeys.FFT.overlapPercent)
        }
        overlapPercent = min(max(overlapPercent, 0), 75.0)

        showExplanations = defaults.object(forKey: PersistenceKeys.FFT.showExplanations) as? Bool ?? true
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

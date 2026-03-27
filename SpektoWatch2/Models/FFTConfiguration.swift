import Foundation
import Combine

/// Konfiguration für die erweiterte FFT-Analyse
/// Ermöglicht Studenten, FFT-Parameter zu ändern und deren Auswirkungen zu beobachten
class FFTConfiguration: ObservableObject {

    // MARK: - Published Properties

    /// Aktuelle Fensterfunktion
    @Published var windowFunction: WindowFunction = .hann {
        didSet {
            UserDefaults.standard.set(windowFunction.rawValue, forKey: "fft_windowFunction")
        }
    }

    /// Aktuelle FFT-Blockgröße
    @Published var blockSize: FFTBlockSize = .size4096 {
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

    /// Aktiviert den A/B Vergleichsmodus
    @Published var comparisonModeEnabled: Bool = false

    /// Konfiguration B für Vergleich
    @Published var comparisonWindowFunction: WindowFunction = .rectangular
    @Published var comparisonBlockSize: FFTBlockSize = .size2048

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

    // MARK: - Preset Configurations

    /// Voreinstellungen für verschiedene Anwendungsfälle
    enum Preset: String, CaseIterable, Identifiable {
        case general = "Allgemein"
        case music = "Musik"
        case speech = "Sprache"
        case transient = "Transienten"
        case precision = "Präzision"
        case educational = "Didaktisch"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .general:
                return "Ausgewogene Einstellungen für allgemeine Analyse"
            case .music:
                return "Optimiert für musikalische Inhalte mit guter Frequenzauflösung"
            case .speech:
                return "Optimiert für Sprachanalyse mit schneller Zeitauflösung"
            case .transient:
                return "Für perkussive Sounds und schnelle Änderungen"
            case .precision:
                return "Maximale Frequenzauflösung für stationäre Signale"
            case .educational:
                return "Zeigt spektrale Leckage deutlich (Rectangular Window)"
            }
        }

        var windowFunction: WindowFunction {
            switch self {
            case .general: return .hann
            case .music: return .blackman
            case .speech: return .hamming
            case .transient: return .hann
            case .precision: return .blackmanHarris
            case .educational: return .rectangular
            }
        }

        var blockSize: FFTBlockSize {
            switch self {
            case .general: return .size4096
            case .music: return .size8192
            case .speech: return .size2048
            case .transient: return .size1024
            case .precision: return .size16384
            case .educational: return .size2048
            }
        }

        var overlap: Float {
            switch self {
            case .general: return 87.5
            case .music: return 87.5
            case .speech: return 75.0
            case .transient: return 25.0
            case .precision: return 87.5
            case .educational: return 0.0
            }
        }
    }

    /// Wendet eine Voreinstellung an
    func applyPreset(_ preset: Preset) {
        windowFunction = preset.windowFunction
        blockSize = preset.blockSize
        overlapPercent = preset.overlap
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

    /// Vergleich der Konfigurationen A und B
    var comparisonSummary: String {
        guard comparisonModeEnabled else { return "" }

        let freqA = frequencyResolution
        let freqB = 44100.0 / Float(comparisonBlockSize.rawValue)
        let timeA = timeResolutionMs
        let timeB = Float(comparisonBlockSize.rawValue) / 44100.0 * 1000.0

        return """
        Konfiguration A: \(windowFunction.localizedName), \(blockSize.rawValue) Samples
        Δf = \(String(format: "%.1f", freqA)) Hz, Δt = \(String(format: "%.0f", timeA)) ms
        Seitenlappen: \(Int(windowFunction.sidelobeAttenuation)) dB

        Konfiguration B: \(comparisonWindowFunction.localizedName), \(comparisonBlockSize.rawValue) Samples
        Δf = \(String(format: "%.1f", freqB)) Hz, Δt = \(String(format: "%.0f", timeB)) ms
        Seitenlappen: \(Int(comparisonWindowFunction.sidelobeAttenuation)) dB
        """
    }
}

import Foundation
import Observation

/// Konfiguration für die erweiterte FFT-Analyse
/// Ermöglicht Studenten, FFT-Parameter zu ändern und deren Auswirkungen zu beobachten
@Observable
@MainActor
class FFTConfiguration {

    // MARK: - Observable Properties

    // Keys live in PersistenceKeys.FFT (M13 task-8).

    @ObservationIgnored var onConfigurationChanged: (() -> Void)?
    @ObservationIgnored private var isLoadingSettings = false

    /// Aktuelle Fensterfunktion
    var windowFunction: WindowFunction = .blackmanHarris {
        didSet {
            UserDefaults.standard.set(windowFunction.rawValue, forKey: PersistenceKeys.FFT.windowFunction)
            if !isLoadingSettings { onConfigurationChanged?() }
        }
    }

    /// Aktuelle FFT-Blockgröße
    var blockSize: FFTBlockSize = .size4096 {
        didSet {
            UserDefaults.standard.set(blockSize.rawValue, forKey: PersistenceKeys.FFT.blockSize)
            if !isLoadingSettings { onConfigurationChanged?() }
        }
    }

    /// Overlap-Prozentsatz (0–75 %)
    var overlapPercent: Float = 75.0 {
        didSet {
            UserDefaults.standard.set(overlapPercent, forKey: PersistenceKeys.FFT.overlapPercent)
            if !isLoadingSettings { onConfigurationChanged?() }
        }
    }

    /// Zeigt Erklärungen im UI an
    var showExplanations: Bool = true {
        didSet {
            UserDefaults.standard.set(showExplanations, forKey: PersistenceKeys.FFT.showExplanations)
        }
    }

    /// Opt-in: Live-Hop = Samplerate / Bildwiederholrate, damit pro
    /// Display-Frame genau eine neue Spektrogramm-Spalte entsteht
    /// (z. B. 400 Samples bei 48 kHz / 120 Hz). Überschreibt den
    /// Overlap-basierten Hop nur für die Live-Analyse.
    var matchDisplayRefreshRate: Bool = false {
        didSet {
            UserDefaults.standard.set(matchDisplayRefreshRate, forKey: PersistenceKeys.FFT.matchDisplayRefreshRate)
            if !isLoadingSettings { onConfigurationChanged?() }
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
        Self.hopSize(blockSize: blockSize, overlapPercent: overlapPercent)
    }

    /// Overlap-basierte Hop-Größe als reine Funktion, damit Combine-Sinks
    /// (die vor dem Setzen des neuen Werts feuern) mit den gelieferten
    /// Werten rechnen können statt mit dem alten Property-Stand.
    nonisolated static func hopSize(blockSize: FFTBlockSize, overlapPercent: Float) -> Int {
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
        isLoadingSettings = true
        defer { isLoadingSettings = false }
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
        matchDisplayRefreshRate = defaults.object(forKey: PersistenceKeys.FFT.matchDisplayRefreshRate) as? Bool ?? false
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

// MARK: - Realtime Hop

/// Reine Hop-Arithmetik für die Live-Analyse. Wird sowohl auf dem Main Thread
/// (veröffentlichter Hop, Messdatei-FPS) als auch auf dem Audio-Render-Thread
/// (Frame-Extraktion) aufgerufen — keine Allokation, kein Locking.
enum RealtimeHop {
    /// Minimum live FFT frame rate. Every SwiftUI widget redraws only when a
    /// new frame is published, so a hop above `sampleRate / 30` (e.g. 2048 or
    /// 4096 samples) would leave them below 24 fps. 30 leaves headroom for
    /// main-thread jitter.
    static let minimumFrameRate: Double = 30

    /// Hop, bei dem pro Display-Frame genau ein FFT-Frame entsteht:
    /// 48 kHz → 400 @ 120 Hz / 800 @ 60 Hz; 44,1 kHz → 368 / 735.
    static func displayMatched(sampleRate: Double, displayFPS: Int) -> Int {
        guard sampleRate > 0, displayFPS > 0 else { return 1 }
        return max(1, Int((sampleRate / Double(displayFPS)).rounded()))
    }

    /// Effektiver Live-Hop. `displayMatchedFPS > 0` aktiviert den
    /// displaysynchronen Hop, sonst gilt `configuredHop`. Ergebnis liegt
    /// immer in `1...fftSize` (keine Samples zwischen Fenstern verloren) und
    /// höchstens bei `sampleRate / minimumFrameRate` (≥ 30 Frames/s für die UI).
    static func resolve(configuredHop: Int, displayMatchedFPS: Int, sampleRate: Double, fftSize: Int) -> Int {
        let raw = displayMatchedFPS > 0
            ? displayMatched(sampleRate: sampleRate, displayFPS: displayMatchedFPS)
            : configuredHop
        let maxHopForFrameRate = sampleRate > 0 ? max(1, Int(sampleRate / minimumFrameRate)) : raw
        return min(max(1, raw), max(1, fftSize), maxHopForFrameRate)
    }
}

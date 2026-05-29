import Foundation

/// Single declared inventory of every UserDefaults / AppGroup /
/// @AppStorage key the app reads or writes.
///
/// Why this exists (M13 task-8):
/// - Before this file, key strings were scattered across ~10 sites.
///   Renaming a key meant grepping for the literal; missing a site
///   produced silent migration failures.
/// - Each entry below documents the storage tier, the schema
///   version (if any), and the migration / sunset rule.
/// - Future correctness fixes (key renames, schema bumps) land in
///   one file, not many.
///
/// Coverage as of M13 task-8 Phase 1:
/// - `UserDefaults.standard` keys: dashboard layouts, calibration,
///   spectrogram smoothing knobs, FFT configuration, bandstop
///   filters, legacy watch dashboard config.
/// - `AppGroup.defaults` keys (`ComplicationSharedKeys`): live
///   level + weighting shared with the watch complication.
/// - `@AppStorage("design.*")` design-token keys.
/// - `@AppStorage("dashboard.activePreset")`.
///
/// What's NOT in the registry today:
/// - The `@AppStorage` literals embedded in property wrappers
///   stayed as inline strings — they're already grouped by the
///   `design.*` / `dashboard.*` prefix and migrating to constants
///   requires changing every declaration site. Documented in
///   `task-8-persistence-registry.md` Phase 2.
public enum PersistenceKeys {

    // MARK: - Dashboard

    /// Legacy single-layout snapshot of the active dashboard.
    /// Still written by `DashboardManager.saveConfiguration` for
    /// readers that pre-date the multi-layout storage (notably
    /// `ControlBarView` capturing widget metadata into recordings).
    ///
    /// **Sunset plan**: keep writing through one release cycle after
    /// every reader migrates to `dashboardLayouts`. Audit before
    /// removing: any code path that reads `DashboardConfiguration_v5`
    /// directly must be updated first.
    public static let dashboardLegacySnapshot = "DashboardConfiguration_v5"

    /// Multi-layout JSON (current dashboard storage format).
    public static let dashboardLayouts = "DashboardLayouts_v1"

    /// Active redesign preset id (@AppStorage). Mirrored here so
    /// the string lives in exactly one place; the @AppStorage
    /// declaration in `ModularDashboardView` still uses the literal.
    public static let dashboardActivePreset = "dashboard.activePreset"

    // MARK: - Calibration

    /// Schema marker for the calibration persistence layout.
    /// Bump when `calibrationOffset` changes meaning.
    public static let calibrationVersion = "calibrationVersion"

    /// Last user-set or device-default microphone calibration offset
    /// (dB). Storage: `Float` via `setObject`.
    public static let calibrationOffset = "calibrationOffset"

    public static let calibrationCurrentSchemaVersion = 2

    // MARK: - Spectrogram smoothing knobs

    /// Persistent frequency-axis smoothing intensity (0…1, `Double`).
    public static let spectrogramFrequencySmoothing = "spectrogramFrequencySmoothing"

    /// Persistent temporal smoothing intensity (0…1, `Double`).
    public static let spectrogramTemporalSmoothing = "spectrogramTemporalSmoothing"

    // MARK: - FFT configuration

    public enum FFT {
        public static let configVersion    = "fft_configVersion"
        public static let windowFunction   = "fft_windowFunction"
        public static let blockSize        = "fft_blockSize"
        public static let overlapPercent   = "fft_overlapPercent"
        public static let showExplanations = "fft_showExplanations"

        /// Schema version for the FFT persistence layout.
        public static let currentVersion = 2
    }

    // MARK: - Bandstop filters

    /// JSON-encoded list of user-configured bandstop filters.
    public static let bandstopFilters = "bandstopFilters"

    // MARK: - Watch dashboard config

    /// Watch dashboard configuration. Used for **both** the local
    /// UserDefaults persistence on the watch side and as the
    /// WCSession `applicationContext` payload key. Keeping these in
    /// sync is intentional — they share a single name.
    public static let watchDashboardConfig = "watchDashboardConfig"

    // MARK: - Design tokens (@AppStorage)
    //
    // The DesignTokens / TweaksPanelView / DesignTweaksSections code
    // declares these as @AppStorage("design.*") literals. Mirrored
    // here so the strings appear in this registry; the call sites
    // still embed the literal because @AppStorage requires a
    // StaticString-shaped key argument. Migrating to a single
    // declared constant is Phase 2 of this task.

    public enum Design {
        public static let theme         = "design.theme"
        public static let canvasInLight = "design.canvasInLight"
        public static let accent        = "design.accent"
        public static let density       = "design.density"
        public static let numerals      = "design.numerals"
        public static let colormap      = "design.colormap"
    }

    // MARK: - Tone Generator widget

    public enum ToneGenerator {
        /// Input mode for the tone generator widget ("Hz" or "Piano").
        /// Storage: @AppStorage, `UserDefaults.standard`.
        public static let inputMode     = "toneGenerator.inputMode"

        /// Last active piano octave (0…8).
        /// Storage: @AppStorage, `UserDefaults.standard`.
        public static let pianoOctave   = "toneGenerator.pianoOctave"

        /// MIDI note number of the last piano key tapped (12…119).
        /// -1 means no note selected. Storage: @AppStorage, `UserDefaults.standard`.
        public static let selectedMidi  = "toneGenerator.selectedMidi"

        /// Last-used frequency in Hz (20…20000).
        /// Storage: @AppStorage, `UserDefaults.standard`.
        public static let frequency     = "toneGenerator.frequency"

        /// Last-used amplitude (0.0…1.0).
        /// Storage: @AppStorage, `UserDefaults.standard`.
        public static let amplitude     = "toneGenerator.amplitude"

        /// Last-used waveform rawValue (e.g. "Sinus").
        /// Storage: @AppStorage, `UserDefaults.standard`.
        public static let waveform      = "toneGenerator.waveform"
    }

    // MARK: - AppGroup shared keys (complication ↔ watch app)
    //
    // These live under `AppGroup.defaults`, not `.standard`. Listed
    // here for inventory completeness; the canonical constants live
    // in `Shared/AppGroup.swift` (`ComplicationSharedKeys`) so the
    // complication and watch app share a single import.
    //
    // - `ComplicationSharedKeys.level` ("spw.complication.level")
    // - `ComplicationSharedKeys.weighting` ("spw.complication.weighting")
}

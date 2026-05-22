import Foundation
import OSLog

/// Microphone calibration helper extracted from `AudioEngine`.
///
/// **Scope (M13 task-3, conservative phase 1):** owns the device-model
/// detection, the per-model recommended offset table, and the
/// `UserDefaults` load/save logic. It does NOT own the active
/// `calibrationOffset` value at runtime — `AudioEngine` keeps that as
/// a `@Published var` so existing consumers (the settings slider's
/// `$audioEngine.calibrationOffset` binding, hot-path reads in the
/// frame processor, watch / playback writers) continue to work
/// unchanged.
///
/// Centralising the device map + persistence here:
/// - Makes the recommendation logic unit-testable without spinning
///   up an AudioEngine.
/// - Pulls ~70 LOC of static tables and load/save scaffolding out of
///   the AudioEngine god-object.
/// - Gives later tasks (A14 backlog: AudioEngine protocol abstraction)
///   a clean seam to swap in a mock.
///
/// Persistence keys consumed (will move into the persistence registry
/// in M13 task-8):
/// - `calibrationVersion: Int` — schema marker (current: 2)
/// - `calibrationOffset: Float` — last-applied offset
enum CalibrationProvider {

    /// Fallback used when no per-device entry exists.
    static let defaultOffset: Float = 94.0

    /// Per-device recommended calibration offset (dB).
    /// Sources: Studio Six Digital, Faber Acoustical, in-house tuning.
    /// Identifiers follow Apple's `utsname.machine` convention
    /// (e.g. "iPhone13,1" = iPhone 12 mini).
    private static let deviceCalibrationOffsets: [String: Float] = [
        // iPhone 12 series — more sensitive microphones
        "iPhone13,1": 91.0,  // iPhone 12 mini
        "iPhone13,2": 92.0,  // iPhone 12
        "iPhone13,3": 92.0,  // iPhone 12 Pro
        "iPhone13,4": 92.0,  // iPhone 12 Pro Max

        // iPhone 13 series
        "iPhone14,4": 91.0,  // iPhone 13 mini
        "iPhone14,5": 92.0,  // iPhone 13
        "iPhone14,2": 92.0,  // iPhone 13 Pro
        "iPhone14,3": 92.0,  // iPhone 13 Pro Max

        // iPhone 14 series
        "iPhone14,7": 92.0,  // iPhone 14
        "iPhone14,8": 92.0,  // iPhone 14 Plus
        "iPhone15,2": 93.0,  // iPhone 14 Pro
        "iPhone15,3": 93.0,  // iPhone 14 Pro Max

        // iPhone 15 series
        "iPhone15,4": 93.0,  // iPhone 15
        "iPhone15,5": 93.0,  // iPhone 15 Plus
        "iPhone16,1": 94.0,  // iPhone 15 Pro
        "iPhone16,2": 94.0,  // iPhone 15 Pro Max

        // iPhone 11 series
        "iPhone12,1": 94.0,  // iPhone 11
        "iPhone12,3": 94.0,  // iPhone 11 Pro
        "iPhone12,5": 94.0,  // iPhone 11 Pro Max

        // Older iPhones
        "iPhone11,2": 95.0,  // iPhone XS
        "iPhone11,4": 95.0,  // iPhone XS Max
        "iPhone11,6": 95.0,  // iPhone XS Max (China)
        "iPhone11,8": 95.0,  // iPhone XR
        "iPhone10,1": 96.0,  // iPhone 8
        "iPhone10,4": 96.0,  // iPhone 8
        "iPhone10,2": 96.0,  // iPhone 8 Plus
        "iPhone10,5": 96.0,  // iPhone 8 Plus
    ]

    /// Detects the device model identifier (e.g. "iPhone13,1" for the
    /// iPhone 12 mini). Pure read — safe to call from any thread.
    static func currentDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    /// Recommended calibration offset for the running device.
    static func recommendedOffset() -> Float {
        let model = currentDeviceModel()
        Logger.audioEngine.info("Detected device model: \(model)")
        return deviceCalibrationOffsets[model] ?? defaultOffset
    }

    /// Recommended offset for an arbitrary device identifier — exposed
    /// for unit tests.
    static func recommendedOffset(for model: String) -> Float {
        deviceCalibrationOffsets[model] ?? defaultOffset
    }

    // MARK: - Persistence

    // Keys + schema version centralised in PersistenceKeys (M13
    // task-8). Local aliases keep call sites compact.
    private enum Keys {
        static let version = PersistenceKeys.calibrationVersion
        static let offset = PersistenceKeys.calibrationOffset
    }

    private static let currentSchemaVersion = PersistenceKeys.calibrationCurrentSchemaVersion

    /// Resolves the offset to apply on engine start: prefers the saved
    /// value if its schema version matches; otherwise returns the
    /// device-recommended default and bumps the schema marker.
    /// Caller is responsible for writing the result into AudioEngine's
    /// published storage (which triggers the existing didSet
    /// persistence path).
    static func resolveStartupOffset(defaults: UserDefaults = .standard) -> Float {
        let savedVersion = defaults.integer(forKey: Keys.version)
        if savedVersion >= currentSchemaVersion,
           let savedOffset = defaults.object(forKey: Keys.offset) as? Float {
            Logger.audioEngine.info("Loaded saved calibration offset: \(savedOffset) dB")
            return savedOffset
        }
        let recommended = recommendedOffset()
        defaults.set(currentSchemaVersion, forKey: Keys.version)
        Logger.audioEngine.info("Using device-specific calibration offset: \(recommended) dB for \(currentDeviceModel())")
        return recommended
    }

    /// Writes the offset to UserDefaults. AudioEngine's didSet already
    /// does this — exposed here for tests / non-engine callers.
    static func persist(offset: Float, defaults: UserDefaults = .standard) {
        defaults.set(offset, forKey: Keys.offset)
    }
}

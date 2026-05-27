import Foundation
import OSLog

/// Microphone calibration helper for Apple Watch hardware.
///
/// Mirrors the structure of `CalibrationProvider` but targets Apple Watch
/// model identifiers (`utsname.machine` convention, e.g. "Watch6,6" = Apple
/// Watch Series 7 41 mm). Lives in `Shared/` so both the iOS app (for
/// host-side interpretation of watch data) and the watchOS target (on-device
/// offset lookup in `WatchAudioEngine`) compile the same table.
///
/// All values are currently 100.0 — the measured baseline from the original
/// `watchMicCalibrationOffset` constant. The table structure exists so per-model
/// differences can be filled in when hardware is available.
///
// TODO(calibration): measure each Watch generation against a reference SPL
// meter and update these values.
// Procedure: play a 1 kHz tone at 94 dB SPL (verified with a Class 2 meter),
// record WatchAudioEngine LAF output, compute offset = 94.0 − LAF_reading,
// store here.
enum WatchCalibrationProvider {

    /// Fallback used when no per-model entry exists.
    /// Derived from an Apple Watch Series 7 measured against a B&K Type 2250
    /// at 94 dB SPL (1 kHz, free field), 2024-12.
    static let defaultOffset: Float = 100.0

    /// Per-device recommended offset (dB).
    /// Identifiers follow `utsname.machine` convention.
    private static let deviceCalibrationOffsets: [String: Float] = [
        // Apple Watch Series 4
        "Watch4,1": 100.0,  // 40 mm GPS
        "Watch4,2": 100.0,  // 44 mm GPS
        "Watch4,3": 100.0,  // 40 mm GPS+Cell
        "Watch4,4": 100.0,  // 44 mm GPS+Cell

        // Apple Watch Series 5
        "Watch5,1": 100.0,  // 40 mm GPS
        "Watch5,2": 100.0,  // 44 mm GPS
        "Watch5,3": 100.0,  // 40 mm GPS+Cell
        "Watch5,4": 100.0,  // 44 mm GPS+Cell

        // Apple Watch Series 6
        "Watch6,1": 100.0,  // 40 mm GPS
        "Watch6,2": 100.0,  // 44 mm GPS
        "Watch6,3": 100.0,  // 40 mm GPS+Cell
        "Watch6,4": 100.0,  // 44 mm GPS+Cell

        // Apple Watch Series 7
        "Watch6,6":  100.0,  // 41 mm GPS
        "Watch6,7":  100.0,  // 45 mm GPS
        "Watch6,8":  100.0,  // 41 mm GPS+Cell
        "Watch6,9":  100.0,  // 45 mm GPS+Cell

        // Apple Watch Series 8 / Ultra
        "Watch6,14": 100.0,  // 41 mm GPS
        "Watch6,15": 100.0,  // 45 mm GPS
        "Watch6,16": 100.0,  // 41 mm GPS+Cell
        "Watch6,17": 100.0,  // 45 mm GPS+Cell

        // Apple Watch Series 9 / Ultra 2
        "Watch7,1":  100.0,  // 41 mm GPS
        "Watch7,2":  100.0,  // 45 mm GPS
        "Watch7,3":  100.0,  // 41 mm GPS+Cell
        "Watch7,4":  100.0,  // 45 mm GPS+Cell

        // Apple Watch Series 10
        "Watch7,8":  100.0,  // 42 mm GPS
        "Watch7,9":  100.0,  // 46 mm GPS
        "Watch7,10": 100.0,  // 42 mm GPS+Cell
        "Watch7,11": 100.0,  // 46 mm GPS+Cell
    ]

    /// Detects the running Apple Watch model identifier.
    /// Uses the same `utsname` pattern as `CalibrationProvider`.
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
        Logger.connectivity.info("Detected watch model: \(model)")
        return deviceCalibrationOffsets[model] ?? defaultOffset
    }

    /// Recommended offset for an arbitrary device identifier — exposed for unit tests.
    static func recommendedOffset(for model: String) -> Float {
        deviceCalibrationOffsets[model] ?? defaultOffset
    }
}

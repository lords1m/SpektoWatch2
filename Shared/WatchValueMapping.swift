import Foundation

/// WL-7: shared dB SPL display range for level graphs (watch level meter and
/// the iOS LAF graph defaults). Values are calibrated dB SPL, so a −120…0 dBFS
/// scale flattened every real reading to the top edge.
public enum LevelDisplayRange {
    public static let minDB: Float = 20
    public static let maxDB: Float = 120

    /// 0…1 position of `value` within the range (clamped; non-finite → 0).
    public static func normalized(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return Swift.min(Swift.max((value - minDB) / (maxDB - minDB), 0), 1)
    }
}

/// WL-7: time span covered by a history buffer, taken from the stored frame
/// timestamps instead of an assumed per-frame duration (the watch UI receives
/// ~5 Hz coalesced frames, not one per 46 ms FFT hop).
public enum DisplayTimeWindow {
    public static func seconds(oldest: Date?, newest: Date?) -> Double {
        guard let oldest, let newest else { return 0 }
        return Swift.max(0, newest.timeIntervalSince(oldest))
    }
}

public struct WatchValueMapping {
    public static func value(for type: WatchSingleValueType, data: SpectrogramData) -> Float {
        switch type {
        case .laeq:
            return data.levels["LAeq"] ?? data.broadbandLevel
        case .lceq:
            return data.levels["LCeq"] ?? data.broadbandLevel
        case .lzeq:
            return data.levels["LZeq"] ?? data.broadbandLevel
        case .lafMax:
            return data.levels["LAFmax"] ?? data.levels["LAF"] ?? data.broadbandLevel
        case .lafMin:
            return data.levels["LAFmin"] ?? data.levels["LAF"] ?? data.broadbandLevel
        case .lcfMax:
            return data.levels["LCFmax"] ?? data.levels["LCF"] ?? data.broadbandLevel
        case .lcfMin:
            return data.levels["LCFmin"] ?? data.levels["LCF"] ?? data.broadbandLevel
        }
    }
}

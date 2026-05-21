import Foundation

/// Maps each `DashboardPreset.id` (from `PresetCatalogue.all`) to a
/// concrete widget composition. The compositions are designed to fit
/// the existing 3-column dashboard grid and respect each widget type's
/// `WidgetConfiguration.sizeRange(for:)` constraints — `WidgetConfiguration.init`
/// will clamp anything out of range, but we stay inside the ranges here
/// so the layout matches the redesign mocks.
enum PresetCompositions {

    static func widgets(forPresetID id: String) -> [WidgetConfiguration] {
        switch id {
        case "overview":    return overview()
        case "spectrogram": return [.init(type: .spectrogram, size: WidgetSize(columns: 3, rows: 4))]
        case "waterfall":   return [.init(type: .waterfall,   size: WidgetSize(columns: 3, rows: 4))]
        case "level-time":  return [.init(type: .levelHistory, size: WidgetSize(columns: 3, rows: 3))]
        case "spectrum":    return [.init(type: .frequencyDisplay, size: WidgetSize(columns: 3, rows: 3))]
        case "phase":       return [.init(type: .phaseMeter,  size: WidgetSize(columns: 2, rows: 2))]
        case "level-meter": return [.init(type: .levelMeter,  size: WidgetSize(columns: 2, rows: 3))]
        case "single":      return singleValueGrid()
        case "tone":        return [.init(type: .toneGenerator, size: WidgetSize(columns: 3, rows: 4))]
        case "masking":     return [.init(type: .masking, size: WidgetSize(columns: 3, rows: 3))]
        case "lab":         return [.init(type: .spektralanalyseLab, size: WidgetSize(columns: 3, rows: 4))]
        default:            return overview()
        }
    }

    // MARK: - Compositions

    /// Hero LAF · LAF Verlauf · Spektrogramm Mini · Pegel-Meter
    private static func overview() -> [WidgetConfiguration] {
        [
            .init(
                type: .singleValue,
                size: WidgetSize(columns: 2, rows: 2),
                settings: ["metric": "LAF"]
            ),
            .init(type: .levelMeter,   size: WidgetSize(columns: 1, rows: 2)),
            .init(type: .levelHistory, size: WidgetSize(columns: 3, rows: 2)),
            .init(type: .spectrogram,  size: WidgetSize(columns: 3, rows: 2))
        ]
    }

    /// 2×2 grid of Einzelwert readouts — LAF / LAeq / LCpeak / LAFmin.
    private static func singleValueGrid() -> [WidgetConfiguration] {
        let metrics = ["LAF", "LAeq", "LCpeak", "LAFmin"]
        return metrics.map { metric in
            WidgetConfiguration(
                type: .singleValue,
                size: WidgetSize(columns: 1, rows: 1),
                settings: ["metric": metric]
            )
        }
        // Two 1×1 tiles per row in a 3-col grid leaves a gap; that's
        // acceptable for now — the redesign mock shows a 2×2 cluster.
        // Pull-in to a 2×2 cluster is a follow-up once we have a
        // GridPosition aware composer.
    }
}

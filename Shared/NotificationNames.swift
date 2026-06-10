import Foundation

extension NSNotification.Name {
    static let startRecordingCommand = NSNotification.Name("startRecordingCommand")
    static let stopRecordingCommand = NSNotification.Name("stopRecordingCommand")
    static let gainOrBandwidthChangedNotification = NSNotification.Name("gainOrBandwidthChangedNotification")
    static let watchDashboardConfigChanged = NSNotification.Name("watchDashboardConfigChanged")
    static let watchMeterLayoutConfigChanged = NSNotification.Name("watchMeterLayoutConfigChanged")
    static let watchMeasurementSourcePreferenceChanged = NSNotification.Name("watchMeasurementSourcePreferenceChanged")
    static let spectrogramResolutionChanged = NSNotification.Name("spectrogramResolutionChanged")
    static let spectrogramFrequencyScaleChanged = NSNotification.Name("spectrogramFrequencyScaleChanged")
    static let spectrogramFrequencyRangeChanged = NSNotification.Name("spectrogramFrequencyRangeChanged")
}

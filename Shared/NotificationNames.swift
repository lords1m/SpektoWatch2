import Foundation

extension NSNotification.Name {
    static let startRecordingCommand = NSNotification.Name("startRecordingCommand")
    static let stopRecordingCommand = NSNotification.Name("stopRecordingCommand")
    static let gainOrBandwidthChangedNotification = NSNotification.Name("gainOrBandwidthChangedNotification")
}

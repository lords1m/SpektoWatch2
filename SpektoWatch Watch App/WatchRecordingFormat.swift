import Foundation

enum WatchRecordingFormat {
    static func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1)))
    }

    static func subtitle(for recording: WatchRecordingMetadata) -> String {
        "\(duration(recording.duration)) · \(timestamp(recording.createdAt))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("ddMM HHmm")
        return f
    }()

    static func timestamp(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

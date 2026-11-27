import Foundation

enum AudioAssetKind: String, Codable, Equatable {
    case measurement
    case audioFile
}

struct AudioMeasurementMetadata: Equatable {
    let laeqFast: Float
    let peakLevel: Float
    let minLevel: Float
    let calibrationOffset: Float
    let timeWeighting: String
    let frequencyWeighting: String
    let measurementDataFileName: String?

    fileprivate init(recording: Recording) {
        laeqFast = recording.laeqFast
        peakLevel = recording.peakLevel
        minLevel = recording.minLevel
        calibrationOffset = recording.calibrationOffset
        timeWeighting = recording.timeWeighting
        frequencyWeighting = recording.frequencyWeighting
        measurementDataFileName = recording.measurementDataFileName
    }
}

struct AudioAsset: Identifiable, Equatable {
    enum Origin: Equatable {
        case managedRecording(UUID)
        case externalFile(URL)
    }

    let id: String
    let displayTitle: String
    let fileURL: URL
    let origin: Origin
    let duration: TimeInterval?
    let sampleRate: Double?
    let channelCount: Int?
    let createdAt: Date?
    let measurement: AudioMeasurementMetadata?

    var recordingID: UUID? {
        guard case .managedRecording(let id) = origin else { return nil }
        return id
    }

    var formattedDuration: String? {
        guard let duration else { return nil }
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    init(recording: Recording, fileURL: URL) {
        id = "recording:\(recording.id.uuidString)"
        displayTitle = recording.name
        self.fileURL = fileURL
        origin = .managedRecording(recording.id)
        duration = recording.duration
        sampleRate = recording.sampleRate
        channelCount = recording.channelCount
        createdAt = recording.startDate
        measurement = recording.assetKind == .measurement
            ? AudioMeasurementMetadata(recording: recording)
            : nil
    }

    init(externalFile url: URL) {
        id = "file:\(url.standardizedFileURL.path)"
        displayTitle = url.deletingPathExtension().lastPathComponent
        fileURL = url
        origin = .externalFile(url)
        duration = nil
        sampleRate = nil
        channelCount = nil
        createdAt = nil
        measurement = nil
    }
}

import Foundation
import CoreLocation

/// Modell für eine gespeicherte Messung
struct Recording: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    let startDate: Date
    let duration: TimeInterval
    
    // Audio-Daten
    let audioFileName: String  // Referenz zur .wav/.m4a Datei
    let sampleRate: Double
    let channelCount: Int
    
    // Pegel-Statistiken
    var laeqFast: Float  // LAF Mittelungspegel
    var peakLevel: Float // Maximalpegel
    var minLevel: Float  // Minimalpegel
    
    // Optionale Metadaten
    var location: CLLocationCoordinate2D?
    var photoFileNames: [String]  // Referenzen zu Fotos
    var tags: [String]
    
    // Mess-Konfiguration
    var timeWeighting: String   // "Fast" oder "Slow"
    var frequencyWeighting: String  // "A", "C" oder "Z"
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        startDate: Date,
        duration: TimeInterval,
        audioFileName: String,
        sampleRate: Double = 44100.0,
        channelCount: Int = 1,
        laeqFast: Float = -120.0,
        peakLevel: Float = -120.0,
        minLevel: Float = -120.0,
        location: CLLocationCoordinate2D? = nil,
        photoFileNames: [String] = [],
        tags: [String] = [],
        timeWeighting: String = "Fast",
        frequencyWeighting: String = "A"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.startDate = startDate
        self.duration = duration
        self.audioFileName = audioFileName
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.laeqFast = laeqFast
        self.peakLevel = peakLevel
        self.minLevel = minLevel
        self.location = location
        self.photoFileNames = photoFileNames
        self.tags = tags
        self.timeWeighting = timeWeighting
        self.frequencyWeighting = frequencyWeighting
    }
    
    /// Formatierte Anzeige der Dauer
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Formatiertes Datum
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: startDate)
    }
}

// MARK: - CLLocationCoordinate2D Codable Extension
extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
        let longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
}

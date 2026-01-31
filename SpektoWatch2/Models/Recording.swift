import Foundation
import CoreLocation

/// Wrapper für CLLocationCoordinate2D um Codable zu unterstützen
struct CodableCoordinate: Codable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    
    init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.latitude = latitude
        self.longitude = longitude
    }
    
    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

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
    private var _location: CodableCoordinate?
    var photoFileNames: [String]  // Referenzen zu Fotos
    var tags: [String]
    
    // Mess-Konfiguration
    var timeWeighting: String   // "Fast" oder "Slow"
    var frequencyWeighting: String  // "A", "C" oder "Z"
    
    // Computed property für location
    var location: CLLocationCoordinate2D? {
        get { _location?.coordinate }
        set { _location = newValue.map { CodableCoordinate($0) } }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case startDate
        case duration
        case audioFileName
        case sampleRate
        case channelCount
        case laeqFast
        case peakLevel
        case minLevel
        case _location = "location"
        case photoFileNames
        case tags
        case timeWeighting
        case frequencyWeighting
    }
    
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
        self._location = location.map { CodableCoordinate($0) }
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

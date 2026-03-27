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
    var audioFileName: String  // Referenz zur .wav/.m4a Datei
    var measurementDataFileName: String?  // Referenz zur .spekto Datei
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
    var widgetConfigurations: Data?  // JSON-Snapshot der Dashboard-Widgets
    var markers: [MeasurementMarker]?  // Benutzer-Marker
    var calibrationOffset: Float
    var fftBlockSize: Int
    
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
        case measurementDataFileName
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
        case widgetConfigurations
        case markers
        case calibrationOffset
        case fftBlockSize
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        startDate: Date,
        duration: TimeInterval,
        audioFileName: String,
        measurementDataFileName: String? = nil,
        sampleRate: Double = 44100.0,
        channelCount: Int = 1,
        laeqFast: Float = -120.0,
        peakLevel: Float = -120.0,
        minLevel: Float = -120.0,
        location: CLLocationCoordinate2D? = nil,
        photoFileNames: [String] = [],
        tags: [String] = [],
        timeWeighting: String = "Fast",
        frequencyWeighting: String = "A",
        widgetConfigurations: Data? = nil,
        markers: [MeasurementMarker]? = nil,
        calibrationOffset: Float = 94.0,
        fftBlockSize: Int = 4096
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.startDate = startDate
        self.duration = duration
        self.audioFileName = audioFileName
        self.measurementDataFileName = measurementDataFileName
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
        self.widgetConfigurations = widgetConfigurations
        self.markers = markers
        self.calibrationOffset = calibrationOffset
        self.fftBlockSize = fftBlockSize
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

    /// Datei-Titel für Listenansicht
    var title: String {
        name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Aufnahme"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate) ?? Date()
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName) ?? ""
        measurementDataFileName = try container.decodeIfPresent(String.self, forKey: .measurementDataFileName)
        sampleRate = try container.decodeIfPresent(Double.self, forKey: .sampleRate) ?? 44100.0
        channelCount = try container.decodeIfPresent(Int.self, forKey: .channelCount) ?? 1
        laeqFast = try container.decodeIfPresent(Float.self, forKey: .laeqFast) ?? -120.0
        peakLevel = try container.decodeIfPresent(Float.self, forKey: .peakLevel) ?? -120.0
        minLevel = try container.decodeIfPresent(Float.self, forKey: .minLevel) ?? -120.0
        _location = try container.decodeIfPresent(CodableCoordinate.self, forKey: ._location)
        photoFileNames = try container.decodeIfPresent([String].self, forKey: .photoFileNames) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        timeWeighting = try container.decodeIfPresent(String.self, forKey: .timeWeighting) ?? "Fast"
        frequencyWeighting = try container.decodeIfPresent(String.self, forKey: .frequencyWeighting) ?? "A"
        widgetConfigurations = try container.decodeIfPresent(Data.self, forKey: .widgetConfigurations)
        markers = try container.decodeIfPresent([MeasurementMarker].self, forKey: .markers)
        calibrationOffset = try container.decodeIfPresent(Float.self, forKey: .calibrationOffset) ?? 94.0
        fftBlockSize = try container.decodeIfPresent(Int.self, forKey: .fftBlockSize) ?? 4096
    }
}

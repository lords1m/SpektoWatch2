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
    /// Peak level in dB SPL stored at recording-stop time.
    ///
    /// **Semantic boundary (2026-05-24 / M15 task-7):**
    /// Recordings stopped *before* this date store the raw broadband sample peak
    /// plus calibration offset (not a C-weighted value, despite the "LCpeak" label
    /// used in CSV/PDF exports). Recordings stopped *on or after* this date store
    /// the IEC 61672 LCpeak: the peak instantaneous amplitude of the C-weighted
    /// FFT spectrum, converted to dB SPL. No migration of old values is performed;
    /// the stored value should be interpreted in light of the recording date.
    var peakLevel: Float
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
    
    /// Formatierte Anzeige der Dauer. Stellt sich bei langen Sessions auf
    /// Stunden um (1:10:00 statt 70:00).
    var formattedDuration: String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Geteilter `DateFormatter` für die Listenanzeige. `DateFormatter` ist
    /// teuer pro Instanz; einmal anlegen reicht.
    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    /// Formatiertes Datum (z.B. „23. Mai 2026, 14:32").
    var formattedDate: String {
        Recording.displayDateFormatter.string(from: startDate)
    }

    /// Datei-Titel für Listenansicht
    var title: String {
        name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `id` is the only required field. Decoding it strictly (instead of
        // silently substituting a fresh UUID when missing) prevents the
        // class of bug where a corrupt or hand-edited metadata file mints
        // a new ID on every reload — breaking `updateRecording`,
        // `deleteRecordings`, and any external reference to the entry.
        // `RecordingManager.loadRecordings` catches per-row decode errors
        // so neighbouring valid entries still load.
        id = try container.decode(UUID.self, forKey: .id)
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

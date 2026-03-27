import Foundation

struct MeasurementMarker: Identifiable, Codable, Hashable {
    var id: UUID
    var time: TimeInterval
    var title: String
    var note: String?

    init(id: UUID = UUID(), time: TimeInterval, title: String, note: String? = nil) {
        self.id = id
        self.time = time
        self.title = title
        self.note = note
    }
}


import Foundation

enum MicrophoneSource: String, CaseIterable, Identifiable {
    case iPhone = "iPhone"
    case appleWatch = "Apple Watch"
    
    var id: String { self.rawValue }
}
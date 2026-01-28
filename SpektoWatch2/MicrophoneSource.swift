import Foundation

public enum MicrophoneSource: String, CaseIterable, Codable {
    case iPhone = "iPhone"
    case appleWatch = "Apple Watch"
    
    public var displayName: String {
        return self.rawValue
    }
}

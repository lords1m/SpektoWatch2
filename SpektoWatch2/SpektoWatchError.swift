import Foundation

enum SpektoWatchError: LocalizedError, Equatable {
    case audioEngineFailure(reason: String)
    case microphonePermissionDenied
    case watchNotReachable
    case metalInitializationFailed
    case filterValidationFailed(reason: String)
    case invalidAudioFormat
    case recordingFailed(reason: String)
    case fileSystemError(reason: String)
    
    var errorDescription: String? {
        switch self {
        case .audioEngineFailure(let reason):
            return "Audio-Engine Fehler: \(reason)"
        case .microphonePermissionDenied:
            return "Mikrofon-Berechtigung verweigert. Bitte in Einstellungen aktivieren."
        case .watchNotReachable:
            return "Apple Watch ist nicht erreichbar. Bitte prüfen Sie die Verbindung."
        case .metalInitializationFailed:
            return "Metal konnte nicht initialisiert werden. GPU-Beschleunigung nicht verfügbar."
        case .filterValidationFailed(let reason):
            return "Filter-Konfiguration ungültig: \(reason)"
        case .invalidAudioFormat:
            return "Ungültiges Audio-Format erkannt."
        case .recordingFailed(let reason):
            return "Aufnahme fehlgeschlagen: \(reason)"
        case .fileSystemError(let reason):
            return "Dateisystem-Fehler: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Öffnen Sie die iOS-Einstellungen > Datenschutz > Mikrofon und aktivieren Sie SpektoWatch."
        case .watchNotReachable:
            return "Stellen Sie sicher, dass die Watch in Reichweite ist und die App dort geöffnet ist."
        case .audioEngineFailure:
            return "Versuchen Sie, die App neu zu starten oder das Audio-Interface neu zu verbinden."
        case .invalidAudioFormat:
            return "Überprüfen Sie die Einstellungen Ihres Audio-Interfaces."
        default:
            return nil
        }
    }
}
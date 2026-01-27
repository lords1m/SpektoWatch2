import Foundation
import Combine

class BandstopFilterManager: ObservableObject {
    static let shared = BandstopFilterManager()
    
    @Published var filters: [BandstopFilter] = []
    
    private let userDefaultsKey = "bandstopFilters"
    
    init() {
        loadFilters()
    }
    
    // MARK: - Filter Operations
    
    func addFilter(_ filter: BandstopFilter) {
        filters.append(filter)
        saveFilters()
    }
    
    func removeFilter(id: UUID) {
        filters.removeAll { $0.id == id }
        saveFilters()
    }
    
    func updateFilter(_ filter: BandstopFilter) {
        if let index = filters.firstIndex(where: { $0.id == filter.id }) {
            filters[index] = filter
            saveFilters()
        }
    }
    
    func toggleFilter(id: UUID) {
        if let index = filters.firstIndex(where: { $0.id == id }) {
            filters[index].isEnabled.toggle()
            saveFilters()
        }
    }
    
    /// Gibt alle aktiven Filter zurück
    var enabledFilters: [BandstopFilter] {
        filters.filter { $0.isEnabled }
    }
    
    /// Prüft ob eine Frequenz von einem aktiven Filter blockiert wird
    func isFrequencyBlocked(_ frequency: Float) -> Bool {
        for filter in enabledFilters {
            if frequency >= filter.lowFrequency && frequency <= filter.highFrequency {
                return true
            }
        }
        return false
    }
    
    /// Gibt den Dämpfungsfaktor für eine Frequenz zurück (0 = blockiert, 1 = unberührt)
    func attenuationFactor(for frequency: Float) -> Float {
        for filter in enabledFilters {
            if frequency >= filter.lowFrequency && frequency <= filter.highFrequency {
                // Sanfte Flanken: Cosine-Taper an den Rändern
                let bandwidth = filter.highFrequency - filter.lowFrequency
                let transitionWidth = min(bandwidth * 0.1, 20.0) // 10% oder max 20 Hz
                
                // Untere Flanke
                if frequency < filter.lowFrequency + transitionWidth {
                    let position = (frequency - filter.lowFrequency) / transitionWidth
                    return (1.0 - cos(position * .pi)) / 2.0 // Smooth fade-in
                }
                // Obere Flanke
                else if frequency > filter.highFrequency - transitionWidth {
                    let position = (filter.highFrequency - frequency) / transitionWidth
                    return (1.0 - cos(position * .pi)) / 2.0 // Smooth fade-out
                }
                // Voll im Sperrbereich
                else {
                    return 0.0
                }
            }
        }
        return 1.0 // Nicht blockiert
    }
    
    // MARK: - Persistence
    
    private func saveFilters() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(filters)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            print("[BandstopFilterManager] Saved \(filters.count) filters")
        } catch {
            print("[BandstopFilterManager] ERROR saving filters: \(error.localizedDescription)")
        }
    }
    
    private func loadFilters() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("[BandstopFilterManager] No saved filters found")
            // Standard-Filter hinzufügen
            loadDefaultFilters()
            return
        }
        
        do {
            let decoder = JSONDecoder()
            filters = try decoder.decode([BandstopFilter].self, from: data)
            print("[BandstopFilterManager] Loaded \(filters.count) filters")
        } catch {
            print("[BandstopFilterManager] ERROR loading filters: \(error.localizedDescription)")
            loadDefaultFilters()
        }
    }
    
    private func loadDefaultFilters() {
        filters = [
            BandstopFilter(
                isEnabled: false,
                lowFrequency: 48,
                highFrequency: 52,
                name: "Netzbrummen 50Hz",
                color: "#FF6B6B"
            )
        ]
        saveFilters()
    }
    
    // MARK: - Presets
    
    func addPreset(_ presetName: String) {
        let preset: BandstopFilter?
        
        switch presetName {
        case "Netzbrummen 50Hz":
            preset = BandstopFilter(lowFrequency: 48, highFrequency: 52, name: presetName, color: "#FF6B6B")
        case "Netzbrummen 60Hz":
            preset = BandstopFilter(lowFrequency: 58, highFrequency: 62, name: presetName, color: "#FF6B6B")
        case "Oberwellen 100Hz":
            preset = BandstopFilter(lowFrequency: 98, highFrequency: 102, name: presetName, color: "#4ECDC4")
        case "Oberwellen 150Hz":
            preset = BandstopFilter(lowFrequency: 148, highFrequency: 152, name: presetName, color: "#4ECDC4")
        default:
            preset = nil
        }
        
        if let filter = preset {
            addFilter(filter)
        }
    }
}

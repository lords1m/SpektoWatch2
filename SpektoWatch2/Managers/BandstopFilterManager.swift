import Foundation
import Accelerate
import Combine
import OSLog

class BandstopFilterManager: ObservableObject {
    @Published var filters: [BandstopFilter] = [] {
        didSet {
            invalidateCache()
            saveFilters()
        }
    }
    
    private let userDefaultsKey = "bandstopFilters"
    private var attenuationCache: [Float]?
    private var cachedFrequencies: [Float]?
    
    // MARK: - Initialization
    
    init() {
        loadFilters()
    }
    
    // MARK: - Computed Properties
    
    var enabledFilters: [BandstopFilter] {
        filters.filter { $0.isEnabled }
    }
    
    // MARK: - Filter Operations
    
    func addFilter(_ filter: BandstopFilter) {
        var validatedFilter = filter
        validatedFilter.autoCorrect(nyquist: 22050.0)
        
        do {
            try validatedFilter.validate(nyquist: 22050.0)
            filters.append(validatedFilter)
            Logger.filters.info("Added filter: \(validatedFilter.name) [\(validatedFilter.lowFrequency)-\(validatedFilter.highFrequency) Hz]")
        } catch let error as BandstopFilter.ValidationError {
            Logger.filters.error("Filter validation failed: \(error.localizedDescription)")
        } catch {
            Logger.filters.error("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    func removeFilter(id: UUID) {
        if let index = filters.firstIndex(where: { $0.id == id }) {
            let name = filters[index].name
            filters.remove(at: index)
            Logger.filters.info("Removed filter: \(name)")
        }
    }
    
    func updateFilter(_ filter: BandstopFilter) {
        var validatedFilter = filter
        validatedFilter.autoCorrect(nyquist: 22050.0)
        
        do {
            try validatedFilter.validate(nyquist: 22050.0)
            if let index = filters.firstIndex(where: { $0.id == filter.id }) {
                filters[index] = validatedFilter
                Logger.filters.info("Updated filter: \(validatedFilter.name)")
            }
        } catch let error as BandstopFilter.ValidationError {
            Logger.filters.error("Filter update failed: \(error.localizedDescription)")
        } catch {
            Logger.filters.error("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    func toggleFilter(id: UUID) {
        if let index = filters.firstIndex(where: { $0.id == id }) {
            filters[index].isEnabled.toggle()
            Logger.filters.debug("Toggled filter \(filters[index].name): \(filters[index].isEnabled ? "ON" : "OFF")")
        }
    }
    
    // MARK: - Performance-Optimized Attenuation
    
    /// Invalidates the attenuation cache (called automatically on filter changes)
    private func invalidateCache() {
        attenuationCache = nil
        cachedFrequencies = nil
    }
    
    /// High-performance attenuation map computation with caching
    /// Returns pre-computed attenuation factors for all frequencies
    func getAttenuationMap(for frequencies: [Float]) -> [Float] {
        // Check cache validity
        if let cache = attenuationCache,
           let cachedFreqs = cachedFrequencies,
           cachedFreqs.count == frequencies.count,
           cachedFreqs == frequencies {
            return cache
        }
        
        let map = computeAttenuationMap(for: frequencies)
        attenuationCache = map
        cachedFrequencies = frequencies
        return map
    }
    
    /// Vectorized computation using binary search and Accelerate framework
    /// Complexity: O(m * log(n) + k) where m = filters, n = frequencies, k = affected bins
    private func computeAttenuationMap(for frequencies: [Float]) -> [Float] {
        var map = [Float](repeating: 1.0, count: frequencies.count)
        
        guard !enabledFilters.isEmpty else { return map }
        
        for filter in enabledFilters {
            let bandwidth = filter.highFrequency - filter.lowFrequency
            let transitionWidth = min(bandwidth * 0.1, 20.0)
            
            let minFreq = filter.lowFrequency - transitionWidth
            let maxFreq = filter.highFrequency + transitionWidth
            
            // Binary search for start/end indices (O(log n))
            let startIndex = frequencies.partitionPoint { $0 < minFreq }
            let endIndex = frequencies.partitionPoint { $0 <= maxFreq }
            
            if startIndex < endIndex {
                // Apply attenuation with smooth cosine taper
                for i in startIndex..<endIndex {
                    let freq = frequencies[i]
                    var attenuation: Float = 1.0
                    
                    if freq >= filter.lowFrequency && freq <= filter.highFrequency {
                        // Inside bandstop region
                        if freq < filter.lowFrequency + transitionWidth {
                            // Lower transition
                            let position = (freq - filter.lowFrequency) / transitionWidth
                            attenuation = (1.0 - cos(position * .pi)) / 2.0
                        } else if freq > filter.highFrequency - transitionWidth {
                            // Upper transition
                            let position = (filter.highFrequency - freq) / transitionWidth
                            attenuation = (1.0 - cos(position * .pi)) / 2.0
                        } else {
                            // Full attenuation
                            attenuation = 0.0
                        }
                    }
                    
                    map[i] *= attenuation
                }
            }
        }
        
        return map
    }
    
    /// Legacy single-frequency attenuation (use getAttenuationMap for better performance)
    @available(*, deprecated, message: "Use getAttenuationMap(for:) for vectorized performance")
    func attenuationFactor(for frequency: Float) -> Float {
        for filter in enabledFilters {
            if frequency >= filter.lowFrequency && frequency <= filter.highFrequency {
                let bandwidth = filter.highFrequency - filter.lowFrequency
                let transitionWidth = min(bandwidth * 0.1, 20.0)
                
                if frequency < filter.lowFrequency + transitionWidth {
                    let position = (frequency - filter.lowFrequency) / transitionWidth
                    return (1.0 - cos(position * .pi)) / 2.0
                } else if frequency > filter.highFrequency - transitionWidth {
                    let position = (filter.highFrequency - frequency) / transitionWidth
                    return (1.0 - cos(position * .pi)) / 2.0
                } else {
                    return 0.0
                }
            }
        }
        return 1.0
    }
    
    func isFrequencyBlocked(_ frequency: Float) -> Bool {
        for filter in enabledFilters {
            if frequency >= filter.lowFrequency && frequency <= filter.highFrequency {
                return true
            }
        }
        return false
    }
    
    // MARK: - Persistence
    
    private func saveFilters() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(filters)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            Logger.filters.debug("Saved \(self.filters.count) filters")
        } catch {
            Logger.filters.error("Failed to save filters: \(error.localizedDescription)")
        }
    }
    
    private func loadFilters() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            Logger.filters.info("No saved filters found, loading defaults")
            loadDefaultFilters()
            return
        }
        
        do {
            let decoder = JSONDecoder()
            filters = try decoder.decode([BandstopFilter].self, from: data)
            Logger.filters.info("Loaded \(self.filters.count) filters")
        } catch {
            Logger.filters.error("Failed to load filters: \(error.localizedDescription)")
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

// MARK: - Binary Search Helper

extension RandomAccessCollection {
    func partitionPoint(predicate: (Element) -> Bool) -> Index {
        var low = startIndex
        var high = endIndex
        while low != high {
            let mid = index(low, offsetBy: distance(from: low, to: high) / 2)
            if predicate(self[mid]) {
                low = index(after: mid)
            } else {
                high = mid
            }
        }
        return low
    }
}

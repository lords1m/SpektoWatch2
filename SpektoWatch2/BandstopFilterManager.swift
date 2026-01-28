import Foundation
import Accelerate
import OSLog

struct BandstopFilter: Identifiable, Equatable {
    let id = UUID()
    var centerFrequency: Float
    var bandwidth: Float
    var attenuationFactor: Float // 0.0 bis 1.0 (1.0 = keine Dämpfung)
    var isEnabled: Bool = true
    
    // Validierung
    var lowFrequency: Float { centerFrequency - bandwidth / 2.0 }
    var highFrequency: Float { centerFrequency + bandwidth / 2.0 }
    
    enum ValidationError: Error {
        case invalidFrequencyRange
        case frequenciesReversed
        case outOfBounds(nyquist: Float)
    }
    
    func validate(nyquist: Float) throws {
        guard lowFrequency < highFrequency else {
            throw ValidationError.frequenciesReversed
        }
        guard lowFrequency >= 20 && highFrequency <= nyquist else {
            throw ValidationError.outOfBounds(nyquist: nyquist)
        }
    }
}

class BandstopFilterManager: ObservableObject {
    
    @Published var filters: [BandstopFilter] = [] {
        didSet {
            invalidateCache()
        }
    }
    
    var enabledFilters: [BandstopFilter] {
        filters.filter { $0.isEnabled }
    }
    
    private var attenuationCache: [Float]?
    
    init() {}
    
    func invalidateCache() {
        attenuationCache = nil
    }
    
    // Legacy-Support (falls benötigt)
    func attenuationFactor(for frequency: Float) -> Float {
        var factor: Float = 1.0
        for filter in enabledFilters {
            if abs(frequency - filter.centerFrequency) <= filter.bandwidth / 2.0 {
                factor *= filter.attenuationFactor
            }
        }
        return factor
    }
    
    func getAttenuationMap(for frequencies: [Float]) -> [Float] {
        // Cache prüfen (Größe muss übereinstimmen)
        if let cache = attenuationCache, cache.count == frequencies.count {
            return cache
        }
        
        let map = computeAttenuationMap(for: frequencies)
        attenuationCache = map
        return map
    }
    
    func computeAttenuationMap(for frequencies: [Float]) -> [Float] {
        var map = [Float](repeating: 1.0, count: frequencies.count)
        
        guard !enabledFilters.isEmpty else { return map }
        
        // Da Frequenzen sortiert sind, können wir binäre Suche verwenden
        for filter in enabledFilters {
            let minFreq = filter.centerFrequency - filter.bandwidth / 2.0
            let maxFreq = filter.centerFrequency + filter.bandwidth / 2.0
            
            // Finde Start- und End-Index effizient (O(log n))
            let startIndex = frequencies.partitionPoint { $0 < minFreq }
            let endIndex = frequencies.partitionPoint { $0 <= maxFreq }
            
            if startIndex < endIndex {
                let count = endIndex - startIndex
                var attenuation = filter.attenuationFactor
                
                // Vectorisierte Multiplikation auf dem Sub-Range (O(k))
                map.withUnsafeMutableBufferPointer { buffer in
                    guard let ptr = buffer.baseAddress?.advanced(by: startIndex) else { return }
                    vDSP_vsmul(ptr, 1, &attenuation, ptr, 1, vDSP_Length(count))
                }
            }
        }
        
        return map
    }
}

// Hilfserweiterung für binäre Suche (Standard in neueren Swift-Versionen, hier zur Sicherheit)
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

// MARK: - Compatibility Wrapper (Temporary)
extension BandstopFilterManager {
    /// Legacy support for Views still using .shared
    /// TODO: Migrate all views to use @EnvironmentObject instead
    static let shared = BandstopFilterManager()
}
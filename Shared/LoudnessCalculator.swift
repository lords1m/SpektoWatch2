//
//  LoudnessCalculator.swift
//  SpektoWatch2
//
//  Lautheit-Rechner basierend auf ISO 226:2003 und ISO 532
//  Konvertierung: dB SPL → Phon → Sone
//

import Foundation
import Combine

class LoudnessCalculator: ObservableObject {
    @Published var result: LoudnessResult?
    
    // MARK: - ISO 226:2003 Equal-Loudness Contour Data
    // Normgerechte Referenzfrequenzen nach ISO 226
    private let isoFrequencies: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500,
        630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000,
        10000, 12500
    ]

    // Normgerechte ISO-226 Kurvenparameter (af, Lu, Tf) je Frequenz
    private let isoAf: [Double] = [
        0.532, 0.506, 0.480, 0.455, 0.432, 0.409, 0.387, 0.367, 0.349, 0.330,
        0.315, 0.301, 0.288, 0.276, 0.267, 0.259, 0.253, 0.250, 0.246, 0.244,
        0.243, 0.243, 0.243, 0.242, 0.242, 0.245, 0.254, 0.271, 0.301
    ]

    private let isoLu: [Double] = [
        -31.6, -27.2, -23.0, -19.1, -15.9, -13.0, -10.3, -8.1, -6.2, -4.5,
        -3.1, -2.0, -1.1, -0.4, 0.0, 0.3, 0.5, 0.0, -2.7, -4.1,
        -1.0, 1.7, 2.5, 1.2, -2.1, -7.1, -11.2, -10.7, -3.1
    ]

    private let isoTf: [Double] = [
        78.5, 68.7, 59.5, 51.1, 44.0, 37.5, 31.5, 26.5, 22.1, 17.9,
        14.4, 11.4, 8.6, 6.2, 4.4, 3.0, 2.2, 2.4, 3.5, 1.7,
        -1.3, -4.2, -6.0, -5.4, -1.5, 6.0, 12.6, 13.9, 12.3
    ]

    // Normgerechte Phon-Stufen, für die Isophonen abgelegt werden
    private let isoPhonLevels: [Double] = Array(stride(from: 0.0, through: 90.0, by: 10.0))

    // Interne Isophonen-Datenbank
    // Format: [Frequenz][Phon-Level] = SPL-Wert
    private lazy var iso226Data: [Double: [Double: Double]] = buildISO226Database()
    
    // MARK: - Public Methods
    
    func calculate(spl: Double, frequency: Double) {
        // 1. Konvertiere dB SPL zu Phon (frequenzabhängig)
        let phon = convertSPLtoPhon(spl: spl, frequency: frequency)
        
        // 2. Konvertiere Phon zu Sone (Stevens' Power Law)
        let sone = convertPhonToSone(phon: phon)
        
        // 3. Berechne SPL für doppelte Lautheit (+10 Phon)
        let doublePhon = phon + 10
        let doubleLoudnessSPL = convertPhonToSPL(phon: doublePhon, frequency: frequency)
        
        // 4. Erstelle Interpretationen
        let phonInterpretation = interpretPhon(phon)
        let soneInterpretation = interpretSone(sone)
        
        result = LoudnessResult(
            inputSPL: spl,
            inputFrequency: frequency,
            phon: phon,
            sone: sone,
            doubleLoudnessSPL: doubleLoudnessSPL,
            phonInterpretation: phonInterpretation,
            soneInterpretation: soneInterpretation
        )
    }

    /// Liefert die vollständige, normgerechte Isophonen-Datenbank (ISO 226).
    /// Struktur: [Frequenz][Phon] = SPL
    func getIsophoneDatabase() -> [Double: [Double: Double]] {
        iso226Data
    }

    /// Liefert eine einzelne Isophone (Phon-Kurve) als sortierte Frequenz/SPL-Paare.
    func getIsophoneContour(phon: Double) -> [(frequency: Double, spl: Double)] {
        let nearestPhon = findNearestPhon(phon)
        return isoFrequencies.compactMap { frequency in
            guard let spl = iso226Data[frequency]?[nearestPhon] else { return nil }
            return (frequency: frequency, spl: spl)
        }
    }
    
    // MARK: - Private Conversion Methods
    
    private func convertSPLtoPhon(spl: Double, frequency: Double) -> Double {
        // Bei 1000 Hz ist SPL = Phon (Referenz)
        if frequency == 1000 {
            return spl
        }
        
        // Approximation mit ISO 226:2003 Daten
        let nearestFreq = findNearestFrequency(frequency)
        
        // Lineare Interpolation zwischen bekannten Phon-Werten
        if let freqData = iso226Data[nearestFreq] {
            return interpolatePhon(spl: spl, freqData: freqData)
        }
        
        // Fallback: Approximation basierend auf allgemeiner Kurvenform
        return approximatePhon(spl: spl, frequency: frequency)
    }
    
    private func convertPhonToSPL(phon: Double, frequency: Double) -> Double {
        // Bei 1000 Hz ist Phon = SPL
        if frequency == 1000 {
            return phon
        }
        
        let nearestFreq = findNearestFrequency(frequency)
        
        if let freqData = iso226Data[nearestFreq] {
            return interpolateSPL(phon: phon, freqData: freqData)
        }
        
        return approximateSPL(phon: phon, frequency: frequency)
    }
    
    private func convertPhonToSone(phon: Double) -> Double {
        let safePhon = max(0.0, phon)

        // Stevens' Power Law: S = 2^((P-40)/10) für P ≥ 40
        if safePhon >= 40 {
            return pow(2.0, (safePhon - 40.0) / 10.0)
        } else {
            // Für Werte unter 40 Phon: modifizierte Formel
            return pow(safePhon / 40.0, 2.642)
        }
    }
    
    // MARK: - Helper Methods
    
    private func findNearestFrequency(_ frequency: Double) -> Double {
        var nearestFreq = iso226Data.keys.first ?? 1000
        var minDiff = abs(frequency - nearestFreq)
        
        for freq in iso226Data.keys {
            let diff = abs(frequency - freq)
            if diff < minDiff {
                minDiff = diff
                nearestFreq = freq
            }
        }
        
        return nearestFreq
    }

    private func findNearestPhon(_ phon: Double) -> Double {
        var nearestPhon = isoPhonLevels.first ?? 40
        var minDiff = abs(phon - nearestPhon)

        for level in isoPhonLevels {
            let diff = abs(phon - level)
            if diff < minDiff {
                minDiff = diff
                nearestPhon = level
            }
        }

        return nearestPhon
    }

    private func buildISO226Database() -> [Double: [Double: Double]] {
        var database: [Double: [Double: Double]] = [:]
        for (index, frequency) in isoFrequencies.enumerated() {
            var contourForFrequency: [Double: Double] = [:]
            for phon in isoPhonLevels {
                contourForFrequency[phon] = iso226SPL(phon: phon, index: index)
            }
            database[frequency] = contourForFrequency
        }
        return database
    }

    private func iso226SPL(phon: Double, index: Int) -> Double {
        let af = isoAf[index]
        let lu = isoLu[index]
        let tf = isoTf[index]

        // ISO 226:2003 Gleichlautstärke-Gleichung
        let term1 = 4.47e-3 * (pow(10.0, 0.025 * phon) - 1.15)
        let term2Base = 0.4 * pow(10.0, ((tf + lu) / 10.0) - 9.0)
        let afValue = term1 + pow(term2Base, af)
        let lp = (10.0 / af) * log10(afValue) - lu + 94.0
        return lp
    }
    
    private func interpolatePhon(spl: Double, freqData: [Double: Double]) -> Double {
        let phonLevels = freqData.keys.sorted()
        
        // Finde die umschließenden Phon-Werte
        for i in 0..<(phonLevels.count - 1) {
            let lowerPhon = phonLevels[i]
            let upperPhon = phonLevels[i + 1]
            let lowerSPL = freqData[lowerPhon]!
            let upperSPL = freqData[upperPhon]!
            
            if spl >= lowerSPL && spl <= upperSPL {
                guard abs(upperSPL - lowerSPL) > 1e-9 else { return lowerPhon }
                let ratio = (spl - lowerSPL) / (upperSPL - lowerSPL)
                return lowerPhon + ratio * (upperPhon - lowerPhon)
            }
        }
        
        // Extrapolation außerhalb des Bereichs
        if spl < freqData[phonLevels.first!]! {
            let firstSPL = freqData[phonLevels.first!]!
            guard abs(firstSPL) > 1e-9 else { return phonLevels.first! }
            return phonLevels.first! * (spl / firstSPL)
        } else {
            let lastSPL = freqData[phonLevels.last!]!
            guard abs(lastSPL) > 1e-9 else { return phonLevels.last! }
            return phonLevels.last! * (spl / lastSPL)
        }
    }
    
    private func interpolateSPL(phon: Double, freqData: [Double: Double]) -> Double {
        let phonLevels = freqData.keys.sorted()
        
        for i in 0..<(phonLevels.count - 1) {
            let lowerPhon = phonLevels[i]
            let upperPhon = phonLevels[i + 1]
            
            if phon >= lowerPhon && phon <= upperPhon {
                let ratio = (phon - lowerPhon) / (upperPhon - lowerPhon)
                let lowerSPL = freqData[lowerPhon]!
                let upperSPL = freqData[upperPhon]!
                return lowerSPL + ratio * (upperSPL - lowerSPL)
            }
        }
        
        if phon < phonLevels.first! {
            let firstPhon = phonLevels.first!
            guard abs(firstPhon) > 1e-9 else { return freqData[firstPhon]! }
            return freqData[firstPhon]! * (phon / firstPhon)
        } else {
            let lastPhon = phonLevels.last!
            guard abs(lastPhon) > 1e-9 else { return freqData[lastPhon]! }
            return freqData[lastPhon]! * (phon / lastPhon)
        }
    }
    
    private func approximatePhon(spl: Double, frequency: Double) -> Double {
        // Vereinfachte Approximation basierend auf Fletcher-Munson-Kurven
        if frequency < 1000 {
            // Tiefe Frequenzen: benötigen höheren SPL für gleiche Lautheit
            let correction = 10 * log10(1000 / frequency)
            return spl - correction
        } else {
            // Hohe Frequenzen: komplexere Korrektur
            let correction = 5 * log10(frequency / 1000)
            return spl - correction
        }
    }
    
    private func approximateSPL(phon: Double, frequency: Double) -> Double {
        if frequency < 1000 {
            let correction = 10 * log10(1000 / frequency)
            return phon + correction
        } else {
            let correction = 5 * log10(frequency / 1000)
            return phon + correction
        }
    }
    
    // MARK: - Interpretation Methods
    
    private func interpretPhon(_ phon: Double) -> String {
        switch phon {
        case 0..<20:
            return "Sehr leise (Blätterrauschen)"
        case 20..<40:
            return "Leise (Flüstern, ruhiges Zimmer)"
        case 40..<60:
            return "Normal (Gespräch, Büro)"
        case 60..<80:
            return "Laut (Straßenverkehr, Staubsauger)"
        case 80..<100:
            return "Sehr laut (Rasenmäher, Motorrad)"
        case 100..<120:
            return "Extrem laut (Presslufthammer, Konzert)"
        default:
            return "Schmerzschwelle (Düsenjet)"
        }
    }
    
    private func interpretSone(_ sone: Double) -> String {
        let referenceText = sone >= 1 ? String(format: "%.1f-fach lauter als 40 Phon", sone) : "Leiser als Referenz (40 Phon)"
        return referenceText
    }
}

// MARK: - Result Model

struct LoudnessResult {
    let inputSPL: Double
    let inputFrequency: Double
    let phon: Double
    let sone: Double
    let doubleLoudnessSPL: Double
    let phonInterpretation: String
    let soneInterpretation: String
}

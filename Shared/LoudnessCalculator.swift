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
    // Vereinfachte Stützpunkte für häufig verwendete Frequenzen
    private let isoFrequencies: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500,
        630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000,
        10000, 12500, 16000, 20000
    ]
    
    // Relative SPL-Werte für verschiedene Phon-Werte bei Referenzfrequenzen
    // Format: [Frequenz][Phon-Level] = SPL-Wert
    private let iso226Data: [Double: [Double: Double]] = [
        1000: [20: 20, 40: 40, 60: 60, 80: 80, 100: 100], // Bei 1kHz: SPL = Phon
        100: [20: 52, 40: 51, 60: 62, 80: 77, 100: 93],
        200: [20: 33, 40: 35, 60: 48, 80: 65, 100: 82],
        500: [20: 15, 40: 23, 60: 42, 80: 62, 100: 82],
        2000: [20: 10, 40: 18, 60: 40, 80: 62, 100: 85],
        4000: [20: 5, 40: 10, 60: 32, 80: 56, 100: 81],
        8000: [20: 9, 40: 13, 60: 35, 80: 61, 100: 88]
    ]
    
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
        // Stevens' Power Law: S = 2^((P-40)/10) für P ≥ 40
        if phon >= 40 {
            return pow(2.0, (phon - 40.0) / 10.0)
        } else {
            // Für Werte unter 40 Phon: modifizierte Formel
            return pow(phon / 40.0, 2.642) * 1.0
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
    
    private func interpolatePhon(spl: Double, freqData: [Double: Double]) -> Double {
        let phonLevels = freqData.keys.sorted()
        
        // Finde die umschließenden Phon-Werte
        for i in 0..<(phonLevels.count - 1) {
            let lowerPhon = phonLevels[i]
            let upperPhon = phonLevels[i + 1]
            let lowerSPL = freqData[lowerPhon]!
            let upperSPL = freqData[upperPhon]!
            
            if spl >= lowerSPL && spl <= upperSPL {
                // Lineare Interpolation
                let ratio = (spl - lowerSPL) / (upperSPL - lowerSPL)
                return lowerPhon + ratio * (upperPhon - lowerPhon)
            }
        }
        
        // Extrapolation außerhalb des Bereichs
        if spl < freqData[phonLevels.first!]! {
            return phonLevels.first! * (spl / freqData[phonLevels.first!]!)
        } else {
            return phonLevels.last! * (spl / freqData[phonLevels.last!]!)
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
            return freqData[phonLevels.first!]! * (phon / phonLevels.first!)
        } else {
            return freqData[phonLevels.last!]! * (phon / phonLevels.last!)
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

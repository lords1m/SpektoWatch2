//
//  LoudnessCalculatorView.swift
//  SpektoWatch2
//
//  Interactive UI für Lautheit-Rechner (ISO 226/532)
//  Zeigt Konvertierung: dB SPL → Phon → Sone
//

import SwiftUI

struct LoudnessCalculatorView: View {
    @StateObject private var calculator = LoudnessCalculator()
    @State private var splInput: String = "60"
    @State private var frequencyInput: String = "1000"
    @State private var showValidationError = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Lautheit-Rechner")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Konvertierung: dB SPL → Phon → Sone")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Eingabefelder
                VStack(alignment: .leading, spacing: 15) {
                    Text("Eingabe")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schalldruckpegel (dB SPL)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("0-130", text: $splInput)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                #endif
                            
                            Text("dB SPL")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Frequenz (Hz)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("20-20000", text: $frequencyInput)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                #endif
                            
                            Text("Hz")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: calculate) {
                        Text("Berechnen")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
                #if os(iOS)
                .background(Color(.systemGray6))
                #else
                .background(Color.gray.opacity(0.2))
                #endif
                .cornerRadius(12)
                
                // Ergebnisse
                if let result = calculator.result {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Ergebnisse")
                            .font(.headline)
                        
                        // Phon-Wert
                        ResultCard(
                            title: "Lautstärkepegel",
                            value: String(format: "%.1f", result.phon),
                            unit: "Phon",
                            description: result.phonInterpretation
                        )
                        
                        // Sone-Wert
                        ResultCard(
                            title: "Wahrgenommene Lautheit",
                            value: String(format: "%.2f", result.sone),
                            unit: "Sone",
                            description: result.soneInterpretation
                        )
                        
                        // Verdopplung
                        ResultCard(
                            title: "Für doppelte Lautheit",
                            value: String(format: "%.1f", result.doubleLoudnessSPL),
                            unit: "dB SPL",
                            description: "Erhöhung um 10 Phon ≈ \(String(format: "%.1f", result.doubleLoudnessSPL - result.inputSPL)) dB"
                        )
                    }
                }
                
                if showValidationError {
                    Text("Ungültige Eingabe! dB SPL: 0-130, Frequenz: 20-20000 Hz")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Info")
                        .font(.headline)
                    
                    Text("• Bei 1000 Hz: dB SPL = Phon (Referenz)")
                    Text("• +10 Phon = Verdopplung der Lautheit")
                    Text("• Basiert auf ISO 226:2003 (Equal-Loudness-Kurven)")
                    Text("• Stevens' Power Law: S = 2^((P-40)/10)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                #if os(iOS)
                .background(Color(.systemGray6))
                #else
                .background(Color.gray.opacity(0.2))
                #endif
                .cornerRadius(12)
            }
            .padding()
        }
    }
    
    private func calculate() {
        guard let spl = Double(splInput),
              let freq = Double(frequencyInput),
              spl >= 0, spl <= 130,
              freq >= 20, freq <= 20000 else {
            showValidationError = true
            calculator.result = nil
            return
        }
        
        showValidationError = false
        calculator.calculate(spl: spl, frequency: freq)
    }
}

struct ResultCard: View {
    let title: String
    let value: String
    let unit: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                
                Text(unit)
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
    }
}

#Preview {
    LoudnessCalculatorView()
}

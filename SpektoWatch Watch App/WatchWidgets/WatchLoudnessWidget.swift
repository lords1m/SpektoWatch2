//
//  WatchLoudnessWidget.swift
//  SpektoWatch Watch App
//
//  Kompaktes Lautheit-Widget für Dashboard
//

import SwiftUI

struct WatchLoudnessWidget: View {
    @StateObject private var calculator = LoudnessCalculator()
    @State private var spl: Double = 60
    @State private var frequency: Double = 1000
    @State private var showingDetail = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.6))
                
                VStack(spacing: 2) {
                    // Phon-Wert (groß)
                    if let result = calculator.result {
                        Text(String(format: "%.0f", result.phon))
                            .font(.system(size: fontSize(for: geometry.size), weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        
                        // Phon Label
                        Text("Phon")
                            .font(.system(size: max(8, geometry.size.height * 0.15)))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        
                        // Sone-Wert (klein)
                        Text(String(format: "%.1f Sone", result.sone))
                            .font(.system(size: max(7, geometry.size.height * 0.12)))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("--")
                            .font(.system(size: fontSize(for: geometry.size), weight: .bold))
                            .foregroundColor(.gray)
                        
                        Text("Phon")
                            .font(.system(size: max(8, geometry.size.height * 0.15)))
                            .foregroundColor(.gray)
                    }
                }
                .padding(2)
            }
            .onTapGesture {
                showingDetail = true
            }
        }
        .sheet(isPresented: $showingDetail) {
            LoudnessCalculatorView()
        }
        .onAppear {
            calculator.calculate(spl: spl, frequency: frequency)
        }
    }
    
    private func fontSize(for size: CGSize) -> CGFloat {
        let minDimension = min(size.width, size.height)
        return max(12, minDimension * 0.45)
    }
}

#Preview {
    WatchLoudnessWidget()
        .frame(width: 80, height: 80)
}

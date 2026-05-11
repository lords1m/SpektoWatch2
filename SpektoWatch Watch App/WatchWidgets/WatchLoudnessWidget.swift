//
//  WatchLoudnessWidget.swift
//  SpektoWatch Watch App
//
//  Kompaktes Lautheit-Widget für Dashboard
//

import SwiftUI

struct WatchLoudnessWidget: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @StateObject private var calculator = LoudnessCalculator()
    @State private var showingDetail = false
    @State private var hasLiveData = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 2) {
                    if hasLiveData, let result = calculator.result {
                        Text(String(format: "%.0f", result.phon))
                            .font(.system(size: fontSize(for: geometry.size), weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)

                        Text(String(format: "%.1f", result.sone))
                            .font(.system(size: max(7, geometry.size.height * 0.14)))
                            .foregroundColor(.secondary.opacity(0.9))
                            .lineLimit(1)
                    } else {
                        Text("--")
                            .font(.system(size: fontSize(for: geometry.size), weight: .bold))
                            .foregroundColor(.secondary.opacity(0.75))
                    }
                }
                .padding(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture {
                showingDetail = true
            }
        }
        .sheet(isPresented: $showingDetail) {
            LoudnessCalculatorView()
        }
        .onReceive(audioEngine.$liveData) { data in
            guard let data else {
                hasLiveData = false
                return
            }

            hasLiveData = true
            calculator.calculate(
                spl: Double(data.broadbandLevel),
                frequency: dominantFrequency(in: data)
            )
        }
    }

    private func fontSize(for size: CGSize) -> CGFloat {
        let minDimension = min(size.width, size.height)
        return max(12, minDimension * 0.45)
    }

    private func dominantFrequency(in data: SpectrogramData) -> Double {
        guard !data.frequencies.isEmpty,
              !data.magnitudes.isEmpty else {
            return 1000
        }

        let count = min(data.frequencies.count, data.magnitudes.count)
        let strongestIndex = data.magnitudes.prefix(count).indices.max { lhs, rhs in
            data.magnitudes[lhs] < data.magnitudes[rhs]
        } ?? 0

        let frequency = data.frequencies[strongestIndex]
        return Double(max(20, min(frequency, 12_500)))
    }
}

#Preview {
    WatchLoudnessWidget()
        .frame(width: 80, height: 80)
}

//
//  WatchLoudnessWidget.swift
//  SpektoWatch Watch App
//
//  Kompaktes Lautheit-Widget für Dashboard
//

import SwiftUI

struct WatchLoudnessWidget: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine
    @State private var showingDetail = false
    @State private var phonValue: Double?
    @State private var soneValue: Double?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 2) {
                    if let phon = phonValue, let sone = soneValue {
                        Text(String(format: "%.0f", phon))
                            .font(.system(size: fontSize(for: geometry.size), weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)

                        Text(String(format: "%.1f", sone))
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
                phonValue = nil
                soneValue = nil
                return
            }
            // PHON and SONE are populated by WatchAudioEngine.performFFT via
            // the static LoudnessCalculator helpers — read directly from levels.
            if let p = data.levels["PHON"], let s = data.levels["SONE"] {
                phonValue = Double(p)
                soneValue = Double(s)
            } else {
                phonValue = nil
                soneValue = nil
            }
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

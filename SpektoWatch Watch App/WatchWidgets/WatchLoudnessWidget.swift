//
//  WatchLoudnessWidget.swift
//  SpektoWatch Watch App
//
//  Kompaktes Lautheit-Widget für Dashboard
//

import SwiftUI

struct WatchLoudnessWidget: View {
    @Environment(WatchAudioEngine.self) private var audioEngine
    @State private var showingDetail = false
    @State private var phonValue: Double?
    @State private var soneValue: Double?

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            GeometryReader { geometry in
                ZStack {
                    VStack(spacing: 2) {
                        if let phon = phonValue, let sone = soneValue {
                            Text(phon, format: .number.precision(.fractionLength(0)))
                                .font(.system(size: fontSize(for: geometry.size), weight: .bold, design: .monospaced))
                                .foregroundStyle(.blue)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)

                            Text(sone, format: .number.precision(.fractionLength(1)))
                                .font(.system(size: max(7, geometry.size.height * 0.14)))
                                .foregroundStyle(.secondary.opacity(0.9))
                                .lineLimit(1)
                        } else {
                            Text("--")
                                .font(.system(size: fontSize(for: geometry.size), weight: .bold))
                                .foregroundStyle(.secondary.opacity(0.75))
                        }
                    }
                    .padding(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            LoudnessCalculatorView()
        }
        .task {
            await ObservationTrackingLoop.observeThrottled(minimumInterval: 0) {
                audioEngine.liveData
            } onUpdate: { data in
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

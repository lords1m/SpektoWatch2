import SwiftUI
import Combine

struct LevelHistoryWidget: View {
    private let audioEngine: AudioEngine
    @ObservedObject private var live: LiveAcousticState
    private let frequencyWeightingPublisher: Published<FrequencyWeighting>.Publisher
    private let timeWeightingPublisher: Published<TimeWeighting>.Publisher
    private let spectrogramDataPublisher: Published<SpectrogramData?>.Publisher
    var settings: [String: String]
    @State private var phonValue: Double?
    @State private var soneValue: Double?
    @State private var engineFrequencyWeighting: String
    @State private var engineTimeWeighting: String

    init(audioEngine: AudioEngine, settings: [String: String]) {
        self.audioEngine = audioEngine
        _live = ObservedObject(initialValue: audioEngine.live)
        self.frequencyWeightingPublisher = audioEngine.$frequencyWeighting
        self.timeWeightingPublisher = audioEngine.$timeWeighting
        self.spectrogramDataPublisher = audioEngine.live.$currentSpectrogramData
        self.settings = settings
        _engineFrequencyWeighting = State(initialValue: audioEngine.frequencyWeighting.rawValue)
        _engineTimeWeighting = State(initialValue: audioEngine.timeWeighting.rawValue)
    }

    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }
    private var resolvedFrequencyWeighting: String {
        if useWidgetOverrides {
            return settings["freqWeighting"] ?? engineFrequencyWeighting
        }
        return engineFrequencyWeighting
    }
    private var resolvedTimeWeighting: String {
        if useWidgetOverrides {
            return settings["timeWeighting"] ?? engineTimeWeighting
        }
        return engineTimeWeighting
    }
    private var selectedHistoryMetric: String {
        if useWidgetOverrides {
            return settings["historyMetric"] ?? WidgetSettings.defaultLevelHistoryMetric
        }
        return WidgetSettings.defaultLevelHistoryMetric
    }
    private var resolvedMetricKey: String {
        if selectedHistoryMetric == WidgetSettings.defaultLevelHistoryMetric {
            return "L\(resolvedFrequencyWeighting)\(resolvedTimeWeighting.prefix(1))"
        }
        return selectedHistoryMetric
    }
    
    var metricLabel: String {
        resolvedMetricKey
    }
    
    @State private var showFullscreen = false

    var body: some View {
        LevelHistoryView(
            audioEngine: audioEngine,
            settings: settings,
            scrollSpeed: .fast,
            isPaused: false
        )
        .cornerRadius(10)
        .overlay(alignment: .topLeading) {
            Text(metricLabel)
                .font(.caption)
                .foregroundColor(.white)
                .padding(4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
                .padding(4)
        }
        .overlay(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 4) {
                // Phon/sone are A-weighted perceptual units; showing them alongside
                // an explicit non-A metric (e.g. LCpeak) would be misleading.
                if let phon = phonValue, let sone = soneValue,
                   selectedHistoryMetric == WidgetSettings.defaultLevelHistoryMetric {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f phon", phon))
                        Text(String(format: "%.2f sone", sone))
                    }
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                }

                Button { showFullscreen = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(4)
        }
        .onReceive(spectrogramDataPublisher) { data in
            guard let data = data else {
                phonValue = nil
                soneValue = nil
                return
            }
            updateLoudness(from: data)
        }
        .onReceive(frequencyWeightingPublisher) { engineFrequencyWeighting = $0.rawValue }
        .onReceive(timeWeightingPublisher) { engineTimeWeighting = $0.rawValue }
        .fullScreenCover(isPresented: $showFullscreen) {
            LevelHistoryFullscreenView(audioEngine: audioEngine, settings: settings)
        }
    }

    private func updateLoudness(from data: SpectrogramData) {
        if let p = data.levels["PHON"], let s = data.levels["SONE"] {
            phonValue = Double(p)
            soneValue = Double(s)
        } else {
            phonValue = nil
            soneValue = nil
        }
    }
}

private struct LevelHistoryFullscreenView: View {
    @Environment(\.dismiss) private var dismiss
    let audioEngine: AudioEngine
    let settings: [String: String]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            LevelHistoryView(
                audioEngine: audioEngine,
                settings: settings,
                scrollSpeed: .fast,
                isPaused: false
            )
            .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(12)
        }
    }
}

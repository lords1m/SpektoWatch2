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

    private var timeSpan: SpectrogramTimeSpan {
        let fallback = WidgetSettings.defaultTimeSpanSeconds
        guard useWidgetOverrides else {
            return SpectrogramTimeSpan(rawValue: fallback) ?? .seconds5
        }
        let raw = Int(settings["timeSpan"] ?? String(fallback)) ?? fallback
        return SpectrogramTimeSpan(rawValue: raw) ?? SpectrogramTimeSpan(rawValue: fallback) ?? .seconds5
    }

    /// Shared rolling buffer so the tile and the fullscreen cover render the
    /// same continuous history rather than each restarting from empty.
    @StateObject private var store = LevelHistoryStore()
    @State private var showFullscreen = false

    var body: some View {
        LevelHistoryView(store: store, settings: settings)
        .innerCanvas(cornerRadius: 0)
        .onAppear { store.configure(timeSpanSeconds: timeSpan.rawValue, scrollSpeed: ScrollSpeed.fast.rawValue) }
        .onChange(of: timeSpan) { _, new in
            store.configure(timeSpanSeconds: new.rawValue, scrollSpeed: ScrollSpeed.fast.rawValue)
        }
        .onChange(of: resolvedMetricKey) { _, _ in store.reset() }
        .overlay(alignment: .topLeading) {
            // Leading inset clears the chart's y-axis gutter (36pt) so the
            // metric badge never collides with the top axis label ("110").
            Text(metricLabel)
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
                .padding(.top, 6)
                .padding(.leading, 40)
        }
        .overlay(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 6) {
                // Phon/sone are A-weighted perceptual units; showing them alongside
                // an explicit non-A metric (e.g. LCpeak) would be misleading.
                // Suppress at/near silence — phon≈0 / sone≈0 are not meaningful
                // loudness readings and rendered as "0.0 phon / 0.00 sone" they
                // read as a broken value rather than "quiet".
                if let phon = phonValue, let sone = soneValue,
                   phon >= 1, sone >= 0.05,
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
            let level = data.levels[resolvedMetricKey] ?? data.broadbandLevel
            store.ingest(level: level, sampleRate: data.sampleRate)
        }
        .onReceive(frequencyWeightingPublisher) { engineFrequencyWeighting = $0.rawValue }
        .onReceive(timeWeightingPublisher) { engineTimeWeighting = $0.rawValue }
        .fullScreenCover(isPresented: $showFullscreen) {
            // Share the SAME store so the level history continues seamlessly —
            // the presenting tile stays mounted and keeps feeding it.
            LevelHistoryFullscreenView(store: store, settings: settings)
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
    @ObservedObject var store: LevelHistoryStore
    let settings: [String: String]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            LevelHistoryView(store: store, settings: settings)
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

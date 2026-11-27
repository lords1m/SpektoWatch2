import SwiftUI

// MARK: - Recordings Home Live Widget

struct RecordingsHomeWidget: View {
    @Environment(AppServices.self) private var services
    @Environment(\.designAccent) private var accent

    @State private var showRecordingsList = false
    @State private var selectedRecording: Recording?

    private var recordings: [Recording] {
        services.recordingManager.recordings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let latest = recordings.first {
                HStack(spacing: 10) {
                    if latest.assetKind == .measurement {
                        Text(latest.laeqFast > -119 ? "\(Int(latest.laeqFast.rounded())) dB" : "— dB")
                            .font(.readout(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: Radius.control).fill(accent.opacity(0.18)))
                    } else {
                        Image(systemName: "waveform")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(latest.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("\(latest.formattedDate) · \(latest.formattedDuration)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button {
                        selectedRecording = latest
                    } label: {
                        Label("Öffnen", systemImage: "play.circle")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: Radius.control).fill(accent.opacity(0.20)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showRecordingsList = true
                    } label: {
                        Label("Alle (\(recordings.count))", systemImage: "list.bullet")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: Radius.control).fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack {
                    Text("Keine Aufnahmen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Liste") {
                        showRecordingsList = true
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showRecordingsList) {
            RecordingsListView()
                .environment(services)
                .polishedSheetChrome()
        }
        .sheet(item: $selectedRecording) { rec in
            NavigationStack {
                RecordingDetailView(recording: rec)
                    .environment(services)
            }
            .polishedSheetChrome()
        }
    }
}

// MARK: - Settings Quick Live Widget

struct SettingsQuickWidget: View {
    var audioEngine: AudioEngine
    @Environment(AppServices.self) private var services
    @Environment(\.designAccent) private var accent

    @State private var showSettings = false
    @State private var selectedSource: MicrophoneSource = .iPhone
    @State private var watchGain: Float = 1.0

    private var activeSourceLabel: String {
        audioEngine.activeMicrophoneSource == .appleWatch ? "Apple Watch" : "iPhone"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(activeSourceLabel, systemImage: audioEngine.activeMicrophoneSource == .appleWatch ? "applewatch" : "iphone")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: "Kal. %+.1f dB", audioEngine.calibrationOffset))
                    .font(.readout(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Picker("Bewertung", selection: Binding(
                    get: { audioEngine.frequencyWeighting },
                    set: { audioEngine.setFrequencyWeighting($0) }
                )) {
                    ForEach(FrequencyWeighting.allCases, id: \.self) { w in
                        Text("dB(\(w.rawValue))").tag(w)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    selectedSource = audioEngine.activeMicrophoneSource ?? .iPhone
                    watchGain = UserDefaults.standard.object(forKey: PersistenceKeys.Watch.gain) as? Float ?? 1.0
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FerriteColor.label)
                        .frame(width: 36, height: 32)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(accent.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Einstellungen öffnen")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            SettingsRootView(
                selectedMicrophoneSource: $selectedSource,
                watchGain: $watchGain,
                audioEngine: audioEngine
            )
            .environment(services)
            .polishedSheetChrome()
        }
    }
}

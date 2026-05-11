import SwiftUI

struct TriggerAcquisitionView: View {

    @ObservedObject var engine: MaskingEngine
    @EnvironmentObject private var profileManager: MaskingProfileManager
    @State private var showPresets = false
    @State private var showProfiles = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Hero: spectrum fills in as captures accumulate
                MaskingSpectrumView(
                    triggerBands: engine.currentTriggerSpectrum?.netBands,
                    suggestion: nil
                )
                .frame(height: 140)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Divider()
                    .opacity(0.12)
                    .padding(.top, 12)

                stateControls
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)

                Spacer(minLength: 0)
            }
            .navigationTitle("Trigger aufnehmen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Bug #4: Reset button — visible during active acquisition only
                ToolbarItem(placement: .topBarLeading) {
                    if case .waitingForTrigger = engine.state {
                        Button("Zurücksetzen") { engine.reset() }
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else if case .calibratingAmbient = engine.state {
                        Button("Zurücksetzen") { engine.reset() }
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else if case .marking = engine.state {
                        Button("Zurücksetzen") { engine.reset() }
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Presets") { showPresets = true }
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showPresets) {
                PresetPickerView(engine: engine)
            }
            .sheet(isPresented: $showProfiles) {
                ProfileListView(engine: engine)
                    .environmentObject(profileManager)
            }
            // Bug #2: Reset mid-acquisition state if the sheet is dismissed unexpectedly
            .onDisappear {
                switch engine.state {
                case .calibratingAmbient, .waitingForTrigger, .marking:
                    engine.reset()
                default:
                    break
                }
            }
        }
    }

    // MARK: – State routing

    @ViewBuilder
    private var stateControls: some View {
        switch engine.state {
        case .idle:
            idleControls
        case .calibratingAmbient(let remaining):
            calibratingControls(remaining: remaining)
        case .waitingForTrigger, .marking:
            markingControls
        case .ready:
            readyPlaceholder
        }
    }

    // MARK: – Idle

    private var idleControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ANALYSE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("Störgeräusch identifizieren")
                    .font(.system(size: 17, weight: .semibold))
            }

            Text("Die App lernt das spektrale Profil des Triggers\nund wählt einen passenden Masker.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Button(action: { engine.startAmbientCalibration() }) {
                    Text("UMGEBUNG KALIBRIEREN")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(action: { engine.skipAmbientCalibration() }) {
                    Text("Ohne Kalibrierung fortfahren")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            // Saved profiles — quick restore
            if !profileManager.profiles.isEmpty {
                Divider().opacity(0.12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("GESPEICHERTE PROFILE")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    ForEach(profileManager.profiles.prefix(3)) { profile in
                        Button(action: { engine.useProfile(profile) }) {
                            HStack {
                                Text(profile.name)
                                    .font(.system(size: 13))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }

                    if profileManager.profiles.count > 3 {
                        Button("Alle anzeigen (\(profileManager.profiles.count))") {
                            showProfiles = true
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: – Calibrating

    private func calibratingControls(remaining: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("KALIBRIERUNG")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(String(format: "%02d", remaining))")
                        .font(.system(size: 40, weight: .thin, design: .monospaced))
                    Text("s")
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Kein Trigger erzeugen. Die App nimmt\ndas Hintergrundgeräusch auf.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Novelty activity bar
            NoveltyBar(score: engine.noveltyScore)

            Button("Überspringen") { engine.skipAmbientCalibration() }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: – Marking

    private var markingControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TAP-TO-MARK")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(engine.captureCount)")
                            .font(.system(size: 40, weight: .thin, design: .monospaced))
                        Text("/ \(engine.minimumCaptures)")
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("KONVERGENZ")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(Int(engine.convergenceScore * 100)) %")
                        .font(.system(size: 20, weight: .thin, design: .monospaced))
                        .foregroundStyle(engine.convergenceScore >= 0.7 ? Color(red: 0.0, green: 0.85, blue: 1.0) : .secondary)
                }
            }

            // The central record button (⏺) in the control bar acts as the mark button.
            HStack(spacing: 10) {
                Image(systemName: engine.state == .marking ? "stop.circle.fill" : "record.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(engine.state == .marking ? .red : Color(red: 0.0, green: 0.85, blue: 1.0))
                    .animation(.easeInOut(duration: 0.15), value: engine.state == .marking)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.state == .marking ? "AUFZEICHNUNG LÄUFT" : "AUFNAHME-BUTTON DRÜCKEN")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(engine.state == .marking ? .red : Color(red: 0.0, green: 0.85, blue: 1.0))
                    Text(engine.state == .marking ? "Erneut drücken wenn Trigger endet" : "Drücken wenn Trigger beginnt")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (engine.state == .marking ? Color.red : Color(red: 0.0, green: 0.85, blue: 1.0))
                    .opacity(0.07)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if engine.captureCount >= 1 {
                Button("Vorschlag berechnen") { engine.computeSuggestionNow() }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: – Ready (Bug #3: informative message instead of dead label)

    private var readyPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.80, blue: 0.30))
                    .frame(width: 6, height: 6)
                Text("VORSCHLAG BEREIT")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.30))
            }
            Text("Masker-Vorschlag wurde berechnet.\nDieses Fenster schließen um ihn anzusehen.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(red: 1.0, green: 0.80, blue: 0.30).opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: – Novelty activity bar

private struct NoveltyBar: View {
    let score: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange.opacity(0.7))
                    .frame(width: geo.size.width * CGFloat(score))
                    .animation(.easeOut(duration: 0.15), value: score)
            }
        }
        .frame(height: 3)
        .overlay(
            HStack {
                Text("AKTIVITÄT")
                Spacer()
            }
            .font(.system(size: 7.5, design: .monospaced))
            .foregroundStyle(.secondary.opacity(0.6))
            .offset(y: -12)
        )
        .padding(.top, 10)
    }
}

// MARK: – Preset picker

struct PresetPickerView: View {
    @ObservedObject var engine: MaskingEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(TriggerPreset.library) { preset in
                Button(action: {
                    engine.usePreset(preset)
                    dismiss()
                }) {
                    HStack {
                        Text(preset.displayName)
                            .font(.system(size: 14))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Trigger-Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

// MARK: – Profile list

struct ProfileListView: View {
    @ObservedObject var engine: MaskingEngine
    @EnvironmentObject private var profileManager: MaskingProfileManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(profileManager.profiles) { profile in
                    Button(action: {
                        engine.useProfile(profile)
                        dismiss()
                    }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .font(.system(size: 14))
                            Text(profile.maskerType.displayName)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    profileManager.delete(offsets: offsets)
                }
            }
            .navigationTitle("Gespeicherte Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }
}

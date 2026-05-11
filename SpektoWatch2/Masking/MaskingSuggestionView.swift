import SwiftUI

struct MaskingSuggestionView: View {

    @ObservedObject var engine: MaskingEngine
    @EnvironmentObject private var profileManager: MaskingProfileManager
    let suggestion: MaskerSuggestion

    @State private var selectedMasker: MaskerType
    @State private var eqBands: [EQBand]
    @State private var volumeDB: Float
    @State private var profileName: String = ""
    @State private var showSaveSheet = false

    @ObservedObject private var preview: MaskingPreviewPlayer

    init(engine: MaskingEngine, suggestion: MaskerSuggestion) {
        self.engine     = engine
        self.suggestion = suggestion
        _selectedMasker = State(initialValue: suggestion.maskerType)
        _eqBands        = State(initialValue: suggestion.eqBands)
        _volumeDB       = State(initialValue: suggestion.volumedBFS)
        self.preview    = engine.previewPlayer
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero
                spectrumHero

                Divider().opacity(0.12)

                VStack(spacing: 24) {
                    maskerSelector
                    eqSection
                    volumeSection
                    previewSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)

                Button(action: { showSaveSheet = true }) {
                    Text("ALS PROFIL SPEICHERN")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Masker-Vorschlag")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { engine.stopPreview() }
        .sheet(isPresented: $showSaveSheet) { saveSheet }
    }

    // MARK: – Hero spectrum

    private var spectrumHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                legendDot(Color(red: 0.0, green: 0.85, blue: 1.0))
                Text("TRIGGER").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                Spacer().frame(width: 10)
                legendDot(Color(red: 1.0, green: 0.80, blue: 0.30))
                Text("MASKER EQ").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                Spacer().frame(width: 10)
                legendDot(Color(white: 0.4))
                Text("MASKER NAT").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("KONFIDENZ \(Int(suggestion.confidenceScore * 100)) %")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            MaskingSpectrumView(
                triggerBands: engine.currentTriggerSpectrum?.netBands,
                suggestion: currentSuggestion
            )
            .frame(height: 160)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func legendDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 6, height: 6)
    }

    // MARK: – Masker selector

    private var maskerSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("MASKER-TEXTUR")

            HStack(spacing: 0) {
                ForEach(Array(MaskerType.allCases.enumerated()), id: \.offset) { idx, masker in
                    Button(action: {
                        selectedMasker = masker
                        if preview.isPlaying { restartPreview() }
                    }) {
                        VStack(spacing: 3) {
                            Text(maskerCode(masker))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            Text(masker.displayName)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(masker == selectedMasker ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            masker == selectedMasker
                                ? Color.white.opacity(0.08)
                                : Color.clear
                        )
                    }
                    .buttonStyle(.plain)

                    if idx < MaskerType.allCases.count - 1 {
                        Divider().frame(height: 28)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if suggestion.maskerType == selectedMasker {
                Text("↑ EMPFOHLEN")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
            }
        }
    }

    private func maskerCode(_ masker: MaskerType) -> String {
        switch masker {
        case .pinkNoise:  return "PINK"
        case .brownNoise: return "BRN"
        case .whiteNoise: return "WHT"
        case .rain:       return "RAIN"
        }
    }

    // MARK: – EQ

    private var eqSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("EQ-KORREKTUR")

            VStack(spacing: 12) {
                ForEach(Array(eqBands.enumerated()), id: \.offset) { idx, band in
                    InstrumentEQRow(band: band) { newGain in
                        eqBands[idx].gainDB = newGain
                        engine.previewPlayer.updateEQ(bands: eqBands)
                    }
                }
            }
        }
    }

    // MARK: – Volume

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("PEGEL")
                Spacer()
                Text(String(format: "%.0f dBFS", volumeDB))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(value: $volumeDB, in: -40...(-10), step: 1) { _ in
                engine.previewPlayer.volumeDB = volumeDB
            }
            .tint(Color(red: 1.0, green: 0.80, blue: 0.30))
        }
    }

    // MARK: – Preview

    private var previewSection: some View {
        Button(action: togglePreview) {
            HStack(spacing: 8) {
                Circle()
                    .fill(preview.isPlaying ? Color.green : Color.accentColor)
                    .frame(width: 8, height: 8)
                Text(preview.isPlaying ? "STOP" : "VORSCHAU")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(preview.isPlaying ? Color(white: 0.2) : Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: – Save sheet

    private var saveSheet: some View {
        NavigationStack {
            Form {
                Section("Profilname") {
                    TextField("z. B. Büro – Tastatur", text: $profileName)
                        .font(.system(size: 14, design: .monospaced))
                }
                Section {
                    Button("Speichern") {
                        saveProfile()
                        showSaveSheet = false
                    }
                    .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Profil speichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { showSaveSheet = false }
                }
            }
        }
    }

    // MARK: – Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    private var currentSuggestion: MaskerSuggestion {
        MaskerSuggestion(maskerType: selectedMasker,
                         eqBands: eqBands,
                         volumedBFS: volumeDB,
                         confidenceScore: suggestion.confidenceScore)
    }

    private func togglePreview() {
        if preview.isPlaying {
            engine.stopPreview()
        } else {
            engine.startPreview(suggestion: currentSuggestion)
        }
    }

    private func restartPreview() {
        guard preview.isPlaying else { return }
        engine.stopPreview()
        engine.startPreview(suggestion: currentSuggestion)
    }

    private func saveProfile() {
        guard let spectrum = engine.currentTriggerSpectrum else { return }
        let profile = currentSuggestion.toProfile(name: profileName, triggerSpectrum: spectrum)
        profileManager.save(profile)
    }
}

// MARK: – Instrument EQ row

private struct InstrumentEQRow: View {
    let band: EQBand
    let onGainChanged: (Float) -> Void

    @State private var gain: Float

    init(band: EQBand, onGainChanged: @escaping (Float) -> Void) {
        self.band = band
        self.onGainChanged = onGainChanged
        _gain = State(initialValue: band.gainDB)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(bandCode)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)

            Text("\(Int(band.frequency)) Hz")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Slider(value: $gain, in: -12...12, step: 0.5) { _ in
                onGainChanged(gain)
            }
            .tint(gainColor)

            Text(String(format: "%+.1f", gain))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(gainColor)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var bandCode: String {
        switch band.type {
        case .lowShelf:  return "LOW"
        case .peak:      return "MID"
        case .highShelf: return "HIGH"
        }
    }

    private var gainColor: Color {
        if gain > 1  { return Color(red: 1.0, green: 0.80, blue: 0.30) }
        if gain < -1 { return Color(red: 0.0, green: 0.85, blue: 1.0) }
        return .secondary
    }
}

import SwiftUI

// Dashboard widget entry point for the masking feature.
// Precision readout style (Spektralgrund): mini spectrum as hero,
// monospaced state label, no prose.
struct MaskingEntryWidget: View {

    var engine: MaskingEngine
    @Environment(AppServices.self) private var services
    @State private var showSheet = false
    @State private var showProfiles = false
    @State private var showResetConfirmation = false

    var body: some View {
        Button(action: { showSheet = true }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(alignment: .center) {
                    Text("MASKING")
                        .font(.readout(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    stateIndicator
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                // Mini spectrum (always rendered; dim grid until data arrives)
                MaskingSpectrumView(
                    triggerBands: engine.currentTriggerSpectrum?.netBands,
                    suggestion: activeSuggestion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                // Footer readout
                HStack {
                    stateReadout
                    Spacer()
                    if engine.previewPlayer.isPlaying {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(FerriteStatus.live)
                                .frame(width: 6, height: 6)
                            Text("AKTIV")
                                .font(.readout(size: 8, weight: .semibold))
                                .foregroundStyle(FerriteColor.label)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .innerCanvas(cornerRadius: 0)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("maskingWidget")
        .sheet(isPresented: $showSheet) {
            acquisitionOrSuggestionSheet
        }
        .confirmationDialog(
            "Kalibrierung verwerfen?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Neu aufnehmen", role: .destructive) {
                engine.reset()
                showSheet = false
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die aktuelle Kalibrierung und alle Aufnahmen gehen verloren.")
        }
    }

    // MARK: – State indicator dot

    private var stateIndicator: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
            .animation(.easeInOut(duration: 0.4), value: engine.previewPlayer.isPlaying)
    }

    private var dotColor: Color {
        if engine.previewPlayer.isPlaying { return FerriteStatus.live }
        switch engine.state {
        case .idle:                        return FerriteColor.labelTertiary.opacity(0.45)
        case .calibratingAmbient:          return FerriteStatus.warning
        case .waitingForTrigger, .marking: return FerriteStatus.info
        case .ready:                       return FerriteStatus.warning
        }
    }

    // MARK: – Footer state readout (monospaced)

    private var stateReadout: some View {
        Group {
            switch engine.state {
            case .idle:
                Text("IDLE · TIPPEN")
                    .foregroundStyle(.secondary)
            case .calibratingAmbient(let r):
                Text("KAL \(String(format: "%02d", r))s")
                    .foregroundStyle(.secondary)
            case .waitingForTrigger:
                Text("\(engine.captureCount)/\(engine.minimumCaptures) CAP")
                    .foregroundStyle(.secondary)
            case .marking:
                Text("REC ●")
                    .foregroundStyle(.primary)
            case .ready(let sug):
                Text("\(maskerCode(sug.maskerType)) \(Int(sug.confidenceScore * 100))%")
                    .foregroundStyle(.primary)
            }
        }
        .font(.readout(size: 9, weight: .medium))
    }

    private func maskerCode(_ type: MaskerType) -> String {
        switch type {
        case .pinkNoise:  return "PINK"
        case .brownNoise: return "BRN"
        case .whiteNoise: return "WHT"
        case .rain:       return "RAIN"
        }
    }

    // MARK: – Active suggestion (for spectrum overlay)

    private var activeSuggestion: MaskerSuggestion? {
        if case .ready(let sug) = engine.state { return sug }
        return nil
    }

    // MARK: – Sheet routing

    @ViewBuilder
    private var acquisitionOrSuggestionSheet: some View {
        if case .ready(let suggestion) = engine.state {
            NavigationStack {
                MaskingSuggestionView(engine: engine, suggestion: suggestion)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Neu aufnehmen", role: .destructive) {
                                showResetConfirmation = true
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            if !services.maskingProfileManager.profiles.isEmpty {
                                Button("Profile") { showProfiles = true }
                                    .font(.readout(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
            .sheet(isPresented: $showProfiles) {
                ProfileListView(engine: engine)
                    .environment(services)
            }
        } else {
            TriggerAcquisitionView(engine: engine)
        }
    }
}

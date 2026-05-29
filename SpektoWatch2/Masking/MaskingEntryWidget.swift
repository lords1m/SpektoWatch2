import SwiftUI

// Dashboard widget entry point for the masking feature.
// Precision readout style (Spektralgrund): mini spectrum as hero,
// monospaced state label, no prose.
struct MaskingEntryWidget: View {

    @ObservedObject var engine: MaskingEngine
    @EnvironmentObject private var profileManager: MaskingProfileManager
    @State private var showSheet = false
    @State private var showProfiles = false
    @State private var showResetConfirmation = false

    var body: some View {
        Button(action: { showSheet = true }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(alignment: .center) {
                    Text("MASKING")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
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
                        Text("▶ AKTIV")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        if engine.previewPlayer.isPlaying { return .green }
        switch engine.state {
        case .idle:                        return Color.white.opacity(0.2)
        case .calibratingAmbient:          return .orange
        case .waitingForTrigger, .marking: return Color(red: 0.0, green: 0.85, blue: 1.0)
        case .ready:                       return Color(red: 1.0, green: 0.80, blue: 0.30)
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
                    .foregroundStyle(.orange)
            case .waitingForTrigger:
                Text("\(engine.captureCount)/\(engine.minimumCaptures) CAP")
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
            case .marking:
                Text("REC ●")
                    .foregroundStyle(Color.accentColor)
            case .ready(let sug):
                Text("\(maskerCode(sug.maskerType)) \(Int(sug.confidenceScore * 100))%")
                    .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.30))
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                            if !profileManager.profiles.isEmpty {
                                Button("Profile") { showProfiles = true }
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
            .sheet(isPresented: $showProfiles) {
                ProfileListView(engine: engine)
                    .environmentObject(profileManager)
            }
        } else {
            TriggerAcquisitionView(engine: engine)
        }
    }
}

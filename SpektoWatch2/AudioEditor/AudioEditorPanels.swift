import SwiftUI

enum AudioEditorToolTab: String, CaseIterable, Identifiable {
    case time = "Zeit"
    case eq = "EQ"
    case filter = "Filter"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .time:   return "scissors"
        case .eq:     return "slider.vertical.3"
        case .filter: return "waveform.badge.magnifyingglass"
        }
    }
}

// MARK: - Thumb-Zone Transport Bar

struct AudioEditorTransportBar: View {
    var engine: AudioEditorEngine
    let selectionDuration: TimeInterval
    @Environment(\.ferriteLine) private var ferriteLine
    @Environment(\.designAccent) private var accent
    @Environment(\.designNumerals) private var numerals

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(AudioTimeFormatting.timestamp(engine.currentTime))
                    .font(.numerals(numerals, size: 13, weight: .semibold))
                    .monospacedDigit()
                Spacer()
                Text("Auswahl \(AudioTimeFormatting.timestamp(selectionDuration))")
                    .font(.readout(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(AudioTimeFormatting.timestamp(engine.duration))
                    .font(.numerals(numerals, size: 13, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 16) {
                Button {
                    engine.isLoopingSelection.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(engine.isLoopingSelection ? ferriteLine.onColor : .primary)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle().fill(engine.isLoopingSelection ? accent : Color.primary.opacity(0.08))
                        )
                }
                .accessibilityLabel("Auswahl in Schleife abspielen")

                Button {
                    engine.seek(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled(!engine.isLoaded)
                .accessibilityLabel("15 Sekunden zurück")

                Button {
                    if engine.isPlaying { engine.pause() } else { engine.play() }
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(accent)
                        .frame(width: 60, height: 60)
                }
                .disabled(!engine.isLoaded)
                .accessibilityLabel(engine.isPlaying ? "Pause" : "Abspielen")
                .accessibilityIdentifier("audioEditorPlayPauseButton")

                Button {
                    engine.seek(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled(!engine.isLoaded)
                .accessibilityLabel("15 Sekunden vor")

                Button {
                    engine.isBypassed.toggle()
                } label: {
                    Text(engine.isBypassed ? "Original" : "Bearbeitet")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 44)
                        .background(
                            Capsule().fill(engine.isBypassed ? FerriteStatus.warning.opacity(0.25) : Color.primary.opacity(0.08))
                        )
                        .overlay(
                            Capsule().strokeBorder(engine.isBypassed ? FerriteStatus.warning : Color.clear, lineWidth: 1)
                        )
                }
                .accessibilityLabel("A/B Vergleich: Original gegen Bearbeitet")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: Radius.card)
    }
}

// MARK: - Time Edit Panel

struct TimeEditPanel: View {
    @Binding var selectionMode: WaveformSelectionMode
    let selectionStart: TimeInterval
    let selectionEnd: TimeInterval
    let recipe: AudioEditRecipe
    let onTrim: () -> Void
    let onCut: () -> Void
    let onUpdateRecipe: (AudioEditRecipe) -> Void

    @Environment(\.designAccent) private var accent

    var body: some View {
        VStack(spacing: 14) {
            Picker("Auswahlmodus", selection: $selectionMode) {
                ForEach(WaveformSelectionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Button(action: onTrim) {
                    Label("Zuschneiden", systemImage: "crop")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(accent.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("audioEditorTrimButton")

                Button(action: onCut) {
                    Label("Bereich löschen", systemImage: "scissors")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(FerriteStatus.recording.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("audioEditorCutButton")
            }

            VStack(spacing: 10) {
                sliderRow(
                    title: "Fade-In",
                    valueText: String(format: "%.1f s", recipe.fadeInDuration),
                    value: Binding(
                        get: { recipe.fadeInDuration },
                        set: { newVal in
                            var copy = recipe
                            copy.fadeInDuration = newVal
                            onUpdateRecipe(copy)
                        }
                    ),
                    range: 0...3.0,
                    step: 0.1
                )

                sliderRow(
                    title: "Fade-Out",
                    valueText: String(format: "%.1f s", recipe.fadeOutDuration),
                    value: Binding(
                        get: { recipe.fadeOutDuration },
                        set: { newVal in
                            var copy = recipe
                            copy.fadeOutDuration = newVal
                            onUpdateRecipe(copy)
                        }
                    ),
                    range: 0...3.0,
                    step: 0.1
                )

                sliderRow(
                    title: "Lautstärke",
                    valueText: String(format: "%+.1f dB", recipe.gainDB),
                    value: Binding(
                        get: { Double(recipe.gainDB) },
                        set: { newVal in
                            var copy = recipe
                            copy.gainDB = Float(newVal)
                            onUpdateRecipe(copy)
                        }
                    ),
                    range: -12...12,
                    step: 0.5
                )

                Toggle("Pegel normalisieren (−1 dBFS)", isOn: Binding(
                    get: { recipe.normalizeEnabled },
                    set: { newVal in
                        var copy = recipe
                        copy.normalizeEnabled = newVal
                        onUpdateRecipe(copy)
                    }
                ))
                .font(.subheadline)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: Radius.card)
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(valueText).font(.readout(size: 11, weight: .semibold))
            }
            Slider(value: value, in: range, step: step)
                .tint(accent)
        }
    }
}

// MARK: - 5-Band EQ Panel

struct EQEditorPanel: View {
    let recipe: AudioEditRecipe
    let onUpdateRecipe: (AudioEditRecipe) -> Void
    @Environment(\.designAccent) private var accent

    var body: some View {
        VStack(spacing: 12) {
            eqResponseCurve
                .frame(height: 82)
                .innerCanvas(cornerRadius: Radius.kernel)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EQPreset.allCases) { preset in
                        Button {
                            var copy = recipe
                            copy.eqBands = preset.apply(to: copy.eqBands)
                            onUpdateRecipe(copy)
                        } label: {
                            Text(preset.rawValue)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(FerriteColor.surfaceSunken))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                ForEach(recipe.eqBands) { band in
                    VStack(spacing: 4) {
                        Text(String(format: "%+.0f", band.gainDB))
                            .font(.readout(size: 10, weight: .semibold))
                        Slider(
                            value: Binding(
                                get: { Double(band.gainDB) },
                                set: { val in
                                    var copy = recipe
                                    if let idx = copy.eqBands.firstIndex(where: { $0.id == band.id }) {
                                        copy.eqBands[idx].gainDB = Float(val)
                                        onUpdateRecipe(copy)
                                    }
                                }
                            ),
                            in: -12...12,
                            step: 0.5
                        )
                        .tint(accent)
                        Text(freqLabel(band.frequency))
                            .font(.readout(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: Radius.card)
    }

    private var eqResponseCurve: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            var zeroLine = Path()
            zeroLine.move(to: CGPoint(x: 0, y: midY))
            zeroLine.addLine(to: CGPoint(x: size.width, y: midY))
            ctx.stroke(zeroLine, with: .color(.primary.opacity(0.15)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

            let samples = 96
            var curve = Path()
            for i in 0..<samples {
                let frac = Float(i) / Float(samples - 1)
                let hz = 20.0 * powf(1000.0, frac) // 20 Hz .. 20 kHz log sweep
                let db = recipe.frequencyResponseDB(at: hz)
                let x = CGFloat(frac) * size.width
                let y = midY - CGFloat(db / 18.0) * (size.height * 0.42)
                let clampedY = max(4, min(size.height - 4, y))
                if i == 0 {
                    curve.move(to: CGPoint(x: x, y: clampedY))
                } else {
                    curve.addLine(to: CGPoint(x: x, y: clampedY))
                }
            }
            ctx.stroke(curve, with: .color(accent), lineWidth: 2)
        }
    }

    private func freqLabel(_ hz: Float) -> String {
        hz >= 1000 ? String(format: "%.0fk", hz / 1000) : String(format: "%.0f", hz)
    }
}

// MARK: - Filter Panel (HPF, LPF, Notch, Enhance Voice)

struct FilterEditorPanel: View {
    let recipe: AudioEditRecipe
    let onUpdateRecipe: (AudioEditRecipe) -> Void
    @Environment(\.designAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                var copy = recipe
                copy.filters.enhanceVoiceEnabled.toggle()
                onUpdateRecipe(copy)
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Sprache verbessern (Rauschen & Hall reduzieren)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: recipe.filters.enhanceVoiceEnabled ? "checkmark.circle.fill" : "circle")
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control)
                        .fill(recipe.filters.enhanceVoiceEnabled ? accent.opacity(0.25) : Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("audioEditorEnhanceButton")

            Divider()

            // High-Pass Filter
            Toggle(isOn: Binding(
                get: { recipe.filters.highPassEnabled },
                set: { val in
                    var copy = recipe
                    copy.filters.highPassEnabled = val
                    onUpdateRecipe(copy)
                }
            )) {
                HStack {
                    Text("Hochpassfilter (Trittschall)")
                    Spacer()
                    Text("\(Int(recipe.filters.highPassCutoffHz)) Hz")
                        .font(.readout(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if recipe.filters.highPassEnabled {
                Slider(
                    value: Binding(
                        get: { Double(recipe.filters.highPassCutoffHz) },
                        set: { val in
                            var copy = recipe
                            copy.filters.highPassCutoffHz = Float(val)
                            onUpdateRecipe(copy)
                        }
                    ),
                    in: 20...500,
                    step: 5
                )
                .tint(accent)
            }

            // Low-Pass Filter
            Toggle(isOn: Binding(
                get: { recipe.filters.lowPassEnabled },
                set: { val in
                    var copy = recipe
                    copy.filters.lowPassEnabled = val
                    onUpdateRecipe(copy)
                }
            )) {
                HStack {
                    Text("Tiefpassfilter (Zischen)")
                    Spacer()
                    Text("\(Int(recipe.filters.lowPassCutoffHz)) Hz")
                        .font(.readout(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if recipe.filters.lowPassEnabled {
                Slider(
                    value: Binding(
                        get: { Double(recipe.filters.lowPassCutoffHz) },
                        set: { val in
                            var copy = recipe
                            copy.filters.lowPassCutoffHz = Float(val)
                            onUpdateRecipe(copy)
                        }
                    ),
                    in: 1000...20000,
                    step: 100
                )
                .tint(accent)
            }

            // Notch / Bandstop Filter
            Toggle(isOn: Binding(
                get: { recipe.filters.notchEnabled },
                set: { val in
                    var copy = recipe
                    copy.filters.notchEnabled = val
                    onUpdateRecipe(copy)
                }
            )) {
                HStack {
                    Text("Notch / Brummfilter")
                    Spacer()
                    Text("\(Int(recipe.filters.notchCenterHz)) Hz")
                        .font(.readout(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if recipe.filters.notchEnabled {
                HStack(spacing: 8) {
                    ForEach([50, 60, 100, 120], id: \.self) { hz in
                        Button("\(hz) Hz") {
                            var copy = recipe
                            copy.filters.notchCenterHz = Float(hz)
                            onUpdateRecipe(copy)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                    }
                }
                Slider(
                    value: Binding(
                        get: { Double(recipe.filters.notchCenterHz) },
                        set: { val in
                            var copy = recipe
                            copy.filters.notchCenterHz = Float(val)
                            onUpdateRecipe(copy)
                        }
                    ),
                    in: 20...4000,
                    step: 5
                )
                .tint(accent)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: Radius.card)
    }
}

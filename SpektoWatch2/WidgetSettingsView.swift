import SwiftUI

struct WidgetSettingsView: View {
    let widget: WidgetConfiguration
    var onSave: ([String: String]) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var settings: [String: String]
    @State private var useWidgetOverrides: Bool
    
    init(widget: WidgetConfiguration, onSave: @escaping ([String: String]) -> Void) {
        self.widget = widget
        self.onSave = onSave
        _settings = State(initialValue: widget.settings)
        _useWidgetOverrides = State(initialValue: WidgetSettings.usesWidgetOverrides(widget.settings))
    }

    /// Shared noise-floor editor. Appears in widgets that support per-widget
    /// floor suppression (Spektrogramm: soft-knee gate; SingleValue: display guard).
    /// The waterfall's floor is its minDB stepper; chart widgets use chartYMinDB.
    @ViewBuilder
    private var noiseFloorSection: some View {
        // The spectrogram gates softly at 10 dB SPL out of the box (see
        // WidgetSettings.spectrogramNoiseFloorDB), so its baseline when no
        // override key is set is the spectrogram default — not the generic
        // −120 "off" used by the SingleValue display guard. Reflecting the
        // right default here keeps the toggle in sync with the render.
        let defaultFloor = widget.type == .spectrogram
            ? WidgetSettings.defaultSpectrogramNoiseFloor
            : WidgetSettings.defaultNoiseFloor
        let raw = Float(settings["noiseFloor"] ?? String(Int(defaultFloor))) ?? defaultFloor
        let isActive = raw > -119
        Section(header: Text("Grundrauschen")) {
            Toggle("Untergrenze aktivieren", isOn: Binding(
                get: { isActive },
                set: { on in settings["noiseFloor"] = on ? "30" : "-120" }
            ))
            if isActive {
                Stepper(
                    "Schwelle: \(Int(raw)) dB SPL",
                    value: Binding(
                        get: { Int(raw) },
                        set: { settings["noiseFloor"] = String($0) }
                    ),
                    in: 0...90,
                    step: 5
                )
                Text(widget.type == .singleValue
                     ? "Werte unter der Schwelle werden ausgeblendet (zeigt –)."
                     : "Signale unterhalb der Schwelle werden weich ausgeblendet (6 dB Übergang).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Shared Y-axis bound editor (dB SPL). Reuses the `chartYMinDB` /
    /// `chartYMaxDB` setting keys defined in `WidgetSettings`.
    @ViewBuilder
    private var yAxisBoundsSection: some View {
        Section(header: Text("Y-Achse (dB SPL)")) {
            Stepper(
                "Minimum: \(Int(currentYMin)) dB",
                value: Binding(
                    get: { Int(currentYMin) },
                    set: { settings["chartYMinDB"] = String($0) }
                ),
                in: 0 ... 90,
                step: 5
            )
            Stepper(
                "Maximum: \(Int(currentYMax)) dB",
                value: Binding(
                    get: { Int(currentYMax) },
                    set: { settings["chartYMaxDB"] = String($0) }
                ),
                in: 40 ... 140,
                step: 5
            )
        }
    }

    private var currentYMin: Float {
        Float(settings["chartYMinDB"] ?? "") ?? WidgetSettings.defaultChartYMinDB
    }
    private var currentYMax: Float {
        Float(settings["chartYMaxDB"] ?? "") ?? WidgetSettings.defaultChartYMaxDB
    }

    private var supportsOverrideToggle: Bool {
        switch widget.type {
        case .spectrogram, .waterfall, .levelHistory, .frequencyDisplay,
             .octaveBands, .singleValue, .levelMeter:
            return true
        default:
            return false
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if supportsOverrideToggle {
                    Section {
                        Toggle("Widget-Einstellungen aktivieren", isOn: $useWidgetOverrides)
                    } footer: {
                        Text(useWidgetOverrides ? "Dieses Widget nutzt eigene Einstellungen." : "Dieses Widget übernimmt die globalen App-Einstellungen.")
                    }
                }

                if widget.type == .spectrogram {
                    Section(header: Text("Spektrogramm Einstellungen")) {
                        Picker("Farbschema", selection: Binding(
                            get: { settings["colormap"] ?? String(WidgetSettings.defaultSpectrogramColormap) },
                            set: { settings["colormap"] = $0 }
                        )) {
                            ForEach(ColormapType.allCases) { cm in
                                Text(cm.label).tag(String(cm.rawValue))
                            }
                        }

                        Picker("Dargestellter Zeitbereich", selection: Binding(
                            get: { settings["timeSpan"] ?? String(WidgetSettings.defaultTimeSpanSeconds) },
                            set: { settings["timeSpan"] = $0 }
                        )) {
                            ForEach(SpectrogramTimeSpan.allCases) { span in
                                Text(span.title).tag(String(span.rawValue))
                            }
                        }

                        // `timeWeighting` (Fast/Slow) was removed 2026-05-21
                        // — the spectrogram render path never read the
                        // setting; only the level-history widgets do. M9
                        // task-1 audit pre-pass.

                        Picker("Frequenzbewertung", selection: Binding(
                            get: { settings["freqWeighting"] ?? "Z" },
                            set: { settings["freqWeighting"] = $0 }
                        )) {
                            Text("Z (Linear)").tag("Z")
                            Text("A-Weighting").tag("A")
                            Text("C-Weighting").tag("C")
                        }
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)

                    Section(header: Text("Empfindlichkeit")) {
                        let sensitivityValue = Float(settings["sensitivity"] ?? String(Int(WidgetSettings.defaultSpectrogramSensitivity))) ?? WidgetSettings.defaultSpectrogramSensitivity

                        VStack(alignment: .leading) {
                            Text("Dynamikbereich: \(Int(sensitivityValue)) dB")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Slider(
                                value: Binding(
                                    get: { Double(settings["sensitivity"] ?? String(Int(WidgetSettings.defaultSpectrogramSensitivity))) ?? Double(WidgetSettings.defaultSpectrogramSensitivity) },
                                    set: { settings["sensitivity"] = String(Int($0)) }
                                ),
                                in: 60...110,
                                step: 5
                            )

                            Text("Niedriger = mehr Kontrast, Höher = mehr Details")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)

                    Section(header: Text("Frequenz-Glättung")) {
                        let smoothingValue = Float(settings["frequencySmoothing"] ?? "0.0") ?? 0.0

                        VStack(alignment: .leading) {
                            Text("Stärke: \(String(format: "%.2f", smoothingValue))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Slider(
                                value: Binding(
                                    get: { Double(settings["frequencySmoothing"] ?? "0.0") ?? 0.0 },
                                    set: { settings["frequencySmoothing"] = String(format: "%.2f", $0) }
                                ),
                                in: 0.0...1.0,
                                step: 0.05
                            )

                            Text("Versteckt FFT-Bin-Grenzen bei niedrigen Frequenzen. Eine leichte Grundglättung ist immer aktiv.")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)

                    noiseFloorSection
                        .disabled(supportsOverrideToggle && !useWidgetOverrides)
                } else if widget.type == .waterfall {
                    Section(header: Text("Wasserfall Einstellungen")) {
                        Picker("Frequenzbewertung", selection: Binding(
                            get: { settings["freqWeighting"] ?? "Z" },
                            set: { settings["freqWeighting"] = $0 }
                        )) {
                            Text("Z (Linear)").tag("Z")
                            Text("A-Weighting").tag("A")
                            Text("C-Weighting").tag("C")
                        }

                        Picker("Zeitscheiben", selection: Binding(
                            get: { settings["waterfallSlices"] ?? String(WidgetSettings.defaultWaterfallSliceCount) },
                            set: { settings["waterfallSlices"] = $0 }
                        )) {
                            Text("48").tag("48")
                            Text("96").tag("96")
                            Text("160").tag("160")
                        }

                        Picker("Spektrum", selection: Binding(
                            get: { settings["waterfallSpectrumMode"] ?? WidgetSettings.defaultWaterfallSpectrumMode },
                            set: { settings["waterfallSpectrumMode"] = $0 }
                        )) {
                            Text("Linie").tag("continuous")
                            Text("Terz").tag("thirdOctave")
                            Text("Bark").tag("bark")
                            Text("Oktav").tag("octave")
                        }

                        Toggle("Spitzenmarker", isOn: Binding(
                            get: {
                                (settings["waterfallShowPeaks"]
                                    ?? (WidgetSettings.defaultWaterfallShowPeaks ? "true" : "false")) == "true"
                            },
                            set: { settings["waterfallShowPeaks"] = $0 ? "true" : "false" }
                        ))
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)

                    Section(header: Text("Dynamikbereich (dB SPL)")) {
                        Stepper(
                            "Minimum: \(Int(Float(settings["waterfallMinDB"] ?? String(Int(WidgetSettings.defaultWaterfallMinDB))) ?? WidgetSettings.defaultWaterfallMinDB)) dB",
                            value: Binding(
                                get: { Int(Float(settings["waterfallMinDB"] ?? String(Int(WidgetSettings.defaultWaterfallMinDB))) ?? WidgetSettings.defaultWaterfallMinDB) },
                                set: { settings["waterfallMinDB"] = String($0) }
                            ),
                            in: 0 ... 90,
                            step: 5
                        )
                        Stepper(
                            "Maximum: \(Int(Float(settings["waterfallMaxDB"] ?? String(Int(WidgetSettings.defaultWaterfallMaxDB))) ?? WidgetSettings.defaultWaterfallMaxDB)) dB",
                            value: Binding(
                                get: { Int(Float(settings["waterfallMaxDB"] ?? String(Int(WidgetSettings.defaultWaterfallMaxDB))) ?? WidgetSettings.defaultWaterfallMaxDB) },
                                set: { settings["waterfallMaxDB"] = String($0) }
                            ),
                            in: 60 ... 140,
                            step: 5
                        )
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)
                } else if widget.type == .levelHistory {
                    Section(header: Text("Pegelverlauf Einstellungen")) {
                        Picker("Messwert über Zeit", selection: Binding(
                            get: { settings["historyMetric"] ?? WidgetSettings.defaultLevelHistoryMetric },
                            set: { settings["historyMetric"] = $0 }
                        )) {
                            Text("Automatisch (aus A/C/Z + Fast/Slow)").tag("AUTO")
                            Text("LAF").tag("LAF")
                            Text("LAS").tag("LAS")
                            Text("LCF").tag("LCF")
                            Text("LCS").tag("LCS")
                            Text("LZF").tag("LZF")
                            Text("LZS").tag("LZS")
                            Text("LAeq").tag("LAeq")
                            Text("LAFmin").tag("LAFmin")
                            Text("LAFmax").tag("LAFmax")
                            Text("LAF5").tag("LAF5")
                            Text("LAF95").tag("LAF95")
                            Text("LAFT5").tag("LAFT5")
                            Text("LAFTeq").tag("LAFTeq")
                            Text("LCpeak").tag("LCpeak")
                        }

                        Picker("Zeitbereich", selection: Binding(
                            get: { settings["timeSpan"] ?? String(WidgetSettings.defaultTimeSpanSeconds) },
                            set: { settings["timeSpan"] = $0 }
                        )) {
                            Text("1 Sekunde").tag("1")
                            Text("5 Sekunden").tag("5")
                        }
                        
                        let isAutoMetric = (settings["historyMetric"] ?? WidgetSettings.defaultLevelHistoryMetric) == WidgetSettings.defaultLevelHistoryMetric

                        Picker("Frequenzbewertung", selection: Binding(
                            get: { settings["freqWeighting"] ?? "A" },
                            set: { settings["freqWeighting"] = $0 }
                        )) {
                            Text("A-Weighting").tag("A")
                            Text("C-Weighting").tag("C")
                            Text("Z-Weighting (Linear)").tag("Z")
                        }
                        .disabled(!isAutoMetric)

                        Picker("Zeitbewertung", selection: Binding(
                            get: { settings["timeWeighting"] ?? "Fast" },
                            set: { settings["timeWeighting"] = $0 }
                        )) {
                            Text("Fast (125ms)").tag("Fast")
                            Text("Slow (1s)").tag("Slow")
                        }
                        .disabled(!isAutoMetric)
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)

                    yAxisBoundsSection
                        .disabled(supportsOverrideToggle && !useWidgetOverrides)

                    Section(header: Text("Erweitert")) {
                        Toggle("Gitter anzeigen", isOn: Binding(
                            get: { WidgetSettings.chartShowGrid(settings) },
                            set: { settings["chartShowGrid"] = $0 ? "1" : "0" }
                        ))
                        let smoothing = WidgetSettings.historySmoothing(settings)
                        VStack(alignment: .leading) {
                            Text("Glättung: \(String(format: "%.1f", smoothing))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Slider(
                                value: Binding(
                                    get: { Double(WidgetSettings.historySmoothing(settings)) },
                                    set: { settings["historySmoothing"] = String(format: "%.1f", $0) }
                                ),
                                in: 0...5,
                                step: 0.5
                            )
                        }
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)
                } else if widget.type == .frequencyDisplay {
                    Section(header: Text("Spektrum Einstellungen")) {
                        Picker("Frequenzbewertung", selection: Binding(
                            get: { settings["freqWeighting"] ?? "Z" },
                            set: { settings["freqWeighting"] = $0 }
                        )) {
                            Text("Z (Linear)").tag("Z")
                            Text("A-Weighting").tag("A")
                            Text("C-Weighting").tag("C")
                        }

                        Picker("Frequenzbänder", selection: Binding(
                            get: { settings["frequencyBands"] ?? WidgetSettings.defaultSpectrumBandMode },
                            set: { settings["frequencyBands"] = $0 }
                        )) {
                            Text("Linie").tag("continuous")
                            Text("Bark").tag("bark")
                            Text("Oktav (optional)").tag("octave")
                            Text("Terz").tag("terz")
                        }
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)

                    yAxisBoundsSection
                        .disabled(supportsOverrideToggle && !useWidgetOverrides)

                    Section(header: Text("Erweitert")) {
                        Toggle("Gitter anzeigen", isOn: Binding(
                            get: { WidgetSettings.chartShowGrid(settings) },
                            set: { settings["chartShowGrid"] = $0 ? "1" : "0" }
                        ))
                        Toggle("Leq-Overlay anzeigen", isOn: Binding(
                            get: { WidgetSettings.spectrumShowLeq(settings) },
                            set: { settings["spectrumShowLeq"] = $0 ? "1" : "0" }
                        ))
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)
                } else if widget.type == .levelMeter {
                    Section(header: Text("Anzeige")) {
                        Picker("Ausrichtung", selection: Binding(
                            get: { WidgetSettings.levelMeterOrientation(settings).rawValue },
                            set: { settings[WidgetSettings.levelMeterOrientationKey] = $0 }
                        )) {
                            ForEach(LevelMeterOrientation.allCases) { orientation in
                                Text(orientation.displayName).tag(orientation.rawValue)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)

                    yAxisBoundsSection
                        .disabled(supportsOverrideToggle && !useWidgetOverrides)
                    Section(header: Text("Erweitert")) {
                        Toggle("Peak-Hold Marker", isOn: Binding(
                            get: { WidgetSettings.levelMeterShowPeak(settings) },
                            set: { settings["levelMeterShowPeak"] = $0 ? "1" : "0" }
                        ))
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)
                } else if widget.type == .singleValue {
                    Section(header: Text("Anzeige")) {
                        Picker("Aktualisierung", selection: Binding(
                            get: {
                                settings[WidgetSettings.singleValueRefreshRateKey]
                                    ?? SingleValueRefreshRate.default.rawValue
                            },
                            set: { settings[WidgetSettings.singleValueRefreshRateKey] = $0 }
                        )) {
                            ForEach(SingleValueRefreshRate.allCases) { rate in
                                Text(rate.displayName).tag(rate.rawValue)
                            }
                        }
                        Picker("Messwert", selection: Binding(
                            get: { settings["metric"] ?? WidgetSettings.defaultSingleValueMetric },
                            set: { settings["metric"] = $0 }
                        )) {
                            Text("LAF (Aktuell)").tag("LAF")
                            Text("LAeq (Equivalent)").tag("LAeq")
                            Text("LAFmin (Minimum)").tag("LAFmin")
                            Text("LAFmax (Maximum)").tag("LAFmax")
                            Text("LAF5 (5% Perzentil)").tag("LAF5")
                            Text("LAF95 (95% Perzentil)").tag("LAF95")
                            Text("LAFT5 (Takt max)").tag("LAFT5")
                            Text("LAFTeq (Takt eq)").tag("LAFTeq")
                            Text("LCpeak (Peak)").tag("LCpeak")
                            Text("Lautheit (Phon)").tag("PHON")
                            Text("Lautheit (Sone)").tag("SONE")
                        }
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)

                    noiseFloorSection
                        .disabled(supportsOverrideToggle && !useWidgetOverrides)
                } else {
                    Text("Keine Einstellungen verfügbar für diesen Widget-Typ.")
                }
            }
            .polishedFormChrome()
            .navigationTitle(widget.type.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        var validatedSettings = settings
                        if let colormap = Int(settings["colormap"] ?? String(WidgetSettings.defaultSpectrogramColormap)), colormap < 0 || colormap > ColormapType.allCases.count - 1 {
                            validatedSettings["colormap"] = String(WidgetSettings.defaultSpectrogramColormap)
                        }
                        if supportsOverrideToggle {
                            validatedSettings[WidgetSettings.useWidgetOverridesKey] = useWidgetOverrides ? "1" : "0"
                        }
                        onSave(validatedSettings)
                        dismiss()
                    }
                }
            }
            .accessibilityIdentifier("widgetSettingsView")
        }
    }
}

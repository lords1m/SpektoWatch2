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

    private var supportsOverrideToggle: Bool {
        switch widget.type {
        case .spectrogram, .waterfall, .levelHistory, .frequencyDisplay, .octaveBands, .singleValue:
            return true
        default:
            return false
        }
    }
    
    var body: some View {
        NavigationView {
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

                        Picker("Zeitbewertung", selection: Binding(
                            get: { settings["timeWeighting"] ?? "Fast" },
                            set: { settings["timeWeighting"] = $0 }
                        )) {
                            Text("Fast (125ms)").tag("Fast")
                            Text("Slow (1s)").tag("Slow")
                        }

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
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)

                    Section(header: Text("Dynamikbereich")) {
                        Stepper(
                            "Minimum: \(Int(Float(settings["waterfallMinDB"] ?? String(Int(WidgetSettings.defaultWaterfallMinDB))) ?? WidgetSettings.defaultWaterfallMinDB)) dB",
                            value: Binding(
                                get: { Int(Float(settings["waterfallMinDB"] ?? String(Int(WidgetSettings.defaultWaterfallMinDB))) ?? WidgetSettings.defaultWaterfallMinDB) },
                                set: { settings["waterfallMinDB"] = String($0) }
                            ),
                            in: -140 ... -40,
                            step: 5
                        )
                        Stepper(
                            "Maximum: \(Int(Float(settings["waterfallMaxDB"] ?? String(Int(WidgetSettings.defaultWaterfallMaxDB))) ?? WidgetSettings.defaultWaterfallMaxDB)) dB",
                            value: Binding(
                                get: { Int(Float(settings["waterfallMaxDB"] ?? String(Int(WidgetSettings.defaultWaterfallMaxDB))) ?? WidgetSettings.defaultWaterfallMaxDB) },
                                set: { settings["waterfallMaxDB"] = String($0) }
                            ),
                            in: -20 ... 120,
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
                        
                        Picker("Frequenzbewertung", selection: Binding(
                            get: { settings["freqWeighting"] ?? "A" },
                            set: { settings["freqWeighting"] = $0 }
                        )) {
                            Text("A-Weighting").tag("A")
                            Text("C-Weighting").tag("C")
                            Text("Z-Weighting (Linear)").tag("Z")
                        }
                        
                        Picker("Zeitbewertung", selection: Binding(
                            get: { settings["timeWeighting"] ?? "Fast" },
                            set: { settings["timeWeighting"] = $0 }
                        )) {
                            Text("Fast (125ms)").tag("Fast")
                            Text("Slow (1s)").tag("Slow")
                        }
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)
                } else if widget.type == .frequencyDisplay || widget.type == .octaveBands {
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
                            Text("Bark").tag("bark")
                            Text("Oktav").tag("octave")
                            Text("Terz").tag("terz")
                        }
                    }
                    .disabled(supportsOverrideToggle && !useWidgetOverrides)
                } else if widget.type == .singleValue {
                    Section(header: Text("Anzeige")) {
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
                } else {
                    Text("Keine Einstellungen verfügbar für diesen Widget-Typ.")
                }
            }
            .navigationTitle(widget.type.rawValue)
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
        }
    }
}

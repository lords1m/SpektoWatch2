import SwiftUI

struct WidgetSettingsView: View {
    let widget: WidgetConfiguration
    var onSave: ([String: String]) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var settings: [String: String]
    
    init(widget: WidgetConfiguration, onSave: @escaping ([String: String]) -> Void) {
        self.widget = widget
        self.onSave = onSave
        _settings = State(initialValue: widget.settings)
    }
    
    var body: some View {
        NavigationView {
            Form {
                if widget.type == .spectrogram {
                    Section(header: Text("Spektrogramm Einstellungen")) {
                        Picker("Farbschema", selection: Binding(
                            get: { settings["colormap"] ?? "0" },
                            set: { settings["colormap"] = $0 }
                        )) {
                            Text("Turbo").tag("0")
                            Text("Jet").tag("1")
                            Text("Viridis").tag("2")
                        }

                        Picker("Zeitbereich", selection: Binding(
                            get: { settings["timeSpan"] ?? "5" },
                            set: { settings["timeSpan"] = $0 }
                        )) {
                            Text("1 Sekunde").tag("1")
                            Text("5 Sekunden").tag("5")
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

                    Section(header: Text("Empfindlichkeit")) {
                        let sensitivityValue = Float(settings["sensitivity"] ?? "50") ?? 50.0

                        VStack(alignment: .leading) {
                            Text("Dynamikbereich: \(Int(sensitivityValue)) dB")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Slider(
                                value: Binding(
                                    get: { Double(settings["sensitivity"] ?? "50") ?? 50.0 },
                                    set: { settings["sensitivity"] = String(Int($0)) }
                                ),
                                in: 30...80,
                                step: 5
                            )

                            Text("Niedriger = mehr Kontrast, Höher = mehr Details")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                } else if widget.type == .levelHistory {
                    Section(header: Text("Pegelverlauf Einstellungen")) {
                        Picker("Zeitbereich", selection: Binding(
                            get: { settings["timeSpan"] ?? "5" },
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
                } else if widget.type == .singleValue {
                    Section(header: Text("Anzeige")) {
                        Picker("Messwert", selection: Binding(
                            get: { settings["metric"] ?? "LAF" },
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
                        }
                    }
                } else {
                    Text("Keine Einstellungen verfügbar für diesen Widget-Typ.")
                }
            }
            .navigationTitle(widget.type.rawValue)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        var validatedSettings = settings
                        if let colormap = Int(settings["colormap"] ?? "0"), colormap < 0 || colormap > 2 {
                            validatedSettings["colormap"] = "0"
                        }
                        onSave(validatedSettings)
                        dismiss()
                    }
                }
            }
        }
    }
}
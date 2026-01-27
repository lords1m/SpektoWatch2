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
                    }
                } else if widget.type == .lafGraph {
                    Section(header: Text("Graph Einstellungen")) {
                        Picker("Zeitbereich", selection: Binding(
                            get: { settings["timeSpan"] ?? "5" },
                            set: { settings["timeSpan"] = $0 }
                        )) {
                            Text("1 Sekunde").tag("1")
                            Text("5 Sekunden").tag("5")
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
                        onSave(settings)
                        dismiss()
                    }
                }
            }
        }
    }
}
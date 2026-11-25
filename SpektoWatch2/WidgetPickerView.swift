import SwiftUI

struct WidgetPickerView: View {
    var dashboardManager: DashboardManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedStyle: WidgetDisplayStyle = .liveWidget

    private struct SectionSpec: Identifiable {
        let id: String
        let title: String
        let types: [AudioWidgetType]
    }

    private static let sections: [SectionSpec] = [
        .init(id: "viz", title: "Visualisierung", types: [.spectrogram, .frequencyDisplay]),
        .init(id: "levels", title: "Pegel & Metriken", types: [.levelHistory, .levelMeter, .singleValue]),
        .init(id: "tools", title: "Werkzeuge & Funktionen", types: [.audioEditor, .recordings, .toneGenerator, .spektralanalyseLab, .settings])
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Darstellung", selection: $selectedStyle) {
                        ForEach(WidgetDisplayStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("widgetPickerDisplayStyle")
                } footer: {
                    Text(selectedStyle == .icon
                         ? "Kompaktes 1×1-Icon für den Home-Bildschirm. Tippen öffnet die Vollbildansicht."
                         : "Zeigt Messwerte und Steuerelemente direkt live auf dem Home-Bildschirm.")
                }

                ForEach(Self.sections) { section in
                    Section(header: Text(section.title)) {
                        ForEach(section.types) { type in
                            Button(action: {
                                withAnimation(.spring()) {
                                    dashboardManager.addWidget(type: type, displayStyle: selectedStyle)
                                }
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: type.sfSymbol)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 26, height: 26)
                                        .background(FerriteColor.surfaceSunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    Text(type.rawValue)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.accent)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(FerriteColor.surface)
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .polishedFormChrome()
            .navigationTitle("Widget hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .accessibilityIdentifier("widgetPickerView")
        }
    }
}

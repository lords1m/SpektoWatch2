import SwiftUI

struct WidgetPickerView: View {
    @ObservedObject var dashboardManager: DashboardManager
    @Environment(\.dismiss) var dismiss

    private struct SectionSpec: Identifiable {
        let id: String
        let title: String
        let types: [AudioWidgetType]
    }

    private static let sections: [SectionSpec] = [
        .init(id: "viz", title: "Visualisierung", types: [.spectrogram, .waterfall, .frequencyDisplay, .octaveBands]),
        .init(id: "levels", title: "Pegel & Metriken", types: [.levelHistory, .levelMeter, .singleValue, .phaseMeter]),
        .init(id: "tools", title: "Werkzeuge", types: [.toneGenerator, .masking, .spektralanalyseLab])
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.sections) { section in
                    Section(header: Text(section.title)) {
                        ForEach(section.types) { type in
                            Button(action: {
                                withAnimation(.spring()) {
                                    dashboardManager.addWidget(type: type)
                                }
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: type.sfSymbol)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 26, height: 26)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                                    .fill(.ultraThinMaterial)
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

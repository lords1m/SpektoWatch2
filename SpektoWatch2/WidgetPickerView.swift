import SwiftUI

struct WidgetPickerView: View {
    var dashboardManager: DashboardManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedStyle: WidgetDisplayStyle = .liveWidget

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

                ForEach(AudioToolCatalog.categories) { category in
                    Section(header: Text(category.title)) {
                        ForEach(AudioToolCatalog.tools(in: category, supporting: selectedStyle)) { tool in
                            Button(action: {
                                withAnimation(.spring()) {
                                    dashboardManager.addWidget(type: tool.type, displayStyle: selectedStyle)
                                }
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: tool.type.sfSymbol)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 26, height: 26)
                                        .background(FerriteColor.surfaceSunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    Text(tool.type.rawValue)
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

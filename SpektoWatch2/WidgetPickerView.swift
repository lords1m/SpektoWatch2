import SwiftUI

struct WidgetPickerView: View {
    @ObservedObject var dashboardManager: DashboardManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(AudioWidgetType.allCases) { type in
                    Button(action: {
                        print("[WidgetPickerView] Selected widget type: \(type.rawValue)")
                        withAnimation(.spring()) {
                            dashboardManager.addWidget(type: type)
                        }
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: symbol(for: type))
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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
            .navigationTitle("Widget hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .accessibilityIdentifier("widgetPickerView")
        }
    }

    private func symbol(for type: AudioWidgetType) -> String {
        switch type {
        case .spectrogram: return "waveform.path.ecg.rectangle"
        case .waterfall: return "water.waves"
        case .levelHistory: return "chart.xyaxis.line"
        case .frequencyDisplay: return "chart.bar.xaxis"
        case .levelMeter: return "gauge.with.needle"
        case .octaveBands: return "slider.horizontal.3"
        case .phaseMeter: return "circle.lefthalf.filled"
        case .singleValue: return "number"
        case .toneGenerator: return "dot.radiowaves.left.and.right"
        case .spektralanalyseLab: return "waveform.badge.magnifyingglass"
        case .masking: return "waveform.slash"
        }
    }
}

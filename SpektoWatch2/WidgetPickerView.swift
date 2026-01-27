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
                        dashboardManager.addWidget(type: type)
                        dismiss()
                    }) {
                        HStack {
                            Text(type.rawValue)
                            Spacer()
                            Image(systemName: "plus.circle")
                        }
                    }
                }
            }
            .navigationTitle("Widget hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}
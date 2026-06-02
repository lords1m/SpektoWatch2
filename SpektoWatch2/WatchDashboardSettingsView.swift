import SwiftUI
import Combine

struct WatchDashboardSettingsView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @Environment(\.designAccent) private var accent
    @StateObject private var viewModel = WatchDashboardSettingsViewModel()
    @State private var widgetToEdit: WatchWidgetConfig?
    @State private var showingWidgetPicker = false

    var body: some View {
        List {
            Section {
                watchPreview
                    .frame(height: 160)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            } header: {
                Text("Vorschau (Apple Watch)")
            } footer: {
                Text("Die Watch zeigt bis zu \(WatchDashboardConfig.watchDisplayColumnCount) Widgets pro Zeile. Die Reihenfolge unten entspricht der Anzeige auf der Uhr.")
            }

            Section("Widgets") {
                ForEach(viewModel.displayWidgets) { widget in
                    Button {
                        widgetToEdit = widget
                        showingWidgetPicker = true
                    } label: {
                        widgetRow(widget)
                    }
                }
                .onDelete(perform: viewModel.deleteDisplayWidgets)
                .onMove(perform: viewModel.moveDisplayWidgets)

                Button {
                    widgetToEdit = nil
                    showingWidgetPicker = true
                } label: {
                    Label("Widget hinzufügen", systemImage: "plus.circle")
                }
                .disabled(!viewModel.canAddWidget)
            }
        }
        .polishedFormChrome()
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    viewModel.syncToWatch(connectivityManager: connectivityManager)
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Mit Watch synchronisieren")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(accent)
                    .foregroundColor(.black)
                    .cornerRadius(10)
                }

                Button {
                    viewModel.resetToDefault(connectivityManager: connectivityManager)
                } label: {
                    Text("Auf Standard zurücksetzen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingWidgetPicker) {
            WidgetPickerSheet(
                currentConfig: widgetToEdit,
                unavailableKeys: viewModel.unavailableDisplayKeys(excluding: widgetToEdit),
                onSelect: { type, valueType in
                    if let existing = widgetToEdit {
                        viewModel.updateWidget(existing, type: type, singleValueType: valueType)
                    } else {
                        viewModel.addWidget(type: type, singleValueType: valueType)
                    }
                    showingWidgetPicker = false
                    widgetToEdit = nil
                }
            )
        }
        .onAppear {
            viewModel.reloadFromStorage()
        }
    }

    // MARK: - Preview (3 columns, matches watch)

    private var watchPreview: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 4),
            count: WatchDashboardConfig.watchDisplayColumnCount
        )

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(viewModel.displayWidgets) { widget in
                widgetPreview(for: widget)
                    .frame(height: 44)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                )
        )
    }

    private func widgetRow(_ widget: WatchWidgetConfig) -> some View {
        HStack(spacing: 12) {
            Image(systemName: widget.type.icon)
                .foregroundColor(previewColor(for: widget.type))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(widget.type.rawValue)
                    .foregroundColor(.primary)
                if let valueType = widget.singleValueType {
                    Text(valueType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func widgetPreview(for widget: WatchWidgetConfig) -> some View {
        let color = previewColor(for: widget.type)
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.opacity(0.25))
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: widget.type.icon)
                        .font(.system(size: 11))
                    if let valueType = widget.singleValueType {
                        Text(valueType.displayName)
                            .font(.system(size: 7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .foregroundColor(color)
            )
    }

    private func previewColor(for type: WatchWidgetType) -> Color {
        switch type {
        case .spectrogram: return .blue
        case .levelMeter: return .green
        case .singleValue: return .orange
        case .loudness: return .purple
        case .empty: return .gray
        }
    }
}

// MARK: - Widget Picker Sheet

struct WidgetPickerSheet: View {
    let currentConfig: WatchWidgetConfig?
    let unavailableKeys: Set<String>
    let onSelect: (WatchWidgetType, WatchSingleValueType?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if currentConfig != nil {
                    Section {
                        Button(role: .destructive) {
                            onSelect(.empty, nil)
                        } label: {
                            Label("Widget entfernen", systemImage: "trash")
                        }
                    }
                }

                Section("Widget-Typ") {
                    ForEach(WatchWidgetType.allCases.filter { $0 != .empty }) { type in
                        if type == .singleValue {
                            DisclosureGroup {
                                ForEach(WatchSingleValueType.allCases, id: \.self) { valueType in
                                    let key = WatchDashboardConfig.displayKey(
                                        for: WatchWidgetConfig(type: .singleValue, position: 0, singleValueType: valueType)
                                    )
                                    pickerRow(
                                        title: valueType.displayName,
                                        systemImage: type.icon,
                                        isSelected: currentConfig?.type == .singleValue && currentConfig?.singleValueType == valueType,
                                        isDisabled: unavailableKeys.contains(key)
                                    ) {
                                        onSelect(.singleValue, valueType)
                                    }
                                }
                            } label: {
                                Label(type.rawValue, systemImage: type.icon)
                            }
                        } else {
                            let key = WatchDashboardConfig.displayKey(
                                for: WatchWidgetConfig(type: type, position: 0)
                            )
                            pickerRow(
                                title: type.rawValue,
                                systemImage: type.icon,
                                isSelected: currentConfig?.type == type,
                                isDisabled: unavailableKeys.contains(key)
                            ) {
                                onSelect(type, nil)
                            }
                        }
                    }
                }
            }
            .polishedFormChrome()
            .navigationTitle("Widget wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .polishedSheetChrome()
    }

    @ViewBuilder
    private func pickerRow(
        title: String,
        systemImage: String,
        isSelected: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
        .disabled(isDisabled && !isSelected)
    }
}

// MARK: - View Model

@MainActor
class WatchDashboardSettingsViewModel: ObservableObject {
    @Published private(set) var config: WatchDashboardConfig

    var displayWidgets: [WatchWidgetConfig] {
        config.orderedDisplayWidgets
    }

    var canAddWidget: Bool {
        displayWidgets.count < WatchDashboardConfig.maxDisplayWidgetCount
    }

    init() {
        self.config = WatchDashboardConfig.load()
    }

    func reloadFromStorage() {
        config = WatchDashboardConfig.load()
    }

    func addWidget(type: WatchWidgetType, singleValueType: WatchSingleValueType?) {
        guard type != .empty, canAddWidget else { return }
        var widgets = displayWidgets
        widgets.append(WatchWidgetConfig(type: type, position: widgets.count, singleValueType: singleValueType))
        config.replaceOrderedDisplayWidgets(widgets)
        config.save()
    }

    func updateWidget(_ existing: WatchWidgetConfig, type: WatchWidgetType, singleValueType: WatchSingleValueType?) {
        var widgets = displayWidgets
        guard let index = widgets.firstIndex(where: { $0.id == existing.id }) else { return }
        if type == .empty {
            widgets.remove(at: index)
        } else {
            widgets[index] = WatchWidgetConfig(
                id: existing.id,
                type: type,
                position: index,
                singleValueType: singleValueType
            )
        }
        config.replaceOrderedDisplayWidgets(widgets)
        config.save()
    }

    func deleteDisplayWidgets(at offsets: IndexSet) {
        var widgets = displayWidgets
        widgets.remove(atOffsets: offsets)
        config.replaceOrderedDisplayWidgets(widgets)
        config.save()
    }

    func moveDisplayWidgets(from source: IndexSet, to destination: Int) {
        var widgets = displayWidgets
        widgets.move(fromOffsets: source, toOffset: destination)
        config.replaceOrderedDisplayWidgets(widgets)
        config.save()
    }

    func unavailableDisplayKeys(excluding widget: WatchWidgetConfig?) -> Set<String> {
        Set(
            displayWidgets
                .filter { $0.id != widget?.id }
                .map { WatchDashboardConfig.displayKey(for: $0) }
        )
    }

    func syncToWatch(connectivityManager: WatchConnectivityManager) {
        connectivityManager.sendWatchDashboardConfig(config)
    }

    func resetToDefault(connectivityManager: WatchConnectivityManager) {
        config = WatchDashboardConfig()
        config.save()
        syncToWatch(connectivityManager: connectivityManager)
    }
}

// MARK: - Limits

extension WatchDashboardConfig {
    /// Practical upper bound for the watch screen (3×4 grid).
    static let maxDisplayWidgetCount = 12
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WatchDashboardSettingsView()
    }
}

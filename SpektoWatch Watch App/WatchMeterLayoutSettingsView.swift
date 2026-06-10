import SwiftUI

/// On-watch editor for the customizable meter face layout.
struct WatchMeterLayoutSettingsView: View {
    @State private var config = WatchMeterLayoutConfig.load()
    @State private var widgetToEdit: WatchWidgetConfig?
    @State private var showingPicker = false
    @State private var isEditing = false
    @State private var tileRefreshRate: SingleValueRefreshRate = .default

    private var displayWidgets: [WatchWidgetConfig] {
        config.orderedMeterWidgets
    }

    var body: some View {
        List {
            Section {
                meterPreview
                    .frame(height: 100)
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Pegelmesser und Wert-Kacheln. Spektrogramm und Verlaufsgraph haben eigene Ansichten.")
            }

            Section("Widgets") {
                ForEach(displayWidgets) { widget in
                    HStack(spacing: 6) {
                        Button {
                            widgetToEdit = widget
                            tileRefreshRate = config.refreshRate(for: widget)
                            showingPicker = true
                        } label: {
                            HStack {
                                Image(systemName: widget.type.icon)
                                VStack(alignment: .leading) {
                                    Text(widget.type.rawValue)
                                    if let valueType = widget.singleValueType {
                                        Text(valueType.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if widget.type == .singleValue {
                                        Text(config.refreshRate(for: widget).displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if isEditing {
                            VStack(spacing: 2) {
                                Button { moveWidget(widget, offset: -1) } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .disabled(displayWidgets.first?.id == widget.id)
                                Button { moveWidget(widget, offset: 1) } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .disabled(displayWidgets.last?.id == widget.id)
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .buttonStyle(.plain)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteWidget(widget)
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }

                Button {
                    widgetToEdit = nil
                    tileRefreshRate = config.defaultSingleValueRefreshRate
                    showingPicker = true
                } label: {
                    Label("Widget hinzufügen", systemImage: "plus.circle")
                }
                .disabled(!canAddWidget)
            }

            Section {
                Picker("Standard-Aktualisierung", selection: $config.defaultSingleValueRefreshRate) {
                    ForEach(SingleValueRefreshRate.allCases) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .onChange(of: config.defaultSingleValueRefreshRate) { _, _ in
                    config.save()
                }
            } header: {
                Text("Einzelwert-Aktualisierung")
            }

            Section {
                Button("Standard wiederherstellen") {
                    config = WatchMeterLayoutConfig()
                    config.save()
                }
                .font(.caption)
            }
        }
        .navigationTitle("Meter-Layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Fertig" : "Bearbeiten") {
                    isEditing.toggle()
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            WatchMeterWidgetPicker(
                currentConfig: widgetToEdit,
                unavailableKeys: unavailableKeys(excluding: widgetToEdit),
                defaultRefreshRate: config.defaultSingleValueRefreshRate,
                tileRefreshRate: $tileRefreshRate,
                onSelect: { type, valueType, refreshRate in
                    applySelection(type: type, valueType: valueType, refreshRate: refreshRate)
                    showingPicker = false
                    widgetToEdit = nil
                },
                onCancel: {
                    showingPicker = false
                    widgetToEdit = nil
                }
            )
        }
        .accessibilityIdentifier("watchMeterLayoutSettingsView")
    }

    private var canAddWidget: Bool {
        displayWidgets.count < 8
    }

    private var meterPreview: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 3),
            count: WatchMeterLayoutConfig.displayColumnCount
        )
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(displayWidgets) { widget in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: widget.type == .pegelmeter ? 36 : 22)
                    .overlay(
                        Image(systemName: widget.type.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.7))
                    )
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.6)))
    }

    private func unavailableKeys(excluding widget: WatchWidgetConfig?) -> Set<String> {
        var keys = Set(displayWidgets.map { WatchDashboardConfig.displayKey(for: $0) })
        if let widget {
            keys.remove(WatchDashboardConfig.displayKey(for: widget))
        }
        return keys
    }

    private func deleteWidget(_ widget: WatchWidgetConfig) {
        var list = displayWidgets
        list.removeAll { $0.id == widget.id }
        config.replaceOrderedWidgets(list)
        config.save()
    }

    private func moveWidget(_ widget: WatchWidgetConfig, offset: Int) {
        var list = displayWidgets
        guard let index = list.firstIndex(where: { $0.id == widget.id }) else { return }
        let destination = index + offset
        guard list.indices.contains(destination) else { return }
        list.swapAt(index, destination)
        config.replaceOrderedWidgets(list)
        config.save()
    }

    private func applySelection(
        type: WatchWidgetType,
        valueType: WatchSingleValueType?,
        refreshRate: SingleValueRefreshRate?
    ) {
        var list = displayWidgets
        if let existing = widgetToEdit, let index = list.firstIndex(where: { $0.id == existing.id }) {
            if type == .empty {
                list.remove(at: index)
            } else {
                list[index] = WatchWidgetConfig(
                    id: existing.id,
                    type: type,
                    position: index,
                    singleValueType: valueType,
                    singleValueRefreshRate: type == .singleValue ? refreshRate : nil
                )
            }
        } else if type != .empty, canAddWidget {
            list.append(
                WatchWidgetConfig(
                    type: type,
                    position: list.count,
                    singleValueType: valueType,
                    singleValueRefreshRate: type == .singleValue ? refreshRate : nil
                )
            )
        }
        config.replaceOrderedWidgets(list)
        config.save()
    }
}

// MARK: - Meter-only widget picker

struct WatchMeterWidgetPicker: View {
    let currentConfig: WatchWidgetConfig?
    let unavailableKeys: Set<String>
    let defaultRefreshRate: SingleValueRefreshRate
    @Binding var tileRefreshRate: SingleValueRefreshRate
    let onSelect: (WatchWidgetType, WatchSingleValueType?, SingleValueRefreshRate?) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if currentConfig != nil {
                    Section {
                        Button(role: .destructive) {
                            onSelect(.empty, nil, nil)
                        } label: {
                            Label("Widget entfernen", systemImage: "trash")
                        }
                    }
                }

                Section("Einzelwert-Aktualisierung") {
                    Picker("Rate", selection: $tileRefreshRate) {
                        ForEach(SingleValueRefreshRate.allCases) { rate in
                            Text(rate.displayName).tag(rate)
                        }
                    }
                }

                Section("Widget") {
                    ForEach(WatchWidgetType.meterFaceTypes) { type in
                        if type == .singleValue {
                            ForEach(WatchSingleValueType.allCases, id: \.self) { valueType in
                                pickerButton(
                                    title: valueType.displayName,
                                    icon: type.icon,
                                    key: WatchDashboardConfig.displayKey(
                                        for: WatchWidgetConfig(type: .singleValue, position: 0, singleValueType: valueType)
                                    ),
                                    selected: currentConfig?.type == .singleValue && currentConfig?.singleValueType == valueType
                                ) {
                                    onSelect(.singleValue, valueType, tileRefreshRate)
                                }
                            }
                        } else {
                            pickerButton(
                                title: type.rawValue,
                                icon: type.icon,
                                key: WatchDashboardConfig.displayKey(
                                    for: WatchWidgetConfig(type: type, position: 0)
                                ),
                                selected: currentConfig?.type == type
                            ) {
                                onSelect(type, nil, nil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Widget wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
            }
        }
    }

    private func pickerButton(
        title: String,
        icon: String,
        key: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                }
            }
        }
        .disabled(unavailableKeys.contains(key) && !selected)
    }
}

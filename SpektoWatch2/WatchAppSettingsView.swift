import SwiftUI
import Combine

/// iPhone editor for all watch-app settings: live source, meter layout, mic gain.
struct WatchAppSettingsView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @Environment(\.designAccent) private var accent
    @Binding var watchGain: Float

    @StateObject private var viewModel = WatchAppSettingsViewModel()
    @State private var widgetToEdit: WatchWidgetConfig?
    @State private var showingWidgetPicker = false

    var body: some View {
        List {
            reachabilitySection

            Section {
                Picker("Live-Messquelle", selection: $viewModel.measurementSourcePreference) {
                    Text(WatchMeasurementSourcePreference.auto.displayName)
                        .tag(WatchMeasurementSourcePreference.auto)
                    Text(WatchMeasurementSourcePreference.iPhone.displayName)
                        .tag(WatchMeasurementSourcePreference.iPhone)
                    Text(WatchMeasurementSourcePreference.appleWatch.displayName)
                        .tag(WatchMeasurementSourcePreference.appleWatch)
                }
                .pickerStyle(.inline)
            } header: {
                Text("Messquelle auf der Watch")
            } footer: {
                Text("Automatisch: iPhone-Spiegelung während der iPhone-Messung, sonst Watch-Mikrofon. Spektrogramm und Verlaufsgraph haben eigene Vollbild-Ansichten auf der Uhr.")
            }

            if viewModel.hasDashboardLevelMeter {
                Section {
                    Picker("Pegel-Ausrichtung", selection: $viewModel.dashboardLevelMeterOrientation) {
                        ForEach(LevelMeterOrientation.allCases) { orientation in
                            Text(orientation.displayName).tag(orientation)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Watch-Dashboard Pegel")
                } footer: {
                    Text("Gilt für das Pegel-Widget auf dem Watch-Dashboard (nicht die Meter-Ansicht).")
                }
            }

            Section {
                meterPreview
                    .frame(height: 120)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)

                ForEach(viewModel.meterDisplayWidgets) { widget in
                    Button {
                        widgetToEdit = widget
                        showingWidgetPicker = true
                    } label: {
                        meterWidgetRow(widget)
                    }
                }
                .onDelete(perform: viewModel.deleteMeterWidgets)
                .onMove(perform: viewModel.moveMeterWidgets)

                Button {
                    widgetToEdit = nil
                    showingWidgetPicker = true
                } label: {
                    Label("Kachel hinzufügen", systemImage: "plus.circle")
                }
                .disabled(!viewModel.canAddMeterWidget)
            } header: {
                Text("Meter-Ansicht (Pegelmesser + Werte)")
            } footer: {
                Text("Erste Kachel: Pegelmesser (große LAF-Anzeige). Darunter bis zu \(WatchMeterLayoutConfig.displayColumnCount) Spalten mit Einzelwerten.")
            }

            Section {
                Picker("Standard-Aktualisierung", selection: $viewModel.defaultSingleValueRefreshRate) {
                    ForEach(SingleValueRefreshRate.allCases) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Einzelwert-Aktualisierung")
            } footer: {
                Text("Gilt für Wert-Kacheln ohne eigene Rate. Pro Kachel beim Bearbeiten einstellbar.")
            }

            Section {
                HStack {
                    Text("0×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $watchGain, in: 0...10, step: 0.1)
                    Text("10×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(format: "Aktuell: %.1f×", watchGain))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Watch-Mikrofon-Verstärkung")
            } footer: {
                Text("Skaliert das Watch-Mikrofon-Signal vor der FFT (nur bei Watch als Quelle).")
            }
        }
        .polishedFormChrome()
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .safeAreaInset(edge: .bottom) { syncBar }
        .sheet(isPresented: $showingWidgetPicker) {
            MeterWidgetPickerSheet(
                currentConfig: widgetToEdit,
                unavailableKeys: viewModel.unavailableMeterKeys(excluding: widgetToEdit),
                defaultRefreshRate: viewModel.defaultSingleValueRefreshRate,
                onSelect: { type, valueType, refreshRate in
                    if let existing = widgetToEdit {
                        viewModel.updateMeterWidget(
                            existing,
                            type: type,
                            singleValueType: valueType,
                            singleValueRefreshRate: refreshRate
                        )
                    } else {
                        viewModel.addMeterWidget(
                            type: type,
                            singleValueType: valueType,
                            singleValueRefreshRate: refreshRate
                        )
                    }
                    showingWidgetPicker = false
                    widgetToEdit = nil
                }
            )
        }
        .onAppear {
            viewModel.reloadFromStorage()
            viewModel.reloadDashboardConfig(from: connectivityManager)
            viewModel.watchGain = watchGain
        }
        .onReceive(connectivityManager.$watchDashboardConfig.compactMap { $0 }) { config in
            viewModel.updateDashboardConfig(config)
        }
        .onChange(of: watchGain) { _, newValue in
            viewModel.watchGain = newValue
        }
        .accessibilityIdentifier("watchAppSettingsView")
    }

    @ViewBuilder
    private var reachabilitySection: some View {
        Section {
            HStack {
                Label(
                    connectivityManager.isReachable ? "Watch erreichbar" : "Watch nicht erreichbar",
                    systemImage: connectivityManager.isReachable ? "applewatch" : "applewatch.slash"
                )
                Spacer()
                Circle()
                    .fill(connectivityManager.isReachable ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
            .font(.subheadline)
        }
    }

    private var syncBar: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.syncToWatch(
                    connectivityManager: connectivityManager,
                    watchGain: watchGain
                )
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
                viewModel.resetToDefaults(
                    connectivityManager: connectivityManager,
                    watchGain: &watchGain
                )
            } label: {
                Text("Alle Watch-Einstellungen zurücksetzen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var meterPreview: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 4),
            count: WatchMeterLayoutConfig.displayColumnCount
        )
        let widgets = viewModel.meterDisplayWidgets
        let hero = widgets.first { $0.type == .pegelmeter }
        let tiles = widgets.filter { $0.type != .pegelmeter }

        return VStack(spacing: 4) {
            if hero != nil {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.mint.opacity(0.25))
                    .frame(height: 36)
                    .overlay(
                        Label("Pegelmesser", systemImage: WatchWidgetType.pegelmeter.icon)
                            .font(.caption2)
                    )
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(tiles) { widget in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.orange.opacity(0.22))
                        .frame(height: 22)
                        .overlay(
                            Image(systemName: widget.type.icon)
                                .font(.system(size: 9))
                        )
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.gray.opacity(0.45), lineWidth: 1.5)
                )
        )
    }

    private func meterWidgetRow(_ widget: WatchWidgetConfig) -> some View {
        HStack(spacing: 12) {
            Image(systemName: widget.type.icon)
                .foregroundStyle(previewColor(for: widget.type))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(widget.type.rawValue)
                if let valueType = widget.singleValueType {
                    Text(valueType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if widget.type == .singleValue {
                    let rate = viewModel.meterConfig.refreshRate(for: widget)
                    Text(rate.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func previewColor(for type: WatchWidgetType) -> Color {
        switch type {
        case .pegelmeter: return .mint
        case .singleValue: return .orange
        case .loudness: return .purple
        default: return .gray
        }
    }
}

// MARK: - Meter widget picker (Pegelmesser / Werte / Lautheit only)

private struct MeterWidgetPickerSheet: View {
    let currentConfig: WatchWidgetConfig?
    let unavailableKeys: Set<String>
    let defaultRefreshRate: SingleValueRefreshRate
    let onSelect: (WatchWidgetType, WatchSingleValueType?, SingleValueRefreshRate?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tileRefreshRate: SingleValueRefreshRate

    init(
        currentConfig: WatchWidgetConfig?,
        unavailableKeys: Set<String>,
        defaultRefreshRate: SingleValueRefreshRate,
        onSelect: @escaping (WatchWidgetType, WatchSingleValueType?, SingleValueRefreshRate?) -> Void
    ) {
        self.currentConfig = currentConfig
        self.unavailableKeys = unavailableKeys
        self.defaultRefreshRate = defaultRefreshRate
        self.onSelect = onSelect
        _tileRefreshRate = State(
            initialValue: currentConfig?.singleValueRefreshRate ?? defaultRefreshRate
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if currentConfig != nil {
                    Section {
                        Button(role: .destructive) {
                            onSelect(.empty, nil, nil)
                        } label: {
                            Label("Kachel entfernen", systemImage: "trash")
                        }
                    }
                }

                Section("Einzelwert-Aktualisierung") {
                    Picker("Rate", selection: $tileRefreshRate) {
                        ForEach(SingleValueRefreshRate.allCases) { rate in
                            Text(rate.displayName).tag(rate)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Kachel-Typ") {
                    ForEach(WatchWidgetType.meterFaceTypes) { type in
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
                                        onSelect(.singleValue, valueType, tileRefreshRate)
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
                                onSelect(type, nil, nil)
                            }
                        }
                    }
                }
            }
            .polishedFormChrome()
            .navigationTitle("Kachel wählen")
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
                        .foregroundStyle(.blue)
                }
            }
        }
        .disabled(isDisabled && !isSelected)
    }
}

// MARK: - View model

@MainActor
final class WatchAppSettingsViewModel: ObservableObject {
    @Published var measurementSourcePreference: WatchMeasurementSourcePreference = .auto
    @Published private(set) var meterConfig: WatchMeterLayoutConfig = WatchMeterLayoutConfig()
    @Published private(set) var dashboardConfig: WatchDashboardConfig = WatchDashboardConfig()
    @Published var dashboardLevelMeterOrientation: LevelMeterOrientation = .default {
        didSet {
            guard dashboardLevelMeterOrientation != oldValue else { return }
            viewModelApplyDashboardLevelMeterOrientation()
        }
    }
    @Published var defaultSingleValueRefreshRate: SingleValueRefreshRate = .default {
        didSet {
            guard defaultSingleValueRefreshRate != oldValue else { return }
            meterConfig.defaultSingleValueRefreshRate = defaultSingleValueRefreshRate
            meterConfig.save()
        }
    }
    var watchGain: Float = 1.0

    var meterDisplayWidgets: [WatchWidgetConfig] {
        meterConfig.orderedMeterWidgets
    }

    var canAddMeterWidget: Bool {
        meterDisplayWidgets.count < WatchMeterLayoutConfig.maxWidgetCount
    }

    var hasDashboardLevelMeter: Bool {
        dashboardConfig.orderedDisplayWidgets.contains { $0.type == .levelMeter }
    }

    func reloadFromStorage() {
        meterConfig = WatchMeterLayoutConfig.load()
        dashboardConfig = WatchDashboardConfig.load()
        reloadDashboardLevelMeterOrientationFromConfig()
        defaultSingleValueRefreshRate = meterConfig.defaultSingleValueRefreshRate
        if let raw = UserDefaults.standard.string(forKey: PersistenceKeys.Watch.measurementSourcePreference),
           let preference = WatchMeasurementSourcePreference(rawValue: raw) {
            measurementSourcePreference = preference
        } else {
            measurementSourcePreference = .auto
        }
    }

    func addMeterWidget(
        type: WatchWidgetType,
        singleValueType: WatchSingleValueType?,
        singleValueRefreshRate: SingleValueRefreshRate?
    ) {
        guard type != .empty, WatchMeterLayoutConfig.isMeterFaceType(type), canAddMeterWidget else { return }
        var widgets = meterDisplayWidgets
        widgets.append(
            WatchWidgetConfig(
                type: type,
                position: widgets.count,
                singleValueType: singleValueType,
                singleValueRefreshRate: type == .singleValue ? singleValueRefreshRate : nil
            )
        )
        meterConfig.replaceOrderedWidgets(widgets)
        meterConfig.save()
    }

    func updateMeterWidget(
        _ existing: WatchWidgetConfig,
        type: WatchWidgetType,
        singleValueType: WatchSingleValueType?,
        singleValueRefreshRate: SingleValueRefreshRate?
    ) {
        var widgets = meterDisplayWidgets
        guard let index = widgets.firstIndex(where: { $0.id == existing.id }) else { return }
        if type == .empty {
            widgets.remove(at: index)
        } else {
            widgets[index] = WatchWidgetConfig(
                id: existing.id,
                type: type,
                position: index,
                singleValueType: singleValueType,
                singleValueRefreshRate: type == .singleValue ? singleValueRefreshRate : nil
            )
        }
        meterConfig.replaceOrderedWidgets(widgets)
        meterConfig.save()
    }

    func deleteMeterWidgets(at offsets: IndexSet) {
        var widgets = meterDisplayWidgets
        widgets.remove(atOffsets: offsets)
        meterConfig.replaceOrderedWidgets(widgets)
        meterConfig.save()
    }

    func moveMeterWidgets(from source: IndexSet, to destination: Int) {
        var widgets = meterDisplayWidgets
        widgets.move(fromOffsets: source, toOffset: destination)
        meterConfig.replaceOrderedWidgets(widgets)
        meterConfig.save()
    }

    func unavailableMeterKeys(excluding widget: WatchWidgetConfig?) -> Set<String> {
        Set(
            meterDisplayWidgets
                .filter { $0.id != widget?.id }
                .map { WatchDashboardConfig.displayKey(for: $0) }
        )
    }

    func reloadDashboardConfig(from connectivityManager: WatchConnectivityManager) {
        if let remote = connectivityManager.watchDashboardConfig {
            dashboardConfig = remote
        } else {
            dashboardConfig = WatchDashboardConfig.load()
        }
        reloadDashboardLevelMeterOrientationFromConfig()
    }

    func updateDashboardConfig(_ config: WatchDashboardConfig) {
        dashboardConfig = config
        reloadDashboardLevelMeterOrientationFromConfig()
    }

    func syncToWatch(connectivityManager: WatchConnectivityManager, watchGain: Float) {
        self.watchGain = watchGain
        dashboardConfig.save()
        connectivityManager.sendWatchDashboardConfig(dashboardConfig)
        connectivityManager.sendWatchAppSettings(
            meterLayout: meterConfig,
            measurementSource: measurementSourcePreference,
            gain: watchGain
        )
    }

    func resetToDefaults(connectivityManager: WatchConnectivityManager, watchGain: inout Float) {
        meterConfig = WatchMeterLayoutConfig()
        dashboardConfig = WatchDashboardConfig()
        defaultSingleValueRefreshRate = meterConfig.defaultSingleValueRefreshRate
        reloadDashboardLevelMeterOrientationFromConfig()
        meterConfig.save()
        dashboardConfig.save()
        measurementSourcePreference = .auto
        watchGain = 1.0
        UserDefaults.standard.set(watchGain, forKey: PersistenceKeys.Watch.gain)
        syncToWatch(connectivityManager: connectivityManager, watchGain: watchGain)
    }

    func reloadDashboardLevelMeterOrientationFromConfig() {
        let meter = dashboardConfig.orderedDisplayWidgets.first { $0.type == .levelMeter }
        let resolved = meter?.resolvedLevelMeterOrientation() ?? .default
        if dashboardLevelMeterOrientation != resolved {
            dashboardLevelMeterOrientation = resolved
        }
    }

    private func viewModelApplyDashboardLevelMeterOrientation() {
        guard let meter = dashboardConfig.orderedDisplayWidgets.first(where: { $0.type == .levelMeter }),
              let index = dashboardConfig.widgets.firstIndex(where: { $0.id == meter.id }) else { return }
        dashboardConfig.widgets[index].levelMeterOrientation = dashboardLevelMeterOrientation
        dashboardConfig.version += 1
        dashboardConfig.save()
    }
}

/// Legacy entry point — redirects to the unified watch settings screen.
typealias WatchDashboardSettingsView = WatchAppSettingsView

#Preview {
    NavigationStack {
        WatchAppSettingsView(watchGain: .constant(1.0))
            .environmentObject(WatchConnectivityManager())
    }
}

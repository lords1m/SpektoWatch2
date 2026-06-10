import SwiftUI

/// Customizable meter face: Pegelmesser hero + single-value tiles.
struct WatchCustomMeterView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @Environment(\.watchTabLiveUpdatesActive) private var tabLiveUpdatesActive

    @State private var config: WatchMeterLayoutConfig = WatchMeterLayoutConfig.load()
    @State private var widgetToEdit: WatchWidgetConfig?
    @State private var showingWidgetPicker = false
    @State private var showingLayoutEditor = false
    @State private var tileRefreshRate: SingleValueRefreshRate = .default

    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: WatchMeterLayoutConfig.displayColumnCount
    )

    private var heroWidget: WatchWidgetConfig? {
        config.orderedMeterWidgets.first { $0.type == .pegelmeter }
    }

    private var gridWidgets: [WatchWidgetConfig] {
        config.orderedMeterWidgets.filter { $0.type != .pegelmeter }
    }

    var body: some View {
        ZStack {
            WatchAppBackground().ignoresSafeArea()

            VStack(spacing: 4) {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        showingLayoutEditor = true
                    } label: {
                        Label("Layout bearbeiten", systemImage: "square.grid.3x3")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchMeterLayoutEditButton")
                }
                .padding(.horizontal, 2)

                if let heroWidget {
                    editableWidget(heroWidget, height: 78)
                }

                if !gridWidgets.isEmpty {
                    LazyVGrid(columns: gridColumns, spacing: 4) {
                        ForEach(gridWidgets) { widget in
                            editableWidget(widget, height: 48)
                        }
                    }
                }

                Spacer(minLength: 0)
                WatchLiveCaptureFooter()
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .accessibilityIdentifier("watchCustomMeterView")
        .onAppear {
            reloadConfig()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchMeterLayoutConfigChanged)) { _ in
            reloadConfig()
        }
        .sheet(isPresented: $showingWidgetPicker) {
            WatchMeterWidgetPicker(
                currentConfig: widgetToEdit,
                unavailableKeys: unavailableKeys(excluding: widgetToEdit),
                defaultRefreshRate: config.defaultSingleValueRefreshRate,
                tileRefreshRate: $tileRefreshRate,
                onSelect: { type, valueType, refreshRate in
                    applySelection(type: type, valueType: valueType, refreshRate: refreshRate)
                    showingWidgetPicker = false
                    widgetToEdit = nil
                },
                onCancel: {
                    showingWidgetPicker = false
                    widgetToEdit = nil
                }
            )
        }
        .sheet(isPresented: $showingLayoutEditor) {
            NavigationStack {
                WatchMeterLayoutSettingsView()
            }
        }
    }

    private func reloadConfig() {
        config = WatchMeterLayoutConfig.load()
    }

    private func editableWidget(_ widget: WatchWidgetConfig, height: CGFloat) -> some View {
        widgetView(for: widget)
            .frame(height: height)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    guard tabLiveUpdatesActive else { return }
                    widgetToEdit = widget
                    tileRefreshRate = config.refreshRate(for: widget)
                    showingWidgetPicker = true
                    WKInterfaceDevice.current().play(.click)
                }
            )
            .accessibilityHint("Gedrückt halten zum Bearbeiten")
    }

    @ViewBuilder
    private func widgetView(for widget: WatchWidgetConfig) -> some View {
        switch widget.type {
        case .pegelmeter:
            WatchPegelmeterWidget()
        case .singleValue:
            if let valueType = widget.singleValueType {
                WatchSingleValueWidget(
                    valueType: valueType,
                    refreshRate: config.refreshRate(for: widget)
                )
            } else {
                Color.clear
            }
        case .loudness:
            WatchLoudnessWidget()
        default:
            Color.clear
        }
    }

    private var canAddWidget: Bool {
        config.orderedMeterWidgets.count < WatchMeterLayoutConfig.maxWidgetCount
    }

    private func unavailableKeys(excluding widget: WatchWidgetConfig?) -> Set<String> {
        var keys = Set(config.orderedMeterWidgets.map { WatchDashboardConfig.displayKey(for: $0) })
        if let widget {
            keys.remove(WatchDashboardConfig.displayKey(for: widget))
        }
        return keys
    }

    private func applySelection(
        type: WatchWidgetType,
        valueType: WatchSingleValueType?,
        refreshRate: SingleValueRefreshRate?
    ) {
        var list = config.orderedMeterWidgets
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

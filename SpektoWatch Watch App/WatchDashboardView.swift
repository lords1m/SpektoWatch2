import SwiftUI

struct WatchDashboardView: View {
    @Environment(WatchConnectivityManager.self) private var connectivityManager

    @State private var config: WatchDashboardConfig = WatchDashboardConfig.load()

    private let gridItems: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    private var activeWidgets: [WatchWidgetConfig] {
        config.orderedDisplayWidgets
    }

    var body: some View {
        ZStack {
            WatchAppBackground().ignoresSafeArea()

            VStack(spacing: 2) {
                LazyVGrid(columns: gridItems, spacing: 4) {
                    ForEach(activeWidgets) { widget in
                        widgetView(for: widget)
                            .frame(height: dashboardCellHeight(for: widget))
                            .gridCellColumns(dashboardCellSpan(for: widget))
                    }
                }
                .frame(maxHeight: .infinity)

                WatchLiveCaptureFooter()
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
        }
        .accessibilityIdentifier("watchDashboardView")
        .onAppear {
            if let received = connectivityManager.watchDashboardConfig {
                config = received
            }
        }
        .onChange(of: connectivityManager.watchDashboardConfig) { _, newConfig in
            guard let newConfig else { return }
            config = newConfig
            newConfig.save()
        }
    }

    @ViewBuilder
    private func widgetView(for widget: WatchWidgetConfig) -> some View {
        switch widget.type {
        case .spectrogram:
            WatchSpectrogramWidget()
        case .levelMeter:
            WatchLevelMeterWidget(orientation: widget.resolvedLevelMeterOrientation())
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
        case .empty:
            Color.clear
        }
    }

    private func dashboardCellSpan(for widget: WatchWidgetConfig) -> Int {
        guard widget.type == .levelMeter else { return 1 }
        return widget.resolvedLevelMeterOrientation() == .horizontal ? 2 : 1
    }

    private func dashboardCellHeight(for widget: WatchWidgetConfig) -> CGFloat {
        switch widget.type {
        case .levelMeter:
            return widget.resolvedLevelMeterOrientation() == .vertical ? 72 : 28
        default:
            return 52
        }
    }
}

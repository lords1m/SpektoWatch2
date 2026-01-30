import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @EnvironmentObject var audioEngine: WatchAudioEngine

    @State private var config: WatchDashboardConfig = WatchDashboardConfig.load()

    // 4x4 Grid
    private let columns = 4
    private let rows = 4

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / CGFloat(columns)
            let cellHeight = geometry.size.height / CGFloat(rows)

            ZStack {
                // Background
                Color.black.edgesIgnoringSafeArea(.all)

                // Render widgets
                ForEach(groupedWidgets, id: \.id) { group in
                    widgetView(for: group, cellWidth: cellWidth, cellHeight: cellHeight)
                        .position(
                            x: CGFloat(group.startCol) * cellWidth + group.width * cellWidth / 2,
                            y: CGFloat(group.startRow) * cellHeight + group.height * cellHeight / 2
                        )
                }

                // Control overlay
                VStack {
                    Spacer()
                    controlBar
                }
            }
        }
        .onReceive(connectivityManager.$watchDashboardConfig) { newConfig in
            if let newConfig = newConfig, newConfig != config {
                config = newConfig
                config.save()
            }
        }
    }

    // MARK: - Widget Rendering

    @ViewBuilder
    private func widgetView(for group: WidgetGroup, cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        let width = group.width * cellWidth - 2
        let height = group.height * cellHeight - 2

        Group {
            switch group.type {
            case .spectrogram:
                WatchSpectrogramWidget()
                    .frame(width: width, height: height)
                    .cornerRadius(4)

            case .levelMeter:
                WatchLevelMeterWidget()
                    .frame(width: width, height: height)
                    .cornerRadius(4)

            case .singleValue:
                if let valueType = group.singleValueType {
                    WatchSingleValueWidget(valueType: valueType)
                        .frame(width: width, height: height)
                        .cornerRadius(4)
                }

            case .empty:
                EmptyView()
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(connectivityManager.isReachable ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Spacer()

            // Play button
            Button(action: {
                audioEngine.startRecording()
            }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
            }
            .frame(width: 24, height: 24)
            .background(audioEngine.isRecording ? Color.green : Color.green.opacity(0.3))
            .clipShape(Circle())

            // Stop button
            Button(action: {
                audioEngine.stopRecording()
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10))
            }
            .frame(width: 24, height: 24)
            .background(audioEngine.isRecording ? Color.red.opacity(0.3) : Color.red.opacity(0.15))
            .clipShape(Circle())
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Widget Grouping

    private var groupedWidgets: [WidgetGroup] {
        var groups: [WidgetGroup] = []
        var processedPositions: Set<Int> = []

        // Find connected widget groups
        for widget in config.widgets where !processedPositions.contains(widget.position) {
            let connectedPositions = findConnectedPositions(
                for: widget.type,
                startingAt: widget.position,
                in: config.widgets
            )

            processedPositions.formUnion(connectedPositions)

            if widget.type != .empty && !connectedPositions.isEmpty {
                let group = WidgetGroup(
                    type: widget.type,
                    positions: connectedPositions,
                    columns: columns,
                    singleValueType: widget.singleValueType
                )
                groups.append(group)
            }
        }

        return groups
    }

    private func findConnectedPositions(for type: WatchWidgetType, startingAt position: Int, in widgets: [WatchWidgetConfig]) -> Set<Int> {
        var connected: Set<Int> = [position]
        var toCheck: Set<Int> = [position]

        while !toCheck.isEmpty {
            let current = toCheck.removeFirst()
            let currentRow = current / columns
            let currentCol = current % columns

            // Check adjacent positions (up, down, left, right)
            let adjacent = [
                (currentRow > 0) ? current - columns : nil,           // up
                (currentRow < rows - 1) ? current + columns : nil,    // down
                (currentCol > 0) ? current - 1 : nil,                 // left
                (currentCol < columns - 1) ? current + 1 : nil        // right
            ].compactMap { $0 }

            for adj in adjacent {
                if !connected.contains(adj),
                   let adjWidget = widgets.first(where: { $0.position == adj }),
                   adjWidget.type == type {
                    connected.insert(adj)
                    toCheck.insert(adj)
                }
            }
        }

        return connected
    }
}

// MARK: - Widget Group Helper

struct WidgetGroup: Identifiable {
    let id = UUID()
    let type: WatchWidgetType
    let positions: Set<Int>
    let columns: Int
    let singleValueType: WatchSingleValueType?

    var startRow: Int {
        positions.map { $0 / columns }.min() ?? 0
    }

    var startCol: Int {
        positions.map { $0 % columns }.min() ?? 0
    }

    var endRow: Int {
        positions.map { $0 / columns }.max() ?? 0
    }

    var endCol: Int {
        positions.map { $0 % columns }.max() ?? 0
    }

    var width: CGFloat {
        CGFloat(endCol - startCol + 1)
    }

    var height: CGFloat {
        CGFloat(endRow - startRow + 1)
    }
}

import SwiftUI
import Combine

struct WatchDashboardSettingsView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @StateObject private var viewModel = WatchDashboardSettingsViewModel()
    @State private var selectedPosition: Int?
    @State private var showingWidgetPicker = false

    private let columns = 4
    private let rows = 4

    var body: some View {
        VStack(spacing: 16) {
            // Header
            Text("Apple Watch Layout")
                .font(.headline)

            // Watch preview (4x4 grid)
            watchPreview
                .aspectRatio(1.0, contentMode: .fit)
                .padding(.horizontal, 40)

            // Instructions
            Text("Tippe auf ein Feld, um das Widget zu ändern")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Sync button
            Button(action: {
                viewModel.syncToWatch(connectivityManager: connectivityManager)
            }) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Mit Watch synchronisieren")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)

            // Reset button
            Button(action: {
                viewModel.resetToDefault(connectivityManager: connectivityManager)
            }) {
                Text("Auf Standard zurüccksetzen")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .sheet(isPresented: $showingWidgetPicker) {
            if let position = selectedPosition {
                WidgetPickerSheet(
                    position: position,
                    currentConfig: viewModel.config.widget(at: position),
                    onSelect: { type, valueType in
                        viewModel.setWidget(at: position, type: type, singleValueType: valueType)
                        showingWidgetPicker = false
                    }
                )
            }
        }
    }

    // MARK: - Watch Preview Grid

    private var watchPreview: some View {
        GeometryReader { geometry in
            let cellSize = min(geometry.size.width, geometry.size.height) / CGFloat(columns)

            ZStack {
                // Watch frame
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray, lineWidth: 3)
                    )

                // Grid cells
                VStack(spacing: 1) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 1) {
                            ForEach(0..<columns, id: \.self) { col in
                                let position = row * columns + col
                                gridCell(for: position, size: cellSize - 2)
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private func gridCell(for position: Int, size: CGFloat) -> some View {
        let widget = viewModel.config.widget(at: position)
        let isPartOfLarger = viewModel.isSecondaryCell(at: position)

        Button(action: {
            if !isPartOfLarger {
                selectedPosition = position
                showingWidgetPicker = true
            }
        }) {
            ZStack {
                if isPartOfLarger {
                    // Part of a larger widget - show connection
                    Color.clear
                } else if let widget = widget {
                    // Show widget preview
                    widgetPreview(for: widget)
                } else {
                    // Empty cell
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "plus")
                                .foregroundColor(.gray)
                        )
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isPartOfLarger)
    }

    @ViewBuilder
    private func widgetPreview(for widget: WatchWidgetConfig) -> some View {
        let color: Color = {
            switch widget.type {
            case .spectrogram: return .blue
            case .levelMeter: return .green
            case .singleValue: return .orange
            case .loudness: return .purple
            case .empty: return .gray.opacity(0.2)
            }
        }()

        RoundedRectangle(cornerRadius: 4)
            .fill(color.opacity(0.3))
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: widget.type.icon)
                        .font(.system(size: 12))
                    if let valueType = widget.singleValueType {
                        Text(valueType.displayName)
                            .font(.system(size: 8))
                    }
                }
                .foregroundColor(color)
            )
    }
}

// MARK: - Widget Picker Sheet

struct WidgetPickerSheet: View {
    let position: Int
    let currentConfig: WatchWidgetConfig?
    let onSelect: (WatchWidgetType, WatchSingleValueType?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Widget-Typ") {
                    ForEach(WatchWidgetType.allCases) { type in
                        if type == .singleValue {
                            // Single value has sub-options
                            DisclosureGroup {
                                ForEach(WatchSingleValueType.allCases, id: \.self) { valueType in
                                    Button(action: {
                                        onSelect(.singleValue, valueType)
                                    }) {
                                        HStack {
                                            Text(valueType.displayName)
                                            Spacer()
                                            if currentConfig?.type == .singleValue &&
                                               currentConfig?.singleValueType == valueType {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label(type.rawValue, systemImage: type.icon)
                            }
                        } else {
                            Button(action: {
                                onSelect(type, nil)
                            }) {
                                HStack {
                                    Label(type.rawValue, systemImage: type.icon)
                                    Spacer()
                                    if currentConfig?.type == type && type != .singleValue {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Widget wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - View Model

class WatchDashboardSettingsViewModel: ObservableObject {
    @Published var config: WatchDashboardConfig

    init() {
        self.config = WatchDashboardConfig.load()
    }

    func setWidget(at position: Int, type: WatchWidgetType, singleValueType: WatchSingleValueType? = nil) {
        // Remove existing widget at this position
        config.widgets.removeAll { $0.position == position }

        // Add new widget
        if type != .empty {
            let newWidget = WatchWidgetConfig(
                type: type,
                position: position,
                singleValueType: singleValueType
            )
            config.widgets.append(newWidget)
        }

        config.version += 1
        config.save()
    }

    func isSecondaryCell(at position: Int) -> Bool {
        // Check if this position is part of a multi-cell widget but not the primary cell
        let sameTypeWidgets = Dictionary(grouping: config.widgets, by: { $0.type })

        for (type, widgets) in sameTypeWidgets where type != .empty && type != .singleValue {
            let positions = Set(widgets.map { $0.position })
            if positions.count > 1 && positions.contains(position) {
                // This is part of a multi-cell widget
                // Check if it's adjacent to another cell of the same type
                let minPosition = positions.min() ?? position
                return position != minPosition && isAdjacent(position, to: positions)
            }
        }
        return false
    }

    private func isAdjacent(_ position: Int, to positions: Set<Int>) -> Bool {
        let row = position / 4
        let col = position % 4

        let adjacent = [
            row > 0 ? position - 4 : nil,
            row < 3 ? position + 4 : nil,
            col > 0 ? position - 1 : nil,
            col < 3 ? position + 1 : nil
        ].compactMap { $0 }

        return adjacent.contains { positions.contains($0) }
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

// MARK: - Preview

#Preview {
    WatchDashboardSettingsView()
}

import SwiftUI
import Combine

enum WatchStylePalette {
    static let accentBlue = Color(red: 0.23, green: 0.64, blue: 1.0)
    static let cardBorder = Color.white.opacity(0.22)
    static let cardShadow = Color.black.opacity(0.28)
}

struct WatchAppBackground: View {
    var body: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.14),
                    Color(red: 0.03, green: 0.04, blue: 0.06),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.clear
                ],
                center: .top,
                startRadius: 0,
                endRadius: 180
            )
        }
    }
}

struct WatchGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(WatchStylePalette.cardBorder, lineWidth: 1)
            )
            .shadow(color: WatchStylePalette.cardShadow, radius: 6, x: 0, y: 3)
    }
}

struct WatchGlassBar: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 7, x: 0, y: 4)
    }
}

extension View {
    func watchGlassCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(WatchGlassCard(cornerRadius: cornerRadius))
    }

    func watchGlassBar(cornerRadius: CGFloat = 14) -> some View {
        modifier(WatchGlassBar(cornerRadius: cornerRadius))
    }
}

struct WatchDashboardView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @EnvironmentObject var audioEngine: WatchAudioEngine

    @State private var config: WatchDashboardConfig = WatchDashboardConfig.load()

    private var isRecording: Bool { audioEngine.isRecording }
    private let gridItems: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    /// Deduplizierte Widgets aus der Config, sortiert nach Position.
    /// Multi-Cell-Typen (spectrogram, levelMeter, loudness) werden nur einmal gerendert.
    /// Empty-Slots werden übersprungen.
    private var activeWidgets: [WatchWidgetConfig] {
        var seenTypes = Set<String>()
        return config.widgets
            .sorted { $0.position < $1.position }
            .filter { widget in
                guard widget.type != .empty else { return false }
                let key: String
                if widget.type == .singleValue {
                    key = "singleValue-\(widget.singleValueType?.rawValue ?? "")"
                } else {
                    key = widget.type.rawValue
                }
                return seenTypes.insert(key).inserted
            }
    }

    var body: some View {
        ZStack {
            WatchAppBackground().ignoresSafeArea()

            VStack(spacing: 2) {
                LazyVGrid(columns: gridItems, spacing: 4) {
                    ForEach(activeWidgets) { widget in
                        widgetView(for: widget)
                            .frame(height: 52)
                    }
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Circle()
                        .fill(isRecording ? Color.red : (connectivityManager.isReachable ? Color.green : Color.gray))
                        .frame(width: 4, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: isRecording)
                    Spacer()
                    recordButton
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
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
        .onReceive(connectivityManager.$watchDashboardConfig.compactMap { $0 }) { newConfig in
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
            WatchLevelMeterWidget()
        case .singleValue:
            if let valueType = widget.singleValueType {
                WatchSingleValueWidget(valueType: valueType)
            } else {
                Color.clear
            }
        case .loudness:
            WatchLoudnessWidget()
        case .empty:
            Color.clear
        }
    }

    private var recordButton: some View {
        Button(action: {
            if isRecording {
                audioEngine.stopRecording()
                connectivityManager.requestWearableRecordingStop()
            } else {
                connectivityManager.requestWearableRecordingStart()
                audioEngine.startRecording()
            }
            WKInterfaceDevice.current().play(.success)
        }) {
            Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(
                        isRecording
                            ? Color.red.opacity(0.80)
                            : WatchStylePalette.accentBlue.opacity(0.80)
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

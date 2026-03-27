import SwiftUI

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

    @State private var crownValue: Double = 0.0
    @State private var isArmed: Bool = false
    @FocusState private var crownFocused: Bool

    private var isRecording: Bool { audioEngine.isRecording }

    private let gridItems: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)
    private let values: [WatchSingleValueType] = [.laeq, .lafMax, .lafMin, .lceq]

    var body: some View {
        ZStack {
            WatchAppBackground().ignoresSafeArea()

            VStack(spacing: 6) {
                statusHeader

                LazyVGrid(columns: gridItems, spacing: 6) {
                    ForEach(values, id: \.self) { valueType in
                        WatchSingleValueWidget(valueType: valueType)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)

                Spacer(minLength: 4)

                controlBar
            }
        }
        .focusable(true)
        .focused($crownFocused)
        .digitalCrownRotation($crownValue, from: 0.0, through: 1.0, by: 0.05, sensitivity: .medium, isContinuous: true)
        .onChange(of: crownValue) { _, newValue in
            let armed = newValue >= 0.7
            if armed != isArmed {
                let generator = WKInterfaceDevice.current()
                generator.play(.click)
            }
            isArmed = armed
        }
        .onAppear {
            crownFocused = true
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchStylePalette.accentBlue)

            Text("Dashboard")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Circle()
                    .fill(connectivityManager.isReachable ? .green : .red)
                    .frame(width: 6, height: 6)
                Text(connectivityManager.isReachable ? "Verbunden" : "Offline")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .watchGlassBar(cornerRadius: 12)
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(connectivityManager.isReachable ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Spacer()

            Button(action: {
                guard isArmed else { return }
                if isRecording {
                    connectivityManager.requestRecordingStop()
                } else {
                    connectivityManager.requestRecordingStart()
                }
                isArmed = false
                crownValue = 0.0
                WKInterfaceDevice.current().play(.success)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isRecording ? "stop.fill" : "play.fill")
                        .font(.system(size: 12))
                    Text(isArmed ? "Tippen" : "Drehen")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(isArmed ? WatchStylePalette.accentBlue.opacity(0.90) : Color.white.opacity(0.14))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .watchGlassBar(cornerRadius: 14)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }
}

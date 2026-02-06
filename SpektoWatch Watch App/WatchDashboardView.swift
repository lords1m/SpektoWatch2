import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject private var connectivityManager: WatchConnectivityManager
    @EnvironmentObject var audioEngine: WatchAudioEngine

    @State private var crownValue: Double = 0.0
    @State private var isArmed: Bool = false
    @State private var isRecording: Bool = false
    @FocusState private var crownFocused: Bool

    private let gridItems: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)
    private let values: [WatchSingleValueType] = [.laeq, .lafMax, .lafMin, .lceq]

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 6) {
                LazyVGrid(columns: gridItems, spacing: 6) {
                    ForEach(values, id: \.self) { valueType in
                        WatchSingleValueWidget(valueType: valueType)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
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
                isRecording.toggle()
                isArmed = false
                crownValue = 0.0
                WKInterfaceDevice.current().play(.success)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isRecording ? "stop.fill" : "play.fill")
                        .font(.system(size: 12))
                    Text(isArmed ? "Tippen" : "Drehen")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(isArmed ? Color.blue.opacity(0.6) : Color.white.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

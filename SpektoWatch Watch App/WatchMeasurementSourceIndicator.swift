import SwiftUI

/// Compact pill showing which device currently supplies live measurements.
struct WatchMeasurementSourceIndicator: View {
    @EnvironmentObject private var audioEngine: WatchAudioEngine

    private let watchAccent = Color(red: 0.45, green: 0.93, blue: 0.55)

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 8, weight: .semibold))
            Text(labelText)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.black.opacity(0.5))
        )
        .overlay(
            Capsule().strokeBorder(borderColor, lineWidth: 0.5)
        )
        .accessibilityIdentifier("watchMeasurementSourceIndicator")
        .accessibilityLabel(accessibilityText)
    }

    private var labelText: String {
        switch audioEngine.measurementSourcePreference {
        case .auto:
            switch audioEngine.activeMeasurementSource {
            case .iPhoneMirror:
                return "Auto · iPhone"
            case .watchMic:
                return "Auto · Watch"
            case .idle:
                return "Auto"
            }
        case .iPhone:
            return audioEngine.activeMeasurementSource == .iPhoneMirror ? "iPhone" : "iPhone …"
        case .appleWatch:
            return "Watch"
        }
    }

    private var iconName: String {
        switch audioEngine.activeMeasurementSource {
        case .iPhoneMirror:
            return "iphone"
        case .watchMic:
            return "applewatch"
        case .idle:
            return audioEngine.measurementSourcePreference.systemImageName
        }
    }

    private var foregroundColor: Color {
        switch audioEngine.activeMeasurementSource {
        case .iPhoneMirror:
            return WatchStylePalette.accentBlue
        case .watchMic:
            return watchAccent
        case .idle:
            return .white.opacity(0.45)
        }
    }

    private var borderColor: Color {
        audioEngine.activeMeasurementSource == .iPhoneMirror
            ? WatchStylePalette.accentBlue.opacity(0.55)
            : Color.white.opacity(0.18)
    }

    private var accessibilityText: String {
        switch audioEngine.activeMeasurementSource {
        case .iPhoneMirror:
            return "Messquelle: iPhone-Spiegelung"
        case .watchMic:
            return "Messquelle: Apple Watch Mikrofon"
        case .idle:
            return "Messquelle: keine Live-Daten"
        }
    }
}

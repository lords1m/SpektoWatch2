import SwiftUI

/// Compact 1×1 Home-Screen launcher tile. Mounts zero Metal drawables or
/// 15 Hz AudioEngine subscriptions so idle icons cost negligible CPU/battery.
struct FeatureIconTileView: View {
    let widget: WidgetConfiguration
    @Environment(AppServices.self) private var services
    @Environment(\.designAccent) private var accent
    @State private var isPressed = false

    private var badgeText: String? {
        switch widget.type {
        case .recordings:
            let count = services.recordingManager.recordings.count
            return count > 0 ? "\(count)" : nil
        case .singleValue:
            return widget.settings["metric"] ?? WidgetSettings.defaultSingleValueMetric
        default:
            return nil
        }
    }

    private var iconTint: Color {
        switch widget.type {
        case .recordings:         return FerriteStatus.recording
        case .toneGenerator:      return FerriteStatus.info
        case .settings:           return FerriteColor.labelSecondary
        default:                  return accent
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // Ferrite tile: square, ink outline, ink symbol; the line
                // colour appears only as the 6pt top bar fill.
                Rectangle()
                    .fill(FerriteColor.surface)
                    .overlay(alignment: .top) {
                        Rectangle().fill(iconTint).frame(height: FerriteStroke.bar)
                    }
                    .overlay(Rectangle().strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: widget.type.sfSymbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(FerriteColor.label)
                            .offset(y: FerriteStroke.bar / 2)
                    }

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(StatusColor.badge))
                        .offset(x: 6, y: -4)
                }
            }

            Text(widget.type.rawValue)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(widget.type.rawValue)
        .accessibilityHint("Icon. Tippen zum Öffnen.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("featureIconTile-\(widget.type.rawValue)")
    }
}

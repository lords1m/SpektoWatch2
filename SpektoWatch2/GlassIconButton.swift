import SwiftUI

/// Circular glass icon button — the shared chrome control used in the
/// dashboard header, the widget-card edit overlay, and the control bar.
/// Previously triplicated; extracting it puts the iOS 26 accessibility
/// workaround (below) in exactly one place.
///
/// iOS 26 note: with PlainButtonStyle the Button wrapper is accessibility-
/// transparent, and `.accessibilityElement(children: .ignore)` on an inner
/// container triggers parent-identifier inheritance (iOS 26 regression).
/// Identifier, label and value therefore sit directly on the Image leaf —
/// no intermediate accessibility wrapper.
struct GlassIconButton: View {
    let symbol: String
    var iconSize: CGFloat = 14
    var diameter: CGFloat = 34
    let identifier: String
    let label: String
    /// Optional accessibility value (e.g. "3 gespeichert" on the recordings button).
    var value: String?
    /// Optional badge count rendered as a red bubble; hidden when 0.
    var badgeCount: Int = 0
    var badgeOffset: CGPoint = CGPoint(x: 10, y: -10)
    /// Set when the button sits under a parent `.onDrag` that would otherwise
    /// swallow the tap (widget-card edit overlay). Touch then fires via the
    /// high-priority gesture, VoiceOver activation via the Button action —
    /// the action must therefore be idempotent (e.g. presenting a sheet).
    var usesHighPriorityTap: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                icon
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(StatusColor.badge)
                        .clipShape(Circle())
                        .offset(x: badgeOffset.x, y: badgeOffset.y)
                }
            }
        }
        .buttonStyle(.plain)
        .modifier(HighPriorityTap(enabled: usesHighPriorityTap, action: action))
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(.thinMaterial))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
            .contentShape(Circle())
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(label)
            // Only emit a value when one is set — passing an empty string still
            // reads as a (blank) value to VoiceOver rather than no value.
            .modifier(OptionalAccessibilityValue(value: value))
            .accessibilityAddTraits(.isButton)
    }
}

private struct OptionalAccessibilityValue: ViewModifier {
    let value: String?

    func body(content: Content) -> some View {
        if let value, !value.isEmpty {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}

private struct HighPriorityTap: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.highPriorityGesture(
                TapGesture().onEnded {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action()
                }
            )
        } else {
            content
        }
    }
}

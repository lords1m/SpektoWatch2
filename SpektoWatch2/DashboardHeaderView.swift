import SwiftUI

/// Floating header pill — eyebrow + title on the left, three glass icon buttons on the right.
/// Edit-mode variant collapses to eyebrow "LAYOUT BEARBEITEN" + an add-widget button and a Done button.
struct DashboardHeaderView: View {
    @Binding var isEditMode: Bool
    var currentLayoutName: String
    var onAddWidget: () -> Void
    var onAddLayout: () -> Void
    var onSaveLayout: () -> Void
    var onShowLayouts: () -> Void
    var onShowSettings: () -> Void

    @Environment(\.designAccent) private var accent

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditMode ? "LAYOUT BEARBEITEN" : "DASHBOARD · LIVE")
                    .font(.eyebrow(size: 9))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(currentLayoutName)
                    .font(.headerTitle())
                    .kerning(-0.34)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if !isEditMode {
                    glassIconButton("gearshape.fill", id: "settingsButton", action: onShowSettings)
                    glassIconButton("square.stack.3d.up", id: "layoutsButton", action: onShowLayouts)
                } else {
                    // In edit mode show an "Add Widget" button alongside the Done button.
                    glassIconButton("plus", id: "addWidgetButton", action: onAddWidget)
                }

                Button(action: toggleEdit) {
                    // In iOS 26, PlainButtonStyle makes the Button wrapper accessibility-
                    // transparent. .accessibilityElement(children: .ignore) on an inner
                    // container triggers parent-identifier inheritance (iOS 26 regression).
                    // Identifiers are placed directly on the leaf elements (Image / Text)
                    // instead, with no intermediate .accessibilityElement wrapper.
                    if isEditMode {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                            Text("Fertig")
                                .font(.system(size: 13, weight: .semibold))
                                .accessibilityIdentifier("editDashboardButton")
                                .accessibilityLabel("Bearbeiten beenden")
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(accent))
                        .shadow(color: accent.opacity(0.5), radius: 10)
                    } else {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.thinMaterial))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                            .accessibilityIdentifier("editDashboardButton")
                            .accessibilityLabel("Layout bearbeiten")
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .floatingPill(cornerRadius: 28)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        // NOTE: No .accessibilityIdentifier("dashboardHeaderView") — same iOS 26 reason
        // as ControlBarView: named container identifiers override leaf button identifiers.
    }

    private func glassIconButton(_ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Identifier directly on the Image leaf — .accessibilityElement(children: .ignore)
            // on an inner container triggers parent-identifier inheritance in iOS 26;
            // placing the identifier on the leaf Image avoids that regression.
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.thinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                .accessibilityIdentifier(id)
        }
        .buttonStyle(.plain)
    }

    private func toggleEdit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isEditMode.toggle()
        }
    }
}

// Equatable conformance so .equatable() in ModularDashboardView can skip
// body re-evaluation when the two values that drive visible content are
// unchanged. Callbacks are intentionally excluded — they are stable
// across renders and don't affect the rendered output (M19 task-5).
extension DashboardHeaderView: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isEditMode == rhs.isEditMode &&
        lhs.currentLayoutName == rhs.currentLayoutName
    }
}

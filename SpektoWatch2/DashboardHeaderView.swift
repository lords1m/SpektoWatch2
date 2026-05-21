import SwiftUI

/// Floating header pill — eyebrow + title on the left, three glass icon buttons on the right.
/// Edit-mode variant collapses to eyebrow "LAYOUT BEARBEITEN" + a single green "Done" button.
struct DashboardHeaderView: View {
    @Binding var isEditMode: Bool
    var currentLayoutName: String
    var onAddWidget: () -> Void
    var onAddLayout: () -> Void
    var onSaveLayout: () -> Void
    var onShowLayouts: () -> Void
    var onShowSettings: () -> Void
    var onShowTweaks: () -> Void = {}

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
                        .accessibilityIdentifier("layoutsButton")
                    glassIconButton("sparkles", id: "tweaksButton", action: onShowTweaks)
                }

                Button(action: toggleEdit) {
                    if isEditMode {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                            Text("Fertig")
                                .font(.system(size: 13, weight: .semibold))
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
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editDashboardButton")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .floatingPill(cornerRadius: 28)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .accessibilityIdentifier("dashboardHeaderView")
    }

    private func glassIconButton(_ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.thinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func toggleEdit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isEditMode.toggle()
        }
    }
}

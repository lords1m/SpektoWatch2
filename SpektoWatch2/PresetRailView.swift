import SwiftUI

/// Horizontal scrolling chip rail that replaces the dot indicator above the dashboard.
/// Selecting a chip is currently a UX hint — wiring to layout switching happens via
/// `onSelect`, which `ModularDashboardView` can map to its layout list.
struct PresetRailView: View {
    let presets: [DashboardPreset]
    @Binding var activeID: String
    var dimmed: Bool = false
    var onSelect: ((DashboardPreset) -> Void)? = nil

    @Environment(\.designAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        chip(preset)
                            .id(preset.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .mask(
                // Edge fades so chips clipped at the screen border read as
                // "scrolls further" rather than an accidental hard cut.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onChange(of: activeID) { _, newID in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            .onAppear {
                // onChange does not fire for the initial value — center the
                // restored chip explicitly so it isn't off-screen on launch.
                DispatchQueue.main.async {
                    proxy.scrollTo(activeID, anchor: .center)
                }
            }
        }
        .opacity(dimmed ? 0.35 : 1.0)
        .allowsHitTesting(!dimmed)
        .animation(.easeInOut(duration: 0.2), value: dimmed)
    }

    @ViewBuilder
    private func chip(_ preset: DashboardPreset) -> some View {
        let isActive = !activeID.isEmpty && preset.id == activeID
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            activeID = preset.id
            onSelect?(preset)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(preset.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 38)
            .contentShape(Capsule())
            .foregroundStyle(isActive ? Color.black : Color.primary.opacity(0.92))
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? AnyShapeStyle(accent) : AnyShapeStyle(inactiveChipFill))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isActive ? Color.clear : inactiveChipStroke,
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: isActive ? accent.opacity(0.45) : .clear,
                radius: isActive ? 12 : 0
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isActive)
    }

    private var inactiveChipFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }

    private var inactiveChipStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }
}

import SwiftUI

/// Horizontal scrolling chip rail that replaces the dot indicator above the dashboard.
/// Selecting a chip is currently a UX hint — wiring to layout switching happens via
/// `onSelect`, which `ModularDashboardView` can map to its layout list.
struct PresetRailView: View {
    let presets: [DashboardPreset]
    @Binding var activeID: String
    var dimmed: Bool = false
    var onSelect: ((DashboardPreset) -> Void)? = nil

    @Environment(\.ferriteLine) private var line

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
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
                Task { @MainActor in
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
            activeID = preset.id
            onSelect?(preset)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(preset.label)
                    .font(.system(size: 12, weight: isActive ? .bold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 38)
            .contentShape(Rectangle())
            .foregroundStyle(isActive ? line.onColor : FerriteColor.label)
            .background(
                RoundedRectangle(cornerRadius: FerriteRadius.tile, style: .continuous)
                    .fill(isActive ? line.color : FerriteColor.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FerriteRadius.tile, style: .continuous)
                    .strokeBorder(isActive ? FerriteColor.label : FerriteColor.hairline,
                                  lineWidth: FerriteStroke.hairline)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isActive)
    }
}

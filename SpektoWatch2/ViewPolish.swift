import SwiftUI

// MARK: - Shared UI polish (forms, sheets, instrument chrome)

extension View {
    /// Hides the default Form/List background and paints the themed app gradient.
    func polishedFormChrome() -> some View {
        scrollContentBackground(.hidden)
            .background(GlassBackground())
    }

    /// Standard sheet chrome for settings / pickers.
    func polishedSheetChrome() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }

    /// Floating expand / readout control used on scientific canvases.
    func canvasControlButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    /// Compact glass circle for transport-style icon buttons.
    func transportGlassButton(diameter: CGFloat = 38, @ViewBuilder label: () -> some View) -> some View {
        label()
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(.thinMaterial))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
    }
}

/// Canvas readout pill (handoff: dark blur plate, mono labels).
struct CanvasReadoutPill: View {
    let label: String
    let value: String
    var unit: String? = nil

    @Environment(\.designNumerals) private var numerals

    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.eyebrow(size: 9))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 4)
            Text(value)
                .font(.numerals(numerals, size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.95))
            if let unit {
                Text(unit.uppercased())
                    .font(.eyebrow(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 96)
        .background(.ultraThinMaterial.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

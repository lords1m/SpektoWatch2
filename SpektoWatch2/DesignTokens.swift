import SwiftUI

// MARK: - User-toggleable design tokens
//
// These map to the "Tweaks" panel described in the redesign handoff.
// All persisted via @AppStorage so they survive app launches.

enum ThemeMode: String, CaseIterable, Identifiable {
    case dark, light
    var id: String { rawValue }
    var label: String { self == .dark ? "Dark" : "Light" }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

enum CanvasMode: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var label: String { self == .dark ? "Dark" : "Light" }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case phosphor, amber, cyan, magenta, paper
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    // OKLCH values from the handoff — approximated in sRGB.
    var color: Color {
        switch self {
        case .phosphor: return Color(red: 0.45, green: 0.93, blue: 0.55) // 0.84 0.18 145
        case .amber:    return Color(red: 0.99, green: 0.74, blue: 0.27) // 0.82 0.16 80
        case .cyan:     return Color(red: 0.40, green: 0.81, blue: 0.95) // 0.82 0.14 220
        case .magenta:  return Color(red: 0.94, green: 0.50, blue: 0.85) // 0.78 0.18 340
        case .paper:    return Color(red: 0.92, green: 0.92, blue: 0.93) // 0.92 0.005 255
        }
    }
}

enum Density: String, CaseIterable, Identifiable {
    case compact, standard, airy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .airy: return "Luftig"
        }
    }
    var cardPadding: CGFloat {
        switch self {
        case .compact: return 10
        case .standard: return 14
        case .airy: return 18
        }
    }
    var cardGap: CGFloat {
        switch self {
        case .compact: return 8
        case .standard: return 12
        case .airy: return 16
        }
    }
}

enum NumeralStyle: String, CaseIterable, Identifiable {
    case mono, sans
    var id: String { rawValue }
    var label: String { self == .mono ? "Mono" : "Sans" }
}

enum Colormap: String, CaseIterable, Identifiable {
    case viridis, inferno, magma
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - Environment plumbing

private struct DesignAccentKey: EnvironmentKey { static let defaultValue: Color = AccentChoice.phosphor.color }
private struct DesignDensityKey: EnvironmentKey { static let defaultValue: Density = .standard }
private struct DesignNumeralsKey: EnvironmentKey { static let defaultValue: NumeralStyle = .mono }

extension EnvironmentValues {
    var designAccent: Color {
        get { self[DesignAccentKey.self] }
        set { self[DesignAccentKey.self] = newValue }
    }
    var designDensity: Density {
        get { self[DesignDensityKey.self] }
        set { self[DesignDensityKey.self] = newValue }
    }
    var designNumerals: NumeralStyle {
        get { self[DesignNumeralsKey.self] }
        set { self[DesignNumeralsKey.self] = newValue }
    }
}

// MARK: - Font helpers

extension Font {
    /// Eyebrow / monospaced caption — JetBrains Mono → SF Mono on iOS.
    static func eyebrow(size: CGFloat = 10) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
    /// Tabular numeric readout. Always mono — used for axis ticks and
    /// any readout that must not reflow when digits change.
    static func readout(size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Numeric readout that respects the user's `NumeralStyle` token.
    /// Pass `.mono` for tabular monospace, `.sans` for proportional SF Pro.
    static func numerals(_ style: NumeralStyle, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch style {
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .sans: return .system(size: size, weight: weight, design: .default)
        }
    }
    /// Header title — SF Pro semibold.
    static func headerTitle(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    /// Hero number — SF Pro Display ultralight.
    static func hero(size: CGFloat = 56) -> Font {
        .system(size: size, weight: .ultraLight, design: .default)
    }
}

// MARK: - Surfaces & modifiers

/// Inner scientific-instrument canvas: always dark, regardless of theme.
/// Flat fill — the kernel paints over most of this region anyway, and
/// stacked gradients per card were noticeable on A14 (iPhone 12 mini).
struct DarkCanvasBackground: View {
    var body: some View {
        Color(red: 0.05, green: 0.06, blue: 0.08)
    }
}

struct InnerCanvas: ViewModifier {
    var cornerRadius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(DarkCanvasBackground())
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }
}

/// New widget card chrome — `.thinMaterial` + hairline inner highlight + a
/// single soft shadow. Material and shadow costs add up fast on the
/// iPhone 12 mini (A14), so we picked the cheaper material tier and
/// collapsed the two prior shadows into one conditional shadow.
struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 22
    var isEditing: Bool = false
    var accent: Color = .green

    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isEditing ? accent.opacity(0.55) : Color.white.opacity(0.06),
                        lineWidth: isEditing ? 1.2 : 0.5
                    )
            )
            .shadow(
                color: isEditing ? accent.opacity(0.25) : .black.opacity(0.35),
                radius: isEditing ? 8 : 6,
                y: 4
            )
    }
}

/// Floating header / transport pill chrome.
struct FloatingPill: ViewModifier {
    var cornerRadius: CGFloat = 28
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }
}

extension View {
    func innerCanvas(cornerRadius: CGFloat = 14) -> some View {
        modifier(InnerCanvas(cornerRadius: cornerRadius))
    }
    func liquidGlassCard(cornerRadius: CGFloat = 22, isEditing: Bool = false, accent: Color = .green) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, isEditing: isEditing, accent: accent))
    }
    func floatingPill(cornerRadius: CGFloat = 28) -> some View {
        modifier(FloatingPill(cornerRadius: cornerRadius))
    }
}

// MARK: - Edit-mode jiggle

struct EditModeJiggle: ViewModifier {
    let isActive: Bool
    let phase: Double  // 0..1; alternate per card to desynchronize
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive ? angle : 0))
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    angle = 0.4 * (phase > 0.5 ? 1 : -1)
                    withAnimation(
                        .easeInOut(duration: 0.14)
                        .repeatForever(autoreverses: true)
                        .delay(0.04 * phase)
                    ) {
                        angle = -angle
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { angle = 0 }
                }
            }
    }
}

extension View {
    func editJiggle(active: Bool, phase: Double = 0) -> some View {
        modifier(EditModeJiggle(isActive: active, phase: phase))
    }
}

// MARK: - SF Symbol mapping for widget types

extension AudioWidgetType {
    var sfSymbol: String {
        switch self {
        case .spectrogram:        return "waveform.path.ecg"
        case .waterfall:          return "square.stack.3d.up"
        case .levelHistory:       return "chart.xyaxis.line"
        case .frequencyDisplay:   return "chart.bar"
        case .levelMeter:         return "speedometer"
        case .octaveBands:        return "chart.bar"
        case .phaseMeter:         return "circle.lefthalf.filled"
        case .singleValue:        return "123.rectangle"
        case .toneGenerator:      return "waveform"
        case .spektralanalyseLab: return "atom"
        case .masking:            return "square.grid.2x2"
        }
    }
}

// MARK: - Preset rail catalogue

struct DashboardPreset: Identifiable, Equatable {
    let id: String
    let label: String
    let symbol: String
}

enum PresetCatalogue {
    static let all: [DashboardPreset] = [
        .init(id: "overview",    label: "Übersicht",            symbol: "square.grid.2x2"),
        .init(id: "spectrogram", label: "Spektrogramm",         symbol: "waveform.path.ecg"),
        .init(id: "waterfall",   label: "Wasserfall",           symbol: "square.stack.3d.up"),
        .init(id: "level-time",  label: "Pegelverlauf",         symbol: "chart.xyaxis.line"),
        .init(id: "spectrum",    label: "Frequenz-Spektrum",    symbol: "chart.bar"),
        .init(id: "phase",       label: "Phasen-Meter",         symbol: "circle.lefthalf.filled"),
        .init(id: "level-meter", label: "Pegel-Meter",          symbol: "speedometer"),
        .init(id: "single",      label: "Einzelwert",           symbol: "123.rectangle"),
        .init(id: "tone",        label: "Tongenerator",         symbol: "waveform"),
        .init(id: "masking",     label: "Sound Masking",        symbol: "square.grid.2x2"),
        .init(id: "lab",         label: "Spektralanalyse-Labor", symbol: "atom")
    ]
}

import SwiftUI

// MARK: - User-toggleable design tokens
//
// These map to the "Tweaks" panel described in the redesign handoff.
// All persisted via @AppStorage so they survive app launches.

enum ThemeMode: String, CaseIterable, Identifiable {
    /// Follow the system appearance (iOS/iPadOS Dark Mode toggle in
    /// Control Center or Settings → Display & Brightness). This is the
    /// default — explicit `.dark` / `.light` only override when the
    /// user picks one in the Tweaks panel.
    case system, dark, light
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .dark:   return "Dunkel"
        case .light:  return "Hell"
        }
    }
    /// Returns `nil` for `.system` so `.preferredColorScheme(_:)`
    /// removes the SwiftUI override and lets `UIUserInterfaceStyle`
    /// flow through.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark:   return .dark
        case .light:  return .light
        }
    }
}

enum CanvasMode: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var label: String { self == .dark ? "Dunkel" : "Hell" }
}

enum Density: String, CaseIterable, Identifiable {
    case compact, standard, airy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .compact: return "Kompakt"
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

private struct DesignAccentKey: EnvironmentKey { static let defaultValue: Color = FerriteLine.default.color }
private struct DesignDensityKey: EnvironmentKey { static let defaultValue: Density = .standard }
private struct DesignNumeralsKey: EnvironmentKey { static let defaultValue: NumeralStyle = .sans }
private struct DesignUseDarkCanvasKey: EnvironmentKey { static let defaultValue: Bool = true }

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
    /// When true, chart kernels use the dark scientific substrate.
    var designUseDarkCanvas: Bool {
        get { self[DesignUseDarkCanvasKey.self] }
        set { self[DesignUseDarkCanvasKey.self] = newValue }
    }
}

enum DesignColormap {
    static func metalRawValue(from storage: String) -> Int {
        switch Colormap(rawValue: storage) ?? .viridis {
        case .viridis: return ColormapType.viridis.rawValue
        case .inferno: return ColormapType.inferno.rawValue
        case .magma: return ColormapType.magma.rawValue
        }
    }
}

// MARK: - Radius scale
//
// Ferrite: cards and canvases are square, controls have a tile's slight
// edge, and only floating glass is rounded. Canvas-internal micro-radii
// (piano keys, markers) stay as literals — they are drawing details.
enum Radius {
    /// Small controls: chips, preset buttons, inline badges.
    static let control: CGFloat = FerriteRadius.tile
    /// Chart kernels / inner canvases.
    static let kernel: CGFloat = FerriteRadius.canvas
    /// Widget cards.
    static let card: CGFloat = FerriteRadius.card
    /// Floating header / transport pills (liquid glass).
    static let pill: CGFloat = FerriteRadius.glass
}

// MARK: - Semantic status colors
//
// Named roles so "green" can mean exactly one thing per context.
// `designAccent` stays the brand/interaction color; these cover state:
enum StatusColor {
    /// Live monitoring is active (LED, live tint).
    static let live = FerriteStatus.live
    /// Recording to file (LED, record button, badges).
    static let recording = FerriteStatus.recording
    /// Masking trigger-capture armed state.
    static let trigger = FerriteStatus.info
    /// Count/notification badge (e.g. recordings count) — an attention marker,
    /// not a recording-state indicator, so it gets its own role even though it
    /// currently shares red.
    static let badge = FerriteStatus.recording
}

// MARK: - Level-meter zone colors
//
// Traffic-light zones for the segmented level meter. The dB thresholds that
// split them are user-configurable (WidgetSettings.levelMeterZone*); these
// are just the three colors a segment can take.
enum MeterZone {
    // Muted, desaturated traffic-light tones — readable as zones without the
    // neon glare of fully-saturated green/amber/red.
    /// Below the low threshold — comfortable.
    static let safe = FerriteStatus.live
    /// Between low and high — getting loud.
    static let caution = FerriteStatus.warning
    /// At/above the high threshold — loud.
    static let loud = FerriteStatus.recording

    /// Zone color for a given dB value against the configured thresholds.
    static func color(for db: Float, low: Float, high: Float) -> Color {
        db < low ? safe : (db < high ? caution : loud)
    }
}

// MARK: - Font helpers
//
// Ferrite is one family (SF Pro), no mono. Tabular digits keep readouts
// from reflowing while values change.

extension Font {
    /// Eyebrow caption — SF Pro bold. Uppercase it and track 1.2pt.
    static func eyebrow(size: CGFloat = 10) -> Font {
        .system(size: size, weight: .bold).monospacedDigit()
    }
    /// Tabular numeric readout, used for axis ticks and any readout that
    /// must not reflow when digits change.
    static func readout(size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
    /// Numeric readout that respects the user's `NumeralStyle` token.
    /// `.mono` keeps the monospaced face for users who chose it.
    static func numerals(_ style: NumeralStyle, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch style {
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .sans: return .system(size: size, weight: weight).monospacedDigit()
        }
    }
    /// Header title — SF Pro bold, like station signage.
    static func headerTitle(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }
    /// Hero number — SF Pro bold, tabular digits.
    static func hero(size: CGFloat = 56) -> Font {
        .system(size: size, weight: .bold).monospacedDigit()
    }
}

// MARK: - Surfaces & modifiers

/// Inner canvas — the Ferrite chart ground: square, theme-following fill
/// (white / black). Chart kernels draw their own axis grid and the card
/// around them carries the 1pt ink outline, so this adds neither (a second
/// grid or frame doubles the lines). When `designUseDarkCanvas` is set in
/// light mode (Tweaks › dark chart) the canvas is forced black so colormaps
/// read the same everywhere. Use `.ferriteCanvas()` for a standalone
/// canvas that needs its own tile grid and outline.
struct InnerCanvas: ViewModifier {
    var cornerRadius: CGFloat = Radius.kernel
    @Environment(\.designUseDarkCanvas) private var useDarkCanvas
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = useDarkCanvas || colorScheme == .dark
        content
            .background(dark ? FerriteColor.canvasDark : FerriteColor.canvas, in: shape)
            .clipShape(shape)
    }
}

/// Widget card chrome — Ferrite card: `surface`, square, 1pt ink outline,
/// no shadow, and *not* glass (cards are content). Edit mode adds the 2pt
/// inner ink line (selected state).
struct WidgetCardChrome: ViewModifier {
    var cornerRadius: CGFloat = Radius.card
    var isEditing: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(FerriteColor.surface, in: shape)
            .overlay(shape.strokeBorder(FerriteColor.label, lineWidth: FerriteStroke.hairline))
            .overlay {
                if isEditing {
                    shape.inset(by: 4)
                        .stroke(FerriteColor.label, lineWidth: FerriteStroke.line)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Floating header / transport pill — liquid glass (the floating
/// navigation layer).
struct FloatingPill: ViewModifier {
    var cornerRadius: CGFloat = Radius.pill

    func body(content: Content) -> some View {
        content.ferriteGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func innerCanvas(cornerRadius: CGFloat = Radius.kernel) -> some View {
        modifier(InnerCanvas(cornerRadius: cornerRadius))
    }
    func widgetCardChrome(cornerRadius: CGFloat = Radius.card, isEditing: Bool = false) -> some View {
        modifier(WidgetCardChrome(cornerRadius: cornerRadius, isEditing: isEditing))
    }
    func floatingPill(cornerRadius: CGFloat = Radius.pill) -> some View {
        modifier(FloatingPill(cornerRadius: cornerRadius))
    }
}

// MARK: - Edit-mode jiggle

struct EditModeJiggle: ViewModifier {
    let isActive: Bool
    let phase: Double  // 0..1; alternate per card to desynchronize
    /// Peak rotation in degrees (0.4° dashboard cards; ~1.6° Home icons, like iOS).
    var amplitude: Double = 0.4
    @State private var angle: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive && !reduceMotion ? angle : 0))
            .onAppear { if isActive { start() } }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    start()
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { angle = 0 }
                }
            }
    }

    private func start() {
        guard !reduceMotion else {
            angle = 0
            return
        }
        angle = amplitude * (phase > 0.5 ? 1 : -1)
        withAnimation(
            .easeInOut(duration: 0.14)
            .repeatForever(autoreverses: true)
            .delay(0.04 * phase)
        ) {
            angle = -angle
        }
    }
}

extension View {
    func editJiggle(active: Bool, phase: Double = 0, amplitude: Double = 0.4) -> some View {
        modifier(EditModeJiggle(isActive: active, phase: phase, amplitude: amplitude))
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
        case .audioEditor:        return "slider.horizontal.3"
        case .recordings:         return "waveform.badge.mic"
        case .settings:           return "gearshape.fill"
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
    private static let deactivatedPresetIDs: Set<String> = ["waterfall", "phase", "masking"]

    static let all: [DashboardPreset] = [
        .init(id: "overview",    label: "Home",                 symbol: "house.fill"),
        .init(id: "spectrogram", label: "Spektrogramm",         symbol: "waveform.path.ecg"),
        .init(id: "level-time",  label: "Pegelverlauf",         symbol: "chart.xyaxis.line"),
        .init(id: "spectrum",    label: "Frequenz-Spektrum",    symbol: "chart.bar"),
        .init(id: "level-meter", label: "Pegel-Meter",          symbol: "speedometer"),
        .init(id: "single",      label: "Einzelwert",           symbol: "123.rectangle"),
        .init(id: "tone",        label: "Tongenerator",         symbol: "waveform"),
        .init(id: "lab",         label: "Spektralanalyse-Labor", symbol: "atom")
    ]
}

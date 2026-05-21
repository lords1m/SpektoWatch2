import SwiftUI

/// Reusable Form sections for the design tokens (theme / canvas /
/// accent / density / numerals / colormap), all backed by @AppStorage.
/// Embed in any Form — used by both `TweaksPanelView` (sheet) and
/// `SpectrogramSettingsView` (main settings).
struct DesignTweaksSections: View {
    @AppStorage("design.theme")        private var themeRaw: String = ThemeMode.dark.rawValue
    @AppStorage("design.canvasInLight") private var canvasInLightRaw: String = CanvasMode.light.rawValue
    @AppStorage("design.accent")       private var accentRaw: String = AccentChoice.phosphor.rawValue
    @AppStorage("design.density")      private var densityRaw: String = Density.standard.rawValue
    @AppStorage("design.numerals")     private var numeralsRaw: String = NumeralStyle.mono.rawValue
    @AppStorage("design.colormap")     private var colormapRaw: String = Colormap.viridis.rawValue

    var body: some View {
        Group {
            Section(header: Text("Darstellung")) {
                enumPicker("Theme", selection: $themeRaw, options: ThemeMode.allCases.map { $0 }, label: { $0.label })
                enumPicker("Canvas (Light Theme)", selection: $canvasInLightRaw, options: CanvasMode.allCases.map { $0 }, label: { $0.label })
            }
            Section(header: Text("Akzentfarbe")) {
                accentGrid
            }
            Section(header: Text("Layout")) {
                enumPicker("Dichte", selection: $densityRaw, options: Density.allCases.map { $0 }, label: { $0.label })
                enumPicker("Ziffern", selection: $numeralsRaw, options: NumeralStyle.allCases.map { $0 }, label: { $0.label })
            }
            Section(header: Text("Wissenschaft")) {
                enumPicker("Colormap", selection: $colormapRaw, options: Colormap.allCases.map { $0 }, label: { $0.label })
            }
        }
    }

    private var accentGrid: some View {
        HStack(spacing: 12) {
            ForEach(AccentChoice.allCases) { choice in
                Button {
                    accentRaw = choice.rawValue
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().strokeBorder(
                                    accentRaw == choice.rawValue ? Color.primary : .clear,
                                    lineWidth: 2
                                )
                            )
                            .shadow(color: choice.color.opacity(0.5), radius: 8)
                        Text(choice.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func enumPicker<T: CaseIterable & RawRepresentable & Identifiable>(
        _ title: String,
        selection: Binding<String>,
        options: [T],
        label: @escaping (T) -> String
    ) -> some View where T.RawValue == String {
        Picker(title, selection: selection) {
            ForEach(options) { option in
                Text(label(option)).tag(option.rawValue)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// Standalone sheet that wraps `DesignTweaksSections` — kept so the
/// accent-menu's "Mehr Optionen…" shortcut still has a target.
struct TweaksPanelView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DesignTweaksSections()
            }
            .navigationTitle("Design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Convenience reader (used by other views)

struct DesignTokens {
    var theme: ThemeMode
    var canvasInLight: CanvasMode
    var accent: AccentChoice
    var density: Density
    var numerals: NumeralStyle
    var colormap: Colormap
}

struct DesignTokensReader<Content: View>: View {
    @AppStorage("design.theme")         private var themeRaw: String = ThemeMode.dark.rawValue
    @AppStorage("design.canvasInLight") private var canvasInLightRaw: String = CanvasMode.light.rawValue
    @AppStorage("design.accent")        private var accentRaw: String = AccentChoice.phosphor.rawValue
    @AppStorage("design.density")       private var densityRaw: String = Density.standard.rawValue
    @AppStorage("design.numerals")      private var numeralsRaw: String = NumeralStyle.mono.rawValue
    @AppStorage("design.colormap")      private var colormapRaw: String = Colormap.viridis.rawValue

    let content: (DesignTokens) -> Content

    var body: some View {
        let tokens = DesignTokens(
            theme: ThemeMode(rawValue: themeRaw) ?? .dark,
            canvasInLight: CanvasMode(rawValue: canvasInLightRaw) ?? .light,
            accent: AccentChoice(rawValue: accentRaw) ?? .phosphor,
            density: Density(rawValue: densityRaw) ?? .standard,
            numerals: NumeralStyle(rawValue: numeralsRaw) ?? .mono,
            colormap: Colormap(rawValue: colormapRaw) ?? .viridis
        )
        content(tokens)
            .preferredColorScheme(tokens.theme.colorScheme)
            .tint(tokens.accent.color)
            .environment(\.designAccent, tokens.accent.color)
            .environment(\.designDensity, tokens.density)
            .environment(\.designNumerals, tokens.numerals)
    }
}

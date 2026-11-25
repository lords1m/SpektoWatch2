import SwiftUI

/// Living reference for the Ferrite system. Open the previews in Xcode to
/// check both appearances; nothing in the app navigates here.
struct FerriteGallery: View {
    enum Tab: Hashable { case live, recordings, settings }

    @State private var level = 0.62
    @State private var notify = true
    @State private var tab: Tab = .live
    @State private var isGlassExpanded = false
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: FerriteSpace.xl) {
                        FerriteTileBand(height: .thin)

                        measurementCard

                        canvasSample
                            .frame(height: FerriteSpace.tile * 7)

                        VStack(alignment: .leading, spacing: FerriteSpace.m) {
                            FerriteEyebrow(text: "Status", style: .quiet)
                            HStack(spacing: FerriteSpace.s) {
                                FerriteStatusBadge(state: .live)
                                FerriteStatusBadge(state: .recording)
                                FerriteStatusBadge(state: .idle)
                                FerriteStatusBadge(state: .warning)
                            }
                        }

                        VStack(alignment: .leading, spacing: FerriteSpace.m) {
                            FerriteEyebrow(text: "Line colour", style: .bar)
                            FerriteLinePicker()
                            HStack(spacing: FerriteSpace.s) {
                                ForEach(FerriteLine.lines) { FerriteLineBadge(line: $0) }
                            }
                            FerriteTileBand(series: .lines)
                        }
                        .ferriteCard(isLined: true)

                        VStack(spacing: FerriteSpace.m) {
                            Toggle("Notify on threshold", isOn: $notify)
                            LabeledContent("Calibration") {
                                Text("94.0 dB").font(FerriteFont.readout)
                            }
                            Slider(value: $level)
                        }
                        .ferriteCard()

                        VStack(spacing: FerriteSpace.m) {
                            Button("Start recording") {}.buttonStyle(.ferritePrimary)
                            Button("Export CSV") {}.buttonStyle(.ferriteSecondary)
                        }

                        HStack(spacing: FerriteSpace.m) {
                            Button {} label: { Image(systemName: "gearshape") }
                                .buttonStyle(.ferriteGlassRound)
                                .accessibilityLabel("Settings")
                            Button {} label: { Label("Recordings", systemImage: "list.bullet") }
                                .buttonStyle(.ferriteGlass)
                            Button("Start recording") {}.buttonStyle(.ferriteGlassProminent)
                        }

                        glassGroupSample

                        FerriteGlassSheet {
                            FerriteEyebrow(text: "Calibration")
                            Text("Hold the phone at arm's length, microphone facing the source.")
                                .font(FerriteFont.callout)
                            Button("Calibrate") {}.buttonStyle(.ferritePrimary)
                        }
                    }
                    .padding(FerriteSpace.l)
                    .padding(.bottom, 96)
                }

                FerriteGlassBar(items: [
                    .init(id: .live, title: "Live", symbol: "waveform.path.ecg.rectangle"),
                    .init(id: .recordings, title: "Recordings", symbol: "list.bullet.rectangle"),
                    .init(id: .settings, title: "Settings", symbol: "gearshape"),
                ], selection: $tab)
                .padding(.bottom, FerriteSpace.s)
            }
            .background(FerriteColor.background)
            .navigationTitle("Ferrite")
        }
        .ferriteTheme()
    }

    /// Grouped glass that morphs (iOS 26) between one control and a
    /// cluster, plus edge glass whose corners follow the container.
    private var glassGroupSample: some View {
        VStack(alignment: .leading, spacing: FerriteSpace.m) {
            FerriteEyebrow(text: "Glass group", style: .quiet)

            FerriteGlassGroup {
                HStack(spacing: FerriteSpace.s) {
                    Button {
                        withAnimation(reduceMotion ? nil : FerriteMotion.standard) {
                            isGlassExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isGlassExpanded ? "xmark" : "slider.horizontal.3")
                    }
                    .buttonStyle(.ferriteGlass(.round, id: "toggle", in: glassNamespace))
                    .accessibilityLabel(isGlassExpanded ? "Collapse" : "Expand")

                    if isGlassExpanded {
                        Button {} label: { Image(systemName: "waveform") }
                            .buttonStyle(.ferriteGlass(.round, id: "spectrum", in: glassNamespace))
                            .accessibilityLabel("Spectrum")
                        Button("Record") {}
                            .buttonStyle(.ferriteGlass(.prominent, id: "record", in: glassNamespace))
                    }
                }
            }

            Label("Edge glass", systemImage: "dock.rectangle")
                .font(FerriteFont.headline)
                .foregroundStyle(FerriteColor.label)
                .frame(maxWidth: .infinity, minHeight: 60)
                .ferriteEdgeGlass()
        }
    }

    private var measurementCard: some View {
        VStack(alignment: .leading, spacing: FerriteSpace.m) {
            HStack {
                FerriteEyebrow(text: "Level · Input 01")
                Spacer()
                FerriteStatusBadge(state: .live)
            }
            FerriteReadout(value: String(format: "%.1f", 40 + level * 50), unit: "dB(A)")
            FerriteMeter(level: level)
            FerriteStatusLine(leading: "LAeq 15 min", trailing: "04:12:08")
        }
        .ferriteCard()
    }

    private var canvasSample: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width, h = geo.size.height
                path.move(to: CGPoint(x: 0, y: h * 0.7))
                for x in stride(from: 0, through: w, by: 4) {
                    let t = x / w
                    let y = h * (0.62 - 0.28 * sin(t * .pi * 3) * exp(-t * 1.4))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(FerriteColor.label, lineWidth: 2)
        }
        .ferriteCanvas()
    }
}

#Preview("Dark") {
    FerriteGallery().preferredColorScheme(.dark)
}

#Preview("Light") {
    FerriteGallery().preferredColorScheme(.light)
}

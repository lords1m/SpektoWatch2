import SwiftUI

// MARK: - Spectrum Band Mode
enum SpectrumBandMode: String, CaseIterable {
    case continuous = "Linie"
    case bark = "Bark"
    case octave = "Oktav"
    case thirdOctave = "Terz"

    init(settingValue: String) {
        switch settingValue.lowercased() {
        case "continuous", "line", "linie": self = .continuous
        case "bark": self = .bark
        case "octave", "oktav": self = .octave
        case "terz", "thirdoctave", "third_octave": self = .thirdOctave
        default: self = .thirdOctave
        }
    }
}

// MARK: - Frequency Spectrum Widget
struct FrequencySpectrumWidget: View {
    var audioEngine: AudioEngine
    private let live: LiveAcousticState
    var settings: [String: String]

    init(audioEngine: AudioEngine, settings: [String: String] = [:]) {
        self.audioEngine = audioEngine
        self.live = audioEngine.live
        self.settings = settings
    }

    private var useWidgetOverrides: Bool { WidgetSettings.usesWidgetOverrides(settings) }
    private var weighting: String {
        if useWidgetOverrides {
            return settings["freqWeighting"] ?? audioEngine.frequencyWeighting.rawValue
        }
        return audioEngine.frequencyWeighting.rawValue
    }
    private var bandMode: SpectrumBandMode {
        // Band mode has no app-global equivalent (unlike frequency weighting),
        // so the per-widget setting is always the source of truth.
        SpectrumBandMode(settingValue: settings["frequencyBands"] ?? WidgetSettings.defaultSpectrumBandMode)
    }
    private var frequencies: [Float] { live.currentSpectrogramData?.frequencies ?? [] }
    private var weightedSpectrum: [Float] {
        live.currentSpectrogramData?.magnitudes(for: weighting) ?? []
    }
    private var weightedThirdOctaveBands: [Float] {
        switch weighting.uppercased() {
        case "A": return live.currentOctaveBandsA
        case "C": return live.currentOctaveBandsC
        default: return live.currentOctaveBandsZ
        }
    }
    private var bandLeqForWeighting: [Float] {
        switch weighting.uppercased() {
        case "A": return live.bandLeqA
        case "C": return live.bandLeqC
        default: return live.bandLeqZ
        }
    }
    private var bandLeqOctaveForWeighting: [Float] {
        switch weighting.uppercased() {
        case "A": return live.bandLeqOctaveA
        case "C": return live.bandLeqOctaveC
        default: return live.bandLeqOctaveZ
        }
    }
    private var barkBandsForWeighting: [Float] {
        switch weighting.uppercased() {
        case "A": return live.currentBarkBandsA
        case "C": return live.currentBarkBandsC
        default: return live.currentBarkBandsZ
        }
    }

    var body: some View {
        SpectrumBandChartView(
            mode: bandMode,
            frequencies: frequencies,
            spectrum: weightedSpectrum,
            precomputedThirdOctave: weightedThirdOctaveBands,
            precomputedBark: barkBandsForWeighting,
            leqThirds: bandLeqForWeighting,
            precomputedOctaveLeq: bandLeqOctaveForWeighting,
            weightingLabel: weighting,
            showGrid: WidgetSettings.chartShowGrid(settings),
            showLeqOverlay: WidgetSettings.spectrumShowLeq(settings),
            yMinDB: Double(WidgetSettings.chartYMinDB(settings)),
            yMaxDB: Double(WidgetSettings.chartYMaxDB(settings))
        )
        .innerCanvas(cornerRadius: 0)
        .overlay(alignment: .topTrailing) {
            // Legend for the two series — without it the orange Leq markers
            // read as unexplained ticks over the live-spectrum bars.
            if WidgetSettings.spectrumShowLeq(settings), bandMode != .continuous {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(ScientificChartPalette.series)
                            .frame(width: 10, height: 6)
                        Text("Spektrum").font(.system(size: 9))
                    }
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(ScientificChartPalette.secondarySeries)
                            .frame(width: 10, height: 2)
                        Text("Leq").font(.system(size: 9))
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                // Sits on the chart (content layer): a solid fill, not material.
                .background(Capsule().fill(FerriteColor.surfaceSunken))
                .padding(6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Legende: grün Spektrum, orange Leq")
            }
        }
        .onAppear {
            #if DEBUG
            print("[FrequencySpectrumWidget] View appeared (\(weighting), \(bandMode.rawValue), override=\(useWidgetOverrides))")
            #endif
        }
    }
}

private struct SpectrumBandData {
    let values: [Float]
    let labels: [String]
    let labelStride: Int
}

// MARK: - Spectrum Band Chart
private struct SpectrumBandChartView: View {
    let mode: SpectrumBandMode
    let frequencies: [Float]
    let spectrum: [Float]
    let precomputedThirdOctave: [Float]
    /// Pre-aggregated Bark bands (24 critical bands) from `AudioEngine`.
    /// Empty when the engine has not been asked to compute Bark (zero widgets
    /// in Bark mode). Falls back to inline aggregation when empty.
    let precomputedBark: [Float]
    /// Pre-smoothed per-band Leq values (31 third-octave, dB).
    /// Computed by `AcousticMetricsCalculator`; this view reads them directly.
    let leqThirds: [Float]
    /// Pre-aggregated octave Leq (10 bands) from `AudioEngine` / `LiveAcousticState`.
    let precomputedOctaveLeq: [Float]
    let weightingLabel: String
    var showGrid: Bool = true
    var showLeqOverlay: Bool = true
    var yMinDB: Double = 20
    var yMaxDB: Double = 110

    #if DEBUG
    @State private var diagnosticsCounter: Int = 0
    private let enableWidgetDiagnostics = ProcessInfo.processInfo.environment["SPEKTO_DEBUG_WIDGET_SPECTRUM"] == "1"
    #endif

    var body: some View {
        Canvas { context, size in
            let bandData = computeBandData(mode: mode, frequencies: frequencies, spectrum: spectrum)
            let bands = bandData.values
            let leqValues = computeLeqBandData(mode: mode, leqThirds: leqThirds)
            let width = size.width
            let height = size.height

            if bands.isEmpty || bands.allSatisfy({ $0 <= -100 }) {
                let text = Text("Warte auf Audio...").font(.caption).foregroundStyle(.gray)
                context.draw(text, at: CGPoint(x: size.width/2, y: size.height/2))
                return
            }

            let bottomPadding: CGFloat = 22
            let leftPadding: CGFloat = 34
            let rightPadding: CGFloat = 8
            let topPadding: CGFloat = 8
            let chartRect = CGRect(
                x: leftPadding,
                y: topPadding,
                width: max(1, width - leftPadding - rightPadding),
                height: max(1, height - topPadding - bottomPadding)
            )

            let minDB: Double = min(yMinDB, yMaxDB - 5)
            let maxDB: Double = max(yMaxDB, yMinDB + 5)
            let majorTicks = ScientificAxis.majorTicks(min: minDB, max: maxDB, targetTicks: 9)
            let minorTicks = ScientificAxis.minorTicks(major: majorTicks, subdivisions: 2)

            if showGrid {
                for tick in minorTicks where tick >= minDB && tick <= maxDB {
                    let yNorm = ScientificAxis.normalized(tick, min: minDB, max: maxDB)
                    let y = chartRect.maxY - CGFloat(yNorm) * chartRect.height
                    var path = Path()
                    path.move(to: CGPoint(x: chartRect.minX, y: y))
                    path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                    context.stroke(path, with: .color(ScientificChartPalette.gridMinor), lineWidth: 0.5)
                }
                for tick in majorTicks where tick >= minDB && tick <= maxDB {
                    let yNorm = ScientificAxis.normalized(tick, min: minDB, max: maxDB)
                    let y = chartRect.maxY - CGFloat(yNorm) * chartRect.height
                    var path = Path()
                    path.move(to: CGPoint(x: chartRect.minX, y: y))
                    path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                    context.stroke(path, with: .color(ScientificChartPalette.gridMajor), lineWidth: 0.7)
                    context.draw(
                        Text("\(Int(tick))").font(.readout(size: 8, weight: .regular)).foregroundStyle(ScientificChartPalette.axis),
                        at: CGPoint(x: chartRect.minX - 14, y: y)
                    )
                }
            } else {
                for tick in majorTicks where tick >= minDB && tick <= maxDB {
                    let yNorm = ScientificAxis.normalized(tick, min: minDB, max: maxDB)
                    let y = chartRect.maxY - CGFloat(yNorm) * chartRect.height
                    context.draw(
                        Text("\(Int(tick))").font(.readout(size: 8, weight: .regular)).foregroundStyle(ScientificChartPalette.axis),
                        at: CGPoint(x: chartRect.minX - 14, y: y)
                    )
                }
            }

            if mode == .continuous {
                var linePath = Path()
                for i in 0..<bands.count {
                    let x = chartRect.minX + chartRect.width * CGFloat(i) / CGFloat(max(bands.count - 1, 1))
                    let normalized = CGFloat(ScientificAxis.normalized(Double(bands[i]), min: minDB, max: maxDB))
                    let y = chartRect.maxY - max(0, min(1, normalized)) * chartRect.height
                    if i == 0 { linePath.move(to: CGPoint(x: x, y: y)) } else { linePath.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(linePath, with: .color(ScientificChartPalette.series), lineWidth: 1.8)
            } else {
                let barCount = bands.count
                let barWidth = chartRect.width / CGFloat(max(barCount, 1))
                let barGap: CGFloat = (mode == .octave) ? 3 : 1
                for i in 0..<barCount {
                    let val = bands[i]
                    let normalized = CGFloat(ScientificAxis.normalized(Double(val), min: minDB, max: maxDB))
                    let clamped = max(0, min(1, normalized))
                    let barHeight = clamped * chartRect.height
                    let x = chartRect.minX + CGFloat(i) * barWidth
                    let barRect = CGRect(
                        x: x + barGap / 2,
                        y: chartRect.maxY - barHeight,
                        width: max(0, barWidth - barGap),
                        height: barHeight
                    )
                    context.fill(Path(barRect), with: .color(ScientificChartPalette.series.opacity(0.85)))
                    if showLeqOverlay, i < leqValues.count {
                        let leqNorm = CGFloat(ScientificAxis.normalized(Double(leqValues[i]), min: minDB, max: maxDB))
                        let leqClamped = max(0, min(1, leqNorm))
                        let leqY = chartRect.maxY - leqClamped * chartRect.height
                        var leqPath = Path()
                        leqPath.move(to: CGPoint(x: x + barGap / 2, y: leqY))
                        leqPath.addLine(to: CGPoint(x: x + barWidth - barGap / 2, y: leqY))
                        context.stroke(leqPath, with: .color(ScientificChartPalette.secondarySeries), lineWidth: 1.4)
                    }
                }
            }

            var axisPath = Path()
            axisPath.move(to: CGPoint(x: chartRect.minX, y: chartRect.minY))
            axisPath.addLine(to: CGPoint(x: chartRect.minX, y: chartRect.maxY))
            axisPath.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.maxY))
            context.stroke(axisPath, with: .color(ScientificChartPalette.axis), lineWidth: 1.0)

            if mode == .continuous {
                context.draw(
                    Text(formatHz(frequencies.first ?? 0)).font(.readout(size: 8, weight: .regular)).foregroundStyle(ScientificChartPalette.axis),
                    at: CGPoint(x: chartRect.minX, y: height - bottomPadding / 2),
                    anchor: .leading
                )
                context.draw(
                    Text(formatHz(frequencies.last ?? 0)).font(.readout(size: 8, weight: .regular)).foregroundStyle(ScientificChartPalette.axis),
                    at: CGPoint(x: chartRect.maxX, y: height - bottomPadding / 2),
                    anchor: .trailing
                )
            } else {
                let barWidth = chartRect.width / CGFloat(max(bands.count, 1))
                for i in stride(from: 0, to: bandData.labels.count, by: max(1, bandData.labelStride)) {
                    let x = chartRect.minX + CGFloat(i) * barWidth + barWidth / 2
                    context.draw(
                        Text(bandData.labels[i]).font(.readout(size: 8, weight: .regular)).foregroundStyle(ScientificChartPalette.axis),
                        at: CGPoint(x: x, y: height - bottomPadding / 2)
                    )
                }
            }
        }
        .drawingGroup()
        .onAppear {
            #if DEBUG
            let bandData = computeBandData(mode: mode, frequencies: frequencies, spectrum: spectrum)
            logBandDiagnosticsIfNeeded(bandData)
            #endif
        }
        .onChange(of: spectrum) { _, newSpectrum in
            #if DEBUG
            let bandData = computeBandData(mode: mode, frequencies: frequencies, spectrum: newSpectrum)
            logBandDiagnosticsIfNeeded(bandData)
            #endif
        }
    }

    /// Returns the mode-appropriate Leq band values from the pre-smoothed
    /// third-octave Leq array produced by `AcousticMetricsCalculator`.
    ///
    /// - For `.thirdOctave`: returns `leqThirds` directly (31 values).
    /// - For `.octave`: uses `precomputedOctaveLeq` from the engine when available.
    /// - For `.bark`: returns `[]` (no Leq overlay in bark mode).
    private func computeLeqBandData(mode: SpectrumBandMode, leqThirds: [Float]) -> [Float] {
        guard leqThirds.count == SpectrumBandAggregator.thirdOctaveCenters.count else { return [] }
        switch mode {
        case .continuous:
            return []
        case .thirdOctave:
            return leqThirds
        case .octave:
            if precomputedOctaveLeq.count == SpectrumBandAggregator.octaveLabels.count {
                return precomputedOctaveLeq
            }
            return SpectrumBandAggregator.octaveBands(frequencies: [], spectrum: [], fromThirds: leqThirds)
        case .bark:
            return []
        }
    }

    private func computeBandData(mode: SpectrumBandMode, frequencies: [Float], spectrum: [Float]) -> SpectrumBandData {
        // Aggregation math lives in `Managers/SpectrumBandAggregator.swift`
        // (M13 task-6). View is responsible only for picking the mode and
        // bundling labels.
        switch mode {
        case .continuous:
            return SpectrumBandData(values: spectrum, labels: [], labelStride: 1)
        case .thirdOctave:
            let values: [Float]
            if precomputedThirdOctave.count == SpectrumBandAggregator.thirdOctaveCenters.count {
                values = precomputedThirdOctave
            } else {
                values = SpectrumBandAggregator.thirdOctaveBands(frequencies: frequencies, spectrum: spectrum)
            }
            return SpectrumBandData(
                values: values,
                labels: SpectrumBandAggregator.thirdOctaveLabels,
                labelStride: 5
            )

        case .octave:
            let precomputedMatches = precomputedThirdOctave.count == SpectrumBandAggregator.thirdOctaveCenters.count
            let values = SpectrumBandAggregator.octaveBands(
                frequencies: frequencies,
                spectrum: spectrum,
                fromThirds: precomputedMatches ? precomputedThirdOctave : nil
            )
            return SpectrumBandData(
                values: values,
                labels: SpectrumBandAggregator.octaveLabels,
                labelStride: 1
            )

        case .bark:
            // Prefer precomputed Bark bands from the AudioEngine pipeline (zero
            // extra work per Canvas redraw). Fall back to inline aggregation only
            // if the engine hasn't been asked to precompute them (e.g. during the
            // first frame before DashboardViewModel registers the requirement).
            let values = precomputedBark.isEmpty
                ? SpectrumBandAggregator.barkBands(frequencies: frequencies, spectrum: spectrum)
                : precomputedBark
            return SpectrumBandData(
                values: values,
                labels: (1...24).map(String.init),
                labelStride: 3
            )
        }
    }

    private func formatHz(_ hz: Float) -> String {
        if hz >= 1000 { return "\((hz / 1000).formatted(.number.precision(.fractionLength(1))))k" }
        return hz.formatted(.number.precision(.fractionLength(0)))
    }

    private func logBandDiagnosticsIfNeeded(_ bandData: SpectrumBandData) {
        #if DEBUG
        guard enableWidgetDiagnostics else { return }
        diagnosticsCounter += 1
        guard diagnosticsCounter % 60 == 0 else { return }

        let preview = zip(bandData.labels, bandData.values)
            .prefix(10)
            .map { label, value in "\(label)=\(String(format: "%.1f", value))" }
            .joined(separator: ",")
        let freqMin = frequencies.first ?? 0
        let freqMax = frequencies.last ?? 0
        let firstPositive = frequencies.first(where: { $0 > 0 }) ?? 0
        print(
            "[SpectrumWidgetDiag] mode=\(mode.rawValue) weighting=\(weightingLabel.uppercased()) bins=\(frequencies.count) " +
            "freqRange=\(String(format: "%.0f", freqMin))-\(String(format: "%.0f", freqMax))Hz binHz=\(String(format: "%.2f", firstPositive)) " +
            "bands{\(preview)}"
        )
        #endif
    }
}

// MARK: - Level Meter Widget
/// M13 task-4 Phase 2 pilot: observes `LiveAcousticState` directly so re-renders
/// are driven by live data ticks only. `audioEngine` is not retained after init —
/// no re-renders from engine settings / status changes.
struct LevelMeterWidget: View {
    private let live: LiveAcousticState
    private let audioEngine: AudioEngine
    @Environment(\.designNumerals) private var numerals
    @ScaledMetric(relativeTo: .largeTitle) private var levelReadoutSize: CGFloat = 30
    var settings: [String: String] = [:]

    init(audioEngine: AudioEngine, settings: [String: String] = [:]) {
        self.live = audioEngine.live
        self.audioEngine = audioEngine
        self.settings = settings
    }

    private var yMinDB: Float { WidgetSettings.chartYMinDB(settings) }
    private var yMaxDB: Float { WidgetSettings.chartYMaxDB(settings) }

    private var weightingLabel: String {
        switch audioEngine.frequencyWeighting {
        case .a: return "dB(A)"
        case .c: return "dB(C)"
        case .z: return "dB(Z)"
        }
    }

    private var orientation: LevelMeterOrientation {
        WidgetSettings.levelMeterOrientation(settings)
    }

    private var showPeak: Bool {
        WidgetSettings.levelMeterShowPeak(settings)
    }

    private var zoneLow: Float { WidgetSettings.levelMeterZoneLow(settings) }
    private var zoneHigh: Float { WidgetSettings.levelMeterZoneHigh(settings) }
    private var statKeys: [String] { WidgetSettings.levelMeterStats(settings) }
    private var levels: [String: Float] { live.currentSpectrogramData?.levels ?? [:] }

    var body: some View {
        let minDB = yMinDB
        let maxDB = max(yMaxDB, yMinDB + 5)
        let level = live.currentLevel
        let peak = live.currentPeakLevel

        Group {
            if orientation == .vertical {
                verticalMeterBody(level: level, peak: peak, minDB: minDB, maxDB: maxDB)
            } else {
                horizontalMeterBody(level: level, peak: peak, minDB: minDB, maxDB: maxDB)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .innerCanvas(cornerRadius: 0)
    }

    /// Current level as the kernel headline (the card header no longer carries
    /// it). "—" below the floor; colored by the (muted) zone it falls in.
    private func levelText(_ level: Float, minDB: Float) -> String {
        level.isFinite && level > minDB ? String(format: "%.1f", level) : "—"
    }
    private func levelColor(_ level: Float, minDB: Float) -> Color {
        level > minDB ? MeterZone.color(for: level, low: zoneLow, high: zoneHigh) : .secondary
    }

    @ViewBuilder
    private func horizontalMeterBody(level: Float, peak: Float, minDB: Float, maxDB: Float) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(levelText(level, minDB: minDB))
                    .font(.numerals(numerals, size: levelReadoutSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(levelColor(level, minDB: minDB))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(weightingLabel)
                    .font(FerriteFont.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }

            SegmentedLevelBar(
                value: level, peak: peak, minDB: minDB, maxDB: maxDB,
                zoneLow: zoneLow, zoneHigh: zoneHigh, showPeak: showPeak, axis: .horizontal
            )
            .frame(maxHeight: .infinity)

            scaleRow(minDB: minDB, maxDB: maxDB, peakDB: showPeak ? peak : nil)

            if !statKeys.isEmpty {
                HStack(spacing: 6) {
                    ForEach(statKeys, id: \.self) { key in
                        statTile(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func verticalMeterBody(level: Float, peak: Float, minDB: Float, maxDB: Float) -> some View {
        HStack(spacing: 12) {
            // Narrow bar column — the segments carry the reading; number + stats sit beside.
            SegmentedLevelBar(
                value: level, peak: peak, minDB: minDB, maxDB: maxDB,
                zoneLow: zoneLow, zoneHigh: zoneHigh, showPeak: showPeak, axis: .vertical
            )
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(levelText(level, minDB: minDB))
                        .font(.numerals(numerals, size: levelReadoutSize, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(levelColor(level, minDB: minDB))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(weightingLabel)
                        .font(FerriteFont.caption)
                        .foregroundStyle(.tertiary)
                }
                // Compact label-left / value-right rows so a few stats fit
                // without clipping even in a short widget.
                ForEach(statKeys, id: \.self) { key in
                    HStack(spacing: 4) {
                        Text(WidgetSettings.levelMeterStatLabel(key))
                            .font(FerriteFont.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 2)
                        Text(statValue(key))
                            .font(FerriteFont.readout.weight(.medium))
                            .foregroundStyle(statColor(key))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statTile(_ key: String) -> some View {
        VStack(spacing: 1) {
            Text(WidgetSettings.levelMeterStatLabel(key))
                .font(FerriteFont.caption)
                .foregroundStyle(.secondary)
            Text(statValue(key))
                .font(FerriteFont.readout.weight(.medium))
                .foregroundStyle(statColor(key))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Color.primary.opacity(0.05)))
    }

    /// Max/Peak share the amber peak-hold accent so the readouts tie back to
    /// the orange peak segment; the rest stay neutral.
    private func statColor(_ key: String) -> Color {
        (key == "LAFmax" || key == "LCpeak") ? ScientificChartPalette.secondarySeries : .primary
    }

    private func statValue(_ key: String) -> String {
        guard let v = levels[key], v.isFinite, v > -119 else { return "—" }
        return String(format: "%.1f", v)
    }

    private func scaleRow(minDB: Float, maxDB: Float, peakDB: Float?) -> some View {
        HStack(spacing: 0) {
            Text("\(Int(minDB))").font(FerriteFont.caption2).foregroundStyle(.tertiary)
            Spacer()
            Text("\(Int((minDB + maxDB) / 2))").font(FerriteFont.caption2).foregroundStyle(.tertiary)
            Spacer()
            Text("\(Int(maxDB))").font(FerriteFont.caption2).foregroundStyle(.tertiary)
            Text(weightingLabel)
                .font(FerriteFont.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            if let peakDB, peakDB > minDB {
                Spacer(minLength: 8)
                Text(String(format: "Spitze %.0f", peakDB))
                    .font(FerriteFont.caption2.weight(.medium))
                    .foregroundStyle(ScientificChartPalette.secondarySeries)
            }
        }
    }
}

/// Segmented (LED-ladder) level bar shared by both orientations. Each segment
/// maps to a dB value and is colored by the configurable zone thresholds;
/// segments above the current level are dimmed. The peak-hold segment stays
/// lit (dimmer) at the highest recent level. Snaps per segment — no fill
/// animation — for the classic LED-meter feel.
private struct SegmentedLevelBar: View {
    let value: Float
    let peak: Float
    let minDB: Float
    let maxDB: Float
    let zoneLow: Float
    let zoneHigh: Float
    let showPeak: Bool
    let axis: Axis

    var body: some View {
        Canvas { ctx, size in
            let span = max(maxDB - minDB, 1)
            let horizontal = axis == .horizontal
            let length = horizontal ? size.width : size.height
            let thickness = horizontal ? size.height : size.width
            guard length > 4, thickness > 0 else { return }

            let targetSegment: CGFloat = horizontal ? 9 : 8   // px per segment incl. gap
            let n = max(6, Int(length / targetSegment))
            let gap: CGFloat = 2
            let segLen = max(1, (length - CGFloat(n - 1) * gap) / CGFloat(n))

            let valFrac = max(0, min(1, CGFloat((value - minDB) / span)))
            let peakFrac = max(0, min(1, CGFloat((peak - minDB) / span)))
            let litCount = Int((valFrac * CGFloat(n)).rounded())
            let peakIdx = showPeak ? Int((peakFrac * CGFloat(n)).rounded()) - 1 : -1

            for i in 0..<n {
                let segDB = minDB + (Float(i) + 0.5) / Float(n) * span
                let zoneColor = MeterZone.color(for: segDB, low: zoneLow, high: zoneHigh)
                let lit = i < litCount
                let isPeak = i == peakIdx
                let opacity: Double = lit ? 1.0 : (isPeak ? 0.85 : 0.10)
                let fill = (lit || isPeak) ? zoneColor : Color.primary
                let off = CGFloat(i) * (segLen + gap)
                let rect = horizontal
                    ? CGRect(x: off, y: 0, width: segLen, height: thickness)
                    : CGRect(x: 0, y: size.height - off - segLen, width: thickness, height: segLen)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(fill.opacity(opacity)))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Pegel")
        .accessibilityValue(String(format: "%.0f dB", value))
    }
}

// MARK: - Octave Band Analyzer Widget
struct OctaveBandWidget: View {
    var audioEngine: AudioEngine

    private var weightedOctaveBands: [Float] {
        switch audioEngine.frequencyWeighting {
        case .a: return audioEngine.live.currentOctaveBandsA
        case .c: return audioEngine.live.currentOctaveBandsC
        case .z: return audioEngine.live.currentOctaveBandsZ
        }
    }
    private var bandLeqForWeighting: [Float] {
        switch audioEngine.frequencyWeighting {
        case .a: return audioEngine.live.bandLeqA
        case .c: return audioEngine.live.bandLeqC
        case .z: return audioEngine.live.bandLeqZ
        }
    }

    var body: some View {
        let weighting = audioEngine.frequencyWeighting.rawValue
        let frequencies = audioEngine.live.currentSpectrogramData?.frequencies ?? []
        let spectrum = audioEngine.live.currentSpectrogramData?.magnitudes(for: weighting) ?? []
        SpectrumBandChartView(
            mode: .thirdOctave,
            frequencies: frequencies,
            spectrum: spectrum,
            precomputedThirdOctave: weightedOctaveBands,
            precomputedBark: [],  // OctaveBandWidget always uses .thirdOctave
            leqThirds: bandLeqForWeighting,
            precomputedOctaveLeq: [],
            weightingLabel: weighting
        )
        .onAppear {
            #if DEBUG
            print("[OctaveBandWidget] View appeared")
            #endif
        }
    }
}

// MARK: - Phase Meter Widget
struct PhaseMeterWidget: View {
    private let live: LiveAcousticState

    init(audioEngine: AudioEngine) {
        self.live = audioEngine.live
    }

    var body: some View {
        Group {
            if live.isStereoActive {
                stereoContent
            } else {
                monoPlaceholder
            }
        }
        .innerCanvas(cornerRadius: 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Phasenmesser")
        .accessibilityValue(
            live.isStereoActive
                ? String(format: "Korrelation %.2f", live.currentStereoPhase)
                : "Kein Stereo-Signal"
        )
    }

    // MARK: Stereo view

    private var stereoContent: some View {
        HStack(spacing: 16) {
            // Correlation bar
            VStack(spacing: 4) {
                Text("Korrelation")
                    .font(.caption)
                    .foregroundStyle(.gray)

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let phase = live.currentStereoPhase

                    // Gradient background: red (–1, out of phase) → green (+1, mono/in phase)
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.red, .yellow, .green],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .opacity(0.3)
                        .clipShape(.rect(cornerRadius: 4))

                    // Center marker
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1, height: h)
                        .position(x: w / 2, y: h / 2)

                    // Needle
                    let x = (CGFloat(phase) + 1.0) / 2.0 * w
                    Circle()
                        .fill(indicatorColor(phase: phase))
                        .frame(width: 12, height: 12)
                        .position(x: x, y: h / 2)
                        .shadow(color: indicatorColor(phase: phase).opacity(0.6), radius: 4)
                }
                .frame(height: 28)

                HStack {
                    Text("−1").font(.caption2)
                    Spacer()
                    Text("0").font(.caption2)
                    Spacer()
                    Text("+1").font(.caption2)
                }
                .foregroundStyle(.gray)

                // Numeric readout
                Text(String(format: "%.2f", live.currentStereoPhase))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(indicatorColor(phase: live.currentStereoPhase))
            }
            .padding()

            // Correlation ellipse (phase-scope approximation)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 6

                // Reference circle
                context.stroke(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(.gray.opacity(0.3))
                )

                // 45° reference lines (L and R axes of a real goniometer)
                let d = radius * 0.85
                var lAxis = Path()
                lAxis.move(to: CGPoint(x: center.x - d * 0.707, y: center.y + d * 0.707))
                lAxis.addLine(to: CGPoint(x: center.x + d * 0.707, y: center.y - d * 0.707))
                context.stroke(lAxis, with: .color(.gray.opacity(0.2)), lineWidth: 1)

                var rAxis = Path()
                rAxis.move(to: CGPoint(x: center.x + d * 0.707, y: center.y + d * 0.707))
                rAxis.addLine(to: CGPoint(x: center.x - d * 0.707, y: center.y - d * 0.707))
                context.stroke(rAxis, with: .color(.gray.opacity(0.2)), lineWidth: 1)

                // Phase ellipse:
                // +1 (mono/in-phase)  → tall vertical line
                //  0 (uncorrelated)   → circle
                // –1 (out-of-phase)   → wide horizontal line
                let phase = CGFloat(live.currentStereoPhase)
                let scaleX = sqrt(max(0, (1.0 - phase) / 2.0))
                let scaleY = sqrt(max(0, (1.0 + phase) / 2.0))
                let ew = radius * scaleX
                let eh = radius * scaleY
                if ew > 0.5 || eh > 0.5 {
                    let ellipseRect = CGRect(x: center.x - ew, y: center.y - eh,
                                            width: ew * 2, height: eh * 2)
                    context.stroke(Path(ellipseIn: ellipseRect),
                                   with: .color(.green), lineWidth: 2)
                }
            }
            .frame(width: 110)
        }
    }

    // MARK: Mono placeholder

    private var monoPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash")
                .font(.title2)
                .foregroundStyle(.gray)
            Text("Kein Stereo-Signal")
                .font(.caption)
                .foregroundStyle(.gray)
            Text("Stereo-Mikrofon in den\nEinstellungen aktivieren")
                .font(.caption2)
                .foregroundStyle(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func indicatorColor(phase: Float) -> Color {
        switch phase {
        case ..<(-0.1): return .red
        case (-0.1)..<0.3: return .yellow
        default: return .green
        }
    }
}

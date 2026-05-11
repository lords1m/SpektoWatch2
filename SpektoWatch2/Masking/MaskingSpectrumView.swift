import SwiftUI

// Spektralgrund frequency response chart.
// Log x-axis (20 Hz → 20 kHz), linear dB y-axis (relative, peak = 0 dB).
//
// Curves:
//   ① Trigger   (cyan)  – measured spectral shape, peak-normalised
//   ② Natural   (dim)   – masker texture reference
//   ③ EQ output (amber) – EQ-adjusted masker output
struct MaskingSpectrumView: View {
    let triggerBands: [Float]?
    let suggestion: MaskerSuggestion?

    private let dBFloor: Float   = -54
    private let dBCeiling: Float = 6
    private let fLow: Float      = 20
    private let fHigh: Float     = 20_000

    private let cyan  = Color(red: 0.0, green: 0.85, blue: 1.0)
    private let amber = Color(red: 1.0, green: 0.80, blue: 0.30)
    private let dim   = Color(white: 0.4, opacity: 0.7)
    private let grid  = Color.white.opacity(0.05)
    private let tick  = Color.white.opacity(0.35)

    private let centers = TriggerSpectrum.bandCenters

    var body: some View {
        Canvas { ctx, size in
            let ins = (t: 6.0 as CGFloat, l: 26.0 as CGFloat,
                       b: 18.0 as CGFloat, r: 4.0  as CGFloat)
            let chart = CGRect(x: ins.l, y: ins.t,
                               width:  size.width  - ins.l - ins.r,
                               height: size.height - ins.t - ins.b)

            drawGrid(ctx, size, chart)

            if let sug = suggestion {
                let nat  = sug.maskerType.naturalSpectrum
                let peak = nat.max() ?? 0
                let normNat = nat.map { $0 - peak }
                let eqd = zip(nat, centers).map { n, f in
                    n + eqGain(at: f, from: sug.eqBands)
                }
                let normEqd = eqd.map { $0 - peak }
                drawLine(ctx, chart, normNat, color: dim,   width: 1.0)
                drawLine(ctx, chart, normEqd, color: amber, width: 2.0)
            }

            if let b = triggerBands {
                let norm = normalizeToZero(b)
                drawFill(ctx, chart, norm, color: cyan.opacity(0.09))
                drawLine(ctx, chart, norm, color: cyan.opacity(0.9), width: 1.5)
            }
        }
    }

    // MARK: – Grid

    private func drawGrid(_ ctx: GraphicsContext, _ size: CGSize, _ chart: CGRect) {
        let vFreqs: [Float] = [50, 100, 200, 500, 1000, 2000, 5000, 10000]
        for f in vFreqs {
            let x = xp(f, chart)
            var p = Path()
            p.move(to: CGPoint(x: x, y: chart.minY))
            p.addLine(to: CGPoint(x: x, y: chart.maxY))
            ctx.stroke(p, with: .color(grid), lineWidth: 1)

            let lbl = f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
            let t = ctx.resolve(
                Text(lbl).font(.system(size: 7.5, design: .monospaced)).foregroundStyle(tick)
            )
            ctx.draw(t, at: CGPoint(x: x, y: chart.maxY + 3), anchor: .top)
        }

        let dBLevels: [Float] = [-48, -36, -24, -12, 0]
        for db in dBLevels {
            let y = yp(db, chart)
            var p = Path()
            p.move(to: CGPoint(x: chart.minX, y: y))
            p.addLine(to: CGPoint(x: chart.maxX, y: y))
            ctx.stroke(p, with: .color(grid), lineWidth: 1)

            let lbl = "\(Int(db))"
            let t = ctx.resolve(
                Text(lbl).font(.system(size: 7.5, design: .monospaced)).foregroundStyle(tick)
            )
            ctx.draw(t, at: CGPoint(x: chart.minX - 2, y: y), anchor: .trailing)
        }
    }

    // MARK: – Curve drawing

    private func drawLine(_ ctx: GraphicsContext, _ chart: CGRect,
                          _ values: [Float], color: Color, width: CGFloat) {
        let pts = chartPoints(values, chart)
        guard !pts.isEmpty else { return }
        ctx.stroke(crSpline(pts), with: .color(color), lineWidth: width)
    }

    private func drawFill(_ ctx: GraphicsContext, _ chart: CGRect,
                          _ values: [Float], color: Color) {
        let pts = chartPoints(values, chart)
        guard !pts.isEmpty else { return }
        var path = crSpline(pts)
        path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: chart.maxY))
        path.addLine(to: CGPoint(x: pts[0].x, y: chart.maxY))
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    // Catmull-Rom spline through pts
    private func crSpline(_ pts: [CGPoint]) -> Path {
        guard pts.count >= 2 else { return Path() }
        var path = Path()
        path.move(to: pts[0])
        for i in 0..<pts.count - 1 {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    private func chartPoints(_ values: [Float], _ chart: CGRect) -> [CGPoint] {
        guard values.count == centers.count else { return [] }
        return zip(centers, values).map { f, db in
            CGPoint(x: xp(f, chart), y: yp(db, chart))
        }
    }

    // MARK: – Coordinate helpers

    private func xp(_ freq: Float, _ r: CGRect) -> CGFloat {
        let t = (log10(freq) - log10(fLow)) / (log10(fHigh) - log10(fLow))
        return r.minX + CGFloat(t) * r.width
    }

    private func yp(_ db: Float, _ r: CGRect) -> CGFloat {
        let clamped = Swift.max(dBFloor, Swift.min(dBCeiling, db))
        let t = (clamped - dBCeiling) / (dBFloor - dBCeiling)
        return r.minY + CGFloat(t) * r.height
    }

    // MARK: – Data transforms

    private func normalizeToZero(_ bands: [Float]) -> [Float] {
        guard let peak = bands.max() else { return bands }
        return bands.map { $0 - peak }
    }

    private func eqGain(at freq: Float, from bands: [EQBand]) -> Float {
        bands.reduce(0) { $0 + singleBandGain(at: freq, band: $1) }
    }

    private func singleBandGain(at freq: Float, band: EQBand) -> Float {
        let oct = log2(freq / band.frequency)
        switch band.type {
        case .lowShelf:
            return band.gainDB * Swift.max(0, Swift.min(1, 0.5 - oct * 0.5))
        case .highShelf:
            return band.gainDB * Swift.max(0, Swift.min(1, 0.5 + oct * 0.5))
        case .peak:
            return band.gainDB * exp(-0.5 * pow(oct / (0.5 / band.q), 2))
        }
    }
}

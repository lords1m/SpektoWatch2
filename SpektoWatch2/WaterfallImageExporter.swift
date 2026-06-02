import Foundation
#if canImport(UIKit)
import UIKit

final class WaterfallImageExporter {
    enum ExportError: LocalizedError {
        case empty
        case pngEncoding
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Keine Wasserfall-Daten vorhanden."
            case .pngEncoding:
                return "Wasserfall-Bild konnte nicht kodiert werden."
            case .writeFailed(let error):
                return "Wasserfall-Bild konnte nicht gespeichert werden: \(error.localizedDescription)"
            }
        }
    }

    func export(dataSet: WaterfallDataSet, recordingID: String) throws -> URL {
        guard !dataSet.isEmpty else { throw ExportError.empty }
        let image = render(dataSet: dataSet)
        guard let png = image.pngData() else { throw ExportError.pngEncoding }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(recordingID)_waterfall.png")
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(error)
        }
        return url
    }

    private func render(dataSet: WaterfallDataSet) -> UIImage {
        let width = max(320, dataSet.slices.count)
        let height = max(240, dataSet.frequencies.count)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let minDB = dataSet.minDB
        let maxDB = max(minDB + 1, dataSet.maxDB)
        let range = maxDB - minDB

        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for (xIndex, slice) in dataSet.slices.enumerated() {
                for (yIndex, value) in slice.magnitudes.enumerated() {
                    let normalized = max(0, min(1, (value - minDB) / range))
                    let color = turboColor(t: normalized)
                    color.setFill()
                    let x = CGFloat(xIndex) / CGFloat(max(1, dataSet.slices.count)) * CGFloat(width)
                    let y = CGFloat(height) - (CGFloat(yIndex + 1) / CGFloat(max(1, slice.magnitudes.count)) * CGFloat(height))
                    let w = max(1, CGFloat(width) / CGFloat(max(1, dataSet.slices.count)))
                    let h = max(1, CGFloat(height) / CGFloat(max(1, slice.magnitudes.count)))
                    ctx.fill(CGRect(x: x, y: y, width: w, height: h))
                }
            }
        }
    }

    private func turboColor(t: Float) -> UIColor {
        let c = max(0, min(1, t))
        let t2 = c * c
        let t3 = t2 * c
        let t4 = t3 * c
        let t5 = t4 * c
        let r =  0.13572138 +  4.61539260 * c - 42.66032258 * t2 + 132.13108234 * t3 - 152.94239396 * t4 +  59.28637943 * t5
        let g =  0.09140261 +  2.19418839 * c +  4.84296658 * t2 -  14.18503333 * t3 +   4.27729857 * t4 +   2.82956604 * t5
        let b =  0.10667330 + 12.64194608 * c - 60.58204836 * t2 + 110.36276771 * t3 -  89.90310912 * t4 +  27.34824973 * t5
        return UIColor(
            red: CGFloat(max(0, min(1, r))),
            green: CGFloat(max(0, min(1, g))),
            blue: CGFloat(max(0, min(1, b))),
            alpha: 1
        )
    }
}
#endif

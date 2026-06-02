#if canImport(UIKit)
import UIKit
import AVFoundation
import Accelerate

final class SpectrogramImageRenderer {
    func renderSpectrogramImage(
        history: [[Float]],
        axis: SpectrogramHistoryAxisKind,
        sampleRate: Double,
        calibrationOffset: Float,
        targetWidth requestedWidth: Int = 1200,
        targetHeight: Int = 420,
        minDb: Float = -110,
        maxDb: Float = -20
    ) throws -> UIImage {
        let columns = history.filter { !$0.isEmpty }
        guard let first = columns.first else {
            throw MeasurementDataError.ioFailure("Leere Spektrogramm-Historie.")
        }

        let width = max(1, min(requestedWidth, columns.count))
        let binCount = first.count
        let frequencies = SpectrogramHistoryAxis.frequencyAxis(
            kind: axis,
            binCount: binCount,
            sampleRate: sampleRate
        )
        guard !frequencies.isEmpty else {
            throw MeasurementDataError.ioFailure("Keine Frequenzachse für Export.")
        }

        var heatmap = [Float](repeating: 0, count: width * targetHeight)
        var rowToBin = [Int](repeating: 0, count: targetHeight)
        for y in 0..<targetHeight {
            let yNorm = 1.0 - Float(y) / Float(max(targetHeight - 1, 1))
            let frequency = SpectrogramHistoryAxis.frequency(
                yNorm: yNorm,
                kind: axis,
                binCount: binCount,
                sampleRate: sampleRate
            )
            rowToBin[y] = SpectrogramHistoryAxis.binIndex(
                forFrequency: frequency,
                kind: axis,
                binCount: binCount,
                sampleRate: sampleRate
            )
        }

        let columnsPerPixel = max(1.0, Double(columns.count) / Double(width))
        for (sourceIndex, column) in columns.enumerated() {
            let pixelX = min(width - 1, Int(Double(sourceIndex) / columnsPerPixel))
            for y in 0..<targetHeight {
                let bin = min(column.count - 1, rowToBin[y])
                let spl = column[bin]
                let dbfs = spl - calibrationOffset
                let normalized = max(0, min(1, (dbfs - minDb) / max(maxDb - minDb, 1e-6)))
                let index = y * width + pixelX
                if normalized > heatmap[index] {
                    heatmap[index] = normalized
                }
            }
        }

        let argb = Self.makeARGBPixels(fromNormalizedHeatmap: heatmap, width: width, height: targetHeight)
        return try makeUIImage(fromARGB: argb, width: width, height: targetHeight)
    }

    func renderSpectrogramImage(
        audioURL: URL,
        targetWidth requestedWidth: Int = 1200,
        targetHeight: Int = 420,
        fftSize: Int = 4096,
        hopSize: Int = 512,
        calibrationOffset: Float = 0,
        minDb: Float = -110,
        maxDb: Float = -20
    ) throws -> UIImage {
        let file = try AVAudioFile(forReading: audioURL)
        let format = file.processingFormat
        let sampleRate = Float(format.sampleRate)
        let nyquist = max(sampleRate / 2, 20)
        let maxFrequency = min(20_000 as Float, nyquist)
        let minFrequency: Float = 20

        let totalFrames = max(0, Int(file.length))
        let estimatedColumns = max(1, (totalFrames - fftSize) / max(1, hopSize) + 1)
        let width = max(1, min(requestedWidth, estimatedColumns))
        let columnsPerPixel = max(1.0, Double(estimatedColumns) / Double(width))

        var heatmap = [Float](repeating: 0, count: width * targetHeight)
        var rowToBin = [Int](repeating: 0, count: targetHeight)
        for y in 0..<targetHeight {
            let normalized = 1.0 - Float(y) / Float(max(targetHeight - 1, 1))
            let frequency = minFrequency * powf(maxFrequency / minFrequency, normalized)
            let bin = Int((frequency / nyquist) * Float(fftSize - 1))
            rowToBin[y] = max(0, min(fftSize - 1, bin))
        }

        guard let dct = vDSP.DCT(count: fftSize, transformType: .II) else {
            throw MeasurementDataError.ioFailure("DCT Setup konnte nicht erstellt werden.")
        }

        let window = WindowFunction.hann.generate(size: fftSize)
        var windowed = [Float](repeating: 0, count: fftSize)
        var coefficients = [Float](repeating: 0, count: fftSize)
        var magnitudes = [Float](repeating: 0, count: fftSize)

        var overlap = [Float]()
        let chunkFrames = fftSize * 8
        var sourceColumn = 0

        while file.framePosition < file.length {
            let remaining = Int(file.length - file.framePosition)
            let toRead = AVAudioFrameCount(min(chunkFrames, remaining))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: toRead) else { break }
            try file.read(into: buffer)
            guard let channel = buffer.floatChannelData?[0] else { break }

            let count = Int(buffer.frameLength)
            let samples = overlap + Array(UnsafeBufferPointer(start: channel, count: count))

            var offset = 0
            while offset + fftSize <= samples.count {
                let pixelX = min(width - 1, Int(Double(sourceColumn) / columnsPerPixel))
                sourceColumn += 1

                samples.withUnsafeBufferPointer { ptr in
                    vDSP_vmul(ptr.baseAddress! + offset, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
                }

                dct.transform(windowed, result: &coefficients)
                vDSP_vabs(coefficients, 1, &magnitudes, 1, vDSP_Length(fftSize))
                var scale = 2.0 / Float(fftSize)
                vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize))

                for y in 0..<targetHeight {
                    let bin = rowToBin[y]
                    let db = 20 * log10(magnitudes[bin] + 1e-12) + calibrationOffset
                    let dbfs = db - calibrationOffset
                    let normalized = max(0, min(1, (dbfs - minDb) / max(maxDb - minDb, 1e-6)))
                    let index = y * width + pixelX
                    if normalized > heatmap[index] {
                        heatmap[index] = normalized
                    }
                }

                offset += hopSize
            }

            overlap = offset < samples.count ? Array(samples[offset..<samples.count]) : []
        }

        let argb = Self.makeARGBPixels(fromNormalizedHeatmap: heatmap, width: width, height: targetHeight)
        return try makeUIImage(fromARGB: argb, width: width, height: targetHeight)
    }

    private func makeUIImage(fromARGB argb: [UInt8], width: Int, height: Int) throws -> UIImage {
        let provider = CGDataProvider(data: Data(argb) as CFData)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw MeasurementDataError.ioFailure("Bild konnte nicht erstellt werden.")
        }
        return UIImage(cgImage: cg)
    }

    private static func makeARGBPixels(fromNormalizedHeatmap heatmap: [Float], width: Int, height: Int) -> [UInt8] {
        let pixelCount = width * height
        guard pixelCount > 0 else { return [] }

        var indices = [UInt8](repeating: 0, count: pixelCount)
        for index in 0..<min(pixelCount, heatmap.count) {
            let t = max(0, min(1, heatmap[index]))
            indices[index] = UInt8(t * 255.0 + 0.5)
        }

        var redTable = [UInt8](repeating: 0, count: 256)
        var greenTable = [UInt8](repeating: 0, count: 256)
        var blueTable = [UInt8](repeating: 0, count: 256)
        for index in 0..<256 {
            let color = color(for: Float(index) / 255.0)
            redTable[index] = color.r
            greenTable[index] = color.g
            blueTable[index] = color.b
        }

        var alpha = [UInt8](repeating: 255, count: pixelCount)
        var red = [UInt8](repeating: 0, count: pixelCount)
        var green = [UInt8](repeating: 0, count: pixelCount)
        var blue = [UInt8](repeating: 0, count: pixelCount)
        var argb = [UInt8](repeating: 0, count: pixelCount * 4)

        indices.withUnsafeMutableBufferPointer { indexPtr in
            red.withUnsafeMutableBufferPointer { redPtr in
                green.withUnsafeMutableBufferPointer { greenPtr in
                    blue.withUnsafeMutableBufferPointer { bluePtr in
                        var source = vImage_Buffer(
                            data: indexPtr.baseAddress!,
                            height: vImagePixelCount(height),
                            width: vImagePixelCount(width),
                            rowBytes: width
                        )
                        var redBuffer = vImage_Buffer(data: redPtr.baseAddress!, height: source.height, width: source.width, rowBytes: width)
                        var greenBuffer = vImage_Buffer(data: greenPtr.baseAddress!, height: source.height, width: source.width, rowBytes: width)
                        var blueBuffer = vImage_Buffer(data: bluePtr.baseAddress!, height: source.height, width: source.width, rowBytes: width)

                        redTable.withUnsafeBufferPointer { table in
                            _ = vImageTableLookUp_Planar8(&source, &redBuffer, table.baseAddress!, vImage_Flags(kvImageNoFlags))
                        }
                        greenTable.withUnsafeBufferPointer { table in
                            _ = vImageTableLookUp_Planar8(&source, &greenBuffer, table.baseAddress!, vImage_Flags(kvImageNoFlags))
                        }
                        blueTable.withUnsafeBufferPointer { table in
                            _ = vImageTableLookUp_Planar8(&source, &blueBuffer, table.baseAddress!, vImage_Flags(kvImageNoFlags))
                        }
                    }
                }
            }
        }

        alpha.withUnsafeMutableBufferPointer { alphaPtr in
            red.withUnsafeMutableBufferPointer { redPtr in
                green.withUnsafeMutableBufferPointer { greenPtr in
                    blue.withUnsafeMutableBufferPointer { bluePtr in
                        argb.withUnsafeMutableBufferPointer { argbPtr in
                            var alphaBuffer = vImage_Buffer(data: alphaPtr.baseAddress!, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                            var redBuffer = vImage_Buffer(data: redPtr.baseAddress!, height: alphaBuffer.height, width: alphaBuffer.width, rowBytes: width)
                            var greenBuffer = vImage_Buffer(data: greenPtr.baseAddress!, height: alphaBuffer.height, width: alphaBuffer.width, rowBytes: width)
                            var blueBuffer = vImage_Buffer(data: bluePtr.baseAddress!, height: alphaBuffer.height, width: alphaBuffer.width, rowBytes: width)
                            var dest = vImage_Buffer(data: argbPtr.baseAddress!, height: alphaBuffer.height, width: alphaBuffer.width, rowBytes: width * 4)
                            _ = vImageConvert_Planar8toARGB8888(
                                &alphaBuffer,
                                &redBuffer,
                                &greenBuffer,
                                &blueBuffer,
                                &dest,
                                vImage_Flags(kvImageNoFlags)
                            )
                        }
                    }
                }
            }
        }

        return argb
    }

    private static func color(for value: Float) -> (r: UInt8, g: UInt8, b: UInt8) {
        let t = max(0, min(1, value))
        let r = max(0, min(1, 1.8 * t - 0.5))
        let g = max(0, min(1, 1.6 * t))
        let b = max(0, min(1, 1.2 - 1.2 * t))
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }
}
#endif

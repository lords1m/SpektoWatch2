#if canImport(UIKit)
import UIKit
import AVFoundation
import Accelerate

final class SpectrogramImageRenderer {
    func renderSpectrogramImage(
        audioURL: URL,
        targetWidth requestedWidth: Int = 1200,
        targetHeight: Int = 420,
        fftSize: Int = 4096,
        hopSize: Int = 512,
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
            let bin = Int((frequency / nyquist) * Float((fftSize / 2) - 1))
            rowToBin[y] = max(0, min((fftSize / 2) - 1, bin))
        }

        guard let fftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD) else {
            throw MeasurementDataError.ioFailure("FFT Setup konnte nicht erstellt werden.")
        }
        defer { vDSP_DFT_DestroySetup(fftSetup) }

        var window = [Float](repeating: 0, count: fftSize)
        // Manual Hann window implementation to avoid vDSP API compatibility issues
        let n = Float(fftSize)
        for i in 0..<fftSize {
            let x = Float(i) / n
            window[i] = 0.5 - 0.5 * cos(2 * .pi * x)
        }

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

                var windowed = [Float](repeating: 0, count: fftSize)
                samples.withUnsafeBufferPointer { ptr in
                    vDSP_vmul(ptr.baseAddress! + offset, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
                }

                var realIn = [Float](repeating: 0, count: fftSize / 2)
                var imagIn = [Float](repeating: 0, count: fftSize / 2)
                for i in 0..<(fftSize / 2) {
                    realIn[i] = windowed[2 * i]
                    imagIn[i] = windowed[2 * i + 1]
                }

                var realOut = [Float](repeating: 0, count: fftSize / 2)
                var imagOut = [Float](repeating: 0, count: fftSize / 2)
                vDSP_DFT_Execute(fftSetup, realIn, imagIn, &realOut, &imagOut)

                var magnitudes = [Float](repeating: 0, count: fftSize / 2)
                realOut.withUnsafeMutableBufferPointer { realPtr in
                    imagOut.withUnsafeMutableBufferPointer { imagPtr in
                        var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                    }
                }

                for y in 0..<targetHeight {
                    let bin = rowToBin[y]
                    let db = 20 * log10(magnitudes[bin] + 1e-12)
                    let normalized = max(0, min(1, (db - minDb) / max(maxDb - minDb, 1e-6)))
                    let index = y * width + pixelX
                    if normalized > heatmap[index] {
                        heatmap[index] = normalized
                    }
                }

                offset += hopSize
            }

            overlap = offset < samples.count ? Array(samples[offset..<samples.count]) : []
        }

        var rgba = [UInt8](repeating: 0, count: width * targetHeight * 4)
        for y in 0..<targetHeight {
            for x in 0..<width {
                let intensity = heatmap[y * width + x]
                let color = Self.color(for: intensity)
                let pixelIndex = (y * width + x) * 4
                rgba[pixelIndex + 0] = color.r
                rgba[pixelIndex + 1] = color.g
                rgba[pixelIndex + 2] = color.b
                rgba[pixelIndex + 3] = 255
            }
        }

        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let cg = CGImage(
            width: width,
            height: targetHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!

        return UIImage(cgImage: cg)
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

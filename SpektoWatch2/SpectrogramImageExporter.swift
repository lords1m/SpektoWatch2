#if canImport(UIKit)
import UIKit

final class SpectrogramImageExporter {
    enum ExportError: LocalizedError {
        case audioNotFound(URL)
        case emptyHistory
        case renderFailed(Error)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .audioNotFound(let url):
                return "Audiodatei nicht gefunden: \(url.lastPathComponent)"
            case .emptyHistory:
                return "Kein Spektrogramm zum Exportieren vorhanden."
            case .renderFailed(let error):
                return "Spektrogramm konnte nicht berechnet werden: \(error.localizedDescription)"
            case .writeFailed(let error):
                return "Bild konnte nicht gespeichert werden: \(error.localizedDescription)"
            }
        }
    }

    private let renderer: SpectrogramImageRenderer

    init(renderer: SpectrogramImageRenderer = SpectrogramImageRenderer()) {
        self.renderer = renderer
    }

    /// Renders from the on-screen history when available (matches playback overview).
    func export(
        history: [[Float]],
        axis: SpectrogramHistoryAxisKind,
        sampleRate: Double,
        calibrationOffset: Float,
        recordingID: String
    ) throws -> URL {
        guard !history.isEmpty else { throw ExportError.emptyHistory }

        let image: UIImage
        do {
            image = try renderer.renderSpectrogramImage(
                history: history,
                axis: axis,
                sampleRate: sampleRate,
                calibrationOffset: calibrationOffset
            )
        } catch {
            throw ExportError.renderFailed(error)
        }
        return try writePNG(image, recordingID: recordingID)
    }

    /// Renders a spectrogram PNG from audio using the recording's FFT settings.
    func export(
        audioURL: URL,
        recordingID: String,
        fftSize: Int,
        calibrationOffset: Float
    ) throws -> URL {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ExportError.audioNotFound(audioURL)
        }

        let resolvedFFT = max(256, fftSize)
        let hopSize = SpectrogramHistoryAxis.hopSize(forFFTSize: resolvedFFT)

        let image: UIImage
        do {
            image = try renderer.renderSpectrogramImage(
                audioURL: audioURL,
                fftSize: resolvedFFT,
                hopSize: hopSize,
                calibrationOffset: calibrationOffset
            )
        } catch {
            throw ExportError.renderFailed(error)
        }
        return try writePNG(image, recordingID: recordingID)
    }

    private func writePNG(_ image: UIImage, recordingID: String) throws -> URL {
        guard let pngData = image.pngData() else {
            throw ExportError.renderFailed(NSError(domain: "SpectrogramImageExporter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "PNG-Kodierung fehlgeschlagen."]))
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(recordingID)_spectrogram.png")
        do {
            try pngData.write(to: outputURL, options: .atomic)
        } catch {
            throw ExportError.writeFailed(error)
        }
        return outputURL
    }
}
#endif

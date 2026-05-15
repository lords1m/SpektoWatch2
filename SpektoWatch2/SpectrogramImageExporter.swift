#if canImport(UIKit)
import UIKit

final class SpectrogramImageExporter {
    enum ExportError: LocalizedError {
        case audioNotFound(URL)
        case renderFailed(Error)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .audioNotFound(let url):
                return "Audiodatei nicht gefunden: \(url.lastPathComponent)"
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

    /// Renders a spectrogram PNG for the given audio URL and writes it to a temp file.
    func export(audioURL: URL, recordingID: String) throws -> URL {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ExportError.audioNotFound(audioURL)
        }

        let image: UIImage
        do {
            image = try renderer.renderSpectrogramImage(audioURL: audioURL)
        } catch {
            throw ExportError.renderFailed(error)
        }

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

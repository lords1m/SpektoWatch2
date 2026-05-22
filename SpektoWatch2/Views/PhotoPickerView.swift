import PhotosUI
import SwiftUI

/// Thin `PHPickerViewController` wrapper used by `RecordingDetailView`
/// to attach a single photo to a recording. Extracted from
/// `RecordingDetailView.swift` as part of M13 task-2.
struct PhotoPickerView: UIViewControllerRepresentable {
    let onPick: (Data?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (Data?) -> Void
        init(onPick: @escaping (Data?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                onPick(nil)
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                let data = (object as? UIImage).flatMap { $0.jpegData(compressionQuality: 0.85) }
                DispatchQueue.main.async { self?.onPick(data) }
            }
        }
    }
}

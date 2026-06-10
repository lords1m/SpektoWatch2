import SwiftUI

// Dedicated card views extracted from `RecordingDetailView`. Keeping these as
// standalone `View` types (instead of computed properties on the detail view)
// lets SwiftUI skip re-rendering them while the playhead ticks ~33×/s during
// playback — only the playback/transport section depends on `currentTime`.

// MARK: - Header

struct RecordingHeaderCard: View {
    let name: String
    let formattedDate: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            Text(name)
                .font(.title3.bold())
            Text(formattedDate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassCard(cornerRadius: 14)
    }
}

// MARK: - Statistics

struct RecordingStatisticsCard: View {
    let laeqFast: Float
    let peakLevel: Float
    let minLevel: Float
    let formattedDuration: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistik")
                .font(.headline)
            Divider()
            StatRow(icon: "waveform.path", title: "LAeq,Fast", value: String(format: "%.1f dB", laeqFast))
            StatRow(icon: "arrow.up.circle", title: "Maximum", value: String(format: "%.1f dB", peakLevel))
            StatRow(icon: "arrow.down.circle", title: "Minimum", value: String(format: "%.1f dB", minLevel))
            StatRow(icon: "clock", title: "Dauer", value: formattedDuration)
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }
}

// MARK: - Configuration

struct RecordingConfigurationCard: View {
    let timeWeighting: String
    let frequencyWeighting: String
    let sampleRate: Double
    let fftBlockSize: Int
    let calibrationOffset: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Konfiguration")
                .font(.headline)
            Divider()
            StatRow(icon: "gauge", title: "Zeitbewertung", value: timeWeighting)
            StatRow(icon: "slider.horizontal.3", title: "Frequenzbewertung", value: frequencyWeighting)
            StatRow(icon: "music.note", title: "Samplerate", value: "\(Int(sampleRate)) Hz")
            StatRow(icon: "hammer", title: "FFT", value: "\(fftBlockSize)")
            StatRow(icon: "ruler", title: "Kalibrierung", value: String(format: "%.1f dB", calibrationOffset))
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }
}

// MARK: - Notes

struct RecordingNotesCard: View {
    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notizen")
                .font(.headline)
            Divider()
            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .frame(minHeight: 72)
                .onChange(of: text) { _, _ in onCommit() }
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Notizen hinzufügen…")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding()
        .glassCard(cornerRadius: 14)
    }
}

// MARK: - Photos

struct RecordingPhotosCard: View {
    let photoFileNames: [String]
    let photoURL: (String) -> URL
    var onDelete: (String) -> Void
    var onAdd: (Data?) -> Void

    @State private var showPhotoPicker = false
    /// Thumbnails are decoded once per file and cached, so the card no longer
    /// reads images from disk inside `body` on every re-render.
    @State private var thumbnails: [String: UIImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fotos")
                    .font(.headline)
                Spacer()
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Hinzufügen", systemImage: "plus")
                        .font(.caption)
                }
            }
            Divider()
            if photoFileNames.isEmpty {
                Text("Keine Fotos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photoFileNames, id: \.self) { fileName in
                            thumbnail(for: fileName)
                        }
                    }
                }
            }
        }
        .padding()
        .glassCard(cornerRadius: 14)
        .task(id: photoFileNames) {
            await loadThumbnails()
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(isPresented: $showPhotoPicker) { imageData in
                onAdd(imageData)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for fileName: String) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = thumbnails[fileName] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 90, height: 90)
                    .overlay(Image(systemName: "photo").foregroundStyle(.gray))
            }
            Button {
                onDelete(fileName)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .padding(4)
        }
    }

    private func loadThumbnails() async {
        var loaded: [String: UIImage] = [:]
        for fileName in photoFileNames {
            if let cached = thumbnails[fileName] {
                loaded[fileName] = cached
                continue
            }
            let url = photoURL(fileName)
            if let image = UIImage(contentsOfFile: url.path) {
                loaded[fileName] = image
            }
        }
        thumbnails = loaded
    }
}

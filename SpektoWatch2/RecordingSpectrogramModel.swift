import Foundation
import AVFoundation
import Accelerate
import Combine

/// Owns the stored-measurement spectrogram pipeline for `RecordingDetailView`:
/// loading the `.spekto` overview (or recomputing from audio), applying
/// frequency weighting, promoting third-octave data to full resolution, and
/// serving level-of-detail tiles.
///
/// Extracted from `RecordingDetailView` so the DSP/model work no longer lives
/// in the view and the heavy state is observed independently of the playhead.
@MainActor
final class RecordingSpectrogramModel: ObservableObject {
    nonisolated static let maxOverviewFrames = 1_800
    /// UI-5: `true` once the 31-band overview was replaced by the
    /// audio-derived full-resolution history.
    private var isPromoted = false

    /// Display-ready history in raw dB SPL (`[column][bin]`).
    @Published private(set) var history: [[Float]] = []
    /// Bumped whenever `history` content changes so the Metal renderer reloads
    /// even when the column count is unchanged (e.g. a weighting switch).
    @Published private(set) var version = 0
    @Published private(set) var axis: SpectrogramHistoryAxisKind = .logSpaced
    @Published private(set) var isLoading = false
    @Published private(set) var isPromotingResolution = false
    @Published private(set) var hasMeasurementData = false
    @Published private(set) var usesAudioSpectralFallback = false
    /// Bumped when `provider` changes so views can react to its availability.
    @Published private(set) var providerToken = 0

    private(set) var provider: StoredDataProvider?

    /// Called on the main actor once the spectral-availability flag is known.
    var onSpectralFlagResolved: ((Bool) -> Void)?
    /// Called on the main actor when the stored provider finishes bootstrapping.
    var onMeasurementDataReady: ((StoredDataProvider) -> Void)?

    private var rawHistory: [[Float]] = []
    private var weightedCache: [FrequencyWeighting: [[Float]]] = [:]
    private var currentWeighting: FrequencyWeighting = .z
    private var loadTask: Task<Void, Never>?
    private var weightingTask: Task<Void, Never>?

    private var audioURL: URL?
    private var calibrationOffset: Float = 94
    private var fftBlockSize: Int = 4096
    private var fallbackSampleRate: Double = 44_100

    var sampleRate: Double { provider?.sampleRate ?? fallbackSampleRate }

    // MARK: - Lifecycle

    func cancel() {
        provider?.pause()
        loadTask?.cancel()
        loadTask = nil
        weightingTask?.cancel()
        weightingTask = nil
    }

    func scrub(to time: TimeInterval) { provider?.scrub(to: time) }
    func providerPlay() { provider?.play() }
    func providerPause() { provider?.pause() }

    private func setHistory(_ newHistory: [[Float]]) {
        history = newHistory
        version &+= 1
    }

    private func setProvider(_ newProvider: StoredDataProvider?) {
        provider = newProvider
        providerToken &+= 1
    }

    // MARK: - Loading

    func load(
        measurementURL: URL?,
        audioURL: URL,
        calibrationOffset: Float,
        fftBlockSize: Int,
        fallbackSampleRate: Double,
        weighting: FrequencyWeighting
    ) {
        self.audioURL = audioURL
        self.calibrationOffset = calibrationOffset
        self.fftBlockSize = fftBlockSize
        self.fallbackSampleRate = fallbackSampleRate
        self.currentWeighting = weighting

        loadTask?.cancel()

        guard let measurementURL,
              FileManager.default.fileExists(atPath: measurementURL.path) else {
            loadFallback(weighting: weighting)
            return
        }

        let maxOverviewFrames = Self.maxOverviewFrames
        isLoading = true
        loadTask = Task.detached(priority: .userInitiated) {
            let result: Result<(StoredDataProvider, [[Float]], Bool), Error>
            do {
                let provider = try StoredDataProvider(fileURL: measurementURL)
                let spectralOK = MeasurementSpectralAvailability.hasUsableSpectralData(fileURL: measurementURL)
                let window = try await provider.spectrogramOverview(maxFrameCount: maxOverviewFrames)
                result = .success((provider, window.bins, spectralOK))
            } catch {
                result = .failure(error)
            }
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                switch result {
                case .success(let (provider, visualHistory, spectralOK)):
                    self.setProvider(provider)
                    self.hasMeasurementData = true
                    self.onSpectralFlagResolved?(spectralOK)
                    self.usesAudioSpectralFallback = !spectralOK
                    if spectralOK {
                        self.isPromoted = false
                        self.rawHistory = visualHistory
                        let binCount = visualHistory.first?.count ?? 0
                        self.axis = SpectrogramHistoryAxis.infer(
                            binCount: binCount,
                            hasFullFFT: provider.hasFullFFT,
                            fftBinCount: provider.fftBinCount
                        )
                        self.weightedCache.removeAll()
                        self.applyWeighting(self.currentWeighting)
                        // UI-6: only the stored path is done here.
                        self.isLoading = false
                    } else {
                        // UI-6: the fallback recompute clears `isLoading`.
                        self.loadFallback(weighting: self.currentWeighting)
                    }
                    self.onMeasurementDataReady?(provider)
                case .failure(let error):
                    print("[RecordingSpectrogramModel] Failed to load stored measurement data: \(error)")
                    self.loadFallback(weighting: self.currentWeighting)
                }
            }
        }
    }

    private func loadFallback(weighting: FrequencyWeighting) {
        loadTask?.cancel()
        guard let url = audioURL else {
            isLoading = false
            return
        }
        let calibrationOffset = self.calibrationOffset
        let fftBlockSize = self.fftBlockSize
        isLoading = true
        loadTask = Task.detached(priority: .userInitiated) {
            let result = Result {
                try Self.computeHistoryStreaming(
                    url: url,
                    calibrationOffset: calibrationOffset,
                    fftBlockSize: fftBlockSize
                )
            }
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                switch result {
                case .success(let history):
                    self.rawHistory = history
                    self.axis = .logSpaced
                    self.weightedCache.removeAll()
                    self.applyWeighting(weighting)
                    self.usesAudioSpectralFallback = self.provider != nil
                case .failure:
                    break
                }
                self.isLoading = false
            }
        }
    }

    // MARK: - Weighting

    func applyWeighting(_ weighting: FrequencyWeighting) {
        currentWeighting = weighting
        guard !rawHistory.isEmpty else {
            setHistory([])
            return
        }

        if weighting != .z, shouldPromoteResolution(), !isPromotingResolution {
            promoteResolutionThenApply(weighting)
            return
        }

        // UI-5: once promoted to the audio-derived full-resolution history,
        // weighting must stay on that history (it used to fall back to the
        // stored 31-band overview).
        if isPromoted {
            if weighting == .z {
                setHistory(rawHistory)
            } else {
                applyProcessorWeighting(weighting)
            }
            return
        }

        if let provider, hasMeasurementData, !usesAudioSpectralFallback {
            if provider.hasFullFFT {
                applyFFTWeighting(weighting)
            } else {
                reloadStoredOverview(weighting: weighting)
            }
            return
        }

        if weighting == .z {
            setHistory(rawHistory)
            return
        }

        applyProcessorWeighting(weighting)
    }

    private func applyFFTWeighting(_ weighting: FrequencyWeighting) {
        if weighting == .z {
            setHistory(rawHistory)
            return
        }
        if let cached = weightedCache[weighting] {
            setHistory(cached)
            return
        }
        applyProcessorWeighting(weighting)
    }

    private func reloadStoredOverview(weighting: FrequencyWeighting) {
        if weighting == .z {
            setHistory(rawHistory)
            return
        }
        if let cached = weightedCache[weighting] {
            setHistory(cached)
            return
        }
        guard let provider else { return }

        weightingTask?.cancel()
        let maxFrames = Self.maxOverviewFrames
        weightingTask = Task.detached(priority: .userInitiated) {
            do {
                let window = try await provider.spectrogramOverview(
                    maxFrameCount: maxFrames,
                    weighting: weighting
                )
                if Task.isCancelled { return }
                let bins = window.bins
                await MainActor.run { [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    self.weightedCache = [weighting: bins]
                    if self.currentWeighting == weighting {
                        self.setHistory(bins)
                    }
                }
            } catch {
                if Task.isCancelled { return }
                print("[RecordingSpectrogramModel] Failed to load \(weighting.rawValue)-weighted overview: \(error)")
            }
        }
    }

    private func applyProcessorWeighting(_ weighting: FrequencyWeighting) {
        if let cached = weightedCache[weighting] {
            setHistory(cached)
            return
        }

        let binCount = rawHistory.first?.count ?? provider?.fftBinCount ?? 0
        let sampleRate = provider?.sampleRate ?? fallbackSampleRate
        guard binCount > 0 else {
            setHistory(rawHistory)
            return
        }

        let fftSize = max(binCount * 2, 256)
        let processor = FrequencyWeightingProcessor(fftSize: fftSize, sampleRate: sampleRate)
        let frequencies = SpectrogramHistoryAxis.frequencyAxis(
            kind: axis,
            binCount: binCount,
            sampleRate: sampleRate
        )
        let source = rawHistory

        weightingTask?.cancel()
        weightingTask = Task.detached(priority: .userInitiated) {
            var weightedHistory: [[Float]] = []
            weightedHistory.reserveCapacity(source.count)
            for column in source {
                weightedHistory.append(
                    processor.applyWeighting(to: column, frequencies: frequencies, weighting: weighting)
                )
            }
            if Task.isCancelled { return }
            let snapshot = weightedHistory
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.weightedCache = [weighting: snapshot]
                if self.currentWeighting == weighting {
                    self.setHistory(snapshot)
                }
            }
        }
    }

    private func shouldPromoteResolution() -> Bool {
        guard let first = rawHistory.first else { return false }
        if first.count > MeasurementDataFormat.thirdOctaveBandCount {
            return false
        }
        if let provider, provider.hasFullFFT {
            return false
        }
        return true
    }

    private func promoteResolutionThenApply(_ weighting: FrequencyWeighting) {
        loadTask?.cancel()
        isPromotingResolution = true
        guard let url = audioURL else { isPromotingResolution = false; return }
        let calibrationOffset = self.calibrationOffset
        let fftBlockSize = self.fftBlockSize
        loadTask = Task.detached(priority: .userInitiated) {
            let result = Result {
                try Self.computeHistoryStreaming(
                    url: url,
                    calibrationOffset: calibrationOffset,
                    fftBlockSize: fftBlockSize
                )
            }
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                switch result {
                case .success(let history):
                    self.rawHistory = history
                    self.axis = .logSpaced
                    self.weightedCache.removeAll()
                    self.isPromotingResolution = false
                    self.isPromoted = true
                    self.applyWeighting(weighting)
                case .failure:
                    self.isPromotingResolution = false
                    self.setHistory(self.rawHistory)
                }
            }
        }
    }

    // MARK: - Level of detail

    /// Builds a tile loader for `NavigableSpectrogramView`, or `nil` when there's
    /// no full-resolution stored spectrum to zoom into.
    func makeDetailTileLoader() -> ((ClosedRange<TimeInterval>, Int) async -> [[Float]]?)? {
        guard let provider, hasMeasurementData, !usesAudioSpectralFallback else {
            return nil
        }
        let weighting = currentWeighting
        return { range, maxColumns in
            await Task.detached(priority: .userInitiated) { () -> [[Float]]? in
                let window = try? await provider.spectrogramTile(
                    timeRange: range,
                    maxColumns: maxColumns,
                    weighting: weighting
                )
                let bins = window?.bins ?? []
                return bins.isEmpty ? nil : bins
            }.value
        }
    }

    // MARK: - DSP

    nonisolated static func computeHistoryStreaming(
        url: URL,
        calibrationOffset: Float,
        fftBlockSize: Int,
        maxColumns: Int = RecordingSpectrogramModel.maxOverviewFrames
    ) throws -> [[Float]] {
        let fftSize = max(256, fftBlockSize > 0 ? fftBlockSize : 4096)
        let hopSize = SpectrogramHistoryAxis.hopSize(forFFTSize: fftSize)
        let frequencyBins = SpectrogramHistoryAxis.logBinCount(
            forFFTSize: fftSize,
            resolution: SpectrogramResolution.current
        )
        let chunkFrames = fftSize * 8

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat

        guard let dct = vDSP.DCT(count: fftSize, transformType: .II) else { return [] }

        let window = WindowFunction.hann.generate(size: fftSize)
        var windowed = [Float](repeating: 0, count: fftSize)
        var coefficients = [Float](repeating: 0, count: fftSize)
        var magnitudes = [Float](repeating: 0, count: fftSize)

        // UI-1: max-pool hops into at most `maxColumns` columns while
        // streaming, so long recordings neither exceed the Metal texture
        // width (16384) nor hold hundreds of MB of columns.
        let totalHops = max(1, Int((audioFile.length - Int64(fftSize)) / Int64(max(1, hopSize))) + 1)
        let poolFactor = max(1, Int((Double(totalHops) / Double(max(1, maxColumns))).rounded(.up)))
        var pooled = [Float](repeating: -.infinity, count: frequencyBins)
        var pooledCount = 0

        var history: [[Float]] = []
        history.reserveCapacity(min(totalHops, maxColumns) + 1)
        var overlap = [Float]()

        while audioFile.framePosition < audioFile.length {
            let remaining = audioFile.length - audioFile.framePosition
            let toRead = AVAudioFrameCount(min(Int64(chunkFrames), remaining))

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: toRead),
                  (try? audioFile.read(into: buffer)) != nil,
                  let channelData = buffer.floatChannelData else { break }

            let frameLength = Int(buffer.frameLength)
            let samples = overlap + Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

            var offset = 0
            while offset + fftSize <= samples.count {
                samples.withUnsafeBufferPointer { ptr in
                    vDSP_vmul(ptr.baseAddress! + offset, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
                }

                dct.transform(windowed, result: &coefficients)
                vDSP_vabs(coefficients, 1, &magnitudes, 1, vDSP_Length(fftSize))
                var scale = 2.0 / Float(fftSize)
                vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize))

                let minFreq: Float = 20.0
                let nyquist = Float(format.sampleRate) / 2.0
                let maxFreq: Float = min(nyquist, 20_000.0)
                let denomBins = Float(max(frequencyBins - 1, 1))
                let denomSrc = Float(max(magnitudes.count - 1, 1))
                var column = [Float](repeating: -120.0, count: frequencyBins)
                for i in 0..<frequencyBins {
                    let t = Float(i) / denomBins
                    let frequency = minFreq * powf(maxFreq / minFreq, t)
                    let srcIndex = min(magnitudes.count - 1, max(0, Int((frequency / nyquist) * denomSrc)))
                    column[i] = 20.0 * log10(magnitudes[srcIndex] + 1e-10) + calibrationOffset
                }

                if poolFactor == 1 {
                    history.append(column)
                } else {
                    vDSP_vmax(pooled, 1, column, 1, &pooled, 1, vDSP_Length(frequencyBins))
                    pooledCount += 1
                    if pooledCount == poolFactor {
                        history.append(pooled)
                        vDSP_vfill([-Float.infinity], &pooled, 1, vDSP_Length(frequencyBins))
                        pooledCount = 0
                    }
                }
                offset += hopSize
            }

            overlap = offset < samples.count ? Array(samples[offset..<samples.count]) : []
        }
        if pooledCount > 0 {
            history.append(pooled)
        }

        return history
    }
}

import Foundation
import Accelerate

/// Pure per-frame DSP for the live audio path: FFT → dB (+calibration) →
/// A/C weighting → spectrogram band processing → third-octave / Bark
/// aggregation → broadband energies (Z/A/C) → IEC 61672 LCpeak.
///
/// Owns the real-time scratch buffers so the audio render thread never
/// allocates in the steady state (buffers only grow when the FFT size
/// changes, via `resetScratch(energyCount:)`). Performs **no** UI work, holds
/// no `@Published` state, and reads no `AudioEngine` properties — every input
/// is passed in explicitly. The processors are passed per call (snapshotted by
/// the caller under its `processingLock`), so this type needs no lock of its
/// own; it is only ever touched from the audio render thread.
///
/// Extracted from `AudioEngine.processFFTFrame` in VERBESSERUNGSPLAN Phase 3,
/// Task 3.3. All math is verbatim.
final class ProcessingPipeline {

    /// All per-frame DSP outputs `AudioEngine` needs to feed metrics, the
    /// measurement writer, and the UI publish path.
    struct FrameResult {
        /// Full-resolution Z-weighted dB SPL magnitudes (calibration applied).
        let fullDBZ: [Float]
        let bandFrequencies: [Float]
        let bandMagnitudesZ: [Float]
        let bandMagnitudesA: [Float]?
        let bandMagnitudesC: [Float]?
        let displayOctaveBandsZ: [Float]
        let displayOctaveBandsA: [Float]
        let displayOctaveBandsC: [Float]
        let hasA: Bool
        let hasC: Bool
        let barkBandsZ: [Float]
        let barkBandsA: [Float]
        let barkBandsC: [Float]
        let energyZ: Float
        let energyA: Float
        let energyC: Float
        let lcPeak: Float
    }

    static let emptyThirdOctaveBands = [Float](
        repeating: -120.0,
        count: SpectrumBandAggregator.thirdOctaveCenters.count
    )

    // Reusable scratch buffers (audio-render-thread only). Resized only when
    // the FFT size changes — see `resetScratch(energyCount:)`.
    private var fftLinearMagnitudesScratch: [Float] = []
    private var fftDBMagnitudesScratch: [Float] = []
    private var fftEnergyScratch: [Float] = []
    /// Scratch buffer for per-bin C-weighted amplitudes used in LCpeak.
    /// Resized alongside `fftEnergyScratch` when the FFT size changes.
    private var lcPeakScratch: [Float] = []

    /// Clears the FFT magnitude scratch and pre-allocates the energy/LCpeak
    /// scratch to `energyCount` (= fftSize/2) so the audio render thread never
    /// hits the lazy-allocation branch in `computeFrame`. Called by the caller
    /// under its `processingLock` when the FFT size changes (AE-7).
    func resetScratch(energyCount: Int) {
        fftLinearMagnitudesScratch.removeAll()
        fftDBMagnitudesScratch.removeAll()
        fftEnergyScratch = [Float](repeating: 0, count: energyCount)
        lcPeakScratch = [Float](repeating: 0, count: energyCount)
    }

    /// Runs the full per-frame DSP. `samples` must already contain at least
    /// `fftProcessor`'s FFT size of samples (checked by the caller). The
    /// processors are the caller's lock-snapshotted instances.
    func computeFrame(
        samples: [Float],
        fftProcessor: FFTProcessor,
        weightingProcessor: FrequencyWeightingProcessor,
        spectrogramProcessor: SpectrogramProcessor,
        sampleRate: Double,
        gainBoost: Float,
        calibrationOffset cal: Float,
        needsA: Bool,
        needsC: Bool,
        needsBark: Bool
    ) -> FrameResult {
        // Perform FFT into reusable buffers to avoid per-frame result arrays.
        fftProcessor.performFFT(on: samples, gainBoost: gainBoost, into: &fftLinearMagnitudesScratch)
        fftProcessor.convertToDB(fftLinearMagnitudesScratch, into: &fftDBMagnitudesScratch)

        // Convert to dB for Spectrogram (dBFS → dB SPL mit Kalibrierung)
        var calOffset = cal
        vDSP_vsadd(fftDBMagnitudesScratch, 1, &calOffset, &fftDBMagnitudesScratch, 1, vDSP_Length(fftDBMagnitudesScratch.count))

        // Gate A/C spectral tracks to data consumers that actually need them.
        let dbZ = fftDBMagnitudesScratch
        let dbA = needsA ? weightingProcessor.applyWeighting(
            to: fftDBMagnitudesScratch, frequencies: fftProcessor.frequencies, weighting: .a) : nil
        let dbC = needsC ? weightingProcessor.applyWeighting(
            to: fftDBMagnitudesScratch, frequencies: fftProcessor.frequencies, weighting: .c) : nil

        // Spectrogram Processing (Filtering, Octaves, Binning, Smoothing)
        let processedZ = spectrogramProcessor.process(
            frequencies: fftProcessor.frequencies,
            dbMagnitudes: dbZ,
            sampleRate: sampleRate,
            smoothingTrack: .z
        )
        let processedA = dbA.map {
            spectrogramProcessor.process(
                frequencies: fftProcessor.frequencies,
                dbMagnitudes: $0,
                sampleRate: sampleRate,
                smoothingTrack: .a
            )
        }
        let processedC = dbC.map {
            spectrogramProcessor.process(
                frequencies: fftProcessor.frequencies,
                dbMagnitudes: $0,
                sampleRate: sampleRate,
                smoothingTrack: .c
            )
        }

        let displayOctaveBandsZ = SpectrumBandAggregator.thirdOctaveBands(
            frequencies: processedZ.bandFrequencies,
            spectrum: processedZ.bandMagnitudes
        )
        let displayOctaveBandsA = processedA.map {
            SpectrumBandAggregator.thirdOctaveBands(
                frequencies: $0.bandFrequencies,
                spectrum: $0.bandMagnitudes
            )
        } ?? Self.emptyThirdOctaveBands
        let displayOctaveBandsC = processedC.map {
            SpectrumBandAggregator.thirdOctaveBands(
                frequencies: $0.bandFrequencies,
                spectrum: $0.bandMagnitudes
            )
        } ?? Self.emptyThirdOctaveBands

        // Bark band aggregation — only when a widget requests it (zero-cost otherwise).
        // Uses the same binned band data as third-octave so no extra FFT pass is needed.
        let displayBarkBandsZ: [Float]
        let displayBarkBandsA: [Float]
        let displayBarkBandsC: [Float]
        if needsBark {
            displayBarkBandsZ = SpectrumBandAggregator.barkBands(
                frequencies: processedZ.bandFrequencies,
                spectrum: processedZ.bandMagnitudes
            )
            displayBarkBandsA = processedA.map {
                SpectrumBandAggregator.barkBands(frequencies: $0.bandFrequencies, spectrum: $0.bandMagnitudes)
            } ?? []
            displayBarkBandsC = processedC.map {
                SpectrumBandAggregator.barkBands(frequencies: $0.bandFrequencies, spectrum: $0.bandMagnitudes)
            } ?? []
        } else {
            displayBarkBandsZ = []
            displayBarkBandsA = []
            displayBarkBandsC = []
        }

        // Calculate energies for acoustic metrics using vectorized Accelerate ops
        let calibrationFactor = pow(10.0, cal / 10.0)
        let energyCount = min(fftLinearMagnitudesScratch.count,
                              min(weightingProcessor.aWeightingGainsSq.count,
                                  weightingProcessor.cWeightingGainsSq.count))
        if fftEnergyScratch.count != energyCount {
            fftEnergyScratch = [Float](repeating: 0, count: energyCount)
            lcPeakScratch = [Float](repeating: 0, count: energyCount)
        }
        vDSP_vsq(fftLinearMagnitudesScratch, 1, &fftEnergyScratch, 1, vDSP_Length(energyCount))

        var energyZ: Float = 0.0
        var energyA: Float = 0.0
        var energyC: Float = 0.0
        vDSP_sve(fftEnergyScratch, 1, &energyZ, vDSP_Length(energyCount))
        vDSP_dotpr(fftEnergyScratch, 1, weightingProcessor.aWeightingGainsSq, 1, &energyA, vDSP_Length(energyCount))
        vDSP_dotpr(fftEnergyScratch, 1, weightingProcessor.cWeightingGainsSq, 1, &energyC, vDSP_Length(energyCount))

        energyZ *= calibrationFactor
        energyA *= calibrationFactor
        energyC *= calibrationFactor

        // --- LCpeak (IEC 61672) ---
        // LCpeak must be derived from the C-weighted signal, not from the raw
        // broadband sample peak. We approximate the instantaneous peak of the
        // C-weighted signal by finding the maximum per-bin C-weighted amplitude
        // across the FFT frame and converting that to dB SPL.
        //
        // C-weighted amplitude for bin i = fftLinearMagnitudesScratch[i] * cGain[i]
        // (amplitude-domain multiply; cGains are amplitude-domain linear factors).
        let cGains = weightingProcessor.getWeightingGains(for: .c)
        let lcPeakCount = min(fftLinearMagnitudesScratch.count, cGains.count)
        if lcPeakScratch.count != lcPeakCount {
            lcPeakScratch = [Float](repeating: 0, count: lcPeakCount)
        }
        vDSP_vmul(fftLinearMagnitudesScratch, 1, cGains, 1, &lcPeakScratch, 1, vDSP_Length(lcPeakCount))
        var cPeakLinear: Float = 0.0
        vDSP_maxv(lcPeakScratch, 1, &cPeakLinear, vDSP_Length(lcPeakCount))
        // 20·log10 (amplitude domain) → dBFS, then add calibration → dB SPL
        let lcPeak = 20.0 * log10(cPeakLinear + 1e-9) + cal

        return FrameResult(
            fullDBZ: dbZ,
            bandFrequencies: processedZ.bandFrequencies,
            bandMagnitudesZ: processedZ.bandMagnitudes,
            bandMagnitudesA: processedA?.bandMagnitudes,
            bandMagnitudesC: processedC?.bandMagnitudes,
            displayOctaveBandsZ: displayOctaveBandsZ,
            displayOctaveBandsA: displayOctaveBandsA,
            displayOctaveBandsC: displayOctaveBandsC,
            hasA: processedA != nil,
            hasC: processedC != nil,
            barkBandsZ: displayBarkBandsZ,
            barkBandsA: displayBarkBandsA,
            barkBandsC: displayBarkBandsC,
            energyZ: energyZ,
            energyA: energyA,
            energyC: energyC,
            lcPeak: lcPeak
        )
    }
}

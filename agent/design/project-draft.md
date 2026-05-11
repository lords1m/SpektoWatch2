# SpektoWatch Project Draft

Status: draft  
Updated: 2026-05-11

## Feature Concept

SpektoWatch is an iOS and watchOS acoustic measurement app for live sound-level
monitoring, spectral analysis, measurement recording, and wearable companion
workflows.

The core feature concept is a field-ready acoustic dashboard: users can inspect
live dB levels, spectral content, loudness behavior, masking signals, and saved
measurements from a modular SwiftUI interface, while Apple Watch acts as a
companion display or wearable measurement surface.

## Goal

The goal is to make acoustic measurement fast, visual, and portable without
reducing the app to a basic sound meter.

SpektoWatch should:

- Show trustworthy live acoustic measurements with low interaction overhead.
- Make spectral content visible through spectrogram, waterfall, and band views.
- Record audio and structured measurement data for later review.
- Support configurable dashboards without fragmenting the underlying data path.
- Use Apple Watch as a meaningful measurement companion, not only a tiny mirror.
- Keep the audio and rendering hot paths efficient enough for sustained use.

## Pain Point

Existing sound measurement tools often fall into two weak categories:

- Basic dB meter apps are quick to open but hide the spectral detail needed to
  understand what is happening.
- Professional tools expose richer analysis but can be slow, expensive, or
  awkward to operate during field checks.

On Apple Watch, many measurement experiences are especially limited: the watch
is treated as a tiny phone screen instead of a wrist-level acoustic surface with
its own role.

## Problem Statement

Users need a way to monitor, understand, and record sound conditions in real
time across iPhone and Apple Watch.

The product must balance several constraints:

- The live audio path must remain low-latency and allocation-conscious.
- Spectral analysis must be visible and useful during measurement, not only
  after export.
- Recording must preserve structured measurement data, not just audio.
- WatchConnectivity bandwidth is limited, so raw audio streaming from watch to
  phone is fragile.
- The interface must stay dense and instrument-like without becoming hard to
  scan.

## Proposed Solution

Build SpektoWatch as a modular acoustic measurement instrument.

The iOS app provides the main analysis surface:

- AVFoundation microphone capture.
- Accelerate/vDSP FFT and metric processing.
- Frequency weighting and acoustic metrics.
- Metal-backed live and playback spectrogram rendering.
- Modular dashboard widgets for spectrum, level, loudness, tone generation,
  waterfall, and masking workflows.
- Recording persistence with metadata and measurement files.
- Export/report workflows for saved measurements.

The watch app provides a constrained companion surface:

- Display compact live measurement data from iPhone.
- Run local watch processing when the watch microphone is the active source.
- Send processed metrics or compact spectrogram data, not continuous raw audio.
- Evolve toward watch-native surfaces such as complications, Smart Stack
  widgets, and threshold notifications.

The engineering approach is to keep one clear live data pipeline, publish
bounded UI snapshots, and avoid duplicating expensive audio processing unless a
recording or explicit feature requires it.

## Requirements

### Functional Requirements

- Capture microphone audio on iOS and process it in real time.
- Compute FFT, frequency weighting, loudness, peak, and time-weighted acoustic
  metrics.
- Render live spectrogram, waterfall, spectrum, level, loudness, tone-generator,
  and masking-related widgets.
- Allow dashboard configuration and per-widget settings.
- Record audio and structured measurement data.
- Persist recordings with metadata, notes, photos, and exportable reports.
- Synchronize relevant state and compact live measurement data with watchOS.
- Support Apple Watch live monitoring with local watch processing where useful.

### Technical Requirements

- Keep AVAudioEngine callback work fast and allocation-conscious.
- Avoid synchronous file I/O on the audio processing path.
- Prefer Accelerate/vDSP operations over scalar loops in hot paths.
- Keep high-rate streams separate from broad `ObservableObject` invalidation.
- Preserve measurement file compatibility unless a migration is explicitly
  designed and tested.
- Keep watch transfer payloads compact and typed.
- Do not reintroduce continuous raw audio transfer over WatchConnectivity.

### Quality Requirements

- Unit-test pure transformations, file formats, protocol encoding, and metric
  calculations.
- Use targeted UI tests for important user-facing workflows.
- Benchmark or profile audio hot-path changes when performance is at risk.
- Run `./agent/scripts/acp-validate` for ACP-only changes.
- Run targeted Xcode tests for Swift behavior changes.

### Near-Term Requirements

- Stabilize modular dashboard and widget settings behavior.
- Reduce Swift-side audio hot-path cost:
  - precompute constant weighting values
  - avoid redundant A/C/Z processing when not recording
  - vectorize scalar FFT and metric loops
  - move measurement file writes off the audio path
- Consolidate duplicated legacy classes where target exceptions hide
  maintenance risk.
- Tighten watch protocol design around typed compact messages.
- Add watch-native surfaces such as complications, Smart Stack widgets, and
  threshold notifications.

## Agent Operating Notes

For future agent work:

- Read `AGENT.md`, `agent/progress.yaml`, and this draft first.
- Check `git status --short` before editing because the tree may contain active
  user work.
- Keep unrelated app changes isolated from ACP/documentation edits.
- Run `./agent/scripts/acp-validate` for ACP-only changes.
- Run targeted Xcode tests for Swift behavior changes.

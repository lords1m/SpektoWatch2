# Task 8-tone-generator: Tone Generator

Status: in_progress
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`

## Code-side pre-pass (2026-05-21)

Method step 1 completed. Hardware steps 2-5 still pending.

### Surface: settings UI

**None.** `WidgetSettingsView` has no `.toneGenerator` arm. The cog
icon falls through to the placeholder "Keine Einstellungen verfügbar
für diesen Widget-Typ." at line 255.

### Surface: render path & state

`SpektoWatch2/ToneGeneratorWidget.swift`:

- `ToneGeneratorWidget` declares `var settings: [String: String]` but
  **never reads from it**. Dead parameter.
- State lives in `@StateObject toneGenerator: ToneGenerator` — purely
  transient (in-memory). No persistence.
- `ToneGenerator` has its own `AVAudioEngine` (separate from the app's
  recording engine) and uses `AVAudioSourceNode` for real-time
  synthesis. Category set to `.playAndRecord, [.defaultToSpeaker,
  .mixWithOthers]` — so the tone plays alongside an active recording.
- Waveforms (`ToneGenerator.Waveform`): sine, square, sawtooth,
  triangle.
- UI: oscilloscope (top, pinch-to-fullscreen + corner button),
  numeric Hz readout, log-frequency slider 20…20 000 Hz, 10
  preset frequency chips (31.5, 63, 125, 250, 500, 1k, 2k, 4k,
  8k, 16k), waveform picker, linear amplitude slider 0…1, big
  Play/Stop button. Stops `onDisappear`.

### Findings (code-side only — no screenshots yet)

- ✅ **`NSLock` on the audio render thread finding outdated** —
  `ToneGenerator` already uses `OSAllocatedUnfairLock<SynthState>` with
  `withLockUnchecked` in the render callback (M11). No `NSLock` present.
- ✅ **Dead `settings` parameter removed** — `ToneGeneratorWidget.settings`
  removed; call site in `WidgetCardView` updated to `ToneGeneratorWidget()`.
  Landed 2026-05-28.
- ✅ **Frequency / amplitude / waveform persistence** — Three new
  `@AppStorage` keys (`toneGenerator.frequency`, `.amplitude`, `.waveform`)
  added to `PersistenceKeys.ToneGenerator`. Widget restores from
  AppStorage on `onAppear`; `onChange` observers write back on each change.
  Landed 2026-05-28.
- ⚠ **play-state still transient** — stopped is the safe default on
  cold-launch; routed to backlog (product decision: auto-resume tone on
  launch is unusual UX).
- ⚠ **No settings sheet** — falls to "Keine Einstellungen verfügbar"
  placeholder. Either hide the cog for `.toneGenerator` or add a
  proper sheet (presets editor, default-on-load behaviour).
- ⚠ **Preset highlighting is exact-only** — `abs(frequency - preset.1) < 1`
  only highlights when the slider lands exactly on a preset. Drag
  near 1000 Hz, you see no "1k" highlight. Either snap-to-preset on
  drag-release or widen the tolerance band.
- ⚠ **Linear amplitude slider** — `0…1` linear is perceptually wrong
  (psychoacoustic loudness ~ logarithmic). Consider exposing as dB
  (-60…0) or applying a `pow(x, 2)`-style mapping under the hood.
- ⚠ **Magnification-gesture fullscreen is undiscoverable** — the
  explicit corner button is fine, but the pinch path has no visual
  cue. Either remove it (one canonical path) or document via
  accessibilityHint.
- ⚠ **`onDisappear { toneGenerator.stop() }` semantics** — switching
  tabs / dashboard layouts kills the tone. Confirm with product:
  do we want the tone to keep playing when the user switches to
  the Recordings tab to compare?
- ⚠ **Audio session category change** — `setCategory(.playAndRecord,
  ...)` runs at start time. If the user is mid-recording with a
  different category (e.g. `.record` only), this silently mutates
  shared state. Worth verifying recording quality isn't disturbed
  when the tone starts.
- ⚠ **Size at 2×2 (`sizeRange(for: .toneGenerator).min`)** — six
  vertical UI groups (oscilloscope ≥ 100 pt + Hz readout + slider +
  preset row + waveform/volume row + Play button) need ~400 pt of
  vertical space. 2×2 cells on iPhone 12 mini are ~412 pt tall
  combined — fits exactly. Verify nothing overlaps on smallest
  allowed size.

### Pending (hardware)

- 📸 Screenshots per allowed size (`sizeRange(for: .toneGenerator)`:
  `2×2 … 3×4`).
- Click-free start/stop: tap Play, ensure no audible pop. Same for
  preset-tap mid-play.
- Tone routing while recording is active — does the recorded audio
  pick up the generated tone via the speaker→mic path? Expected
  yes, document.
- Persistence after app cold-launch: confirm finding above
  (everything resets).
- Magnification gesture: pinch to enter fullscreen, exit, re-enter
  via button. Same end state?

## Subject

- Widget type: `AudioWidgetType.generator` (verify exact case in
  `SpektoWatch2/WidgetConfiguration.swift`).
- Source: `SpektoWatch2/ToneGeneratorWidget.swift`
- Settings exposed: waveform, frequency, amplitude, routing

## Method

1. Read the widget source + its settings sheet. Note every public
   knob and every persisted setting key.
2. Launch on hardware (AGENT.md: local simulator is broken).
3. For every size in `WidgetConfiguration.sizeRange(for: .generator)`
   from min to max, capture a screenshot. Edit mode and view mode.
4. Cycle every settings combination. Capture before/after.
5. Stress: silence, clipped input, sample-rate change mid-stream,
   recording active vs inactive, dark mode, light mode.

## Specific checks

- click-free start/stop; routing to default output; persistence across app relaunch; behaviour while recording is active.
- Layout integrity at each allowed size.
- Touch-target accessibility (>= 44pt).
- Color contrast pass for the displayed metric text.
- No `Logger` errors / warnings on the relevant subsystem during
  the audit.
- Settings persist across app restart.

## Output

- `agent/screenshots/m9-generator-<n>.png` (or linked from a shared
  album — note the source location here).
- Per-screenshot one-line annotation in this task file under
  "Findings".
- Findings split into: ✅ confirmed working, ⚠ open issue (file
  follow-up + link), ❌ broken (block acceptance).

## Acceptance

- All size + settings combinations covered with at least one
  screenshot.
- Findings list is exhaustive — every ⚠ / ❌ either has a fix in
  this task or a queued follow-up backlog item.

## Non-Goals

- Refactoring the widget's internal architecture beyond fixing
  obvious bugs surfaced by the audit.
- Cross-widget consistency (handled by the acceptance task).

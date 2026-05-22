# M9 — Widget Audit Acceptance

Date: 2026-05-21
Branch: `redesign/liquid-glass` (audits ran across M9 + M12 work)
Milestone: M9 Widget Audit
Tasks covered: task-1 … task-10 (per-widget) + this report = task-11

## Status

**Code-side acceptance: complete.** All ten per-widget tasks have a
documented findings list with verdicts. Hardware screenshot grids
(every widget × every allowed size × edit/view × dark/light) remain
gated on a hardware session per `AGENT.md` (local simulator broken).

## Per-widget verdict

| # | Widget | Code-side verdict | Notes |
|---|---|---|---|
| 1 | Spectrogram | ✅ | 3 audit-driven code fixes landed (timeWeighting picker removed, scrollOffset knob purged end-to-end, per-widget frequencySmoothing added). |
| 2 | Waterfall | ⚠ | 4 medium findings (no minDB<maxDB cross-validation, 0.12 s throttle vs 60 fps cadence mismatch, O(n) `removeFirst` on history, arbitrary maxHistory cap). M12 also fixed the dBFS-vs-SPL default-range bug here. |
| 3 | Level History | ⚠ | 4 findings (conditional `freqWeighting`/`timeWeighting` pickers silently no-op outside AUTO mode; phon/sone overlay uses LAF regardless of explicit metric; dead `scrollOffset` knob (same dead-pattern that was purged from spectrogram); AUTO-vs-explicit label ambiguity). |
| 4 | Frequency Spectrum | ⚠ | 5 findings. **One was resolved in M12 task-8**: hardcoded 20-110 dB Y-axis is now editable via shared `chartYMinDB/chartYMaxDB`. Remaining: bandMode locked without override + no global fallback; dead `.octaveBands` arm in settings sheet after normalize-on-load; hardcoded leqAlpha=0.02; debug env var not `#if DEBUG`-gated. |
| 5 | Level Meter | ⚠ | 7 findings. **Two resolved in M12 task-8**: empty settings sheet now has the shared Y-bounds editor; hardcoded [30, 100] dB range now token-driven. Remaining: inconsistent peak-hold semantics (watch-source max-hold vs local-mic direct-assign), no peak-hold decay, hardcoded color thresholds, no weighting indicator on widget, multi-meter weighting limitation. |
| 6 | Phase Meter | **Deactivated** | **Resolved by removal in M12.** `AudioWidgetType.allCases` excludes `.phaseMeter`; `DashboardManager.normalizeWidgets` filters persisted instances. Enum case kept for legacy decoding only. All 6 prior findings are moot. |
| 7 | Single Value | ⚠ | 7 findings (metric locked without override; picker metric set inconsistent with LevelHistory's 15-option set; AttributedString switch is brittle; "0.0" placeholder ambiguous with real 0 dB; loudness fallback uses LAF regardless of weighting — shared with task-3; unit-suffix-by-prefix is fragile; no AUTO mode). |
| 8 | Tone Generator | ❌ **Blocker** | **Critical**: `NSLock` on the audio render thread (`ToneGenerator.phaseLock`, lines 95/100) — exactly the M6-task-6 anti-pattern that was fixed for `AudioEngine.processingLock` but missed because the tone generator runs its own AVAudioEngine. Plus 9 polish findings (dead `settings` param, no persistence across launch, no settings sheet, exact-match preset highlight, linear amplitude slider, undiscoverable pinch fullscreen, onDisappear stops tone, audio session category mutation during recording, 2×2 minimum is tight). |
| 9 | Spektralanalyse Lab | ⚠ | 10 findings (shared state across instances, no settings sheet, app-global FFT mutation without warning, no undo/reset, mid-recording mutation unverified, overlap slider step 25 looks continuous, duplicate Parameter/Fenster UI, German strings hardcoded, tight tabs at 2×2, nested ScrollView). |
| 10 | Masking | ⚠ | 6 findings (zero user-facing settings; convergence + novelty constants hardcoded; "Neu aufnehmen" resets without confirmation; no `accessibilityIdentifier`; 1×1 spectrum strip is thin; 3×3 footer mono text stays small while spectrum dominates; state colors are RGB literals, not `AccentChoice`). |

## Cross-cut findings

### 1. Empty settings sheet across multiple widget types (high)

`WidgetSettingsView` has no per-type arm for **toneGenerator**,
**spektralanalyseLab**, **masking**. Cog icon in edit mode opens
"Keine Einstellungen verfügbar für diesen Widget-Typ." placeholder.

**M12 partial resolution:** levelMeter now uses the shared
`yAxisBoundsSection`. The three above are still empty.

**Backlog:** either hide the cog for those widgets, or add per-type
settings (toneGenerator: persistence + default state; lab: default
tab + warning; masking: `minimumCaptures` + ambient calibration time).

### 2. Override-toggle UX inconsistency (medium)

Widgets that *have* an override toggle: spectrogram, waterfall,
levelHistory, frequencyDisplay, levelMeter, singleValue.

Without the toggle on, per-widget settings revert to **defaults**,
not to a **global app-level setting** — because none exists for
`bandMode` (task-4), `metric` (task-7), waterfall slice count, etc.
Net effect: a user who never flips override is permanently stuck on
factory defaults for keys that have no global fallback.

**Backlog (product decision required):** per-widget-only with no
override toggle (simpler) **or** add app-level defaults that the
toggle can fall back to.

### 3. Hardcoded dB ranges (resolved for most)

- **Waterfall:** had its own `waterfallMinDB`/`MaxDB` keys + migration
  from legacy dBFS scheme (M12).
- **LevelHistory, FrequencyDisplay, LevelMeter:** now use the shared
  `chartYMinDB`/`chartYMaxDB` keys + reusable `yAxisBoundsSection`
  (M12 task-8).
- **Spectrogram:** Y axis is frequency, not dB; dynamic range governed
  by the sensitivity setting + Metal shader. Out of scope.
- **Single Value, Tone Generator, Lab, Masking:** no chart Y axis.

**Verdict:** acceptable as of M12 task-8. No further work required
unless we also add a freq-axis range to the spectrogram.

### 4. Hardcoded color literals vs `AccentChoice` (low)

Multiple widgets use inline RGB literals for state colors:
- Masking state indicator: `Color(red: 0.0, green: 0.85, blue: 1.0)`
  (cyan), `1.0, 0.80, 0.30` (gold).
- Phase Meter (deactivated): green/yellow/red gradient.
- Level Meter: same gradient.
- Watch faces 4a/4b/4c (M12): phosphor hardcoded
  `Color(red: 0.45, green: 0.93, blue: 0.55)` because watch can't
  yet read iOS `AccentChoice` (App Group plumbing).

**Backlog:** consolidate into a shared "state palette" alongside
`AccentChoice` — independent of accent (these are semantic colors:
warn, info, success). Watch propagation gated on App Group.

### 5. Loudness phon/sone overlay reads LAF regardless (medium)

Same finding in **LevelHistory task-3 #2** and **SingleValue task-7 #5**.
Both pass `data.levels["LAF"]` into `LoudnessCalculator` even when the
user explicitly selected `LCpeak` or another metric. Visually:
overlay disagrees with the line/number.

**Backlog:** add a `LoudnessCalculator` caller helper that picks the
right level key from `resolvedMetricKey`, used by both widgets.

### 6. Dead `scrollOffset` knob in LevelHistoryView (low)

`LAFGraphView` still declares `var scrollOffset: Float`, uses it at
line 118 in the offset calculation, but no caller ever passes a
non-zero value. Same dead-pattern that was successfully purged from
the spectrogram pipeline in task-1.

**Backlog:** purge if confirmed dead, OR connect to playback scrubbing
in `RecordingDetailView` if intended. Quick win — single file.

### 7. O(n) `removeFirst` on history arrays (low)

Waterfall history (task-2 #3) uses `Array.removeFirst(_:)` on every
FFT callback (~86 Hz). The cap is small (≤ 240 frames) so wall-clock
cost is low, but `Shared/RingBuffer.swift` was added in M6 task-7
for exactly this pattern and the watch spectrogram view adopted it.

**Backlog:** migrate WaterfallWidget to RingBuffer for consistency.

### 8. Audio session category mutation by Tone Generator (medium)

`setCategory(.playAndRecord, ...)` runs at tone-start. If the user
is mid-recording with a different category, this silently mutates
shared state.

**Backlog:** check recording integrity when tone starts mid-recording.
Paired with the NSLock blocker.

### 9. NSLock on audio render thread (blocker)

ToneGenerator (task-8 #1). Exactly the M6 task-6 fix pattern.

**Backlog:** M11 task-1 (Render Thread Safety Precheck) — already
queued.

### 10. Destructive actions without confirmation (low)

Masking "Neu aufnehmen" toolbar button (task-10) calls `engine.reset()`
without `.alert`. No other widget has destructive in-widget actions
right now, but the pattern is worth establishing.

### 11. Missing accessibility identifiers (low)

Masking widget body (task-10 #7). Other widgets carry them. UI-test
parity.

### 12. Localization (low)

Spektralanalyse-Lab has hardcoded German tab labels (task-9 #8). The
app is German-default but if it ever ships English, several strings
across the audit set (eyebrow caps, tab labels, picker labels) need
`String(localized:)`.

## Prioritized backlog

### High / Blocker

- **M11 task-1** Tone Generator render-thread safety — `NSLock` →
  `OSAllocatedUnfairLock`. Already queued under M11; this audit
  confirms necessity.
- **Empty settings sheet** for toneGenerator + lab + masking.
  Recommend a new milestone or fold into task-8/9/10 directly:
  - tone: persistence + default-on-load.
  - lab: default tab + mid-recording-mutation warning.
  - masking: `minimumCaptures` (1…10) + ambient calibration time
    (5…30 s).

### Medium

- **Loudness metric coherence** (cross-cut #5): single
  `LoudnessCalculator` helper consumed by both LevelHistory and
  SingleValue. Low risk, single file change pair.
- **Peak-hold semantics consistency** (Level Meter task-5):
  unify watch-source vs local-mic peak handling + add a real decay
  envelope.
- **Override-toggle UX decision** (cross-cut #2): product decision
  required first. No code work until then.

### Low / Polish (backlog)

- Cross-widget shared "state palette" replacing hardcoded RGB
  literals (cross-cut #4).
- LAFGraphView `scrollOffset` dead-knob purge (cross-cut #6).
- WaterfallWidget → RingBuffer migration (cross-cut #7).
- Audio-session-category interaction with recording when tone starts
  (cross-cut #8).
- Masking "Neu aufnehmen" confirmation alert (cross-cut #10).
- Masking `accessibilityIdentifier` (cross-cut #11).
- Localization sweep across audit set (cross-cut #12).
- Frequency Spectrum: dead `.octaveBands` arm in settings sheet
  (task-4 #2); `bandMode` override semantics decision (task-4 #1);
  `leqAlpha` exposure or document (task-4 #4); `#if DEBUG`-gate
  spectrum diagnostics block (task-4 #5).
- Level History: AUTO-vs-explicit label disambiguation; conditional
  pickers UX (task-3 #1 + #4).
- Single Value: refactor AttributedString title switch (task-7 #3);
  "0.0" → "—" placeholder (task-7 #4); unit-by-enum (task-7 #6).
- Tone Generator polish (task-8 #2-9): dead settings param, no
  persistence, no settings sheet, exact-match preset highlight,
  linear amplitude, undiscoverable pinch, onDisappear stop,
  2×2 layout tightness.
- Lab polish (task-9 #2-10): shared-state warning, undo/reset,
  overlap slider semantics, duplicate window selector, German
  localisation, tab tightness, nested ScrollView.
- Masking polish (task-10): hardcoded convergence constants;
  1×1 vs 3×3 layout treatments.

## Hardware acceptance — still required

These cannot be closed from CLI. All 10 widgets need:

- Screenshots per allowed size × edit/view × dark/light.
- Settings cycling (per-widget enumerated lists).
- Stress: silence, clipped input, sample-rate change mid-stream,
  recording active vs inactive.

Tracked under each per-widget task's "Pending (hardware)" section
plus the masking task's checklist. Acceptance of M9 as a whole is
gated on this work and produces no new findings expected — purely
verification.

## Action

Mark M9 task-11 as **completed (code-side)**. Promotion of M9 as a
milestone to `completed` is gated on the hardware screenshot pass.
The blocker-class finding (toneGenerator NSLock) is already routed
to M11 task-1.

# Milestone 6 Handoff — Code Audit Remediation

Date: 2026-05-19
Author: agent (M6 lead)
Status: implementation cycles complete; manual hardware acceptance + Xcode-side wiring outstanding
Source review: full-codebase audit, 2026-05-18 (five parallel reviewer agents over DSP, WatchConnectivity, recording/persistence, iOS UI, watchOS+complications)

## Outcome at a glance

44 audit findings catalogued. Of those:

| Status | Count | Notes |
|---|---:|---|
| **Landed in code** | 32 | Bug fixed, code changed. |
| **Partial** | 3 | Code-side complete; remaining work is either structural (texture race), needs Xcode UI (App Group), or coordinated cross-target change (protocol version). |
| **Deferred — real future work** | 4 | Intentional defer with rationale (calibration migration, format-version pairing, consolidation decision, product locale decision). |
| **Verification reversal** | 5 | Audit claim did not survive verification (math, existing passing test, SwiftUI semantics, or dead-code that doesn't exist on the live path). |

**The audit's accuracy rate against verification: ~89% (39 of 44 valid findings).** Five claims were demonstrably wrong on closer inspection — see the per-finding rationale below. Three more were correctly identified bugs whose suggested fix would not actually work as written (the fix had to be reformulated). This is the main argument for verifying every audit claim before mutating code, and is the discipline this milestone followed throughout.

## Full coverage table

Severity column reproduces the audit's classification. "Result" links to the task file that addresses the finding.

| # | Sev | Area | Result | Task |
|---:|:---:|---|---|---|
| 1 | Crit | Watch FFT `zop`→`zrop` | **REVERSAL** — existing `WatchFFTTests.testNormalizationPreventsOverscaling` locks the current `zop + 2/N` behavior; vDSP `zop`/`zrop` apply the same `N` scaling for real input | Task 1 |
| 2 | Crit | Watch LAF exponent `/10`→`/20` | **REVERSAL** — current code computes `Σ A_i²` (= power per Parseval); matches iPhone path; audit's proposed `/20` would sum amplitudes | Task 1 |
| 3 | Crit | iOS `sendSpectrogramData` flooding | **LANDED** — ported coalescing + adaptive interval from Shared manager | Task 3 |
| 4 | Crit | Duplicate `RecordingManager` | **LANDED** — file deleted | Task 2 |
| 5 | Crit | Writer `frameCount`-before-write | **LANDED** — increment moved inside `writeQueue.async` after `handle.write` | Task 2 |
| 6 | Crit | `StoredDataProvider.bootstrap` on main | **LANDED** — moved off main via `Task.detached`; added cancellation | Task 2 |
| 7 | High | Background-thread `NotificationCenter` posts | **LANDED** — posts moved inside `DispatchQueue.main.async` blocks | Task 3 |
| 8 | High | A/C magnitudes in binary payload | **DEFERRED** — needs format-version byte; pair with #12 in a follow-up | Task 3 |
| 9 | High | `NSLock` on audio render thread | **LANDED** — `processingLock` → `OSAllocatedUnfairLock` across 6 call sites | Task 6 |
| 10 | High | `print`/`String(format:)` on watch audio thread | **LANDED** — both blocks under `#if DEBUG` | Task 6 |
| 11 | High | Window normalization ENBW | **DEFERRED** — calibration-shifting; needs hardware re-validation paired with calibration migration | Task 1 |
| 12 | High | Protocol version + unknown-type log | **PARTIAL** — unknown-type log landed both sides; `applicationContext` version handshake deferred (coordinated cross-target change) | Task 3 |
| 13 | High | iOS `processQueue` race | **DEFERRED** — cleaner fix is consolidation onto Shared manager; needs explicit decision | Task 3 |
| 14 | High | CSV decimal/separator locale | **DEFERRED** — M4 task-3 explicitly listed locale redesign as a non-goal; needs product decision (always-DE vs always-POSIX vs locale-driven) | Task 2 |
| 15 | High | `CGImage` bitmap-info mismatch | **LANDED** — `.last` → `.noneSkipLast` | Task 2 |
| 16 | High | `PDFReportGenerator` path duplication | **LANDED** — URLs sourced from `RecordingManager`; helpers deleted | Task 2 |
| 17 | High | `SaveRecordingView` absolute path | **LANDED** — `lastPathComponent`; later the (unused) view itself was deleted in Task 9 | Task 2 → Task 9 |
| 18 | High | Reader doubles file descriptor | **LANDED** — header parsed from open `FileHandle`; `Data(contentsOf:.mappedIfSafe)` removed | Task 2 |
| 19 | Med | Dead reachability reschedule | **LANDED** — both unreachable branches deleted with rationale comment | Task 3 |
| 20 | Med | Complication reload TOCTOU | **LANDED** — `lastComplicationReload` assigned before reload | Task 3 |
| 21 | Med | Octave-band edges `pow(2, ±1/6)` | **LANDED** — constants replaced | Task 1 |
| 22 | Med | C-weighting normalization sign | **REVERSAL** — at f = 1 kHz the raw formula evaluates to ≈ −0.062 dB; existing code `cDb = formula − (−0.062) = 0 dB`; already normalized | Task 1 |
| 23 | Med | `sampleBuffer` ceiling | **LANDED** — absolute compaction threshold added after backlog trimmer | Task 1 |
| 24 | Med | `recordingDuration` torn read | **LANDED** — derived from `recordingStartTime` on audio thread | Task 1 |
| 25 | Med | `RecordingDetailView` uncancellable load | **LANDED** — bundled with #6 via `spectrogramLoadTask` + `onDisappear` cancel | Task 2 |
| 26 | Crit | App Group complication shared state | **PARTIAL** — code-side complete with safe `UserDefaults.standard` fallback; Xcode Signing & Capabilities + Apple Developer Portal App Group registration outstanding | Task 4 |
| 27 | Crit | Complication reload exhausts daily budget | **LANDED** — throttle raised to ≥ 60 s minimum | Task 3 |
| 28 | Crit | `HighEndSpectrogramAdapter` texture race | **PARTIAL** — scalar-state race fixed with `OSAllocatedUnfairLock`; the GPU/CPU race on `spectrogramTexture.replace` needs structural fix (double-buffer or `inFlightSemaphore` gate) | Task 5 |
| 29 | Crit | Reachable `fatalError` in Metal setup | **LANDED** — `isMetalReady` flag; graceful degradation | Task 5 |
| 30 | Crit | `DashboardViewModel` nested `ObservableObject` | **REVERSAL** — the `objectWillChange` forwarder sink already catches `WidgetDropDelegate` mutations via `@Published` propagation; UI is not stale. The body-recompute granularity concern is real but structural (`@Observable` migration) and deferred | Task 8 |
| 31 | High | Watch audio engine on background | **LANDED** — `WKExtendedRuntimeSessionDelegate` callbacks now stop engine; `scenePhase` observer on `WindowGroup` defends the no-extended-session path | Task 7 |
| 32 | Med | Watch `frames.removeFirst()` O(n) | **LANDED** — new `Shared/RingBuffer.swift`; `WatchSpectrogramView` + `WatchSpectrogramWidget` migrated | Task 7 |
| 33 | High | Watch iOS-only `UIBackgroundModes` | **LANDED** — removed from `SpektoWatch-Watch-App-Info.plist` | Task 4 |
| 34 | High | Complication timeline policy `.after(60s)` | **LANDED** — `.never`; explicit reloads from connectivity manager are the sole driver | Task 4 |
| 35 | High | `HighEndSpectrogramAdapter` private state sync | **LANDED** — shares the lock from #28 | Task 5 |
| 36 | High | Dead `SpectrogramView` entry point | **LANDED** — struct deleted (kept the `SpectrogramTimeSpan` enum) | Task 9 |
| 37 | High | `WidgetSize.height` zero-clamp | **LANDED** — clamping setter + Codable decode migration + resize-site clamp | Task 8 |
| 38 | High | `computeFromAudioSamples` on main | **REVERSAL** then **LANDED** — function had no callers; was dead code; deleted entirely in Task 9 | Task 5 → Task 9 |
| 39 | Med | Watch main-thread hop per audio callback | **LANDED** — 5 Hz coalescing via `OSAllocatedUnfairLock` + `pendingLiveData` | Task 7 |
| 40 | Med | `buildColormapTexture` in `draw()` | **LANDED** — eager build in `setColormap`; removed from draw loop (audit's "already done" claim was wrong — added the eager build as part of this fix) | Task 5 |
| 41 | Med | `MaskingSuggestionView` cached preview | **REVERSAL** — SwiftUI re-runs `init` on parent re-render so the cache refreshes; audit's proposed direct-access fix would actually break observation (`MaskingPreviewPlayer` is itself an `ObservableObject` and needs an `@ObservedObject` wrapper) | Task 8 |
| 42 | Med | `onChange` re-entrancy on mic-source fallback | **LANDED** — guard on `audioEngine.activeMicrophoneSource != newSource`. The audit's suggested guard `newSource != selectedMicrophoneSource` doesn't actually work — SwiftUI `onChange(of:_:)` fires AFTER the property is updated, so the two are always equal in the closure | Task 8 |
| 43 | Med | Dead files (`DashboardView`, `WidgetSystem`, `AudioWidget`) | **LANDED** — all deleted; bonus: stripped dead `MetalWidgetRenderer`-dependent surface from `MetalWidgetManager` | Task 9 |
| 44 | Med | Watch debug counter every frame in release | **LANDED** — `debugCounter` storage + the `reduce(0, +)` block under `#if DEBUG` | Task 3 |

## Outstanding manual work

These items the agent cannot complete via text edits to source / pbxproj; they require Xcode UI or Apple Developer Portal access:

1. **App Group entitlement (Task 4, finding #26)**
   - Apple Developer Portal: register `group.BrandtAcoustics.SpektoWatch2.shared`; enable on the watch app and complication extension App IDs; regenerate provisioning profiles.
   - Xcode → both targets → Signing & Capabilities → add "App Groups" capability and point at the `.entitlements` files already shipped under each target's folder.
   - Optional consolidation: add `Shared/AppGroup.swift` to the `SpektoWatch Complications` target's Compile Sources so the duplicated `ComplicationAppGroup` enum in `WatchComplicationProvider.swift` can be deleted.
   - Until this is done, `AppGroup.defaults` falls back to `UserDefaults.standard` (i.e. the M5 behavior) — no regression, but the complication continues to render placeholder data only.

2. **Pbxproj cleanup**
   - The `Managers/RecordingManager.swift` line in the `membershipExceptions` of the app target is now a dangling reference (the file is gone). It's inert but cosmetically stale — should be removed in Xcode the next time the project file is touched.

## Manual hardware acceptance

Tests cannot be run in the local simulator (broken per standing rule). The milestone acceptance criteria listed in `agent/milestones/milestone-6-code-audit-remediation.md` need real-hardware verification:

- [ ] Phone + watch SPL parity within ±0.5 dB on a 1 kHz tone (validates that the deferred audit #1 / #2 calls were correct — the implementations should already agree). If divergence > 0.5 dB is observed, re-open audit #1 / #2 with hardware data.
- [ ] Watch complication updates within 60 s of a meaningful level change during a 5-minute session; Console shows no widget-budget-exhausted warnings. **Blocked on App Group entitlement wiring above.**
- [ ] Crash-mid-recording → reopen → correct duration (validates Task 2 #5).
- [ ] Reinstall app → previously saved recordings still playable (validates Task 2 #17).
- [ ] Background / wrist-down → watch audio engine stops within 5 s (validates Task 7 #31).

## Verification commands run

```
$ git diff main...HEAD ... | grep -E "^\+" | grep -E "fatalError|try!|as!"
# (empty — no new fatalError / try! / as! introduced)

$ grep -rn "UserDefaults.standard" "SpektoWatch Complications/"
# Only comment references; no live code reads the wrong defaults instance.

$ grep -rn "vDSP_DFT_zop" SpektoWatch2 Shared "SpektoWatch Watch App"
# Only WatchAudioEngine.swift:71 (intentional — finding #1 verification reversal).

$ grep -rn "NSLock()" SpektoWatch2
# 5 remaining: AudioEngine.widgetSpectralWeightingsLock, MeasurementDataWriter
#   (lifecycleLock, bufferPoolLock — not audio-thread), BandstopFilterManager
#   .snapshotLock, ToneGeneratorWidget.phaseLock. See follow-ups.
```

## Follow-up tasklist

Bundle into a future milestone (call it M7 or fold into the next planning cycle):

**DSP / acoustic correctness**
- Window ENBW correction paired with a calibration migration (finding #11). Measurement-shifting; needs hardware re-baselining.

**WatchConnectivity hardening**
- Binary spectrogram payload format-version byte + A/C-weighted magnitudes (findings #8, #12). Single coordinated cycle.
- Decide consolidation vs. serial-queue for iOS `WatchConnectivityManager` (finding #13). Pbxproj surgery if consolidating.

**Metal / spectrogram**
- Structural fix for the `HighEndSpectrogramAdapter` GPU/CPU texture race (finding #28). Either double-buffer or gate writes on `inFlightSemaphore`.

**iOS UI structural**
- `DashboardViewModel` body-recompute granularity (finding #30). Lift `DashboardManager` to a sibling `@ObservedObject` or adopt `@Observable`.

**Audio-thread RT-safety, bonus cleanups discovered**
- Convert `AudioEngine.widgetSpectralWeightingsLock` from `NSLock` → `OSAllocatedUnfairLock` (same shape as the processingLock fix in Task 6).
- Audit `ToneGeneratorWidget.phaseLock` and `BandstopFilterManager.snapshotLock` for audio-thread acquisition.

**Product / locale decision**
- CSV decimal/separator policy (finding #14). Always-DE? Always-POSIX with a doc note? Locale-driven? — needs a decision before any code change.

## Files changed in M6

Code (28 modified, 5 deleted, 4 created):

| | |
|---|---|
| Modified | `Shared/WatchConnectivityManager.swift`, `SpektoWatch Complications/WatchComplicationProvider.swift`, `SpektoWatch Watch App/SpektoWatchApp.swift`, `SpektoWatch Watch App/WatchAudioEngine.swift`, `SpektoWatch Watch App/WatchSpectrogramView.swift`, `SpektoWatch Watch App/WatchWidgets/WatchSpectrogramWidget.swift`, `SpektoWatch-Watch-App-Info.plist`, `SpektoWatch2/AudioEngine.swift`, `SpektoWatch2/DashboardManager.swift`, `SpektoWatch2/DashboardViewModel.swift`, `SpektoWatch2/HighEndSpectrogramAdapter.swift`, `SpektoWatch2/MeasurementDataReader.swift`, `SpektoWatch2/MeasurementDataWriter.swift`, `SpektoWatch2/MetalWidgetManager.swift`, `SpektoWatch2/PDFReportGenerator.swift`, `SpektoWatch2/PlaybackSpectrogramView.swift`, `SpektoWatch2/SpectrogramImageRenderer.swift`, `SpektoWatch2/SpectrogramProcessor.swift`, `SpektoWatch2/SpectrogramView.swift`, `SpektoWatch2/Views/RecordingDetailView.swift`, `SpektoWatch2/WatchConnectivityManager.swift`, `SpektoWatch2/WidgetConfiguration.swift` |
| Deleted | `SpektoWatch2/AudioWidget.swift`, `SpektoWatch2/DashboardView.swift`, `SpektoWatch2/Managers/RecordingManager.swift`, `SpektoWatch2/Views/SaveRecordingView.swift`, `SpektoWatch2/WidgetSystem.swift` |
| Created | `Shared/AppGroup.swift`, `Shared/RingBuffer.swift`, `SpektoWatch Watch App/SpektoWatchWatchApp.entitlements`, `SpektoWatch Complications/SpektoWatchComplications.entitlements` |

ACP infrastructure:

| | |
|---|---|
| Modified | `agent/progress.yaml`, `agent/scripts/acp-validate` (added M6 task-dir mapping) |
| Created | `agent/milestones/milestone-6-code-audit-remediation.md`, `agent/tasks/milestone-6-code-audit-remediation/` (10 task files), this report |

## Lessons for the next audit cycle

The audit was net very useful — it surfaced 32 real bugs that have now been fixed. But the 5 verification reversals and 3 reformulated-fix items all have the same root cause: **the reviewer agents did not run the existing tests, did not verify SwiftUI API semantics, and trusted a quick read of the code over checking the math.** Recommended for the next audit:

1. Tell reviewer agents to run / read the existing test suite as part of their review; flag any claim that contradicts a passing test.
2. For any claim involving SwiftUI lifecycle (`@ObservedObject`, `@StateObject`, `onChange` timing), require the agent to cite the framework docs or test the proposed fix mentally.
3. For DSP/math claims, require working out the units explicitly.
4. Cap reviewer claims by severity: a "Critical" finding should require evidence that the bug is reproducible, not just a code-smell observation.

Even with those guardrails, **verify-before-changing remains the right discipline** — every audit at scale will have ~10% false positives, and silently "fixing" non-bugs can introduce new ones (especially around DSP and concurrency).

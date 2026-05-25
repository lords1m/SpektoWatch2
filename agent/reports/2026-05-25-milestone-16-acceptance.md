# M16 Acceptance Report — Watch Connectivity Hardening

Date: 2026-05-25
Branch: redesign/liquid-glass
Milestone: M16

## Binary Outcomes

| # | Outcome | Status |
|---|---------|--------|
| 1 | WKExtendedRuntimeSession delegate never mutates `isRecording`/`session`/`stopRecording()` off main | ✅ |
| 2 | All four complication kinds reload on state change | ✅ |
| 3 | `sendWithRetry` / `processQueue` / `handleMessageError` only run on main | ✅ |
| 4 | No O(n) history shifts; no per-call DateFormatter allocations in watch views | ✅ |
| 5 | Schema-version mismatches are logged before returning nil | ✅ |

## Per-Task Verdicts

### Task 1 — WA-1 Critical (delegate thread race) ✅
`SpektoWatch Watch App/WatchAudioEngine.swift`:
- `extendedRuntimeSession(_:didInvalidateWith:)` body wrapped in
  `DispatchQueue.main.async { [weak self] in ... }`.
  `session = nil` moved inside the async block.
- `extendedRuntimeSessionWillExpire(_:)` body wrapped in
  `DispatchQueue.main.async { [weak self] in ... }`.
- `stopRecording()` gained `dispatchPrecondition(condition: .onQueue(.main))`.
  The previously nested `DispatchQueue.main.async` inside `stopRecording` was
  flattened to direct calls (already on main, no re-entrancy needed).
- Notification call sites (`handleStartRecording`, `handleStopRecording`)
  verified safe — `WatchConnectivityManager` wraps all command posts in
  `DispatchQueue.main.async` already.

### Task 2 — WA-2 High (corner complication reload) ✅
`Shared/WatchConnectivityManager.swift` and
`SpektoWatch2/WatchConnectivityManager.swift`:
- `"SpektoWatchLevelCorner"` added to both `complicationWidgetKinds` arrays.
- Both `WidgetCenter.shared.reloadTimelines` sites iterate the array via
  `forEach` — no per-kind hardcoding.
- Kind string verified against `LevelCornerWidget.kind` — exact match.

### Task 3 — WA-3 High (sendWithRetry race) ✅
`SpektoWatch2/WatchConnectivityManager.swift`:
- `sendWithRetry` body wrapped in `DispatchQueue.main.async { [weak self] in ... }`.
- `dispatchPrecondition(condition: .onQueue(.main))` added to `processQueue()`
  and `handleMessageError()`.
- Watch-side `Shared/WatchConnectivityManager.swift` has no `sendWithRetry` —
  no change needed.
- `AudioEngine.frequencyWeighting.didSet` call site (the only off-main risk)
  is now safe via the async hop.

### Task 4 — WA-4 + WA-5 Medium (watch view perf) ✅
`SpektoWatch Watch App/WatchLevelMeterView.swift`:
- `levelHistory: [Float]` → `RingBuffer<Float>(capacity: historyLength)`.
- `appendLevel` `removeFirst` guard deleted; single `RingBuffer.append` is O(1).
- Canvas draw path uses `inOrder()` snapshot.

`SpektoWatch Watch App/WatchSpectrogramView.swift`:
- `DateFormatter` promoted to `private static let timeFormatter` lazy closure
  (runs once). `timeString(from:)` calls `Self.timeFormatter.string(from:)`.

### Task 5 — WA-6 Low (silent version rejection) ✅
`Shared/SpectrogramData.swift`:
- `print("[SpectrogramData] Unknown schema version …")` added before `return nil`.

`Shared/WatchAppState.swift`:
- `print("[WatchAppState] Unknown schema version …")` added before `return nil`.

## Build Verification

```
xcodebuild -scheme "SpektoWatch Watch App" ... BUILD SUCCEEDED
xcodebuild -scheme "SpektoWatch2" ...         BUILD SUCCEEDED
```

## Hardware Acceptance (pending manual pass)

- **WA-1**: Extended-runtime session start → expire → invalidate on paired Watch;
  confirm `isRecording` / `session` mutations always happen on main and no
  concurrent tear occurs.
- **WA-2**: Set corner complication on a watch face; trigger a level update;
  confirm complication refreshes.
- **WA-3**: Rapid gain / recording-start / dashboard-config sends while watch
  foregrounds / backgrounds; confirm no duplicate messages or double-remove.
- **WA-4**: Level meter history scrolls correctly at historyLength=120 frames;
  no visual glitch at capacity boundary.
- **WA-5**: Spectrogram time-label shows correct HH:mm across a recording session.

## Files Changed

| File | Change |
|------|--------|
| `SpektoWatch Watch App/WatchAudioEngine.swift` | WA-1: delegate main hop + stopRecording precondition |
| `Shared/WatchConnectivityManager.swift` | WA-2: corner kind added |
| `SpektoWatch2/WatchConnectivityManager.swift` | WA-2: corner kind + WA-3: sendWithRetry main.async + preconditions |
| `SpektoWatch Watch App/WatchLevelMeterView.swift` | WA-4: RingBuffer migration |
| `SpektoWatch Watch App/WatchSpectrogramView.swift` | WA-5: static DateFormatter |
| `Shared/SpectrogramData.swift` | WA-6: version-mismatch log |
| `Shared/WatchAppState.swift` | WA-6: version-mismatch log |

## Deferred / Backlog

None from M16 scope. Earlier-identified items remain in their original
milestones: M17 (UI-1…UI-7 SwiftUI lifecycle), M18 (TT-2…TT-9 test debt).

# M17 Acceptance Report: SwiftUI Lifecycle & Performance

Date: 2026-05-25
Author: ACP agent
Status: **CODE-SIDE COMPLETE**

## Binary Outcomes

| # | Outcome | Status |
|---|---------|--------|
| 1 | No strong-`self` captures in `AVAudioPlayerNode` completion closures | ✅ |
| 2 | All async work from `RecordingDetailView` tracked and cancelled on `onDisappear` | ✅ |
| 3 | `cancelActiveExport()` clears `activeExportKind` synchronously | ✅ |
| 4 | `PhotoPickerView.isPresented` binding reset on dismiss | ✅ |
| 5 | `DashboardViewModel.dashboardManager` no longer `@Published` nested ObservableObject | ✅ |

## Per-finding Verdicts

### UI-1 · Critical · AudioPlayerManager strong-`self` leak

**File**: `SpektoWatch2/Views/AudioPlayerManager.swift` lines 89–93  
**Fix**: Completion closure changed to `{ [weak self] in DispatchQueue.main.async { [weak self] in guard let self, self.isPlaying else { return }; self.stop() } }`.  
**`stop()` idempotency**: `AVAudioPlayerNode.stop()` + `AVAudioEngine.stop()` tolerate duplicate calls. The `isPlaying` guard eliminates the double-stop path in the normal flow.  
**Verdict**: ✅ Completed 2026-05-25

### UI-2 · High · `promoteSpectrogramResolutionThenApply` untracked GCD work

**File**: `SpektoWatch2/Views/RecordingDetailView.swift` ~lines 1254–1279  
**Fix**: Converted to `Task.detached(priority: .userInitiated)`, assigned to existing `spectrogramLoadTask` (which is already cancelled in `onDisappear`). Cancellation check before and inside the `MainActor.run` block.  
**Verdict**: ✅ Completed 2026-05-25

### UI-3 · High · `applyPlaybackWeighting` untracked GCD work

**File**: `SpektoWatch2/Views/RecordingDetailView.swift` ~lines 1212–1232  
**Fix**: Added `@State private var weightingTask: Task<Void, Never>?`. Converted to `Task.detached(priority: .userInitiated)` with `weightingTask?.cancel()` before each new launch. `weightingTask?.cancel()` added to `onDisappear`. `Task.isCancelled` guards before state mutation.  
**Verdict**: ✅ Completed 2026-05-25

### UI-4 · High · `exportSpectrogramImage` can present sheet on dismissed view

**File**: `SpektoWatch2/Views/RecordingDetailView.swift` ~lines 1055–1079  
**Fix**: Added `@State private var spectrogramExportTask: Task<Void, Never>?`. Converted to `Task.detached`. `spectrogramExportTask?.cancel()` added to `onDisappear`. `Task.isCancelled` guard prevents `showShareSheet = true` after dismissal.  
**Verdict**: ✅ Completed 2026-05-25

### UI-5 · Medium · Export overlay stuck during slow cancellation

**File**: `SpektoWatch2/Views/RecordingDetailView.swift` lines 1028–1031  
**Fix**: `cancelActiveExport()` now sets `activeExportKind = nil` immediately after `exportTask?.cancel()`. The in-flight task's completion path (`finishExport()`) guards on `activeExportKind != nil` (see `finishSuccessfulExport`) — no double-clear risk.  
**Verdict**: ✅ Completed 2026-05-25

### UI-6 · Medium · `PhotoPickerView.isPresented` not reset

**File**: `SpektoWatch2/Views/PhotoPickerView.swift`  
**Fix**: Added `@Binding var isPresented: Bool` to the struct and threaded it through to the `Coordinator`. The coordinator sets `isPresented.wrappedValue = false` before `picker.dismiss(animated:true)`. Empty-results (cancel) path reaches the same code path.  
**Call site**: `RecordingDetailView.swift` updated to pass `isPresented: $showPhotoPicker`.  
**Verdict**: ✅ Completed 2026-05-25

### UI-7 · Medium · `DashboardViewModel` nested `ObservableObject`

**Files**: `SpektoWatch2/DashboardViewModel.swift`, `SpektoWatch2/ModularDashboardView.swift`  
**Fix**:
- `@Published var dashboardManager = DashboardManager()` → `let dashboardManager: DashboardManager` (injected via init)
- Removed the manual `objectWillChange` forwarding sink (was lines 28–32)
- Kept the `$widgets` sink for `updateWidgetSpectralWeightingRequirements`
- `DashboardViewModel.init` now requires `dashboardManager: DashboardManager` as first arg
- `ModularDashboardView.init` creates `DashboardManager()` once, passes it to both `DashboardViewModel` and a new `@ObservedObject private var dashboardManager: DashboardManager`
- All `viewModel.dashboardManager.*` references in `ModularDashboardView` replaced with `dashboardManager.*`; `$viewModel.dashboardManager.*` bindings replaced with `$dashboardManager.*`

**Verdict**: ✅ Completed 2026-05-25

## Negative Checks

| Check | Result |
|-------|--------|
| `grep "scheduleSegment" AudioPlayerManager.swift` → closure uses `[weak self]` | ✅ |
| `grep "DispatchQueue.global.async" RecordingDetailView.swift` → 0 hits | ✅ |
| `cancelActiveExport()` sets `activeExportKind = nil` synchronously | ✅ |
| `PhotoPickerView` delegate sets `isPresented.wrappedValue = false` | ✅ |
| `DashboardViewModel.dashboardManager` declared as `let` | ✅ |
| iOS build (`xcodebuild -scheme SpektoWatch2 -destination generic/platform=iOS Simulator`) | ✅ BUILD SUCCEEDED |

## Hardware Acceptance (Manual — still required)

The following items cannot be verified code-side:

- **UI-1**: Open a long recording, scrub mid-segment, dismiss the view mid-playback. Confirm no AVAudio `stop()-on-not-playing` warning and that `AudioPlayerManager.deinit` fires.
- **UI-2**: Open recording detail, trigger resolution promotion (long time span), dismiss before it completes. Confirm no state mutation logged after dismissal.
- **UI-3**: Rapidly change the weighting picker multiple times, then dismiss. Only the last selection should populate the cache.
- **UI-4**: Tap spectrogram image export, dismiss the view before the share sheet appears. Confirm no `UISheetPresentationController` assertion.
- **UI-5**: Tap export, then tap Abbrechen — overlay disappears within one frame.
- **UI-6**: Open photo picker, pick a photo, close. Re-open picker — should appear every time.
- **UI-7**: Navigate the dashboard, switch layouts, edit widgets. Confirm all mutations (add/delete/reorder widget, rename layout) still propagate and redraw correctly.

## Deferred / Out of Scope

- None from M17 task scope. All 7 UI findings fully closed code-side.
- M18 (Test & Tooling Debt — TT-2…TT-9) still pending; plan via `@acp.plan`.
- TT-1 (wire 5 new test files into Xcode target) still requires manual Xcode action.

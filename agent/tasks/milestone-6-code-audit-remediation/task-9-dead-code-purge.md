# Task 9: Dead Code Purge

Status: completed
Created: 2026-05-18
Updated: 2026-05-19
Milestone: `milestone-6-code-audit-remediation`

## Status Summary

| Item | Result |
|---|---|
| 1. `SpectrogramView.swift` | **PARTIAL** — `struct SpectrogramView` deleted; `enum SpectrogramTimeSpan` kept (still used by 4 other files) |
| 2. `DashboardView.swift` | **DELETED** — file was zero bytes |
| 3. `WidgetSystem.swift` | **DELETED** — file was zero bytes |
| 4. `AudioWidget.swift` | **DELETED** — all three protocols (`AudioWidget`, `MetalAudioWidget`, `MetalWidgetRenderer`) had no conformers |
| 5. `Managers/RecordingManager.swift` | (already deleted in Task 2) |
| 6. `Views/SaveRecordingView.swift` | **DELETED** — never instantiated |
| 7. `PlaybackSpectrogramRenderer.computeFromAudioSamples` | **DELETED** — function had no callers |

Bonus cleanup discovered during deletion:

| Item | Result |
|---|---|
| `MetalWidgetManager.renderers` cache, `getRenderer(for:factory:)`, `releaseRenderer(for:)` | **DELETED** — all transitively depended on the now-gone `MetalWidgetRenderer` protocol, and none were called |
| `MetalWidgetManager.sharedCommandQueue` | **DELETED** — set in init, never read |

## What Landed

### Deleted files

- `SpektoWatch2/DashboardView.swift` (0 bytes — placeholder for the deprecated dashboard view)
- `SpektoWatch2/WidgetSystem.swift` (0 bytes — placeholder for an old widget abstraction)
- `SpektoWatch2/Views/SaveRecordingView.swift` — view defined but never used. Defensive `lastPathComponent` fix from Task 2 went down with the file (intentional; no reviver needed because nothing presented it).
- `SpektoWatch2/AudioWidget.swift` — `AudioWidget`, `MetalAudioWidget`, `MetalWidgetRenderer` protocols. Verified no conformers.

### `SpektoWatch2/SpectrogramView.swift` — reduced to `SpectrogramTimeSpan`

The `SpectrogramView` struct was a legacy entry point that itself instantiated `ModularDashboardView`, doubling the audio-engine subscription graph if it ever appeared on screen. The live navigation graph is `ContentView → ModularDashboardView` only.

`SpectrogramTimeSpan` (defined in the same file) is still consumed by `LAFGraphView`, `WidgetSettingsView`, `SpectrogramWidget`, and `HighEndSpectrogramAdapter`. Kept it in place with a historical-note header rather than rename the file (synchronized-folder rename has higher risk than a slightly-misleading filename).

### `SpektoWatch2/MetalWidgetManager.swift` — stripped

Removed the dead `renderers: [UUID: MetalWidgetRenderer]` cache, the `getRenderer(for:factory:)` and `releaseRenderer(for:)` methods, and the unused `sharedCommandQueue` property. The class now exposes just `sharedDevice`, which is the single live use across the codebase (called from `SpektoWatch2App`, `PlaybackSpectrogramView.makeUIView`, and `HighEndSpectrogramAdapter.makeUIView`).

### `SpektoWatch2/PlaybackSpectrogramView.swift` — `computeFromAudioSamples` removed

The function was a self-contained synchronous FFT loop intended as a fallback path. `updateUIView` never called it (and never has, per git history). All playback FFT happens either via `StoredDataProvider` (Task 2) or `computeSpectrogramHistoryStreaming` on `RecordingDetailView` (also moved off-main in Task 2). Replaced with a one-line historical comment.

## Verification

- `grep -rn "MetalWidgetRenderer\|MetalAudioWidget\|sharedCommandQueue\|releaseRenderer\|getRenderer\|computeFromAudioSamples\|SaveRecordingView\|struct SpectrogramView\b" SpektoWatch2 Shared "SpektoWatch Watch App"` returns only historical-note comments; no live code references the deleted symbols.
- Xcode synchronized folders: the project uses `PBXFileSystemSynchronizedRootGroup`, so deleting files from disk removes them from the build automatically. Existing membership-exceptions for the (now deleted) `Managers/RecordingManager.swift` were left in place — they're inert dangling references; cleaning them is a separate cosmetic pass.
- Build will need to succeed on Xcode Cloud / a developer machine to confirm no stale references slipped through (local simulator broken per standing rule).

## Out of Scope

- Removing legacy Xcode test plans.
- Reorganizing folder structure.
- Cleaning the `Managers/RecordingManager.swift` line from the pbxproj `membershipExceptions` list (cosmetic only — the file is already gone).

## Audit References

#36 (landed), #43 (landed), #4 cross-ref (already handled in Task 2), plus Task-2 and Task-5 follow-up additions for `SaveRecordingView.swift` and `PlaybackSpectrogramRenderer.computeFromAudioSamples`.

## Objective

Remove the dead files and abstractions identified by the audit so that
future readers can trust the visible code surface. Smaller surface area
also reduces the chance that a future change accidentally binds to a
stale implementation (see Task 2 #1 for the realised risk).

## Scope

1. **`SpektoWatch2/SpectrogramView.swift`** — Legacy entry point that
   instantiates a full `ModularDashboardView` inside its body. If ever
   surfaced, it doubles all audio-engine subscriptions. Only
   `ContentView → ModularDashboardView` is on the live path. Delete the
   file and remove from the Xcode project.

2. **`SpektoWatch2/DashboardView.swift`** — Contains only a "deprecated"
   comment. Delete.

3. **`SpektoWatch2/WidgetSystem.swift`** — Contains only a "deprecated"
   comment. Delete.

4. **`SpektoWatch2/AudioWidget.swift`** — Defines `AudioWidget`,
   `MetalAudioWidget`, `MetalWidgetRenderer` protocols that nothing
   conforms to. `WidgetCardView.renderWidgetContent()` uses concrete
   structs directly. Delete the file and remove the protocols.

5. **`SpektoWatch2/Managers/RecordingManager.swift`** — Already covered
   by Task 2 #1. Cross-reference here so this task is a single source
   of truth for the dead-code removal commit.

6. **`SpektoWatch2/Views/SaveRecordingView.swift`** — The view is never
   instantiated anywhere in the project (verified by Task 2). Delete the
   file. (Defensive `lastPathComponent` fix in Task 2 stays in case the
   view is ever revived, but the file itself is dead.)

7. **`SpektoWatch2/PlaybackSpectrogramView.swift` —
   `PlaybackSpectrogramRenderer.computeFromAudioSamples(_:sampleRate:fftSize:hopSize:)`**
   (lines 154-219). Defined but has no callers. Verified by Task 5
   (project-wide grep returns only the definition). Delete the function
   and its associated synchronous-on-main FFT helpers.

## Out of Scope

- Removing legacy Xcode test plans.
- Restructuring folders.
- Removing the second `RecordingManager` (handled by Task 2 for
  traceability of the data-integrity fix).

## Verification

- After deletion, run `xcodebuild -list` and confirm no scheme
  references the removed files.
- `grep -rn "SpectrogramView\|DashboardView\|WidgetSystem\|AudioWidget\|MetalAudioWidget\|MetalWidgetRenderer" SpektoWatch2/ Shared/` returns no
  matches that point at the deleted types.
- Confirm the iOS and watch builds still succeed.

## Audit References

#36, #43, (#4 cross-ref)

# Task 1: AudioPlayer Weak Self in scheduleSegment Completion

Status: completed
Created: 2026-05-25

## Goal

Stop `AudioPlayerManager` from leaking after view dismissal mid-playback,
and stop the second `stop()` from firing when the segment completion
runs on an already-stopped engine.

## Source

UI-1 (Critical) — `agent/reports/2026-05-24-code-review-synthesis.md`
lines ~279–285.

File: `SpektoWatch2/Views/AudioPlayerManager.swift` lines ~89–93.

## Sub-items

- **Sub-1**: Audit every `playerNode.scheduleSegment` / `scheduleBuffer`
  / `scheduleFile` call site in the file. Each completion closure that
  references `self` must use `[weak self] in guard let self else { return }`.
- **Sub-2**: Confirm completion runs on a main-thread hop before
  mutating `@Published` state. If the existing code already hops via
  `DispatchQueue.main.async`, keep it. If not, add the hop inside the
  `guard let self else { return }` block.
- **Sub-3**: Verify `stop()` is idempotent — calling it twice (real-world:
  user-stop + drained-segment-completion fires after) does not error.
  If `AVAudioPlayerNode.stop()` already tolerates this, document it; if
  not, add an `isStopping` flag or check `playerNode.isPlaying`.

## Acceptance

- Completion closure uses `[weak self]` capture.
- iOS build green.
- Manual regression: scrub through a recording, dismiss the detail
  view mid-playback; confirm no console warnings about
  `AVAudioPlayerNode.stop()` on a not-playing node and that the
  manager deinit fires (add a temporary `print` in `deinit` if useful).

Milestone: `milestone-17-swiftui-lifecycle-performance`

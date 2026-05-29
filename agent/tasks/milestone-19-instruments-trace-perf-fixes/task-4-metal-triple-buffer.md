# Task 4: MTKView Triple-Buffering + Drawable Off Main Thread

Status: completed
Created: 2026-05-29
Priority: P2

## Problem

The 2026-05-29 trace shows `HighEndSpectrogramAdapter.draw(_:)` (38
samples, ~1.2%) with two samples blocked on:

```
CAMetalLayerPrivateNextDrawableLocked
-[CAMetalLayer nextDrawable]
-[MTKView currentDrawable]
-[MTKView currentRenderPassDescriptor]
```

`nextDrawable` blocks the calling thread when all drawables in the pool
are in-flight (i.e. held by the GPU). On the main thread this directly
causes frame drops and contributes to main-thread CPU time. The standard
fix is triple-buffering (3 drawables in the pool) and acquiring the
drawable on a dedicated render thread rather than on `@MainActor`.

## Acceptance

- `HighEndSpectrogramAdapter.draw(_:)` does not block on
  `CAMetalLayerPrivateNextDrawableLocked` in a re-trace.
- `MTKView.preferredFramesPerSecond` is set appropriately (60 fps for
  the spectrogram widget; ProMotion 120 fps is a separate decision).
- `MTKView` has `maximumDrawableCount = 3` (triple-buffer) confirmed
  in code.
- The spectrogram render does not perform `nextDrawable` acquisition on
  the main thread; it either runs in `MTKViewDelegate.draw(in:)` (which
  is called on the MTKView's render thread) or acquires the drawable
  on the `AURemoteIO` / dedicated render queue.
- No visual regression in the spectrogram display.
- iOS build succeeds.

## Implementation notes

- Check `HighEndSpectrogramAdapter` — if it calls `view.currentDrawable`
  from a SwiftUI `.onDraw` or a `Canvas` callback, that runs on the main
  thread. Move the Metal encode + present work into `MTKViewDelegate.draw`.
- Set `mtkView.maximumDrawableCount = 3` at setup if not already set
  (default is 2 on some iOS versions).
- Verify `mtkView.isPaused = false` and `mtkView.enableSetNeedsDisplay = false`
  for continuous rendering; or use `isPaused = true` +
  `setNeedsDisplay()` for on-demand rendering driven by audio callbacks.
- If `HighEndSpectrogramAdapter` is currently a SwiftUI `View` that
  wraps an `MTKView` via `UIViewRepresentable`, confirm the
  `Coordinator` is set as the `MTKViewDelegate` and that `draw(in:)` is
  the only draw entry point.
- The `_os_object_release_without_xref_dispose` frame in the hot path
  suggests a drawable is being over-retained — check for `retain` cycles
  on the `MTLRenderPipelineState` or `MTLCommandBuffer` in draw closures.

Milestone: `milestone-19-instruments-trace-perf-fixes`
Source: 2026-05-29 Instruments trace — CAMetalLayer drawable stall

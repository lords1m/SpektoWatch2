# Task 5: Schema Version Logging

Status: completed
Created: 2026-05-25
Completed: 2026-05-25

## Outcome

- **Sub-1** (`Shared/SpectrogramData.swift` ~line 206): Added
  `print("[SpectrogramData] Unknown schema version \(version); expected \(SpectrogramData.currentSchemaVersion) — dropping payload")`
  in the version-check `else` branch before `return nil`.
- **Sub-2** (`Shared/WatchAppState.swift` ~line 95): Added
  `print("[WatchAppState] Unknown schema version \(envelope.schemaVersion); expected \(currentSchemaVersion) — dropping update")`
  in the `guard envelope.schemaVersion == currentSchemaVersion else` branch.
- **Sub-3**: Both decode sites are called from WatchConnectivity delivery
  callbacks (not the audio render thread). No render-path risk.

Acceptance grep:
```
grep -n "Unknown schema version" Shared/SpectrogramData.swift  → hit
grep -n "Unknown schema version" Shared/WatchAppState.swift    → hit
```

iOS build: `BUILD SUCCEEDED`.

Milestone: `milestone-16-watch-connectivity-hardening`
Source: WA-6 Low — `agent/reports/2026-05-24-code-review-synthesis.md`

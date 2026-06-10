# Test plans

Index of manual test matrices and Xcode `.xctestplan` configurations for SpektoWatch2.

## Manual / QA

| Document | Purpose |
|----------|---------|
| [manual-test-matrix.md](manual-test-matrix.md) | Full manual test concept (TEST-IE-* cases, hardware, environments) |

## Automated (Xcode)

| File | `-testPlan` name | Targets | Use when |
|------|------------------|---------|----------|
| [xcode-test-plans.md](xcode-test-plans.md) · `TestPlans/spekto-watch2.xctestplan` | `spekto-watch2` | Unit + UI | Default CI/local full suite; pinned `en`/`US`/`light`/`TZ=UTC`, coverage |
| [snapshot-testing.md](snapshot-testing.md) · `TestPlans/snapshots.xctestplan` | `snapshots` | Unit (snapshots only) | Point-Free snapshot verify/record |
| [ui-tests.md](ui-tests.md) · `TestPlans/ui-tests.xctestplan` | `ui-tests` | UI only | Screenshot catalog, UITest-only schemes |

## How-to guides

| Document | Purpose |
|----------|---------|
| [snapshot-testing.md](snapshot-testing.md) | Snapshot baselines, `RECORD_SNAPSHOTS`, `__Snapshots__/` layout |
| [ui-tests.md](ui-tests.md) | UI screenshot tests, launch arguments, Xcode Cloud artifacts |

## Related

- `run_tests.sh` — scripted unit/UI runs (does not select a test plan; runs by test class)
- `agent/scripts/record-snapshots.sh` — re-record snapshot baselines (`-testPlan snapshots`)
- `agent/scripts/capture-screenshots.py` — export UI test PNGs from `.xcresult`

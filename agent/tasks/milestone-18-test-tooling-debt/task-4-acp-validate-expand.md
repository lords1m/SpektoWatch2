# Task 4: Expand acp-validate to M6–M17

Status: pending
Created: 2026-05-25

## Goal

Stop `acp-validate` from silently passing when accepted task records
from M6 onwards are deleted. Today the required-file list stops at M5.

## Source

- TT-5 (High) — `agent/reports/2026-05-24-code-review-synthesis.md`
  lines ~375–380.
- Coverage gap 1 — `acp-validate` static file list covers M1–M5 only.

File: `agent/scripts/acp-validate` lines ~7–57.

## Sub-items

- **Sub-1**: Audit the existing `required` list in `acp-validate` to
  understand its shape.
- **Sub-2**: Replace the static M1–M5 list with a loop that:
  - Globs every `agent/milestones/milestone-*.md` and asserts each
    exists + has the expected frontmatter.
  - For each milestone, globs every `agent/tasks/<milestone-id>/task-*.md`
    and asserts each exists.
  - Cross-references with `agent/progress.yaml` so a task listed in
    `tasks:` but absent on disk fails validation.
- **Sub-3**: Preserve the existing `current_task does not resolve`
  check that already catches dangling pointers.
- **Sub-4**: Run `./agent/scripts/acp-validate` against the current
  repo state — it must pass. Then delete a single task file as a
  smoke test — it must fail with a useful error message — and restore
  the file.

## Acceptance

- Deleting any task file from M6–M17 causes `acp-validate` to fail.
- Current repo state passes validation.
- No regression in pointer-resolution checks.

Milestone: `milestone-18-test-tooling-debt`

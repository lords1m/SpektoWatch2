# Task 11: Acceptance

Status: pending
Created: 2026-05-21
Milestone: `milestone-9-widget-audit`
Depends on: task-1 … task-10

## Objective

Collate per-widget findings into a single handoff report and cross-check
for inconsistencies between widgets that share patterns (level metering,
settings sheets, dB scaling, color zones).

## Steps

1. Read each per-widget task's Findings section.
2. Cross-cut analysis:
   - Inconsistent metric naming (LAF vs L_AF vs `laf` etc.)
   - Inconsistent dB scale defaults across widgets that show levels
   - Settings sheet patterns — are they visually consistent?
   - Edit-mode overlay behaviour — same across all widgets?
   - Color-zone usage — same thresholds where applicable?
3. Write a report `agent/reports/<date>-milestone-9-widget-audit.md`
   with:
   - Per-widget verdict (✅ / ⚠ / ❌).
   - Cross-cut findings.
   - Prioritized backlog of follow-ups (with proposed milestone or
     "leave as backlog").

## Acceptance

- Report exists and is reviewable.
- Every per-widget task has a verdict.
- Open backlog items are either ticketed (linked task IDs) or
  explicitly deferred with rationale.

# Milestone 24: Liquid Glass System Adoption

Status: in_progress
Created: 2026-11-26 (work started 2026-11-25)
Priority: medium
Estimated: 2 weeks
Design: `agent/design/liquid-glass-system-adoption.md`
Builds on: M12 (Liquid Glass Redesign), M23 (Home Screen), Ferrite v2 design system

## Goal

Make Liquid Glass read as one system material across iOS and watchOS. All
glass goes through the Ferrite API in `SpektoWatch2/DesignSystem/`, and the
layer model is enforced: solid content, glass navigation, and at most one
tinted accent per bar. Deployment targets stay iOS 18 / watchOS 11; iOS 26 and
watchOS 26 APIs are gated inside Ferrite only.

## Context

- Ferrite v2 (U-Bahnhof Paradestraße) replaced the earlier token set on
  2026-11-25 (`ba6137c`). Phase 1 of this milestone landed in the same commit.
- The M23 Home Screen removed the header pill and preset rail, so Phase 2 was
  adapted to the shell that exists (see the "As built" notes in the design doc).
- M12 task-6 (hardware acceptance) is folded into task-5 here, so the chrome is
  verified once, after Phases 2–4.

## Tasks

| # | Task | Status |
|---|------|--------|
| 1 | [Foundation API](../tasks/milestone-24-liquid-glass-system-adoption/task-1-foundation-api.md) | completed (`ba6137c`) |
| 2 | [Home shell](../tasks/milestone-24-liquid-glass-system-adoption/task-2-home-shell.md) | completed (`b1671b7`) |
| 3 | [Secondary screens & sheets](../tasks/milestone-24-liquid-glass-system-adoption/task-3-secondary-screens-and-sheets.md) | completed (`615c1a3`) |
| 4 | [watchOS](../tasks/milestone-24-liquid-glass-system-adoption/task-4-watchos.md) | pending |
| 5 | [Performance, accessibility & acceptance](../tasks/milestone-24-liquid-glass-system-adoption/task-5-performance-accessibility-acceptance.md) | pending |

## Acceptance

See section 6 of the design doc. In short: iOS 26 glass groups and morphs
correctly, iOS 18 fallback unchanged, Reduce Transparency removes all
translucency, no `Material`/`glassEffect` outside `DesignSystem/`, no new
hitches against the M19 baseline, all builds and UI tests green.

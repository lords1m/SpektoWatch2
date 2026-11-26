# Task 1: Foundation API

Status: completed
Created: 2026-11-25
Milestone: `milestone-24-liquid-glass-system-adoption`
Commit: `ba6137c`

## Goal

Add the Ferrite glass API so call sites never write `#available`:
`FerriteGlassGroup`, `FerriteBar` (`ferriteBar(edge:)`), edge glass,
`ferriteGlassButton` styles, and Reduce Transparency / Increase Contrast
handling in the fallback path.

## Files

`DesignSystem/FerriteEffects.swift`, `FerriteComponents.swift`,
`FerriteGallery.swift`, `FerriteGlassGroup.swift`, `FerriteBar.swift`,
`GlassStyle.swift`, `DesignTokens.swift`, `WidgetCardView.swift`.

## Outcome

Landed together with Ferrite v2. iOS build green; the Gallery renders every
variant.

## Deferred

- Rename `glassCard` → `ferriteCard` (23 callers remain). `glassCard` is a solid
  card, so the name is misleading. Do it in a dedicated change.

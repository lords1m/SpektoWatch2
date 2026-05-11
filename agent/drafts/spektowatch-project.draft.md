# SpektoWatch Project Draft

Source: `agent/design/project-draft.md`  
Status: draft  
Updated: 2026-05-11

This file is the canonical ACP draft input for clarification and design
generation workflows. The current full draft is maintained in
`agent/design/project-draft.md`.

## Feature Concept

SpektoWatch is an iOS and watchOS acoustic measurement app for live sound-level
monitoring, spectral analysis, measurement recording, and wearable companion
workflows.

## Goal

Make acoustic measurement fast, visual, and portable without reducing the app
to a basic sound meter.

## Pain Point

Existing tools are either quick but shallow dB meters or powerful but awkward
professional analysis tools. Apple Watch sound workflows are often treated as a
small phone mirror instead of a wrist-level acoustic surface.

## Problem Statement

Users need a way to monitor, understand, and record sound conditions in real
time across iPhone and Apple Watch while preserving performance, measurement
data quality, and watch bandwidth constraints.

## Proposed Solution

Build SpektoWatch as a modular acoustic measurement instrument with an iOS
analysis dashboard, structured measurement recording, Metal spectrogram
rendering, and a watch companion that sends compact processed data instead of
continuous raw audio.

## Requirements

See `agent/design/project-draft.md`.

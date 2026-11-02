---
title: F13.4 — Metronome-Aware Looping
feature: F13.4
version: V0.3
phase: "Phase 13 — Metronome Timing"
status: proposed
tags:
  - feature-pr
  - v0-3
---

# F13.4 — Metronome-Aware Looping

[[../releases/v0-3|← V0.3]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F13.4.1 — Beat and bar boundaries|F13.4.1 — Beat and bar boundaries]]
- [x] [[#Task PR F13.4.2 — Optional count-in|F13.4.2 — Optional count-in]]
- [x] [[#Task PR F13.4.3 — Loop boundary assistance|F13.4.3 — Loop boundary assistance]]
- [x] [[#Task PR F13.4.4 — Preserve free-form looping|F13.4.4 — Preserve free-form looping]]

## Task PR F13.4.1 — Beat and bar boundaries

Expose beat and bar boundaries from the shared transport.

## Task PR F13.4.2 — Optional count-in

Provide an optional one-bar count-in before recording.

## Task PR F13.4.3 — Loop boundary assistance

Allow loop recording to begin and end on a selected beat or bar boundary where practical.

## Task PR F13.4.4 — Preserve free-form looping

The user can still record loops without quantization or a count-in.

## Feature acceptance criteria

The metronome improves timing without forcing tempo-aware behavior on users who want free-form looping.

---

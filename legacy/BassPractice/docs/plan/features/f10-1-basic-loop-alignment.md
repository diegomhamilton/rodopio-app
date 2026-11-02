---
title: F10.1 — Basic Loop Alignment
feature: F10.1
version: V0.2
phase: "Phase 10 — Loop Synchronization"
status: proposed
tags:
  - feature-pr
  - v0-2
---

# F10.1 — Basic Loop Alignment

[[../releases/v0-2|← V0.2]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F10.1.1 — Shared loop start|F10.1.1 — Shared loop start]]
- [x] [[#Task PR F10.1.2 — Loop boundary scheduling|F10.1.2 — Loop boundary scheduling]]
- [x] [[#Task PR F10.1.3 — Synchronized mute and unmute|F10.1.3 — Synchronized mute and unmute]]

## Task PR F10.1.1 — Shared loop start

All loops start from the same transport origin.

## Task PR F10.1.2 — Loop boundary scheduling

Provide a reliable concept of the current loop boundary for starting and stopping loop playback.

This is timing infrastructure, not tempo-aware quantization.

## Task PR F10.1.3 — Synchronized mute and unmute

Mute and unmute operations should not restart a loop at an arbitrary position.

Unmuting rejoins at the current transport position.

## Feature acceptance criteria

Multiple loops remain phase-aligned after mute and unmute.

---

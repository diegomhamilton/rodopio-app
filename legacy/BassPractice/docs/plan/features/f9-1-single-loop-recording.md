---
title: F9.1 — Single Loop Recording
feature: F9.1
version: V0.2
phase: "Phase 9 — Basic Looper"
status: partially-implemented
tags:
  - feature-pr
  - v0-2
---

# F9.1 — Single Loop Recording

[[../releases/v0-2|← V0.2]] · [[../implementation-plan|Plan index]]

## Current implementation

First-pass looping is implemented and confirmed on the built-in iPhone mic/speaker. It reuses the existing `Recording` model and persistence: only one selected take plays at a time, repeating until stopped. This is the first slice of F9.1, not the full V0.2 milestone.

## Delivery checklist

- [x] F9.1.2 — Record Loop → Finish & Loop establishes length and repeats automatically.
- [x] F9.1.3 — Native `.loops` scheduling; complete bounded PCM loading; rendered continuity across multiple wraps and silence after Stop.
- [x] F9.1.4 — Empty/recording/playing/stopped/failed states reuse recording/playback state; cancellation on replacement and lifecycle events.
- [x] F9.1.5 — Practice loop transport and saved-take Play Loop/Stop; Record New Loop retains older takes.
- [ ] F9.1.1 — Dedicated Loop model with per-loop name/volume/mute, when multiple-track work requires it. Current Recording metadata is sufficient for single-take repetition.
- [ ] Endpoint smoothing/click assessment with musical input; scheduling tests do not prove arbitrary endpoints are click-free.
- [ ] Physical interface/headphone, monitoring, interruption/route recovery and accessibility review.

## Implemented behavior and limits

Finishing capture saves the take and starts repetition. Stop retains it; Play Loop starts from the beginning. New capture stops playback first. Input monitoring is separate in Audio Settings. Source-wide playback volume/mute remains available. Decoded phrase allocation is capped at 64 MiB; oversized takes show a shorter-phrase error. Nonaligned mono/stereo CAF loading is sample-for-sample tested. No overdub, independent simultaneous tracks, dedicated per-loop clear/mute, shared clock or quantization.

The native voice workaround is limited to neutral built-in mic capture with monitoring off. Effects and interfaces retain engine capture and need physical validation. See [[2026-10-10-recording-quality-and-monitoring|confirmed findings]] and [[../reference/audio-regression-prevention|regression prevention]].

## Acceptance and remaining release scope

The user confirmed automatic and saved-take repetition. Playing bass over a loop through a monitored interface is still pending. F9.2 multiple tracks, F9.3 overdub, F10.1 alignment, F11.1 loop-specific persistence and F12.1 multi-loop UI remain proposed. Single-take recording persistence does not complete those features.

---
title: F6.1 — Main Mixer
feature: F6.1
version: V0.1
phase: "Phase 6 — Mixer"
status: hardware-review-pending
tags:
  - feature-pr
  - v0-1
---

# F6.1 — Main Mixer

[[../releases/v0-1|← V0.1]] · [[../implementation-plan|Plan index]]

## Task PR checklist

Implemented at `a6c9119`: independent playback volume/mute, instrument monitoring volume/mute, pre-fader RMS/peak/clipping meters and one shared tap for instrument metering/recording. Graph generations reject stale callbacks. Full scheme: 114 logical /230 expanded cases passed. Physical balance/continuous audio and UI controls below the fold remain review gates.

- [x] [[#Task PR F6.1.1 — Mixer domain model|F6.1.1 — Mixer domain model]]
- [x] [[#Task PR F6.1.2 — Channel volume|F6.1.2 — Channel volume]]
- [x] [[#Task PR F6.1.3 — Mute|F6.1.3 — Mute]]
- [x] [[#Task PR F6.1.4 — Metering|F6.1.4 — Metering]]

## Task PR F6.1.1 — Mixer domain model

Channels:

```text
Instrument
Playback
```

Loop channels are added in V0.2.

## Task PR F6.1.2 — Channel volume

Independent volume controls.

## Task PR F6.1.3 — Mute

Each source can be muted.

## Task PR F6.1.4 — Metering

Add basic level metering.

Important for identifying:

```text
no signal
signal
clipping
```

## Feature acceptance criteria

User can balance live bass and recording playback without modifying recorded signal levels.

---

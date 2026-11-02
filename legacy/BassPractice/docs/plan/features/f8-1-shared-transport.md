---
title: F8.1 — Shared Transport
feature: F8.1
version: V0.2
phase: "Phase 8 — Shared Transport Foundation"
status: proposed
tags:
  - feature-pr
  - v0-2
---

# F8.1 — Shared Transport

[[../releases/v0-2|← V0.2]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F8.1.1 — Transport clock|F8.1.1 — Transport clock]]
- [x] [[#Task PR F8.1.2 — Transport states|F8.1.2 — Transport states]]
- [x] [[#Task PR F8.1.3 — Scheduled playback|F8.1.3 — Scheduled playback]]

## Task PR F8.1.1 — Transport clock

Introduce an engine-level timeline.

```swift
struct TransportPosition {
    let sampleTime: AVAudioFramePosition
    let seconds: TimeInterval
}
```

Avoid relying on wall-clock time for loop scheduling.

## Task PR F8.1.2 — Transport states

```swift
enum TransportState {
    case stopped
    case playing
    case paused
}
```

## Task PR F8.1.3 — Scheduled playback

Enable sample-accurate scheduling where practical.

## Feature acceptance criteria

Loops use one timing system without audible scheduling gaps, and future playback sources can join the same timeline.

---

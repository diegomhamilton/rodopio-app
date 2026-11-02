---
title: F13.1 — Metronome Clock
feature: F13.1
version: V0.3
phase: "Phase 13 — Metronome Timing"
status: proposed
tags:
  - feature-pr
  - v0-3
---

# F13.1 — Metronome Clock

[[../releases/v0-3|← V0.3]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F13.1.1 — BPM model|F13.1.1 — BPM model]]
- [x] [[#Task PR F13.1.2 — Time-signature model|F13.1.2 — Time-signature model]]
- [x] [[#Task PR F13.1.3 — Sample-based click scheduling|F13.1.3 — Sample-based click scheduling]]
- [x] [[#Task PR F13.1.4 — Start and stop behavior|F13.1.4 — Start and stop behavior]]

## Task PR F13.1.1 — BPM model

```swift
struct Tempo {
    var bpm: Double
}
```

## Task PR F13.1.2 — Time-signature model

```swift
struct TimeSignature {
    var beatsPerBar: Int
    var beatUnit: Int
}
```

## Task PR F13.1.3 — Sample-based click scheduling

Schedule clicks against the shared transport rather than using UI timers.

## Task PR F13.1.4 — Start and stop behavior

Metronome follows transport state:

```text
transport stopped → metronome stopped
transport playing → metronome playing
transport paused → metronome paused
```

---

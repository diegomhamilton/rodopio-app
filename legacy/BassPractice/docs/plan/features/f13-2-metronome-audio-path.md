---
title: F13.2 — Metronome Audio Path
feature: F13.2
version: V0.3
phase: "Phase 13 — Metronome Timing"
status: proposed
tags:
  - feature-pr
  - v0-3
---

# F13.2 — Metronome Audio Path

[[../releases/v0-3|← V0.3]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F13.2.1 — Click source|F13.2.1 — Click source]]
- [x] [[#Task PR F13.2.2 — Playback-only routing|F13.2.2 — Playback-only routing]]
- [x] [[#Task PR F13.2.3 — Recording exclusion tests|F13.2.3 — Recording exclusion tests]]

## Task PR F13.2.1 — Click source

Create a lightweight click source using bundled samples or generated audio.

## Task PR F13.2.2 — Playback-only routing

Route the metronome into the playback mixer after the recording tap.

```text
Instrument
    ↓
Effects
    ↓
Recording tap
    ↓
Instrument mixer ─────┐
                      ├── Output
Loops ────────────────┤
Metronome ────────────┘
```

## Task PR F13.2.3 — Recording exclusion tests

Verify that:

- instrument recordings contain no metronome;
- loop recordings contain no metronome;
- playback still contains the metronome.

## Feature acceptance criteria

The metronome is audible during practice but absent from all captured instrument and loop audio.

---

---
title: F3.2 — Parametric EQ
feature: F3.2
version: V0.1
phase: "Phase 3 — DSP V1"
status: hardware-review-pending
tags:
  - feature-pr
  - v0-1
---

# F3.2 — Parametric EQ

[[../releases/v0-1|← V0.1]] · [[../implementation-plan|Plan index]]

## Task PR checklist

Implemented at `8d859c7`: native parametric EQ with up to eight bands, Q-to-octave conversion, per-band enable/global bypass, distinct Bass/Guitar starting curves and Tone editor. Complete scheme: 96 logical /203 expanded cases passed; native sine-wave rendering verifies center-frequency boost/cut, bypass and Flat clearing. Physical listening remains pending; see [checkpoint](../../snapshots/2026-10-05_F2-1_F3-2_live-profiles/README.md).

- [x] [[#Task PR F3.2.1 — EQ model|F3.2.1 — EQ model]]
- [x] [[#Task PR F3.2.2 — EQ audio node|F3.2.2 — EQ audio node]]
- [x] [[#Task PR F3.2.3 — Bass EQ preset|F3.2.3 — Bass EQ preset]]
- [x] [[#Task PR F3.2.4 — Guitar EQ preset|F3.2.4 — Guitar EQ preset]]
- [x] [[#Task PR F3.2.5 — EQ editor UI|F3.2.5 — EQ editor UI]]

## Task PR F3.2.1 — EQ model

Example:

```swift
struct EQBand {
    var frequency: Float
    var gain: Float
    var q: Float
    var enabled: Bool
}
```

## Task PR F3.2.2 — EQ audio node

Use native audio processing initially.

Likely:

```text
AVAudioUnitEQ
```

## Task PR F3.2.3 — Bass EQ preset

Initial bass-oriented frequency ranges.

## Task PR F3.2.4 — Guitar EQ preset

Separate defaults from Bass.

## Task PR F3.2.5 — EQ editor UI

First version can be controls rather than a graphical frequency curve.

Example:

```text
LOW
80 Hz
+2.5 dB

LOW MID
350 Hz
-1.0 dB

HIGH MID
1.6 kHz
+3.0 dB
```

A graphical EQ can be added later.

## Feature acceptance criteria

Changing EQ is audible in real time without restarting the engine.

---

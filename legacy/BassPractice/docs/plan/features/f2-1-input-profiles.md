---
title: F2.1 — Input Profiles
feature: F2.1
version: V0.1
phase: "Phase 2 — Instrument Profiles"
status: hardware-review-pending
tags:
  - feature-pr
  - v0-1
---

# F2.1 — Input Profiles

[[../releases/v0-1|← V0.1]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F2.1.1 — Domain model|F2.1.1 — Domain model]]
- [x] [[#Task PR F2.1.2 — Built-in profiles|F2.1.2 — Built-in profiles]]
- [x] [[#Task PR F2.1.3 — Profile persistence|F2.1.3 — Profile persistence]]
- [x] [[#Task PR F2.1.4 — Profile selector UI|F2.1.4 — Profile selector UI]]

Domain, built-in Bass/Guitar EQ presets, custom-file persistence and live profile selection are implemented at `8d859c7`. Session and Tone expose the selector, and Tone can save/reopen/delete custom tones. Profile application validates the complete input gain/EQ before native writes. Complete scheme: 96 logical /203 expanded cases passed. Physical switching/listening remains pending; see [checkpoint](../../snapshots/2026-10-05_F2-1_F3-2_live-profiles/README.md).

## Task PR F2.1.1 — Domain model

Introduce:

```swift
enum InstrumentType {
    case bass
    case guitar
    case custom
}
```

And:

```swift
struct InputProfile {
    let id: UUID
    var name: String
    var instrument: InstrumentType
    var inputGain: Float
    var eq: EQConfiguration
}
```

## Task PR F2.1.2 — Built-in profiles

Provide sensible starting profiles:

```text
Bass
Guitar
Flat / Custom
```

These are defaults, not hard-coded processing modes.

## Task PR F2.1.3 — Profile persistence

Persist custom profiles.

## Task PR F2.1.4 — Profile selector UI

On the Session screen:

```text
INPUT
Cube Baby USB

INSTRUMENT
Bass ▼
```

Changing profile updates processing immediately.

## Feature acceptance criteria

User can switch Bass → Guitar → Custom while monitoring.

---

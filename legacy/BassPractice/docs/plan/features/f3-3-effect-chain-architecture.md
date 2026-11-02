---
title: F3.3 — Effect Chain Architecture
feature: F3.3
version: V0.1
phase: "Phase 3 — DSP V1"
status: review-pending
tags:
  - feature-pr
  - v0-1
---

# F3.3 — Effect Chain Architecture

[[../releases/v0-1|← V0.1]] · [[../implementation-plan|Plan index]]

## Task PR checklist

Implemented at `3347214`: ordered native processor abstraction with an independent processed-instrument boundary, validated ordered effect/preset data, bypass retained in each gain/EQ configuration and versioned atomic preset storage. Full scheme passed 100 logical /210 expanded cases. Preset application/reordering UI is outside this architectural feature; the app currently uses Gain → EQ. See [checkpoint](../../snapshots/2026-10-05_F3-3_effect-chain/README.md).

- [x] [[#Task PR F3.3.1 — Effect model|F3.3.1 — Effect model]]
- [x] [[#Task PR F3.3.2 — Effect ordering|F3.3.2 — Effect ordering]]
- [x] [[#Task PR F3.3.3 — Bypass|F3.3.3 — Bypass]]
- [x] [[#Task PR F3.3.4 — Effect preset persistence|F3.3.4 — Effect preset persistence]]

This is primarily an architectural PR.

## Task PR F3.3.1 — Effect model

```swift
struct EffectChain {
    var effects: [EffectConfiguration]
}
```

## Task PR F3.3.2 — Effect ordering

Support:

```text
Gain
 ↓
EQ
 ↓
Effect A
 ↓
Effect B
 ↓
Output
```

## Task PR F3.3.3 — Bypass

Every processor supports bypass.

## Task PR F3.3.4 — Effect preset persistence

Create:

```swift
struct EffectPreset {
    let id: UUID
    var name: String
    var inputProfile: UUID?
    var effects: [EffectConfiguration]
}
```

## Feature acceptance criteria

Architecture supports adding future processors without modifying the recorder or mixer.

---

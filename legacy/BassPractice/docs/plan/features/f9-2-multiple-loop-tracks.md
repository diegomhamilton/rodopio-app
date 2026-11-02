---
title: F9.2 — Multiple Loop Tracks
feature: F9.2
version: V0.2
phase: "Phase 9 — Basic Looper"
status: proposed
tags:
  - feature-pr
  - v0-2
---

# F9.2 — Multiple Loop Tracks

[[../releases/v0-2|← V0.2]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F9.2.1 — Loop collection|F9.2.1 — Loop collection]]
- [x] [[#Task PR F9.2.2 — Independent players|F9.2.2 — Independent players]]
- [x] [[#Task PR F9.2.3 — Mute and volume|F9.2.3 — Mute and volume]]
- [x] [[#Task PR F9.2.4 — Loop list UI|F9.2.4 — Loop list UI]]

## Task PR F9.2.1 — Loop collection

Session contains:

```swift
var loops: [Loop]
```

## Task PR F9.2.2 — Independent players

Each loop has an independently controllable playback node.

## Task PR F9.2.3 — Mute and volume

Support:

```text
mute
unmute
volume
clear
```

Solo is deferred unless it is trivial to add without complicating the basic loop workflow.

## Task PR F9.2.4 — Loop list UI

Example:

```text
LOOPS

1  Bass Groove       ▶   M
2  Harmonics         ▶   M
3  Chords            ▶   M

+ Add Loop
```

## Feature acceptance criteria

User can create multiple loops, hear them together, mute individual loops, adjust their levels, and clear them.

---

---
title: F11.1 — Loop Persistence
feature: F11.1
version: V0.2
phase: "Phase 11 — Looper Session Integration"
status: proposed
tags:
  - feature-pr
  - v0-2
---

# F11.1 — Loop Persistence

[[../releases/v0-2|← V0.2]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F11.1.1 — Store loop files|F11.1.1 — Store loop files]]
- [x] [[#Task PR F11.1.2 — Persist loop metadata|F11.1.2 — Persist loop metadata]]
- [x] [[#Task PR F11.1.3 — Restore loop playback|F11.1.3 — Restore loop playback]]

## Task PR F11.1.1 — Store loop files

Use a session-specific directory:

```text
Sessions/
    <session-id>/
        session.json
        recordings/
            <recording-id>.caf
        loops/
            <loop-id>.caf
```

## Task PR F11.1.2 — Persist loop metadata

Save:

```text
loop name
loop file
frame count
volume
mute state
order
```

## Task PR F11.1.3 — Restore loop playback

Opening a session restores the loop list and makes each loop available for playback.

## Feature acceptance criteria

Closing and reopening the app preserves the loops and their basic mixer state.

---

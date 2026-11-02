---
title: F9.3 — Basic Overdub
feature: F9.3
version: V0.2
phase: "Phase 9 — Basic Looper"
status: proposed
tags:
  - feature-pr
  - v0-2
---

# F9.3 — Basic Overdub

[[../releases/v0-2|← V0.2]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F9.3.1 — Record against existing loops|F9.3.1 — Record against existing loops]]
- [x] [[#Task PR F9.3.2 — Independent loop creation|F9.3.2 — Independent loop creation]]
- [x] [[#Task PR F9.3.3 — Basic cancel behavior|F9.3.3 — Basic cancel behavior]]

Overdub is included in V0.2 only in its simplest form: recording a new loop while existing loops continue playing.

## Task PR F9.3.1 — Record against existing loops

Existing loops continue playing while a new loop is captured.

## Task PR F9.3.2 — Independent loop creation

The new recording becomes a separate loop track rather than destructively replacing an existing loop.

## Task PR F9.3.3 — Basic cancel behavior

Allow the user to cancel a loop recording before committing it.

## Feature acceptance criteria

User can:

```text
record groove
→ hear it repeat
→ record another part over it
→ keep both loops independently
```

Advanced overdub merging and revision history are deferred.

---

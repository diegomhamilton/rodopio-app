---
title: F5.1 — Track Import
feature: F5.1
version: V0.4
phase: "Phase 5 — Backing Tracks"
status: proposed
tags:
  - feature-pr
  - v0-4
---

# F5.1 — Track Import

[[../releases/v0-4|← V0.4]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F5.1.1 — Document picker|F5.1.1 — Document picker]]
- [x] [[#Task PR F5.1.2 — Backing track model|F5.1.2 — Backing track model]]
- [x] [[#Task PR F5.1.3 — File management|F5.1.3 — File management]]
- [x] [[#Task PR F5.1.4 — Session integration|F5.1.4 — Session integration]]

## Task PR F5.1.1 — Document picker

Import common audio formats.

## Task PR F5.1.2 — Backing track model

```swift
struct BackingTrack {
    let id: UUID
    let fileURL: URL
    var name: String
}
```

## Task PR F5.1.3 — File management

Imported audio becomes owned by the app rather than relying permanently on an external URL.

## Task PR F5.1.4 — Session integration

Associate the managed backing-track asset with the session so it survives save, close, and reopen.

Add to `MusicSession`:

```swift
var backingTrack: BackingTrack?
```

## Feature acceptance criteria

A supported audio file can be imported, retained by the app, and restored with its session.

---

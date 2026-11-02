---
title: F7.2 — Library Screen
feature: F7.2
version: V0.1
phase: "Phase 7 — Session Persistence"
status: review-pending
tags:
  - feature-pr
  - v0-1
---

# F7.2 — Library Screen

[[../releases/v0-1|← V0.1]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F7.2.1 — Session list|F7.2.1 — Session list]]
- [x] [[#Task PR F7.2.2 — Open session|F7.2.2 — Open session]]
- [x] [[#Task PR F7.2.3 — Rename/delete session|F7.2.3 — Rename/delete session]]

## Task PR F7.2.1 — Session list

Show:

```text
Name
Date
Number of recordings
```

## Task PR F7.2.2 — Open session

Restore:

```text
instrument profile
effect preset
recordings
mixer levels
```

## Task PR F7.2.3 — Rename/delete session

## Feature acceptance criteria

Closing and reopening the app preserves the complete working session.

## Implemented checkpoint

The Library lists name, date and recording count, opens saved audio workspaces, renames sessions, creates sessions, and confirms deletion of the chosen session and its recordings. Deleting the current session first switches to a replacement; the repository rejects cancelled saves and late saves for IDs it has deleted. Failed reads remain visible and corrupt/future metadata cannot be overwritten by a normal save.

Session and Library share one workspace model. The most recently saved session is reopened at launch with audio stopped; Tone refreshes for the opened session. See [the F7 checkpoint](../../snapshots/2026-10-05_F7_session-library/README.md). Manual Library interaction and physical audio validation remain review gates.

---

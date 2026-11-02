---
title: iOS Bassy App
aliases:
  - Bass App Project Home
tags:
  - ios
  - audio
  - project
---

# iOS Bassy App

An Obsidian-ready project vault for a native iOS practice and recording app for bass and guitar.

## Current implementation

The native SwiftUI app has Practice and Recordings tabs. Practice offers Record Loop,
Finish & Loop, Stop Loop and Play Loop; finished and saved takes repeat by default.
Input monitoring lives in Audio Settings; Tone opens from the toolbar. Recordings lists
the current session's takes and opens saved workspaces through Sessions. Audio
Settings and Diagnostics hold advanced controls. See
[F0.2 — Simplified Practice UI](docs/plan/features/f0-2-simplified-practice-ui.md)
for review status and physical validation still required. Open
`BassPractice.xcodeproj` and run the `BassPractice` scheme on an iOS 17 or newer simulator.

## Development baseline

`develop` contains the complete merged stack, including the clear built-in voice capture,
speaker routing, default looping and audio regression safeguards. Built-in mic/speaker
voice and looping are user-confirmed. Remaining hardware gates and V0.2 scope are
tracked in [the current plan](docs/plan/features/2026-10-10-recording-quality-and-monitoring.md).
CI runs on pushes to `main` and `develop` and on pull requests; tests run without
parallel simulator clones.

## Start here

- [[docs/plan/implementation-plan|Implementation plan through V0.4]] — review release scope and toggle feature checklists.
- [[docs/prompts/codex-kickoff|Codex kickoff guideline]] — use this to begin the first implementation session.
- [iOS feature validation skill](.agents/skills/ios-feature-validation/SKILL.md) — build, test, launch, reject boot-screen captures, and assemble review evidence after implementation.
- [[docs/prompts/README|Agent prompt rules]] — every prompt crafted for another agent belongs here.
- [[docs/snapshots/README|Snapshot conventions]] — required evidence at human-review checkpoints.
- [[docs/snapshots/2026-09-29_F0-1_application-skeleton/README|F0.1 application skeleton checkpoint]] — build, test, and simulator evidence.

## Product direction

The app begins as a reliable practice and recording tool: select an input and instrument profile, monitor through gain/EQ/effects, play backing tracks, record, loop, and restore sessions. Later releases add metronome-aware practice, advanced loop editing, richer tone workflows, diagnostics, and export.

## Working agreement

Continue development from `develop`, the consolidated default branch. Create small
feature branches from it and target PRs back to `develop`; prefer squash merges.
The prior open Task/Feature PR stack was consolidated on 2026-10-10. Use the repository's `$ios-feature-validation` skill after implementation. A human-review checkpoint is ready only after the required validation route has built and tested the app, launched the simulator, captured verified screens, and documented the evidence under `docs/snapshots/`.

> [!important]
> Open this folder itself as the Obsidian vault. Keep implementation decisions, agent prompts, and review evidence linked from this home note.

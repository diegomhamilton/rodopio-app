---
title: F0.2 — Simplified Practice UI
feature: F0.2
version: V0.1
phase: "Phase 0 — Usability"
status: hardware-review-partial
tags: [feature-pr, v0-1, usability]
---

# F0.2 — Simplified Practice UI

[[../releases/v0-1|← V0.1]] · [[../implementation-plan|Plan index]]

## Goal

Make the next practice action available in one or two taps without searching a long form. This task takes priority over additional V0.1 features following the [navigation/audio exploration](../../explorations/2026-10-05-navegacao-audio/PROPOSTA.md).

## Task PR checklist

- [x] F0.2.1 — Practice transport: Record Loop starts audio as needed; Finish & Loop automatically repeats; Stop Loop/Play Loop stays in place; Record New Loop retains previous takes.
- [x] F0.2.2 — Recording navigation: Recordings shows the current session's takes; Sessions opens another workspace and returns directly to its takes.
- [x] F0.2.3 — Progressive disclosure: Tone is reachable from Practice; source mix/input lives in Audio Settings, technical formats/routes/meters in Diagnostics.
- [x] F0.2.4 — Honest feedback: visible output identity, silent playback notice, confirmed save/pending/failure status and save retry; permission/startup errors preserve the workspace.
- [ ] F0.2.5 — Physical usability/audio review with built-in microphone, speaker and interface/headphones, including relaunch and route changes.

## Acceptance criteria

- Record/finish/listen to latest take require no scroll at the reference iPhone size.
- Listening to another take in the open session is two taps from Practice.
- Opening another session reveals its takes without returning to Practice and scrolling.
- Capture and playback stop actions stay with their controls. Playback is blocked during capture; starting capture stops playback.
- Internal mic/speaker monitoring requires confirmation and starts at conservative volume; headphones allow one-action monitoring.
- Playback mute/zero volume is visible and restored only by explicit action.
- “Saved” represents successful metadata persistence, not merely a finalized CAF.
- Audio Settings and Diagnostics retain input discovery, independent mixer values, actual route/formats and pre-mute meters.
- Permission denial, startup failure and save failure do not discard recordings.

## Scope and dependencies

Stacks on F7 session persistence/Library (PR #22). Uses the existing audio graph and repository. Speaker routing and neutral built-in voice capture are fixed and physically confirmed; see [[2026-10-10-recording-quality-and-monitoring|audio findings and regression safeguards]]. Playback still uses the input-capable engine and therefore requires microphone permission. Single-take playback loops by default. No pause/seek, shared transport, multi-track loops, overdub, imported tracks or global recording search.

Validation and screenshots: [F0.2 checkpoint](../../snapshots/2026-10-05_F0-2_simplified-practice-ui/README.md). Implementation is merged. Built-in mic/speaker voice and looping are physically confirmed; remaining interface/headphone, lifecycle and accessibility checks are pending.

## Current physical review

Built-in mic/speaker voice quality and both loop actions confirmed by the user on 2026-10-10. Input monitoring is in Audio Settings. Interface/headphone, relaunch/route-change and accessibility review remain pending; F0.2.5 is not fully complete.

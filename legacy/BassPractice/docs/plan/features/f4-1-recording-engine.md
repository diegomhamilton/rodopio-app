---
title: F4.1 — Recording Engine
feature: F4.1
version: V0.1
phase: "Phase 4 — Recording"
status: hardware-review-pending
tags:
  - feature-pr
  - v0-1
---

# F4.1 — Recording Engine

[[../releases/v0-1|← V0.1]] · [[../implementation-plan|Plan index]]

## Task PR checklist

Implemented CAF recording and lifecycle finalization. Current neutral built-in mic capture uses `AVAudioRecorder` with monitoring off; requested effects/monitoring and external inputs retain the processed engine tap. Neutral voice quality is user-confirmed, while affected non-neutral engine capture remains a physical review gate. Playback loads a bounded complete PCM phrase in partial-read-aware blocks and loops by default through the playback mixer/output gain. F7 persists recordings and workspace metadata for reopening. See [[2026-10-10-recording-quality-and-monitoring|current audio evidence]] and [[../reference/audio-regression-prevention|required regression safeguards]]. Historical [F4.1 checkpoint](../../snapshots/2026-10-05_F4-1_recording-playback/README.md) records the original implementation.

- [x] [[#Task PR F4.1.1 — Recorder abstraction|F4.1.1 — Recorder abstraction]]
- [x] [[#Task PR F4.1.2 — Engine tap recording|F4.1.2 — Engine tap recording]]
- [x] [[#Task PR F4.1.3 — Audio file storage|F4.1.3 — Audio file storage]]
- [x] [[#Task PR F4.1.4 — Recording state|F4.1.4 — Recording state]]
- [x] [[#Task PR F4.1.5 — Record controls UI|F4.1.5 — Record controls UI]]

## Task PR F4.1.1 — Recorder abstraction

```swift
protocol AudioRecording {
    func start() throws
    func stop() async throws -> Recording
}
```

## Task PR F4.1.2 — Engine tap recording

Install an audio tap at the correct point.

Recommended default:

```text
Input
 ↓
Effects
 ↓
┌──────────────┐
│ recording tap│
└──────────────┘
 ↓
Mixer
```

This means recordings contain the selected tone.

Later we could optionally record dry + wet simultaneously.

## Task PR F4.1.3 — Audio file storage

Define file layout:

```text
Sessions/
    <session-id>/
        session.json
        recordings/
            <recording-id>.caf
```

Prefer a lossless internal format.

## Task PR F4.1.4 — Recording state

```swift
enum RecordingState {
    case idle
    case recording(startedAt: Date)
    case stopping
}
```

## Task PR F4.1.5 — Record controls UI

Session screen:

```text
● Record
■ Stop
▶ Playback
```

## Feature acceptance criteria

User can:

```text
connect bass
→ select tone
→ record
→ stop
→ play recording
```

---

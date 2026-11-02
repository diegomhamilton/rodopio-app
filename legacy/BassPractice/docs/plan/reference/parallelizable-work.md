---
title: Parallelizable Work
tags: [planning, reference]
---

[[../implementation-plan|← Plan index]]

# Parallelizable Work

Once the audio engine is stable, these streams can proceed independently:

```text
STREAM A — DSP
Gain
EQ
Effect chain
Basic presets

STREAM B — Recording
Recorder
File storage
Recording playback

STREAM C — Backing Tracks
Import
Playback
Transport UI

STREAM D — Persistence
Session model
Repository
Library

STREAM E — UI
Session
Tone
Library
```

For V0.2:

```text
STREAM A
Shared transport
Loop engine

STREAM B
Loop file storage
Loop persistence

STREAM C
Looper UI

STREAM D
Basic loop synchronization
```

For V0.3:

```text
STREAM A
Metronome clock

STREAM B
Playback-only metronome routing

STREAM C
Metronome controls

STREAM D
Count-in and loop timing assistance
```

For V0.4:

```text
STREAM A
Track import and managed file storage

STREAM B
Backing-track playback and controls
```

For V0.5:

```text
STREAM A
Advanced tone UX

STREAM B
Audio recovery and diagnostics

STREAM C
Audio export
```

Avoid parallelizing changes to the actual `AVAudioEngine` graph until its topology is stable.

---

---
title: Architecture Rule for V0.1–V0.5
tags: [planning, reference]
---

[[../implementation-plan|← Plan index]]

# Architecture Rule for V0.1–V0.5

One principle should remain strict:

```text
UI
does NOT know
about AVAudioEngine topology.
```

Instead:

```text
SwiftUI
   ↓
Feature Model
   ↓
Audio Engine API
   ↓
Audio Graph
```

For example:

```swift
audioEngine.selectInput(...)
audioEngine.setInputProfile(...)
audioEngine.applyPreset(...)
audioEngine.startRecording(...)
audioEngine.playBackingTrack(...)
audioEngine.createLoop(...)
audioEngine.setMetronome(...)
```

rather than:

```swift
view.audioEngine.attach(...)
view.audioEngine.connect(...)
```

The recording path must remain explicitly separate from playback-only sources:

```text
Instrument
    ↓
Effects
    ↓
Recording tap
    ↓
Instrument recording
    ↓
Playback mixer
```

Playback-only sources such as the metronome must be connected after the recording tap:

```text
Instrument recording ─────┐
Backing track ────────────┤
Loops ────────────────────┤
Metronome ────────────────┤
                          ▼
                        Output
```

This boundary will become particularly valuable when future versions introduce custom DSP, amp transfer functions, cabinet simulation, and more advanced routing.

---

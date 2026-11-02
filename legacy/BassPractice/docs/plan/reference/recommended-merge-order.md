---
title: Recommended Merge Order
tags: [planning, reference]
---

[[../implementation-plan|← Plan index]]

# Recommended Merge Order

The critical path is:

```text
F0.1 Project Foundation
 │
 ▼
F1.1 Audio Session
 │
 ▼
F1.2 Audio Engine
 │
 ├──────────────┐
 ▼              ▼
F2.1 Profiles   F3.1 Gain
                │
                ▼
              F3.2 EQ
                │
                ▼
              F3.3 Effect Chain
                │
                ▼
             F4.1 Recording
                ▼
             F6.1 Mixer
                │
                ▼
             F7.1 Sessions
                │
                ▼
             F7.2 Library
                │
             V0.1
                │
                ▼
             F8.1 Transport
                │
                ▼
             F9.1 Single Loop
                │
                ▼
             F9.2 Multi-loop
                │
                ▼
             F9.3 Basic Overdub
                │
                ▼
             F10.1 Loop Alignment
                │
                ▼
             F11.1 Loop Persistence
                │
                ▼
             F12.1 Looper UI
                │
             V0.2
                │
                ▼
             F13.1 Metronome Clock
                │
                ▼
             F13.2 Playback-only Routing
                │
                ▼
             F13.3 Metronome Controls
                │
                ▼
             F13.4 Metronome-aware Looping
                │
             V0.3
                │
                ▼
             F5.1 Import
                │
                ▼
             F5.2 Playback
                │
             V0.4
                │
       ┌────────┴─────────┐
       ▼                  ▼
   F14 Tone          F17 Reliability
       │                  │
       └────────┬─────────┘
                ▼
             F18 Export
                │
             V0.5
```

Unscheduled F15 advanced loop editing and F16 advanced practice features remain in [[../releases/backlog|Backlog]].

---

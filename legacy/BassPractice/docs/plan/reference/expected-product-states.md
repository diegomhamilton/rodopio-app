---
title: Expected state at the end of V0.2
tags: [planning, reference]
---

[[../implementation-plan|← Plan index]]

# Expected state at the end of V0.2

The application is a reliable basic looping practice tool:

```text
               BASS / GUITAR
                     │
                     ▼
              INPUT PROFILE
                     │
                     ▼
                TONE CHAIN
                     │
          ┌──────────┴───────────┐
          │                      │
          ▼                      ▼
       RECORDER                LOOPER
                                 │
                     ┌───────────┼───────────┐
                     ▼           ▼           ▼
                   Loop 1      Loop 2      Loop N
                     │           │           │
                     └───────────┼───────────┘
                                 │
                                 ▼
                              MIXER
                                 │
                                 ▼
                              OUTPUT
```

The user can record, repeat, layer, mute, clear, save, and restore loops.

---

# Expected state at the end of V0.3

The playback system includes a metronome while the recording system remains isolated from it:

```text
Instrument ────────┐
                   ▼
                Effects
                   │
                   ├── Recording tap ── Instrument recording
                   │
                   ▼
             Playback mixer
                   ▲
                   ├── Loops
                   └── Metronome
                   │
                   ▼
                 Output
```

The metronome is available during playback and practice but is never captured in instrument or loop recordings.

---

# Expected state at the end of V0.4

The application adds imported backing tracks to its existing practice workflow:

```text
Imported audio file
       ↓
Managed session asset
       ↓
Backing-track player ──┐
                       ├── Playback mixer ── Output
Instrument / loops ────┤
Metronome ─────────────┘
```

The user can import, play, pause, seek, mix, save, and restore a backing track.

---

# Expected state at the end of V0.5

The application is a more complete practice workstation:

```text
               BASS / GUITAR
                     │
                     ▼
              INPUT PROFILE
                     │
                     ▼
              EDITABLE TONE CHAIN
                     │
          ┌──────────┴───────────┐
          │                      │
          ▼                      ▼
       RECORDER                LOOPER
                                 │
                     ┌───────────┼───────────┐
                     ▼           ▼           ▼
                   Loop 1      Loop 2      Loop N
                     │           │           │
                     └───────────┼───────────┘
                                 │
BACKING TRACK ───────────────────┤
METRONOME ───────────────────────┤
                                 ▼
                              MIXER
                                 │
                                 ▼
                              OUTPUT
                                 │
                                 ▼
                         EXPORT / SHARE
```

V0.5 improves control, reliability, diagnostics, and export without changing the core separation between live input, recording, playback, looping, and metronome routing.

One thing I’d strongly preserve from this plan is **F8.1 Shared Transport before implementing the looper**. It may seem like extra infrastructure, but it prevents the classic situation where backing tracks, recordings, and loops each develop their own notion of time and synchronization becomes a rewrite later.

For actual implementation, I’d start with **F0 → F1.1 → F1.2 and make the first hardware milestone “hear the Cube Baby through the app reliably.”** Everything after that can build on a known-good audio foundation.

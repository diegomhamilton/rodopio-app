---
title: F1.2 — Audio Engine Core
feature: F1.2
version: V0.1
phase: "Phase 1 — Audio Hardware Foundation"
status: hardware-review-pending
tags:
  - feature-pr
  - v0-1
---

# F1.2 — Audio Engine Core

[[../releases/v0-1|← V0.1]] · [[../implementation-plan|Plan index]]

## Verified implementation checkpoint

Commit `2b8aacc7eae622aaa52341d88bf3950a02302f05` passed the complete `BassPractice` scheme through XcodeBuildMCP: 62 logical / 98 expanded cases, 0 failures or skips. [Checkpoint evidence and hardware checklist](../../snapshots/2026-10-05_F1-2_audio-engine-core/README.md). The earlier checked boxes predated implementation; this checkpoint supplies the actual verification.

The same source commit was built with the user's local uncommitted signing configuration, installed on Diego Phone (iPhone Air, iOS 26.6.1), and launched without the debugger; BassPractice PID 3115 was confirmed active. Hardware audio review remains pending.

Complete [Feature PR #13](https://github.com/diegomhamilton/bassy-ios/pull/13), branch `codex/test-feature-f1-2-audio-engine-core`, is based on F1.1 [PR #6](https://github.com/diegomhamilton/bassy-ios/pull/6). Task stack: [#7](https://github.com/diegomhamilton/bassy-ios/pull/7) → [#8](https://github.com/diegomhamilton/bassy-ios/pull/8) → [#9](https://github.com/diegomhamilton/bassy-ios/pull/9) → [#10](https://github.com/diegomhamilton/bassy-ios/pull/10) → [#12](https://github.com/diegomhamilton/bassy-ios/pull/12). Efficiency [PR #11](https://github.com/diegomhamilton/bassy-ios/pull/11) is separate, based on main, and contains no app code. Hardware review, feature review and explicit merge authorization remain pending.

## Task PR checklist

- [x] [[#Task PR F1.2.1 — Engine lifecycle|F1.2.1 — Engine lifecycle]]
- [x] [[#Task PR F1.2.2 — Input node integration|F1.2.2 — Input node integration]]
- [x] [[#Task PR F1.2.3 — Monitoring|F1.2.3 — Monitoring]]
- [x] [[#Task PR F1.2.4 — Audio format diagnostics|F1.2.4 — Audio format diagnostics]]
- [x] [[#Task PR F1.2.5 — Interruption recovery|F1.2.5 — Interruption recovery]]

## Task PR F1.2.1 — Engine lifecycle

Create an `AudioEngine`.

Responsibilities:

```text
configure graph
start
stop
restart after route change
report engine state
```

Suggested state:

```swift
enum AudioEngineState {
    case stopped
    case starting
    case running
    case interrupted
    case failed(Error)
}
```

## Task PR F1.2.2 — Input node integration

Connect:

```text
AVAudioInputNode
        ↓
instrument processing
        ↓
main mixer
        ↓
output
```

Initially processing can simply pass the signal through.

## Task PR F1.2.3 — Monitoring

Add live monitoring:

```text
Input → Engine → Output
```

Expose:

```swift
monitoringEnabled
monitoringGain
```

## Task PR F1.2.4 — Audio format diagnostics

Record and display/debug:

- sample rate;
- channel count;
- input format;
- output format;
- IO buffer duration.

This PR is especially useful for testing Cube Baby compatibility.

## Task PR F1.2.5 — Interruption recovery

Handle:

- phone interruption;
- audio session interruption;
- device disconnect;
- route changes.

## Feature acceptance criteria

Bass connected through the interface can be heard through the configured output continuously.

---

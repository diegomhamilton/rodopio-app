---
title: F1.1 — Audio Session Management
feature: F1.1
version: V0.1
phase: "Phase 1 — Audio Hardware Foundation"
status: awaiting-hardware-review
tags:
  - feature-pr
  - v0-1
---

# F1.1 — Audio Session Management

[[../releases/v0-1|← V0.1]] · [[../implementation-plan|Plan index]]

## Current session policy and review gate

Practice uses `.playAndRecord`, `.default`, `.defaultToSpeaker`, system-negotiated I/O buffer duration and a receiver-only override after activation. User confirmed built-in speaker playback; connected outputs must stay eligible. Forced buffer duration worsened periodic input gaps and must not be reintroduced without physical comparisons. [[2026-10-10-recording-quality-and-monitoring|Findings]] · [[../reference/audio-regression-prevention|Regression checklist]]. External interface/headphone, reconnection and recovery review remain pending.

## Task PR checklist

- [x] [[#Task PR F1.1.1 — AVAudioSession abstraction|F1.1.1 — AVAudioSession abstraction]]
- [x] [[#Task PR F1.1.2 — Route change observation|F1.1.2 — Route change observation]]
- [x] [[#Task PR F1.1.3 — Input device discovery|F1.1.3 — Input device discovery]]
- [x] [[#Task PR F1.1.4 — Preferred input selection|F1.1.4 — Preferred input selection]]

## Task PR F1.1.1 — AVAudioSession abstraction

Create:

```swift
protocol AudioSessionManaging {
    func activate() async throws
    func deactivate() async
}
```

Configure the app for simultaneous:

```text
input
processing
recording
playback
monitoring
```

Likely category:

```swift
.playAndRecord
```

with appropriate options determined during hardware testing.

## Task PR F1.1.2 — Route change observation

Observe:

```swift
AVAudioSession.routeChangeNotification
```

Represent routes internally:

```swift
struct AudioRoute {
    let inputs: [AudioDevice]
    let outputs: [AudioDevice]
}
```

## Task PR F1.1.3 — Input device discovery

Expose available inputs.

Example:

```swift
enum AudioInputKind {
    case builtInMicrophone
    case usb
    case bluetooth
    case unknown
}
```

Do not encode Cube Baby-specific behavior into the domain layer.

## Task PR F1.1.4 — Preferred input selection

Allow selecting an available input where iOS permits it.

Handle:

- disconnected device;
- route becoming unavailable;
- app background/foreground;
- audio interruption.

## Feature acceptance criteria

Connecting or disconnecting an interface updates the app without restarting it.

## Implementation evidence

- Task PR F1.1.1: [#2](https://github.com/diegomhamilton/bassy-ios/pull/2), commit `b03399f`.
- Task PR F1.1.2: [#3](https://github.com/diegomhamilton/bassy-ios/pull/3), commit `017dd90`.
- Task PR F1.1.3: [#4](https://github.com/diegomhamilton/bassy-ios/pull/4), commit `bf1a14b`.
- Task PR F1.1.4: [#5](https://github.com/diegomhamilton/bassy-ios/pull/5), commit `1870999`.
- Direct Xcode checkpoint: complete scheme passed with 24 logical tests and 42 generated cases on iPhone 17 Pro / iOS 26.2.
- Simulator launch evidence: [[../../snapshots/2026-10-04_F1-1_audio-session-management/README|F1.1 checkpoint]].
- XcodeBuildMCP: blocked because the integration was not exposed in the validation task; direct-tool evidence remains provisional.
- Remaining gate: physical Cube Baby, microphone, output-route, interruption, and reconnect validation after F1.2 provides monitoring controls.

---

---
title: F0.1 — Application Skeleton
feature: F0.1
version: V0.1
phase: "Phase 0 — Project Foundation"
status: awaiting-review
tags:
  - feature-pr
  - v0-1
---

# F0.1 — Application Skeleton

[[../releases/v0-1|← V0.1]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F0.1.1 — Create project structure|F0.1.1 — Create project structure]]
- [x] [[#Task PR F0.1.2 — Dependency container|F0.1.2 — Dependency container]]
- [x] [[#Task PR F0.1.3 — Navigation shell|F0.1.3 — Navigation shell]]
- [x] [[#Task PR F0.1.4 — Logging infrastructure|F0.1.4 — Logging infrastructure]]

### Task PR F0.1.1 — Create project structure

Create the initial native iOS application.

Suggested modules:

```text
App
Core
Audio
DSP
Sessions
Library
Features
    Session
    Tone
    Looper
    Library
UI
Tests
```

Initial dependency direction:

```text
UI
 ↓
Features
 ↓
Domain / Sessions
 ↓
Audio / DSP
 ↓
AVFoundation
```

Avoid allowing UI code to directly manipulate `AVAudioEngine`.

### Task PR F0.1.2 — Dependency container

Introduce explicit dependency injection.

Example:

```swift
struct AppDependencies {
    let audioEngine: AudioEngineProtocol
    let sessionRepository: SessionRepository
    let fileStore: AudioFileStore
}
```

No service locator or global audio singleton.

### Task PR F0.1.3 — Navigation shell

Implement the primary destinations:

```text
Session
Tone
Library
```

The Looper destination is introduced in V0.2.

### Task PR F0.1.4 — Logging infrastructure

Add structured logging for:

- audio route changes;
- audio session state;
- engine start/stop;
- recording;
- file errors;
- session loading.

Use `Logger` / `os.Logger`.

### Acceptance criteria

- App launches.
- Navigation works.
- Core components can be mocked.
- No actual audio processing yet.
- Unit-test target exists.
- CI can build and run tests.

### Implementation evidence

- Local implementation commit: `a9dc2a0`
- Build: passed with Xcode 26.2 on the iPhone 17 Pro simulator.
- Tests: 3 passed in `AppDependenciesTests`.
- CI: `.github/workflows/ios.yml` builds and tests pull requests and `main` pushes.
- Simulator states: [[../../snapshots/2026-09-29_F0-1_application-skeleton/README|F0.1 checkpoint]].
- Remaining gate: XcodeBuildMCP validation is blocked because the integration was not available in the implementation task.

---

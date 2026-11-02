---
title: F17.2 — Performance Instrumentation
feature: F17.2
version: V0.5
phase: "Phase 17 — Reliability and Diagnostics"
status: proposed
tags:
  - feature-pr
  - v0-5
---

# F17.2 — Performance Instrumentation

[[../releases/v0-5|← V0.5]] · [[../implementation-plan|Plan index]]

## Task PR checklist

- [x] [[#Task PR F17.2.1 — Render performance counters|F17.2.1 — Render performance counters]]
- [x] [[#Task PR F17.2.2 — CPU measurements|F17.2.2 — CPU measurements]]
- [x] [[#Task PR F17.2.3 — Latency diagnostics|F17.2.3 — Latency diagnostics]]
- [x] [[#Task PR F17.2.4 — Glitch reporting|F17.2.4 — Glitch reporting]]

## Task PR F17.2.1 — Render performance counters

Watch for audio render failures.

## Task PR F17.2.2 — CPU measurements

Measure processing load during:

```text
monitoring
recording
backing playback
metronome playback
multiple loops
```

## Task PR F17.2.3 — Latency diagnostics

Provide a debug screen showing:

```text
Sample rate
IO buffer
Input latency
Output latency
Reported total latency
Input channels
Output channels
```

## Task PR F17.2.4 — Glitch reporting

Record and surface audio underruns or render failures for debugging.

---

---
title: Audio regression prevention
status: active
tags: [audio, reference, validation]
---

# Audio regression prevention

[[../implementation-plan|Plan index]] · [[../features/2026-10-10-recording-quality-and-monitoring|Evidence and implementation]]

Use this checklist when changing capture, audio-session policy, file loading, playback or lifecycle handling.

- Preserve speaker default plus external-output eligibility; verify actual routes on the target iPhone. Run `AudioSessionOutputPolicyTests` after policy changes.
- Preserve system-negotiated I/O timing and the explicit neutral built-in-mic recorder fallback unless physical evidence supports replacing them. Simulator success cannot rule out periodic input gaps. Do not silently skip requested effects/monitoring.
- Preserve arbitrary callback lengths and every PCM sample. Run `irregularCallbackLengths` for capture writer changes.
- Read until the expected frame count is accumulated; handle partial reads and zero progress. Run `completeLoopBuffer` for mono/stereo, nonaligned lengths and sample rates. Do not restore a one-read/equal-length assumption.
- Bound decoded memory; keep loop scheduling off the UI thread. Run `nativePlaybackRendersCAF` across multiple wraps and after Stop. Separately assess musical endpoint clicks.
- Verify Stop/replacement, session changes, interruptions, route rebuilds and backgrounding cancel playback. Retain stale-generation protections; do not automatically enable restored monitoring.
- Finalize and retain a successful take even if playback/save fails. Check save/retry, permission and startup failure tests.
- For physical failures, isolate capture versus output with preserved files, actual route logs and raw/processed comparison. Change one variable per fresh recording. Keep diagnostic taps/counters out of normal capture and remove temporary instrumentation before PR delivery.

Known boundary: neutral built-in mic/speaker voice and looping are physically confirmed. Effectful engine capture, interfaces/headphones and route recovery still need device checks. Do not mark V0.2 complete based on one-take looping.

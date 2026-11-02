---
title: Recording quality and default looping — verified implementation
status: hardware-review-partial
tags: [audio, regression-prevention, v0-1, v0-2]
---

# Recording quality and default looping — 2026-10-10

[[../implementation-plan|Plan index]] · [[f0-2-simplified-practice-ui|F0.2]] · [[f9-1-single-loop-recording|F9.1]]

## Current state

The user confirmed clear voice recording ("now it sounds great") and then confirmed both automatic and saved-take looping work ("both work"). Implemented and physically tested with the built-in iPhone microphone and speaker. The fixes are merged into the consolidated development baseline. This does not certify external-interface capture, headphone reconnection, monitoring latency, non-neutral effects or the entire V0.2 release.

Practice uses Record Loop → Finish & Loop → Stop Loop → Play Loop. Finishing establishes the loop length and automatically repeats the take. Record New Loop stops playback, retains older takes and starts capture. Saved takes on Practice and Recordings repeat by default. Monitor Input lives independently in Audio Settings; built-in mic/speaker monitoring retains confirmation and conservative volume. Backgrounding, Stop, replacement, session switches, interruptions and route rebuilds cancel playback. Successful capture schedules saving before playback; a playback failure retains the take and save failures remain visible/retryable.

## Proven failures and retained safeguards

| Failure observed | Evidence and conclusion | Implementation safeguard | Regression coverage / remaining check |
|---|---|---|---|
| Playback used the receiver | User repeatedly reported earpiece playback. Speaker category option/receiver override alone did not resolve it; default mode with speaker policy produced confirmed speaker output. | `.playAndRecord`, `.default`, `.defaultToSpeaker`; receiver-only override after activation. Never force connected headphones/interfaces to speaker. Log actual category/mode/output. | `AudioSessionOutputPolicyTests`; physical headphone/interface transitions still pending. |
| Voice contained periodic silence before file writing | Raw and processed taps had matching gaps (~20–30% zeros); a larger forced I/O duration worsened silence to ~80%. No clipping in the inspected take. Native-recorder control under the same session had zero missing samples. | Use system-negotiated buffer duration. Neutral built-in mic + monitoring off uses `AVAudioRecorder`, stopping the engine during capture and restarting after finalization. Effects/external inputs/monitoring use the graph. | Irregular callback PCM fidelity test; physical neutral capture had 150960 samples and zero exact zeros, followed by user quality confirmation. Engine capture discontinuity for affected non-neutral modes remains unresolved. |
| Valid take rejected as unreadable by loop loader | Actual take: 163286 frames, single read returned 162816. Explicitly requesting full length still returned short. Original power-of-two fixture hid the defect. | Read in bounded 1024-frame blocks, copy each returned block, include the final partial block, reject only no progress/read errors. Cap decoded phrase at 64 MiB. | `completeLoopBuffer`: every sample preserved for 163286-frame mono 48k/stereo 44.1k CAFs. Loader also checked all nonempty copied device takes. |
| UI timer/completion scheduling could leave loop gaps | Repetition must stay independent of UI scheduling. | `AVAudioPlayerNode.scheduleBuffer(options: .loops)` repeats on the render thread. Stop releases scheduling; old completion generations cannot stop newer playback. | Offline production mixer/output-gain rendering across three boundaries with a 16397-frame source; Stop produces silence. User confirms looping. |

The underlying engine/system-input interaction is not fully explained. The native capture path is a bounded workaround, not proof that all audio modes are fixed. Flat input gain (0 dB) and neutral EQ bypass redundant processors, allowing reliable native voice capture without silently omitting requested effects. Input tone changes and enabling monitoring during native capture are rejected; UI controls prevent those unsupported transitions.

## Rules for future audio changes

1. Do not treat a running engine, playback state, duration, meter or successful simulator test as evidence of audible physical output. Record the actual input/output route and listen on the target device.
2. Preserve the original CAF before diagnosing capture versus playback. Compare PCM frame count, peak/RMS, clipping and discontinuities. Compare raw versus processed capture when needed; extra taps/file I/O are diagnostic confounders.
3. Do not tune mode or I/O duration from intuition. Change one variable, log the actual hardware-negotiated format/duration, and compare fresh captures. Speaker routing success does not establish capture quality.
4. Keep the native voice eligibility conditions explicit. Do not apply this path to effectful or monitoring-enabled recordings: it would bypass requested processing or stop live audio. Before removing it, reproduce continuous engine capture on the affected physical device and compare files.
5. File reads may return fewer frames than requested before EOF. Preserve every returned frame and require forward progress. Retain non-block-aligned, multi-channel and differing-rate fixtures; aligned synthetic audio alone missed the real failure.
6. Keep playback allocation bounded and scheduling on the audio thread. Verify multiple wraps, Stop, replacement and lifecycle cancellation. Scheduling continuity does not guarantee arbitrary phrase endpoints are click-free; endpoint smoothing/trimming is future work.
7. Preserve successfully recorded files when playback or metadata saving fails. Avoid restarting a stopped/replaced loop through stale callbacks. Monitoring must stay off on restored startup until explicitly enabled.
8. Temporary raw capture, sample counters and automatic recording launch actions must not ship. Investigation recordings and the user's screen recording remain outside Git. This PR removes the temporary diagnostic instrumentation.

## Validation and limits

- Complete suite before PR cleanup: **142 logical tests / 263 expanded cases, zero failures/skips**. Focused recording/playback: 11 / 13. Result `/tmp/BassyLoopReadFix-full.xcresult`; log `/tmp/BassyLoopReadFix-full.log`.
- Direct Xcode 26.2 fallback; selected XcodeBuildMCP installation lacked the iOS platform. Do not report these as MCP passes.
- Simulator: iPhone 17 Pro, iOS 26.2, UDID `34AA36AD-2704-4759-A347-01A023DEB371`; DerivedData `/tmp/BassyVoiceFix-20261010`.
- Signed physical build succeeded, installed and launched; user confirmed voice quality and both loop actions. Source based on `0bee590` plus the fixes.
- [Practice screenshot/checkpoint](../../snapshots/2026-10-10_loop-pedal/README.md) passed boot-screen detection and visual inspection. Empty Practice state only; active looping is supported by rendered tests and user feedback.
- Still pending: external instrument/interface, non-neutral effects, input monitoring, reconnect/route recovery, background/interruption physical checks, long loop limits, endpoint click assessment and accessibility. Multi-track loops, overdub, shared transport/alignment and loop-specific persistence remain later V0.2 work.

See [[../reference/audio-regression-prevention|Audio regression prevention]] for the cross-feature review checklist. Existing damaged captures are not repaired by these changes.

Final PR cleanup checkpoint: **142 logical / 263 expanded cases passed, zero failures/skips**, after removing raw diagnostic taps/counters. Result `/tmp/BassyLoopPR-final.xcresult`; log `/tmp/BassyLoopPR-final.log`; same Xcode 26.2 simulator and DerivedData. Local signing/project changes and unrelated user guide/backup files are excluded from the PR. PR #24 and its simplified UI dependency #23 are merged; the remaining prior stack is consolidated into `develop`.

Merged-baseline checkpoint: the prior PR stack is consolidated into `develop`; app/test sources match `92486d1`. XcodeBuildMCP validation now succeeds with the configured session: **142 logical / 263 expanded cases passed, zero failures/skips**. This is newer evidence than the earlier direct-tool fallback. See [develop handoff](../../snapshots/2026-10-10_develop-baseline/README.md). No new physical claims are added by consolidation.

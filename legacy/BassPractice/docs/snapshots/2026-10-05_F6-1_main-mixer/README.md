# Main mixer checkpoint

Reviewed source `a6c9119`, branch `codex/main-mixer`, based on recording PR #20.

Playback and instrument volume/mute are independent and survive graph rebuilds. Committed values remain after failed writes; invalid/nonfinite playback values are rejected before native writes. Source meters report pre-fader RMS, peak and clipping; a muted source can still show signal. Instrument metering and CAF capture share one tap. A graph-generation token rejects buffers from removed taps before they can update meters or enter a new recording.

Initial focused mixer/recording suites passed 13 logical tests. The final complete XcodeBuildMCP scheme passed **114 logical /230 expanded cases**, zero failures/skips, 199.7 seconds. This includes a new stale-tap test and alternating signed samples to distinguish RMS from mean, clipping and lossless capture. Production native playback/CAF tests still pass with shared taps installed.

Retained iPhone 17 Pro simulator, iOS 26.2; DerivedData `/tmp/BassPracticeF12Validation`. Result `/Users/dmh/Library/Developer/XcodeBuildMCP/workspaces/ios-bass-app-791fac75e19c/result-bundles/test_sim_2026-10-05T14-51-42-399Z_pid30850_123f1e6a.xcresult`.

Hardware level/balance and continuous-recording checks remain pending. The new mixer/meter controls are below the initial Session fold and were not exercised by UI automation. No new device listening result is claimed. User-owned signing/project formatting, test scheme and .orig files are excluded.

F7 session metadata/library persistence remains required for reopening the working session after relaunch. V0.1 remains incomplete pending that implementation and the physical release gates.

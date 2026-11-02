# F1.1 Audio Session Management checkpoint

- Date/time: 2026-10-04 09:36 America/Recife
- Commit: `1870999` (`audio: select preferred input and handle session lifecycle`)
- Branch / PR: `feature/F1-1-audio-session-management` / Feature PR pending hardware review
- Scheme: `BassPractice`
- Validation method: direct Xcode tools, provisional because XcodeBuildMCP was unavailable
- Build and test recipe: one complete `xcodebuild test` action for the `BassPractice` scheme
- DerivedData location: `/tmp/BassPracticeF11ValidationDerivedData`
- Simulator model and OS: iPhone 17 Pro, iOS 26.2
- Single simulator UDID retained during run: yes (identifier intentionally not committed)
- Simulator boot completion confirmed: yes
- Xcode version: 26.2 (17C52)
- XcodeBuildMCP build: blocked — integration not exposed in this task
- XcodeBuildMCP tests: blocked — integration not exposed in this task
- Direct Xcode build/tests: passed (24 logical tests; 42 generated test cases; 0 failures)
- Hardware route: simulator only; physical audio-route behavior remains a human gate
- Screenshots match reviewed commit: yes

## Scope demonstrated

- The app configures an injectable `.playAndRecord` / `.measurement` audio session with requested 48 kHz sample rate and 5.33 ms IO buffer duration.
- Route changes publish immutable route snapshots and typed reasons to multiple subscribers.
- Available inputs are classified generically as built-in microphone, USB, Bluetooth, or unknown without device-name special cases.
- Preferred input selection, disconnect fallback, interruption policy, and background/foreground reconciliation are covered by deterministic Swift Testing suites.
- The existing app shell still launches from the same tested output; F1.1 intentionally adds no user-facing audio controls.

## Steps exercised

1. Confirmed the reviewed commit, branch, scheme, and known untracked user-owned `.orig` files.
2. Recorded XcodeBuildMCP as unavailable after one availability check.
3. Discovered available simulators once and retained one iPhone 17 Pro destination.
4. Ran the complete scheme once into stable DerivedData.
5. Booted the retained simulator and waited for `bootstatus -b` to finish.
6. Installed the already-tested app, launched the deterministic Session destination, and captured the screen.
7. Accepted the capture with `check_screenshot.swift` and visually inspected it once.

## Screenshots

1. ![[01-session.png]] — tested F1.1 build launched on the existing Session shell; no clipping, boot screen, stale content, or unrelated sensitive information was present.

## Known limitations or failures

- XcodeBuildMCP was not available, so direct Xcode results are provisional and are not represented as an XcodeBuildMCP pass.
- The simulator cannot prove Cube Baby discovery, built-in microphone routing, wired/USB output, physical disconnect/reconnect, interruption recovery, latency, or continuous monitoring.
- F1.1 exposes audio-session behavior through internal APIs. The minimal hardware-review controls are part of F1.2.
- `.gitignore.orig` and `README.md.orig` were pre-existing untracked files and were not included in the checkpoint.

## Human decision requested

After F1.2 supplies the monitoring and diagnostics controls, run the combined F1.1/F1.2 hardware checklist and decide whether the physical route behavior satisfies the feature acceptance criteria.

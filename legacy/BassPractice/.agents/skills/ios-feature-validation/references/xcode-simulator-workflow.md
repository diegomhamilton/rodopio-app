# Xcode and Simulator workflow

Use these recipes from the repository root. Replace placeholders rather than committing machine-specific simulator identifiers.

## Preflight

```sh
git status --short --branch
xcodebuild -version
xcodebuild -project BassPractice.xcodeproj -scheme BassPractice -showdestinations
xcrun simctl list devices available
```

Run simulator discovery with host access if the restricted environment reports an invalid `CoreSimulatorService` connection, log-store permission errors, or no available runtimes.

Request host authorization once, then run these commands individually. Do not combine several Xcode/CoreSimulator commands into one opaque long-running call; individual boundaries make stalls attributable and recoverable.

## Focused iteration

Use quiet, targeted tests while correcting validation-specific issues:

```sh
xcodebuild \
  -project BassPractice.xcodeproj \
  -scheme BassPractice \
  -destination 'id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/BassPracticeDerivedData \
  -only-testing:BassPracticeTests/AppDependenciesTests \
  -quiet \
  test
```

Keep full logs in DerivedData or the result bundle. Return only relevant diagnostics and the summary to the conversation.

## Full checkpoint validation

One `test` action builds the app and runs the complete scheme. Do not precede it with a duplicate full build.

```sh
xcodebuild \
  -project BassPractice.xcodeproj \
  -scheme BassPractice \
  -destination 'id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/BassPracticeDerivedData \
  test
```

## Simulator preparation

Recheck the selected base device after the full test action. XCTest can run on a clone and leave the base simulator `Shutdown`. If the base device is shut down, boot it once. If it is already `Booted`, skip the boot command.

```sh
xcrun simctl boot <SIMULATOR_UDID>
xcrun simctl bootstatus <SIMULATOR_UDID> -b
xcrun simctl install \
  <SIMULATOR_UDID> \
  /tmp/BassPracticeDerivedData/Build/Products/Debug-iphonesimulator/BassPractice.app
```

The Simulator window appearing is not proof that data migration and SpringBoard initialization have finished. `bootstatus -b` is the readiness gate.

## Deterministic review states

```sh
xcrun simctl launch --terminate-running-process \
  <SIMULATOR_UDID> \
  com.example.BassPractice \
  -initial-tab session

xcrun simctl io \
  <SIMULATOR_UDID> \
  screenshot docs/snapshots/<checkpoint>/01-session.png

.agents/skills/ios-feature-validation/scripts/check_screenshot.swift \
  docs/snapshots/<checkpoint>/01-session.png
```

Repeat with the required launch states. A checker exit status of `2` means the image is probably the Apple boot screen and must be discarded. Status `0` permits one visual inspection; it does not prove that the intended workflow is correct.

Check every command result before proceeding. Do not run the screenshot checker when capture failed or the file does not exist, and stop the state loop at its first failure.

## Failure routing

| Observation | Response |
|---|---|
| XcodeBuildMCP is unavailable | Record it once as blocked; use direct tools only as labeled fallback evidence. |
| CoreSimulator service or log permission errors in the sandbox | Request host authorization once, then run simulator operations as separate observable commands. |
| A host command stalls | Stop that command, inspect the last proven device/process state, and resume only from that boundary; do not restart the entire workflow. |
| Selected device is shut down | Boot once, then block on `bootstatus -b`. |
| Tests fail | Report the failing suite and stop the checkpoint. |
| Screenshot checker returns `2` | Wait for boot completion, relaunch, recapture, and rerun the checker. |
| Screenshot is stale, clipped, or unrelated | Recapture before writing checkpoint evidence. |
| Local and CI simulator names differ | Preflight each environment; do not assume device names are interchangeable. |

## Evidence sequence

1. Commit the reviewed implementation when the task calls for commits.
2. Validate that commit.
3. Add checkpoint notes and verified screenshots.
4. Confirm CI configuration separately from local validation.
5. Inspect the final documentation-only diff and present one decision to the human.

## CI is a separate environment

The repository's current workflow uses:

```sh
xcodebuild \
  -project BassPractice.xcodeproj \
  -scheme BassPractice \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath "$RUNNER_TEMP/BassPracticeDerivedData" \
  test
```

Local F0.1 evidence used an iPhone 17 Pro running iOS 26.2. Preflight local and CI destinations independently; do not assume that a device installed locally exists on the CI runner.

---
name: ios-feature-validation
description: Validate an implemented native iOS feature with Xcode builds, focused and full tests, simulator launches, screenshot gates, and checkpoint evidence. Use after implementation or when refreshing review evidence; do not use it to implement the feature itself.
---

# iOS feature validation

Validate the existing implementation without expanding or recreating it.

## Workflow

1. Confirm the requested feature, reviewed commit, active branch, clean status, scheme, and intended test scope.
   Use `python3 .agents/skills/ios-feature-validation/scripts/checkpoint.py --github` for a compact JSON snapshot of HEAD, untracked changes, local/remote refs and open PR base/head pairs. Remote refs are cached; the helper does not fetch or switch branches. A stacked task tip may contain newer code than its feature branch: select the reviewed commit from actual ancestry and PR heads, not branch naming or plan checkboxes. Preserve unrelated untracked files.
2. Check XcodeBuildMCP availability once. Use it when available. If absent, record that gate as blocked and use direct Xcode tools only as provisional evidence unless the user explicitly accepts the fallback.
3. Discover available simulator destinations once and retain one UDID for the entire checkpoint.
4. During iteration, run only the affected test suite with quiet output. At the final checkpoint, run the complete scheme once into a stable DerivedData directory.
5. Use host-level access for CoreSimulator operations when the restricted environment cannot connect to `CoreSimulatorService`. Request the authorization once, but execute discovery, boot, install, launch, and capture as separate observable commands so a stall has a clear boundary.
6. Recheck the selected base simulator after `xcodebuild test`; XCTest may use a clone and leave the base device shut down. Boot it when needed and wait for `bootstatus -b` before installing, launching, or capturing.
7. Install the app from the already-tested DerivedData output. Do not rebuild merely to launch it.
8. Launch deterministic review states when the app provides launch arguments. Stop at the first failed install, launch, or capture. Run `scripts/check_screenshot.swift` only after capture succeeds and the image exists, and discard any image it identifies as a likely boot screen.
9. Visually inspect accepted screenshots once for the requested state, clipping, stale content, or unrelated sensitive information.
10. Record the validation method, exact test result, simulator identity, DerivedData location, reviewed commit, screenshots, blocked gates, and the one human decision requested.

Read [references/xcode-simulator-workflow.md](references/xcode-simulator-workflow.md) when commands or failure recovery are needed.

For physical-device requests, read [references/physical-device-preflight.md](references/physical-device-preflight.md). Check which XcodeBuildMCP capabilities are exposed: simulator tooling availability does not establish device tooling availability.

Capture an existing result bundle with the helper's `--xcresult <path>` option. It returns the tool's structured summary without flattening Swift Testing logical tests into expanded cases. Record unavailable summaries as unavailable; retain the original test log as evidence.

When validation is delegated, give its owner the reviewed commit, test scope, retained destination and tested app path. Session defaults may be scoped per agent; verify them in the validating agent. Keep one owner for build/test/simulator mutations and let the coordinator own branch changes. Confirm the implementation editor has stopped writes before starting validation; a source change during a running build invalidates evidence for the new source and requires fresh validation. Read-only reviews can run alongside implementation; checkpoint documentation follows the verified result. If a delegated tool or approval stalls, report its exact boundary so the coordinator can take over from the last proven step without rebuilding or racing the original call.
Do not count raw MCP `testCases` entries as expanded Swift Testing cases: entries can duplicate and discovery totals can differ from the completed runner count. Report the authoritative completed summary and explicitly distinguish logical tests, parameterized cases and discovery totals when available.

## Stop conditions

- Do not change production code while performing a validation-only request.
- Stop after one confirmed XcodeBuildMCP availability check; do not spend retries proving that an unavailable integration is unavailable.
- Stop and report exact failures when the full test run fails.
- Do not accept screenshots captured before simulator boot completion or from a different implementation commit.
- Never represent direct `xcodebuild` success as an XcodeBuildMCP pass.

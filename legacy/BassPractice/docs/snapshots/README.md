---
title: Simulator Snapshots
aliases:
  - Snapshot Index
tags:
  - screenshots
  - review
  - evidence
---

# Simulator snapshots

All simulator screenshots and the evidence for every human-interaction checkpoint live under `/docs/snapshots`.

## Required checkpoint layout

Create one directory per checkpoint:

```text
docs/snapshots/
└── YYYY-MM-DD_Fx-y_short-name/
    ├── README.md
    ├── 01-start-state.png
    ├── 02-primary-action.png
    ├── 03-result-state.png
    └── test-results.txt        # optional; no secrets or sensitive logs
```

Use the Task/Feature identifier when available. Keep file names ordered, lowercase, and descriptive. Store actual PNG files here rather than linking to temporary simulator locations.

## Checkpoint note template

Each checkpoint `README.md` must contain:

```markdown
# [F?.?] Checkpoint title

- Date/time:
- Commit:
- Branch / PR:
- Scheme:
- Validation method: XcodeBuildMCP / direct Xcode tools / human waiver
- Build and test command or recipe:
- DerivedData location:
- Simulator model and OS:
- Single simulator UDID retained during run: yes/no (do not commit the value)
- Simulator boot completion confirmed: yes/no
- Xcode version:
- XcodeBuildMCP build: pass/fail
- XcodeBuildMCP tests: pass/fail (count and relevant suite)
- Direct Xcode build/tests, if used: pass/fail (count and relevant suite)
- Hardware route, if applicable:
- Screenshots match reviewed commit: yes/no

## Scope demonstrated

## Steps exercised

## Screenshots

1. ![[01-start-state.png]] — expected state and what to inspect.
2. ![[02-primary-action.png]] — action/state under review.
3. ![[03-result-state.png]] — resulting state.

## Known limitations or failures

## Human decision requested
```

## Capture rules

- Use XcodeBuildMCP at every human-interaction checkpoint to build, test, launch, and capture the simulator.
- Use the repository's `$ios-feature-validation` skill to coordinate checkpoint commands and failure recovery.
- Check XcodeBuildMCP availability once. If unavailable, label direct Xcode validation as provisional rather than repeatedly retrying the unavailable integration.
- Reuse one discovered simulator identifier and one stable DerivedData directory throughout the checkpoint.
- Wait for simulator boot completion before installing or launching the app.
- Run `.agents/skills/ios-feature-validation/scripts/check_screenshot.swift <image>` on every capture. Exit status `2` rejects a likely Apple boot screen before visual review.
- Visually inspect checker-accepted images once for the intended state, clipping, stale content, and sensitive information.
- Capture the changed workflow, empty/loading/error states when relevant, and enough context to identify the screen.
- Keep screenshots current with the commit presented for review; replace or create a new checkpoint after visual changes.
- Never include secrets, personal notifications, account data, or unrelated app content.
- Link each checkpoint from the PR and human-review message.

No checkpoint is complete when the screenshot files exist without the accompanying note, or when the note refers to a different build/commit.

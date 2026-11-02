---
title: PR and Task Conventions
tags: [planning, reference]
---

[[../implementation-plan|← Plan index]]

# PR and Task Conventions

Feature branch:

```text
feature/F3-effect-chain
```

Task branches:

```text
task/F3.1-audio-processor-protocol
task/F3.2-gain-node
task/F3.3-eq-node
task/F3.4-chain-routing
```

PR title:

```text
[F3.2] Add parametric EQ processor
```

Commit examples:

```text
audio: add AVAudioUnitEQ wrapper
audio: map EQ configuration to audio unit
test: cover EQ configuration mapping
```

---

# Task PR Template

Every task PR should explicitly contain:

## Goal

One or two sentences describing the change.

## Why

The architectural or product reason.

## Changes

Concrete implementation changes.

## Out of scope

Important things intentionally excluded.

## Test plan

For example:

```text
[ ] Unit tests pass
[ ] App builds
[ ] Tested with built-in mic
[ ] Tested with Cube Baby
[ ] Tested reconnecting the interface
```

## Follow-up

Reference the next task PR.

This makes stacked PR review significantly easier.

---


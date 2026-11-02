---
title: Delivery Model
tags: [planning, delivery]
---

[[../implementation-plan|← Plan index]]

# Delivery Model

Development is organized at three levels:

```text
Version
└── Implementation Phase
    └── Feature PR
        ├── Task PR
        ├── Task PR
        └── Task PR
```

A Task PR should ideally:

- change one architectural concept or user-visible behavior;
- remain reviewable in roughly 10 minutes;
- include tests where practical;
- avoid unrelated refactors;
- leave the project compiling and tests passing.

A Feature PR is the integration point for a complete capability.

Example:

```text
feature/audio-input
├── task/audio-session
├── task/audio-device-discovery
├── task/audio-engine-input
└── task/input-device-ui
```

During development, task PRs can be stacked:

```text
main
  ↓
feature/audio-input
  ↓
task/audio-session
  ↓
task/audio-routing
  ↓
task/audio-input-ui
```

Once all task PRs are reviewed, the complete feature branch is merged into `main`.

# In summary, our main goal is that both task level PRs and feature level PRs are reviewable and testable

I could overpass individual task PRs and decide the overall feature looks nice. as it is.
I should have a test_feature branch that allows me that. It must contain all the tasks for human validation.

---


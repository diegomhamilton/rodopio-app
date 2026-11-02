---
title: Initial Codex Session Guideline
aliases:
  - Codex Kickoff
tags:
  - prompt
  - codex
  - kickoff
---

# Initial Codex session guideline

You are implementing the native iOS Bass App described in [[../plan/implementation-plan|the implementation plan]]. Treat that plan as the product and delivery source of truth. Do not expand scope silently; surface conflicts and record agreed changes in the plan.

## Initial goal

Deliver V0.1 as a reliable musical practice and recording tool, beginning with the smallest hardware-validation path: prove the Cube Baby/built-in microphone audio route, formats, stable monitoring and recording, and measured latency before investing in substantial UI. Preserve the architecture needed for V0.2–V0.4 without prematurely building those features.

## Required architecture

- Native iOS, SwiftUI, AVFoundation/AVAudioEngine unless an accepted decision says otherwise.
- UI talks to feature/domain APIs and never manipulates AVAudioEngine topology.
- Use explicit dependency injection; no service locator or global audio singleton.
- Keep instrument recording paths separate from playback-only sources such as backing tracks, loops, and the metronome.
- Keep Bass/Guitar/Custom behavior in `InputProfile`, not scattered special cases.

## Phased execution

1. V0.1: project foundation → audio session and engine → input profiles → gain/EQ/effect-chain foundation → recording → backing tracks → mixer → sessions/library.
2. V0.2: shared transport → single and multiple loops → basic overdub → loop alignment → persistence → performance-oriented Looper UI.
3. V0.3: transport-clocked metronome → playback-only routing → controls → count-in and optional loop timing assistance.
4. V0.4: tone library/editor → loop revisions/editing/synchronization → practice and routing tools → reliability/diagnostics → export/share.

Implement only checked/accepted features in the plan. Follow the documented merge order, especially Shared Transport before the looper. Do not parallelize audio-graph topology changes until the graph is stable.

## PR hierarchy and rules

- Version → phase → Feature PR → Task PR.
- Create one Feature PR branch such as `feature/F3-effect-chain`; stack focused Task PR branches such as `task/F3.2-parametric-eq` onto it.
- A Task PR changes one architectural concept or one user-visible behavior, is normally reviewable in 10–30 minutes, includes practical tests, avoids unrelated refactors, and leaves the project building with tests passing.
- A Feature PR integrates its reviewed Task PRs and must satisfy the feature acceptance criteria before merging to `main`.
- PR titles use `[F3.2] Add parametric EQ processor` form.
- Every PR states Goal, Why, Changes, Out of scope, Test plan, visual evidence when UI changes, and Follow-up/dependency.
- Never mix formatting churn, opportunistic cleanup, or a second feature into a Task PR.

## Commit rules

- Make atomic commits that compile and preserve passing tests whenever feasible.
- Use imperative, scoped subjects such as `audio: add AVAudioUnitEQ wrapper`, `test: cover EQ mapping`, or `ui: show input route status`.
- Keep production change and its direct tests together when that improves review; separate mechanical moves from behavioral changes.
- Do not commit generated build products, DerivedData, secrets, credentials, or unexplained binary artifacts.
- Do not rewrite shared branch history or squash reviewed Task PR context unless the human reviewer requests it.

## Mandatory human-interaction checkpoints

A checkpoint occurs before asking for human review, approval, a product/scope choice, hardware validation, or merge; when reporting a Task PR/Feature PR/milestone as ready; and at each release gate.

Use the repository's `$ios-feature-validation` skill for checkpoint work. The skill validates an existing implementation; it does not authorize or perform feature implementation.

At every checkpoint, use XcodeBuildMCP to:

1. build the active scheme for the agreed simulator;
2. run the relevant unit/UI tests and report exact failures;
3. launch the current app in the simulator;
4. exercise the changed workflow and capture screenshots of every relevant state;
5. save screenshots and a checkpoint note under `/docs/snapshots` using [[../snapshots/README|the snapshot convention]].

Check XcodeBuildMCP availability once. If it is unavailable, do not repeatedly retry it. Direct `xcodebuild` and `simctl` results may be recorded as provisional evidence, but they are not an XcodeBuildMCP pass unless the human explicitly waives that gate.

Discover simulator destinations once and retain one simulator identifier throughout the checkpoint. Simulator commands may require host-level access when the restricted environment cannot connect to CoreSimulator. Wait for `bootstatus -b`; a visible Simulator window does not prove that booting or data migration is complete.

No checkpoint is ready for human interaction until the build, tests, simulator state, screenshots, and snapshot index are current. Run the skill's screenshot checker before visual inspection and discard likely Apple boot-screen captures. If XcodeBuildMCP, the simulator, hardware, or tests are unavailable, do not claim readiness: document the blocker, commands/actions attempted, and remaining validation.

At the checkpoint, summarize the scope delivered, PR/commit references, build and test results, simulator/device used, screenshot links, known limitations, and the single next decision or action requested from the human.

## Documentation discipline

- Every prompt crafted for another agent or Codex session must be saved under `/docs/prompts` before use.
- Record review screenshots and checkpoint evidence only under `/docs/snapshots`.
- Update the implementation plan when scope or sequencing changes; do not let PR descriptions become the only record.
- Keep documentation changes in the same Task PR when they describe that task's behavior or evidence.

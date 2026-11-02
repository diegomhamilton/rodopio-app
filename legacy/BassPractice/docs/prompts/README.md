---
title: Agent Prompts
tags:
  - prompts
  - agents
---

# Agent prompts

`docs/prompts/` is the canonical and mandatory home for every prompt crafted for a different agent or a new Codex session.

## Rules

- Save the prompt here before sending or using it.
- Use one file per goal and a descriptive kebab-case name, such as `F3.2-parametric-eq.md`.
- Identify the target Feature PR and Task PR, dependencies, goal, in-scope work, out-of-scope work, acceptance criteria, and required tests.
- Link the relevant section of [[../plan/implementation-plan|the implementation plan]].
- Include the mandatory human-interaction checkpoint procedure from [[codex-kickoff|the Codex kickoff]].
- Update an existing prompt when continuing the same task; create a new prompt when handing off a distinct task.
- Do not store executable secrets, signing credentials, personal data, or machine-specific tokens in prompts.

## Available prompt

- [[codex-kickoff|Initial Codex session guideline]]

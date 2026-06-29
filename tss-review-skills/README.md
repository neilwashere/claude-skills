# tss-review-skills

Multi-model PR/diff review that produces a learning corpus. Every skill here
invokes as `tss-review-skills:<skill>` once the plugin is installed.

## Install

See the [marketplace README](../README.md#install) for install instructions.

## Reference

Skills are split into **User-invoked** (reachable only when you type them —
`disable-model-invocation: true`) and **Model-invoked** (model- or
user-reachable).

### User-invoked

- **[synthesize-review-learnings](./skills/synthesize-review-learnings/SKILL.md)** — Harvest converged ledgers into anonymised, self-converging lessons under `docs/contributing/lessons/`.

### Model-invoked

- **[review-changes](./skills/review-changes/SKILL.md)** — Dispatch a panel of reviewer models against a diff/PR + spec; findings land in a canonical JSON ledger; drive the address-loop to no-open-HIGH/MEDIUM.

> **v1 dedup simplification:** duplicate findings are identified by exact
> `(dimension, file, line)` triple — no fuzzy matching. Two findings collide
> only when all three fields match exactly.

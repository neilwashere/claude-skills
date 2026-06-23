# Threadsafe Skills

My personal Claude Code skills — engineering workflows I use day to day, plus the **instincts** session-learning subsystem.

This repo is a **marketplace** hosting `threadsafe` (the general catch-all, skills invoke as `threadsafe:<skill>`) plus one curated **domain** plugin per domain, each named `tss-<domain>` (skills invoke as `tss-<domain>:<skill>`). Skills are small, composable, and meant to be hacked on.

## Install

Install as a local-directory marketplace so your edits stay live and git-synced:

```bash
/plugin marketplace add /home/neil/code/threadsafe/claude-skills
/plugin install threadsafe@threadsafe
```

## Reference

Skills are split into **User-invoked** (reachable only when you type them — `disable-model-invocation: true`) and **Model-invoked** (model- or user-reachable). See [docs/invocation.md](./docs/invocation.md) for the distinction.

### Engineering

**User-invoked**

- **[grill-with-docs](./skills/engineering/grill-with-docs/SKILL.md)** — A relentless interview to sharpen a plan or design that also writes the docs (ADRs and a glossary) as you go.

**Model-invoked**

- **[tdd](./skills/engineering/tdd/SKILL.md)** — Test-driven development, red-green-refactor; build features or fix bugs test-first.
- **[diagnosing-bugs](./skills/engineering/diagnosing-bugs/SKILL.md)** — Disciplined diagnosis loop for hard bugs and performance regressions.
- **[codebase-design](./skills/engineering/codebase-design/SKILL.md)** — Shared vocabulary for designing deep modules: small interfaces, clean seams, testable code.
- **[domain-modeling](./skills/engineering/domain-modeling/SKILL.md)** — Build and sharpen a project's domain model; record decisions as ADRs and a glossary.
- **[adversarial-review](./skills/engineering/adversarial-review/SKILL.md)** — Pre-landing PR review: parallel specialists hunt structural issues tests miss.
- **[address-pr-comments](./skills/engineering/address-pr-comments/SKILL.md)** — Triage and address PR review comments: fix, commit, push, reply inline.

### Productivity

**Model-invoked**

- **[grilling](./skills/productivity/grilling/SKILL.md)** — Interview the user relentlessly about a plan or design until every branch of the decision tree is resolved. (Used by `grill-with-docs`.)
- **[multi-perspective-research](./skills/productivity/multi-perspective-research/SKILL.md)** — Research a topic from several adaptively-chosen expert lenses in parallel, then map where they agree, clash, and collectively miss (contradiction / consensus / blind-spot map).

### Subsystems

A self-contained system that ships plugin-level hooks and commands. It lives outside the buckets at `skills/continuous-learning-v2/` so its hook paths stay stable — see [CLAUDE.md](./CLAUDE.md).

- **[continuous-learning-v2](./skills/continuous-learning-v2/SKILL.md)** (instincts) — Session-learning loop: hooks observe tool use and inject high-confidence instincts at session start. Managed by the `/evolve`, `/promote`, `/prune`, `/instinct-status`, `/instinct-import`, `/instinct-export`, and `/projects` commands (all `threadsafe:`-namespaced). Shares instinct data (`~/.local/share/ecc-homunculus`) with any prior ECC/Emerge install.

## tss-git-skills

A separate, separately-installed plugin in this marketplace (namespaced `tss-git-skills:<skill>`): `/plugin install tss-git-skills@threadsafe`. Full list in [tss-git-skills/README.md](./tss-git-skills/README.md).

**User-invoked**

- **[setup-worktree-discipline](./tss-git-skills/skills/setup-worktree-discipline/SKILL.md)** — One-time installer: a PreToolUse hook making the main checkout read-only in opted-in repos (all writes go through a worktree), plus the global CLAUDE.md rule.

**Model-invoked**

- **[create-and-enter-worktree](./tss-git-skills/skills/create-and-enter-worktree/SKILL.md)** — Create a sibling worktree off `origin/<default>` and relocate the session into it via the `EnterWorktree` tool, before writing a feature's spec, plan, or code.
- **[exit-and-dispose-worktree](./tss-git-skills/skills/exit-and-dispose-worktree/SKILL.md)** — After a PR merges, leave the worktree session then remove the tree.

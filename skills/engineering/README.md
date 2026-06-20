# Engineering

Skills for daily code work.

## User-invoked

Reachable only when you type them (`disable-model-invocation: true`).

- **[grill-with-docs](./grill-with-docs/SKILL.md)** — A relentless interview to sharpen a plan or design that also writes the docs (ADRs and a glossary) as you go.
- **[setup-worktree-discipline](./setup-worktree-discipline/SKILL.md)** — One-time installer: a PreToolUse hook that makes the main checkout read-only in opted-in repos (all writes go through a worktree), plus the global CLAUDE.md rule.

## Model-invoked

Model- or user-reachable (rich trigger phrasing so the model can reach for them).

- **[tdd](./tdd/SKILL.md)** — Test-driven development, red-green-refactor; build features or fix bugs test-first.
- **[diagnosing-bugs](./diagnosing-bugs/SKILL.md)** — Disciplined diagnosis loop for hard bugs and performance regressions.
- **[codebase-design](./codebase-design/SKILL.md)** — Shared vocabulary for designing deep modules: small interfaces, clean seams, testable code.
- **[domain-modeling](./domain-modeling/SKILL.md)** — Build and sharpen a project's domain model; record decisions as ADRs and a glossary.
- **[adversarial-review](./adversarial-review/SKILL.md)** — Pre-landing PR review: parallel specialists hunt structural issues tests miss (SQL safety, trust boundaries, conditional side effects).
- **[address-pr-comments](./address-pr-comments/SKILL.md)** — Triage and address PR review comments: fix, commit, push, reply inline.
- **[create-and-enter-worktree](./create-and-enter-worktree/SKILL.md)** — Create a sibling worktree off `origin/<default>` and relocate the session into it via the `EnterWorktree` tool. Run before writing a feature's spec, plan, or code.
- **[exit-and-dispose-worktree](./exit-and-dispose-worktree/SKILL.md)** — After a PR merges, leave the worktree session (`ExitWorktree({keep})`) then remove the tree with `wt-rm.sh` (refuses if dirty/unpushed).

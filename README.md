# tss-git-skills

Curated git/worktree workflow skills for Claude Code — branch discipline and worktree create / enter / dispose, packaged as one installable plugin.

This repo is a Claude Code **marketplace** hosting a single plugin, `tss-git-skills`; its skills invoke as `tss-git-skills:<skill>`.

## Install

```bash
/plugin marketplace add neilwashere/claude-skills
/plugin install tss-git-skills@neilwashere
```

For live, git-synced local development, point the marketplace at your checkout instead:

```bash
/plugin marketplace add /path/to/claude-skills
```

## Skills

Full list in [tss-git-skills/README.md](./tss-git-skills/README.md).

**User-invoked**

- **[setup-worktree-discipline](./tss-git-skills/skills/setup-worktree-discipline/SKILL.md)** — One-time installer: a PreToolUse hook making the main checkout read-only in opted-in repos (all writes go through a worktree), plus the global CLAUDE.md rule.
- **[teardown-worktree-discipline](./tss-git-skills/skills/teardown-worktree-discipline/SKILL.md)** — The clean exit: deregisters the hook, deletes the copied script, and strips the global CLAUDE.md rule. Run before `/plugin uninstall` (uninstall alone leaves the hook firing).
- **[worktree-enforce](./tss-git-skills/skills/worktree-enforce/SKILL.md)** — Opt the current repo `in`/`out` of enforcement, show `status`, or run `doctor` (a global-wiring audit + live-deny health check). Manages the per-repo marker the setup hook reads.
- **[configure-worktree](./tss-git-skills/skills/configure-worktree/SKILL.md)** — Guided `AskUserQuestion` setup for the worktree-config marker family (worktree location, files to mirror, post-create command, branch naming) at global / committed / local scope. Config only — enforcement stays with `worktree-enforce`.

**Model-invoked**

- **[create-and-enter-worktree](./tss-git-skills/skills/create-and-enter-worktree/SKILL.md)** — Create a sibling worktree off `origin/<default>` and relocate the session into it via the `EnterWorktree` tool, before writing a feature's spec, plan, or code.
- **[exit-and-dispose-worktree](./tss-git-skills/skills/exit-and-dispose-worktree/SKILL.md)** — After a PR merges, leave the worktree session then remove the tree.

> Worktree creation is configurable via `worktree-config.json` (three-tier: committed / local / global). See [`docs/superpowers/specs/2026-06-25-worktree-customisation-design.md`](./docs/superpowers/specs/2026-06-25-worktree-customisation-design.md).

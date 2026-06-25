# tss-git-skills

Curated git/worktree workflow skills. Every skill here invokes as
`tss-git-skills:<skill>` once the plugin is installed.

## Install

```bash
/plugin marketplace add neilwashere/claude-skills
/plugin install tss-git-skills@neilwashere
```

## Reference

Skills are split into **User-invoked** (reachable only when you type them —
`disable-model-invocation: true`) and **Model-invoked** (model- or
user-reachable).

## User-invoked

- **[setup-worktree-discipline](./skills/setup-worktree-discipline/SKILL.md)** — One-time installer: a PreToolUse hook that makes the main checkout read-only in opted-in repos (all writes go through a worktree), plus the global CLAUDE.md branch-discipline rule.
- **[teardown-worktree-discipline](./skills/teardown-worktree-discipline/SKILL.md)** — The clean exit: deregister the hook from `~/.claude/settings.json`, delete the copied hook script, and strip the global CLAUDE.md rule. Run it before `/plugin uninstall` (uninstall alone leaves the hook firing).
- **[worktree-enforce](./skills/worktree-enforce/SKILL.md)** — Opt the current repo `in`/`out` of worktree-discipline enforcement, show `status`, or run `doctor` (global-wiring audit + live-deny smoke test). Manages the per-repo marker the setup hook reads (committed policy + gitignored local override).
- **[configure-worktree](./skills/configure-worktree/SKILL.md)** — Guided `AskUserQuestion` setup for the worktree-config marker family (worktree location, files to mirror, post-create command, branch naming) at global / committed / local scope. Config only — enforcement stays with `worktree-enforce`.

## Model-invoked

- **[create-and-enter-worktree](./skills/create-and-enter-worktree/SKILL.md)** — Create a sibling worktree off `origin/<default>` and relocate the session into it via the `EnterWorktree` tool. Run before writing a feature's spec, plan, or code.
- **[exit-and-dispose-worktree](./skills/exit-and-dispose-worktree/SKILL.md)** — After a PR merges, leave the worktree session (`ExitWorktree({keep})`) then remove the tree with `wt-rm.sh` (refuses if dirty/unpushed).

> Worktree creation is configurable: `wt-new`/`wt-rm` read a three-tier `worktree-config.json` family (`.claude/worktree-config.json` → `.local.json` → `~/.claude/worktree-config.json`). See `docs/superpowers/specs/2026-06-25-worktree-customisation-design.md`.

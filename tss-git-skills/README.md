# tss-git-skills

Curated git/worktree workflow skills. Every skill here invokes as
`tss-git-skills:<skill>` once the plugin is installed.

## Install

```bash
/plugin marketplace add /home/neil/code/threadsafe/claude-skills
/plugin install tss-git-skills@threadsafe
```

## Reference

Skills are split into **User-invoked** (reachable only when you type them —
`disable-model-invocation: true`) and **Model-invoked** (model- or
user-reachable).

## User-invoked

- **[setup-worktree-discipline](./skills/setup-worktree-discipline/SKILL.md)** — One-time installer: a PreToolUse hook that makes the main checkout read-only in opted-in repos (all writes go through a worktree), plus the global CLAUDE.md branch-discipline rule.

## Model-invoked

- **[create-and-enter-worktree](./skills/create-and-enter-worktree/SKILL.md)** — Create a sibling worktree off `origin/<default>` and relocate the session into it via the `EnterWorktree` tool. Run before writing a feature's spec, plan, or code.
- **[exit-and-dispose-worktree](./skills/exit-and-dispose-worktree/SKILL.md)** — After a PR merges, leave the worktree session (`ExitWorktree({keep})`) then remove the tree with `wt-rm.sh` (refuses if dirty/unpushed).

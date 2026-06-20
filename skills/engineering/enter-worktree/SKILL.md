---
name: enter-worktree
description: Use when starting an epic, plan, or feature that needs its own git worktree, BEFORE writing its spec, plan, or code - or whenever tempted to reach for the harness EnterWorktree tool. Keywords worktree, wt-new, wt-go, repo.worktrees, isolation, parallel stream, kickoff.
---

# enter-worktree

## Overview

Run every feature/epic in its own git worktree at `<repo-parent>/<repo>.worktrees/<branch>` - a SIBLING tree, **not** `.claude/worktrees/`. A bundled script (`scripts/wt-enter.sh`) owns that path and links `.claude` context + gitignored creds (`settings.local.json`, `.credentials.json`) so a session in the worktree shares the same project memory and auth.

**Create the worktree BEFORE the first file write for the feature.** The design spec, the plan, the code, and the wrap-up docs are ALL authored in the worktree and reach `main` only via the feature's PR. Writing them on `main` lands design docs unreviewed - the failure this skill prevents.

## Do NOT use the harness `EnterWorktree` tool

It hard-codes `.claude/worktrees/<name>` and cannot target `<repo>.worktrees/`, so it puts the worktree in the wrong place (observed 2026-06-16). Use the helpers below instead.

## Create / enter (one command - lands your cwd in the worktree)

Run this single Bash call from the **main repo checkout** (not a worktree):

```
cd "$(bash /home/neil/code/threadsafe/claude-skills/skills/engineering/enter-worktree/scripts/wt-enter.sh <branch> [base])"
git status -sb      # confirm you are in the worktree before writing anything
```

The script creates (or resumes) `<repo>.worktrees/<branch>` off `origin/<base>` (default: origin's default branch) and links the Claude project context + gitignored creds. Its **stdout is exactly the worktree path and nothing else**; all progress ("Worktree ready at ...", link notes) goes to stderr, so it stays visible in the tool output while the `cd "$(...)"` substitution moves you in. The Claude Code Bash tool persists its working directory between calls, so that one `cd` puts the whole session inside the worktree - every later Bash call runs from there. No need to copy a path by hand.

A child process still cannot cd its parent shell; the `cd "$(...)"` does it on the caller side. The script itself does **no `cd`** and needs **no `source ~/.zshrc`**, so interactive zsh chpwd hooks (e.g. `auto_vrun`) can never break the `.claude` link - the failure mode observed 2026-06-16 when the `wt-new` zsh function was sourced into the non-interactive tool shell. The `wt-new` / `wt-go` zsh helpers in `~/.zshrc` remain for interactive terminal use; the bundled script is the one to use from a Claude session.

## After entering

A fresh worktree does NOT share `node_modules` (npm workspaces). If your repo uses workspaces, run `npm install` in the worktree before relying on a local build or test run.

## Cleanup

Remove the worktree only AFTER the PR merges - use the `exit-worktree` skill.

---
name: exit-worktree
description: Use when a feature's PR has merged and its git worktree should be removed (the cleanup tail) - or whenever tempted to reach for the harness ExitWorktree tool. Keywords worktree removal, wt-rm, repo.worktrees, cleanup, merge, teardown.
---

# exit-worktree

## Overview

Remove a feature worktree (at `<repo>.worktrees/<branch>`) after its PR has merged - **never before** (the handover + bootstrap repoint reach the next session only via `main`).

## Do NOT use the harness `ExitWorktree` tool

It only manages worktrees it created under `.claude/worktrees/`. These worktrees live at `<repo>.worktrees/<branch>`; the harness tool is a no-op or wrong target for them. Use the helper.

## Remove

Run the bundled script from the **main repo checkout** (leave the worktree first - do not remove the tree you are standing in):

```
cd <main repo>
bash /home/neil/code/threadsafe/claude-skills/skills/engineering/exit-worktree/scripts/wt-exit.sh <branch> [--force]
git branch -d <branch>    # delete the merged branch (optional tidy-up)
```

`wt-exit.sh` unlinks the Claude context, then removes the worktree, and **REFUSES if it is dirty or has unpushed commits** - that guard is intentional. Investigate before overriding; pass `--force` only when you genuinely intend to discard that work.

The script is self-contained (no `source ~/.zshrc`); it mirrors the `wt-rm` zsh helper, which remains for interactive terminal use.

## Order

This is the LAST step of the wrap-up tail, after the PR has merged. If the worktree still has unpushed commits or uncommitted files, you are not done - finish the PR first.

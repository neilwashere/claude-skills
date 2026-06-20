---
name: exit-and-dispose-worktree
description: Use when a feature's PR has merged and its worktree should be torn down. Leaves the worktree session via the ExitWorktree tool, then removes the tree from disk with wt-rm.sh. Keywords worktree removal, wt-rm, dispose, teardown, cleanup, after merge.
---

# exit-and-dispose-worktree

A **compound** workflow: leave the worktree session **and** dispose the tree. Two operations, and the split is forced by a hard constraint:

- The harness **`ExitWorktree` tool** is the only thing that moves the session back to the main checkout — but `ExitWorktree({action: "remove"})` **refuses to delete a worktree it did not create.** Ours are created by `wt-new.sh` and entered by `path`, so the tool will not remove them.
- `wt-rm.sh` (bundled) removes the tree from disk — but a script cannot move the session, so it must be run from the main checkout, *after* you have left.

So: leave with the tool (`keep`), then dispose with the script.

## Order — only after the PR has merged

Disposing before merge throws away the work (the branch reaches `main` only via its PR). If the worktree still has uncommitted files or unpushed commits, you are not done — finish the PR first. `wt-rm.sh` enforces this and **refuses** on a dirty or unpushed tree; pass `--force` only when you genuinely intend to discard.

## The flow

**Step 1 — leave the session (the `ExitWorktree` tool, not Bash).** Use `keep`, never `remove` (remove is a no-op on our path-entered worktrees):

```
ExitWorktree({ action: "keep" })
```

The session is now back in the main checkout. (If `ExitWorktree` reports no active worktree session, you are already in the main checkout — skip to Step 2.)

**Step 2 — dispose the tree (Bash, from the main checkout):**

```
bash /home/neil/code/threadsafe/claude-skills/skills/engineering/exit-and-dispose-worktree/scripts/wt-rm.sh <branch> [--force]
git branch -d <branch>    # delete the merged branch (optional tidy-up)
```

`wt-rm.sh` unlinks the Claude context, then removes the worktree, with the dirty/unpushed guard above.

## Just want to leave, not dispose?

To step out of a worktree but keep it on disk (switching tasks, coming back later), call the harness **`ExitWorktree({action: "keep"})` directly** — do not use this skill. This skill is specifically *exit + dispose*.

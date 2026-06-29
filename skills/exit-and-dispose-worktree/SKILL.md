---
name: exit-and-dispose-worktree
description: Use when a feature's PR has merged and its worktree should be torn down. Leaves the worktree session via the ExitWorktree tool, then removes the tree from disk with wt-rm.sh. Keywords worktree removal, wt-rm, dispose, teardown, cleanup, after merge.
license: MIT
compatibility: "Requires git and a POSIX shell. Claude Code leaves the session via ExitWorktree; elsewhere leave the worktree session manually, then run the removal script from the main checkout."
metadata:
  version: "1.0.0"
---

# exit-and-dispose-worktree

A **compound** workflow: leave the worktree session **and** dispose the tree. Two operations, and the split is forced by a hard constraint:

- Claude Code's **`ExitWorktree` tool** is the only thing that moves the session back to the main checkout — but `ExitWorktree({action: "remove"})` **refuses to delete a worktree it did not create.** Ours are created by `wt-new.sh` and entered by `path`, so the tool will not remove them.
- `wt-rm.sh` (bundled) removes the tree from disk — but a script cannot move the session, so it must be run from the main checkout, *after* you have left.

So: leave with the tool (`keep`), then dispose with the script.

## Order — only after the PR has merged

Disposing before merge throws away the work (the branch reaches `main` only via its PR). If the worktree still has uncommitted files or unpushed commits, you are not done — finish the PR first. `wt-rm.sh` enforces this and **refuses** on a dirty or unpushed tree; pass `--force` only when you genuinely intend to discard.

## The flow

**Step 1 — leave the worktree session, returning to the main checkout.**

- **Claude Code:** `ExitWorktree({ action: "keep" })` (use `keep`, never `remove` — `remove` is a no-op on path-entered worktrees).
- **Other harnesses:** return to / open the main checkout directory yourself.

**Step 2 — dispose the tree (Bash, from the main checkout):**

```
# Run the bundled scripts/wt-rm.sh from the main checkout, after you have left the worktree session.
# Claude Code (plugin): bash "${CLAUDE_PLUGIN_ROOT}/skills/exit-and-dispose-worktree/scripts/wt-rm.sh" <branch> [--force] \
# Otherwise:            bash <this-skill-dir>/scripts/wt-rm.sh <branch> [--force] \
  && git branch -d <branch>    # delete the merged branch — only if removal succeeded
```

`wt-rm.sh` unlinks the Claude context, then removes the worktree, with the dirty/unpushed guard above. The `&&` matters: `wt-rm.sh` exits non-zero when it refuses a dirty/unpushed tree, so chaining the branch delete behind it stops a confusing half-done state where the branch is gone but the worktree is still on disk.

## Validate (after Step 2)

Disposal is destructive and has silent failure modes — in Claude Code, the Step 1 `ExitWorktree` is a no-op if no session was active (so you might still be effectively in the tree), and removing a tree you were still sitting in can leave a `prunable` stub. Assert the end-state:

```
# Back in the main checkout? git-dir and git-common-dir resolve to the SAME real
# path only OUTSIDE a worktree — canonicalize before comparing (raw strings can
# differ from a subdir even in main; same approach as worktree-enforce).
gd=$( (cd "$(git rev-parse --git-dir)" && pwd -P) )
gc=$( (cd "$(git rev-parse --git-common-dir)" && pwd -P) )
[ "$gd" = "$gc" ] && echo "back in main: OK" \
  || echo "STILL IN A WORKTREE — run ExitWorktree({action: \"keep\"}) first"
# The tree is actually gone (substitute the branch's dir slug — '/' becomes '-'):
git worktree list --porcelain | grep -q "\.worktrees/<branch-dir>" \
  && echo "DISPOSAL FAILED — worktree still registered" || echo "tree gone: OK"
# Sweep any stale entry left by removing a tree you were sitting in:
git worktree list | grep -q prunable && git worktree prune
```

## Just want to leave, not dispose?

To step out of a worktree but keep it on disk (switching tasks, coming back later), Claude Code: call **`ExitWorktree({action: "keep"})` directly** — do not use this skill. This skill is specifically *exit + dispose*.

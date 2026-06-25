---
name: create-and-enter-worktree
description: Use when starting an epic, plan, or feature that needs its own git worktree, BEFORE writing its spec, plan, or code. Creates a sibling worktree off the default branch and relocates the session into it via the EnterWorktree tool. Keywords worktree, wt-new, isolation, parallel stream, kickoff, start feature.
---

# create-and-enter-worktree

A **compound** workflow: create a sibling git worktree **and** relocate the session into it. It is two operations because no single primitive does both:

- `wt-new.sh` (bundled) creates `<repo-parent>/<repo>.worktrees/<branch>` off `origin/<default>` and links `.claude` context + gitignored creds — but a script **cannot** move the session.
- The harness **`EnterWorktree` tool** is the only thing that relocates the session's cwd — but its own `name` mode only creates under `.claude/worktrees/`, not the sibling layout.

So we create with the script, then enter by **path**. (`EnterWorktree({path})` accepts any worktree in `git worktree list` — verified **from the main checkout**; for the worktree→sibling caveat see *Switching between worktrees* below.)

## Why you cannot just `cd`

`cd` does **not** persist in this harness — the working directory is reverted after every Bash call. `cd ../repo.worktrees/x && …` runs that one command in the worktree and then snaps back to the main checkout. The **only** way to keep the session in the worktree is the `EnterWorktree` tool. Do not attempt `cd`.

## Create the worktree BEFORE the first file write

The design spec, the plan, the code, and the wrap-up docs are ALL authored in the worktree and reach `main` only via the feature's PR. Writing them in the main checkout pollutes the active branch — and when a second feature spins up it can add files to a branch the first one owns.

## The flow

**Step 1 — create (Bash, run from the main checkout).** Its stdout is *exactly* the worktree path; progress goes to stderr.

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/create-and-enter-worktree/scripts/wt-new.sh" <branch> [base]
```

`wt-new.sh` creates (or resumes) `<repo>.worktrees/<branch>` off `origin/<base>` (default: origin's default branch — this is what stops worktrees being branched off the *active* branch) and links the Claude project context + gitignored creds.

**Step 2 — enter (the `EnterWorktree` tool, not Bash).** Take the path printed in Step 1 and call:

```
EnterWorktree({ path: "<the path wt-new.sh printed>" })
```

Pass the **exact single line** `wt-new.sh` wrote to stdout — don't reconstruct the path from the branch name (the directory slug encodes `/` as `-`, so `feat/x` lives at `…/feat-x`), and don't pipe `wt-new.sh` through anything that could prepend to its output. Progress notes go to stderr precisely to keep that one stdout line clean.

The session is now in the worktree. **Step 3 — assert you actually relocated.** This is the whole point of the skill, so *check* it, don't eyeball it — `git-dir` and `git-common-dir` differ **only** inside a worktree:

```
# git-dir and git-common-dir resolve to the SAME real path only OUTSIDE a worktree.
# Canonicalize before comparing: from a subdir the raw strings can differ (one
# absolute, one relative) even in the main checkout (same approach as worktree-enforce).
gd=$( (cd "$(git rev-parse --git-dir)" && pwd -P) )
gc=$( (cd "$(git rev-parse --git-common-dir)" && pwd -P) )
[ "$gd" != "$gc" ] && echo "in worktree: OK ($(git rev-parse --abbrev-ref HEAD))" \
  || echo "NOT IN WORKTREE — EnterWorktree did not take; do NOT write files (they would land on main)"
git status -sb
```

If it prints `NOT IN WORKTREE`, **stop**: `EnterWorktree` was skipped or given the wrong path. Re-enter (`EnterWorktree({ path })`) before any file write — otherwise every edit pollutes the main checkout's active branch, the exact failure this skill exists to prevent.

## Already created a worktree but stuck on main?

If a worktree exists (you or a prior step ran `git worktree add` / `wt-new.sh`) but the session is still in the main checkout, you do **not** re-create it — just enter it:

```
EnterWorktree({ path: "<existing worktree path from `git worktree list`>" })
```

## Switching between worktrees

`EnterWorktree({ path })` relocates **from the main checkout into a worktree**. It will **not** hop directly from one worktree into a sibling — you get `Cannot enter worktree: …/.claude/worktrees does not exist`. To switch features, return to the main checkout first, then enter the other tree:

```
ExitWorktree({ action: "keep" })          # back to the main checkout
EnterWorktree({ path: "<other worktree path>" })
```

If you only need to *read or edit* files in another worktree (not relocate the session), don't switch at all — use `git -C <other-tree> …` with absolute paths.

## After entering

A fresh worktree starts clean — it does not share `node_modules`, build caches, or other gitignored artifacts. If your repo configures `postCreate` (in `worktree-config.json`), `wt-new.sh` prints those commands on stderr as `postCreate: <cmd>` notes; run them in the worktree before relying on a local build or test run. (No `postCreate` configured → no notes; e.g. a Node repo would set `postCreate: "npm install"`.)

## Cleanup

Remove the worktree only AFTER its PR merges — use the `exit-and-dispose-worktree` skill (it leaves the session via `ExitWorktree({keep})` then removes the tree with `wt-rm.sh`).

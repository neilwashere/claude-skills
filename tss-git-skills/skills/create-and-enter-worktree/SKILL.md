---
name: create-and-enter-worktree
description: Use when starting an epic, plan, or feature that needs its own git worktree, BEFORE writing its spec, plan, or code. Creates a sibling worktree off the default branch and relocates the session into it via the EnterWorktree tool. Keywords worktree, wt-new, isolation, parallel stream, kickoff, start feature.
---

# create-and-enter-worktree

A **compound** workflow: create a sibling git worktree **and** relocate the session into it. It is two operations because no single primitive does both:

- `wt-new.sh` (bundled) creates `<repo-parent>/<repo>.worktrees/<branch>` off `origin/<default>` and links `.claude` context + gitignored creds — but a script **cannot** move the session.
- The harness **`EnterWorktree` tool** is the only thing that relocates the session's cwd — but its own `name` mode only creates under `.claude/worktrees/`, not the sibling layout.

So we create with the script, then enter by **path**. (`EnterWorktree({path})` accepts any worktree in `git worktree list`, including a sibling — verified.)

## Why you cannot just `cd`

`cd` does **not** persist in this harness — the working directory is reverted after every Bash call. `cd ../repo.worktrees/x && …` runs that one command in the worktree and then snaps back to the main checkout. The **only** way to keep the session in the worktree is the `EnterWorktree` tool. Do not attempt `cd`.

## Create the worktree BEFORE the first file write

The design spec, the plan, the code, and the wrap-up docs are ALL authored in the worktree and reach `main` only via the feature's PR. Writing them in the main checkout pollutes the active branch — and when a second feature spins up it can add files to a branch the first one owns.

## The flow

**Step 1 — create (Bash, run from the main checkout).** Its stdout is *exactly* the worktree path; progress goes to stderr.

```
bash /home/neil/code/threadsafe/claude-skills/tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh <branch> [base]
```

`wt-new.sh` creates (or resumes) `<repo>.worktrees/<branch>` off `origin/<base>` (default: origin's default branch — this is what stops worktrees being branched off the *active* branch) and links the Claude project context + gitignored creds.

**Step 2 — enter (the `EnterWorktree` tool, not Bash).** Take the path printed in Step 1 and call:

```
EnterWorktree({ path: "<the path wt-new.sh printed>" })
```

The session is now in the worktree. **Step 3 — confirm:**

```
git rev-parse --git-dir          # .../.git/worktrees/<branch>
git rev-parse --git-common-dir   # .../.git   ← differs ⇒ you are in the worktree
git status -sb
```

## Already created a worktree but stuck on main?

If a worktree exists (you or a prior step ran `git worktree add` / `wt-new.sh`) but the session is still in the main checkout, you do **not** re-create it — just enter it:

```
EnterWorktree({ path: "<existing worktree path from `git worktree list`>" })
```

## After entering

A fresh worktree does NOT share `node_modules` (npm workspaces). If your repo uses workspaces, run `npm install` in the worktree before relying on a local build or test run.

## Cleanup

Remove the worktree only AFTER its PR merges — use the `exit-and-dispose-worktree` skill (it leaves the session via `ExitWorktree({keep})` then removes the tree with `wt-rm.sh`).

---
name: create-and-enter-worktree
description: Use when starting an epic, plan, or feature that needs its own git worktree, BEFORE writing its spec, plan, or code. Creates a sibling worktree off the default branch and relocates the session into it via the EnterWorktree tool. Keywords worktree, wt-new, isolation, parallel stream, kickoff, start feature.
license: MIT
compatibility: "Requires git and a POSIX shell. Claude Code relocates the session automatically (EnterWorktree); on other harnesses the bundled script creates the worktree but you must cd in / start a session there yourself."
metadata:
  version: "1.0.0"
---

# create-and-enter-worktree

A **compound** workflow: create a sibling git worktree **and** relocate the session into it. It is two operations because no single primitive does both:

- `wt-new.sh` (bundled) creates `<repo-parent>/<repo>.worktrees/<branch>` off `origin/<default>` and links `.claude` context + gitignored creds — but a script **cannot** move the session.
- Claude Code's **`EnterWorktree` tool** is the only thing that relocates the session's cwd — but its own `name` mode only creates under `.claude/worktrees/`, not the sibling layout.

So we create with the script, then enter by **path**. (Claude Code: `EnterWorktree({path})` accepts any worktree in `git worktree list` — verified **from the main checkout**; for the worktree→sibling caveat see *Switching between worktrees* below.)

> **Portability.** This skill is fully automatic in Claude Code, which has a session-relocation tool. Other harnesses have no such tool: there, run the bundled `scripts/wt-new.sh` to *create* the worktree, then open a session in / `cd` into the printed path yourself. See `docs/SUPPORT-MATRIX.md`.

## Why you cannot just `cd`

`cd` does **not** persist in Claude Code (and several other harnesses) — the working directory is reverted after every Bash call. `cd ../repo.worktrees/x && …` runs that one command in the worktree and then snaps back to the main checkout. The **only** way to keep the session in the worktree is the `EnterWorktree` tool. Do not attempt `cd`.

## Create the worktree BEFORE the first file write

The design spec, the plan, the code, and the wrap-up docs are ALL authored in the worktree and reach `main` only via the feature's PR. Writing them in the main checkout pollutes the active branch — and when a second feature spins up it can add files to a branch the first one owns.

## Choosing a branch name

Name the branch `<type>/<slug>` — a conventional-commit type, then a short slug:

- **type** — the conventional-commit corpus: `feat` and `fix` (mandated), plus `docs`, `chore`, `refactor`, `perf`, `test`, `build`, `ci`, `style`, `revert`. Use `fix`, never `bug`.
- **slug** — resolve in this order:
  1. an explicit name the caller gave → use it verbatim;
  2. an issue/ticket reference → `<type>/<N>-<slug-from-title>`, embedding the number (GitHub `#9` → `feat/9-configure-worktree`) — **unless** the repo opts out (see below);
  3. otherwise infer a kebab-case slug from the task;
  4. if still ambiguous, ask.

Before embedding an issue number, honor the repo's `branchNaming.embedIssueId` (default `true`):

```
# Claude Code (plugin): the bundled resolver answers this directly —
. "${CLAUDE_PLUGIN_ROOT}/lib/worktree-config.sh"; wtc_branch_naming "$(git rev-parse --show-toplevel)"
# Elsewhere: source the bundled lib/worktree-config.sh by its installed path, then call wtc_branch_naming <repo-root>.
```

`true` → embed the number; `false` → omit it (e.g. `feat/configure-worktree`). Set this with `configure-worktree`.

`wt-new.sh` slugs `/` → `-` for the directory only, so `feat/9-x` lives at `…/feat-9-x` while the branch keeps the slash.

## The flow

**Step 1 — create (Bash, run from the main checkout).** Its stdout is *exactly* the worktree path; progress goes to stderr.

```
# Run the bundled scripts/wt-new.sh from the main checkout.
# Claude Code (plugin): bash "${CLAUDE_PLUGIN_ROOT}/skills/create-and-enter-worktree/scripts/wt-new.sh" <branch> [base]
# Otherwise: bash <this-skill-dir>/scripts/wt-new.sh <branch> [base]
```

`wt-new.sh` creates (or resumes) `<repo>.worktrees/<branch>` off `origin/<base>` (default: origin's default branch — this is what stops worktrees being branched off the *active* branch) and links the Claude project context + gitignored creds.

**Step 2 — relocate the session into the worktree.** Use the single path line Step 1 printed.

- **Claude Code:** call the session-relocation tool — `EnterWorktree({ path: "<the path wt-new.sh printed>" })`.
- **Other harnesses:** there is usually no relocation tool. Start a session in that directory, or `cd` into it. Note some harnesses revert `cd` between commands — if so, open the path as a fresh working directory rather than relying on `cd`.

Pass the **exact single line** `wt-new.sh` wrote to stdout — don't reconstruct it from the branch name (the directory slug encodes `/` as `-`), and don't pipe `wt-new.sh` through anything that could prepend to its output.

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

If it prints `NOT IN WORKTREE`, **stop**: Claude Code's `EnterWorktree` was skipped or given the wrong path. In Claude Code, re-enter (`EnterWorktree({ path })`) before any file write — otherwise every edit pollutes the main checkout's active branch, the exact failure this skill exists to prevent.

## Already created a worktree but stuck on main?

If a worktree exists (you or a prior step ran `git worktree add` / `wt-new.sh`) but the session is still in the main checkout, you do **not** re-create it — just enter it:

```
# Claude Code:
EnterWorktree({ path: "<existing worktree path from `git worktree list`>" })
```

## Switching between worktrees

Claude Code's `EnterWorktree({ path })` relocates **from the main checkout into a worktree**. It will **not** hop directly from one worktree into a sibling — you get `Cannot enter worktree: …/.claude/worktrees does not exist`. To switch features in Claude Code, return to the main checkout first, then enter the other tree:

```
# Claude Code:
ExitWorktree({ action: "keep" })          # back to the main checkout
EnterWorktree({ path: "<other worktree path>" })
```

If you only need to *read or edit* files in another worktree (not relocate the session), don't switch at all — use `git -C <other-tree> …` with absolute paths.

## After entering

A fresh worktree starts clean — it does not share `node_modules`, build caches, or other gitignored artifacts. If your repo configures `postCreate` (in `worktree-config.json`), `wt-new.sh` prints those commands on stderr as `postCreate: <cmd>` notes; run them in the worktree before relying on a local build or test run. (No `postCreate` configured → no notes; e.g. a Node repo would set `postCreate: "npm install"`.)

## Cleanup

Remove the worktree only AFTER its PR merges — use the `exit-and-dispose-worktree` skill (Claude Code: `ExitWorktree({keep})` to leave, then `wt-rm.sh` to remove the tree).

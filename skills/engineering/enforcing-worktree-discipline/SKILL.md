---
name: enforcing-worktree-discipline
description: Use when the user wants a mechanical guarantee that Claude never creates or switches to a feature branch in the main repo directory — installs a PreToolUse Bash hook that denies branch-creation, branch-switch, and cherry-pick in the main repo dir, and forces all feature work into git worktrees. Triggers on phrases like "enforce worktree discipline", "stop Claude making branches in main", "prevent branching in the default repo", "mechanical fix for branch hygiene".
---

# Enforcing Worktree Discipline

## Overview

A `PreToolUse` hook on the `Bash` tool that physically blocks Claude from:

- creating a branch in the main repo dir (`git checkout -b`, `git switch -c`)
- switching to a non-default branch in the main repo dir
- cherry-picking in the main repo dir
- compounding damage when the main repo dir's HEAD has already drifted off `main`/`master`

The hook detects "main repo dir" by comparing `git rev-parse --git-dir` to `git rev-parse --git-common-dir` — when they differ, the cwd is a worktree, and the hook gets out of the way. Memory alone (CLAUDE.md notes) does not enforce this; only a hook can deny a tool call before it runs.

## When to Use

- User asks for a "mechanical fix" so Claude "physically can't" create branches in the main repo dir
- User has had work land on the wrong branch because a subagent committed in the main dir while another process or the IDE was switching HEAD
- User wants to standardise on the `../<repo>.worktrees/<branch>` layout for all feature work
- User already has memory rules about worktrees but they're being ignored under pressure

**Do not use** if the user works without worktrees on purpose, or if the project's flow expects feature branches in the primary checkout (e.g. some monorepos with custom tooling).

## Install

Three steps. All paths absolute so it works from any cwd.

**1. Write the hook script** to `~/.claude/hooks/git-branch-discipline.sh`. Copy `git-branch-discipline.sh` (in this skill directory) verbatim, then:

```bash
mkdir -p ~/.claude/hooks
# (Write the script content here via the Write tool, or cp from a checkout of this plugin.)
chmod +x ~/.claude/hooks/git-branch-discipline.sh
```

**2. Register the hook** in `~/.claude/settings.json`. Read the file first, then add this entry to `hooks.PreToolUse` (merge with any existing entries — do not replace):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /home/<user>/.claude/hooks/git-branch-discipline.sh",
            "if": "Bash(git *)"
          }
        ]
      }
    ]
  }
}
```

The `if: "Bash(git *)"` filter means the hook script only runs for git invocations — every other Bash call skips the fork entirely.

**3. Validate JSON and the wired-up hook**:

```bash
jq '.hooks.PreToolUse[0]' ~/.claude/settings.json

# IMPORTANT: cd into the main checkout of a real repo before piping into the
# hook. The hook intentionally exits silently outside a git repo and inside
# any worktree, so testing it from a non-repo cwd looks like a broken install.
cd /path/to/any/main/checkout    # NOT a worktree
echo '{"tool_name":"Bash","tool_input":{"command":"git checkout -b should-be-blocked"}}' \
  | bash ~/.claude/hooks/git-branch-discipline.sh
```

Expected output: a JSON object containing `"permissionDecision": "deny"`. Interpretation of other outputs:

- **Empty output from a main checkout** — the hook script isn't reachable (wrong path in `settings.json`, or file isn't executable). Re-check step 1 and 2.
- **Empty output from a worktree or non-repo dir** — expected. The hook's `git rev-parse` exit-0 path is the silent-allow case; it's not a sign of a broken install.

**Settings-watcher caveat:** Claude Code's settings file watcher picks up the new hook block automatically only if the file was present at session start. If it isn't picked up, open `/hooks` once to force a reload, or start a fresh session.

## What the Hook Decides

| Command in main repo dir | Decision |
|---|---|
| `git checkout -b <branch>` / `git switch -c <branch>` | deny |
| `git checkout <non-default-branch>` / `git switch <branch>` | deny |
| `git checkout main` / `git checkout master` | allow |
| `git checkout <sha>` (detached HEAD on a sha) | allow |
| `git checkout -- path/to/file` / `git checkout HEAD -- file` | allow |
| `git cherry-pick <sha>` | deny |
| `git commit` / `merge` / `rebase` / `push` while HEAD is off `main`/`master` | deny (bad-state catch) |
| Any of the above **inside a worktree** | allow |

The deny reason quoted to Claude always names the exact bad command and the worktree-flavoured replacement, so a fresh session can recover without re-deriving the rule.

## After Install — Fix Pre-Existing Bad State

If the main repo dir is already on a feature branch when the hook lands, the hook will keep denying writes until HEAD goes home. The standard recovery is:

```bash
git checkout main
git worktree add ../$(basename $PWD).worktrees/<branch-slug> <branch>
```

Then `cd` into the worktree to keep working.

## Companion Rule for Memory

Pair the hook with a CLAUDE.md rule under the user's global `~/.claude/CLAUDE.md`, titled "Branch discipline". The memory tells Claude *why* the rule exists; the hook ensures Claude can't drift even when the rule is forgotten or context-compressed away.

## Common Mistakes

- **Replacing existing `hooks` block.** Always read `~/.claude/settings.json` first and merge — clobbering wipes other hooks like log emitters or PR guards.
- **Forgetting `chmod +x`.** The hook line invokes `bash <path>` so it works even without the exec bit, but pipe-tests via `bash <path>` mask permission issues that other shells (e.g. `/run` hook runner) would surface.
- **Using `~` inside the command field.** Settings.json hook commands run under `bash -c` without tilde expansion in every harness path. Use the absolute home path `/home/<user>/...` to be safe.
- **Putting the script inside the repo.** It belongs in `~/.claude/hooks/`, not in the project — the hook applies across every repo Claude opens, and project-local copies drift.

## Red Flags — Stop and Re-verify

- The verification one-liner prints nothing → script not reachable; re-check the path in `settings.json`.
- The hook denies inside a worktree → the worktree was created weirdly (e.g. by copying the `.git` dir); confirm `git rev-parse --git-common-dir` differs from `git rev-parse --git-dir`.
- The hook allows `git checkout -b foo` in the main dir → `if: "Bash(git *)"` filter isn't being honoured; check the harness's hook syntax and that the JSON parses cleanly.

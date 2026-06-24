---
name: setup-worktree-discipline
description: Install the worktree-discipline enforcement — a PreToolUse hook that blocks direct writes (and branch/cherry-pick ops) in the main checkout of opted-in repos, plus the global CLAUDE.md rule. Run once to set it up.
disable-model-invocation: true
---

# Setup Worktree Discipline

This is a **one-time installer**, run deliberately by the human — not a runtime behaviour. It lays down three things, then you opt repos in one at a time.

What it enforces (in a repo that has opted in): all feature work happens in a git **worktree**; the **main checkout is read-only** (changes reach `main` only via a merged worktree PR); branches come off `origin/<default>`, never the active branch; and you **enter** worktrees with the `EnterWorktree` tool / `/create-and-enter-worktree`, never `cd` (the harness reverts cwd every Bash call).

It is **opt-in per repo** and off by default everywhere. See `worktree-discipline.sh` (this skill dir) for the exact decision table.

## Install

**1. Install the hook script.** Copy the bundled hook to the global hooks dir and make it executable:

```bash
mkdir -p ~/.claude/hooks
cp "${CLAUDE_PLUGIN_ROOT}/skills/setup-worktree-discipline/worktree-discipline.sh" ~/.claude/hooks/worktree-discipline.sh
chmod +x ~/.claude/hooks/worktree-discipline.sh
```

**2. Remove the superseded hook, if present.** This replaces the older git-only `git-branch-discipline.sh`. Read `~/.claude/settings.json`; if a `PreToolUse` entry points at `git-branch-discipline.sh`, delete that entry (and the old script) so the two don't both fire.

**3. Register the hook.** Read `~/.claude/settings.json` first, then **merge** this into `hooks.PreToolUse` (do not clobber other hooks). Use `$HOME` — `~` is not expanded in every hook-runner:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|NotebookEdit|Bash",
        "hooks": [
          { "type": "command", "command": "bash $HOME/.claude/hooks/worktree-discipline.sh" }
        ]
      }
    ]
  }
}
```

No `if:` filter — the script fast-bails itself (it exits 0 immediately in any repo that hasn't opted in, so non-enforced repos pay only a couple of `git rev-parse` calls).

**4. Add the global rule.** Ensure `~/.claude/CLAUDE.md` has a "Worktree discipline" section (replace the old "Branch discipline" one). Suggested text:

```markdown
## Worktree discipline

In a repo that has opted in (a `.claude/worktree-discipline.json` with `{"enforce": true}`), the main checkout is read-only:

- **All feature work happens in a git worktree.** The main checkout's HEAD stays on `main`/`master`; it receives changes only by merging a worktree's PR.
- **Enter worktrees with the `EnterWorktree` tool** (or `/create-and-enter-worktree`), **never `cd`.** `cd` does not persist — the harness reverts cwd after every Bash call, so `cd ../wt && …` writes still land in the main checkout. `EnterWorktree({path})` is the only thing that relocates the session.
- **Branch worktrees off `origin/<default>`, never the active branch** (`/create-and-enter-worktree` and `wt-new.sh` do this).
- **Dispose** a worktree after its PR merges with `/exit-and-dispose-worktree` (`ExitWorktree({keep})` to leave, then `wt-rm.sh` to remove — `ExitWorktree({remove})` won't touch script-created worktrees).
- Direct writes to a main checkout are **opt-in**: allowed only where the repo has no marker, where the path is in `allowPaths`, or where a gitignored `.claude/worktree-discipline.local.json` sets `{"enforce": false}`.
```

**5. Reload.** Open `/hooks` once (or start a fresh session) so the watcher picks up the new block.

## Opt a repo in

Create the marker at the repo root and commit it:

```bash
# in <repo>
mkdir -p .claude
printf '{\n  "enforce": true,\n  "allowPaths": ["CHANGELOG.md", ".changeset/**"]\n}\n' > .claude/worktree-discipline.json
```

- **`allowPaths`** — globs (relative to repo root) you may still edit on the main checkout (release files, etc.). The marker itself and `.git/` are always allowed.
- **Temporary escape** — to write directly on main in a checkout without changing committed config, add a gitignored `.claude/worktree-discipline.local.json` with `{"enforce": false}`. It overrides the committed marker. Add `worktree-discipline.local.json` to the repo's `.gitignore`.

## Validate

```bash
jq '.hooks.PreToolUse' ~/.claude/settings.json   # hook is registered

# From the MAIN checkout of an opted-in repo, a write should be denied:
cd /path/to/opted-in/repo        # main checkout, NOT a worktree
echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/probe.txt"}}' \
  | bash ~/.claude/hooks/worktree-discipline.sh
# expect: a JSON object with "permissionDecision": "deny"
```

Empty output from an opted-in main checkout means the script isn't reachable (check the path/exec bit). Empty output from a worktree, a non-opted-in repo, or a non-repo dir is **expected** — that's the silent-allow path.

## Update the installed hook

Step 1 **copies** `worktree-discipline.sh` into `~/.claude/hooks/` rather than referencing it in place — that's deliberate (the rule then survives independently of the plugin). The cost: a plugin update does **not** refresh the copy. After upgrading the plugin, re-copy:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/skills/setup-worktree-discipline/worktree-discipline.sh" ~/.claude/hooks/worktree-discipline.sh
chmod +x ~/.claude/hooks/worktree-discipline.sh
```

No reload needed — the hook command re-reads the file on every tool call. `worktree-enforce status` detects this drift: it prints **STALE** (with the exact `cp` to run) when the installed copy differs from the plugin's bundled hook, **MISSING** if the registered file is gone, else plain **installed**.

## Removing it

This installs *outside* the plugin (a copied hook + a `settings.json` entry + a CLAUDE.md rule), so `/plugin uninstall` does **not** undo it — the hook keeps firing. To remove cleanly, run `/teardown-worktree-discipline` **before** uninstalling the plugin.

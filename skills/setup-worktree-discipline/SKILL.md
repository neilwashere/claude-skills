---
name: setup-worktree-discipline
description: Install the worktree-discipline enforcement — a PreToolUse hook that blocks direct writes (and branch/cherry-pick ops) in the main checkout of opted-in repos, plus the global CLAUDE.md rule. Run once to set it up.
disable-model-invocation: true
license: MIT
compatibility: "Claude Code only: installs a PreToolUse hook plus ~/.claude integration that make an opted-in main checkout read-only. No equivalent primitive on other harnesses."
metadata:
  version: "1.0.0"
---

# Setup Worktree Discipline

> **Claude Code only.** This installs a `PreToolUse` hook and `~/.claude` integration — mechanisms no other harness has. There is no portable equivalent; see `docs/SUPPORT-MATRIX.md`.

This is a **one-time installer**, run deliberately by the human — not a runtime behaviour. It lays down three things, then you opt repos in one at a time.

What it enforces (in a repo that has opted in): all feature work happens in a git **worktree**; the **main checkout is read-only** (changes reach `main` only via a merged worktree PR); branches come off `origin/<default>`, never the active branch; and you **enter** worktrees with the Claude Code `EnterWorktree` tool / `/create-and-enter-worktree`, never `cd` (the harness reverts cwd every Bash call).

It is **opt-in per repo** and off by default everywhere. See `worktree-discipline.sh` (this skill dir) for the exact decision table.

**The Bash layer is best-effort.** Write/Edit/NotebookEdit into the main checkout are blocked robustly; for **Bash** the hook additionally scans for `>` / `>>` / `tee` / `sed -i` writes that resolve into the tree. That scan is heuristic and can false-positive on a command that merely *contains* a literal `>` — a regex, `grep -E`, a heredoc, an `awk`/`perl` one-liner (`=>` and `->` are already special-cased, but other `>` uses are not). If a benign Bash command is wrongly denied, rephrase it to avoid the literal `>`, or run it from a worktree. The Write/Edit block is the real guard; the Bash scan is a backstop, not a complete one.

Known `sed -i` gap: `sed -i 's/x/y/' f1 f2` only checks `f2` — `f1` is unguarded (the Write/Edit block only applies to Write/Edit/NotebookEdit tool calls, not to Bash-invoked `sed -i`). Single-file `sed -i` is caught.

## Install

**1. Install the hook script.** Copy the bundled hook to the global hooks dir and make it executable:

In Claude Code the bundled hook lives at `${CLAUDE_PLUGIN_ROOT}/skills/setup-worktree-discipline/worktree-discipline.sh`; if you installed via `install.sh`, use that copy's path instead.

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

**Separate config marker family** — worktree *creation* settings (where `wt-new` places the tree, which symlinks it seeds, etc.) live in a **distinct** three-tier family: `.claude/worktree-config.json` (committed) / `.claude/worktree-config.local.json` (gitignored override) / `~/.claude/worktree-config.json` (global). These are read by `wt-new`/`wt-rm` and are unrelated to enforcement. See `docs/superpowers/specs/2026-06-25-worktree-customisation-design.md` for the full field reference.

## Validate

The quickest check is **`worktree-enforce doctor`** — it audits the global wiring
(registered / installed / executable / fresh / old-hook-gone / CLAUDE.md rule) and
runs a live-deny smoke test that proves the hook actually fires, in one command.
The manual checks below are the same assertions broken out:

```bash
jq '.hooks.PreToolUse' ~/.claude/settings.json   # hook is registered

# From the MAIN checkout of an opted-in repo, a write should be denied:
cd /path/to/opted-in/repo        # main checkout, NOT a worktree
echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/probe.txt"}}' \
  | bash ~/.claude/hooks/worktree-discipline.sh
# expect: a JSON object with "permissionDecision": "deny"

# The installed copy is executable (a non-exec hook silently never fires):
test -x ~/.claude/hooks/worktree-discipline.sh && echo "exec: OK" || echo "NOT EXECUTABLE — hook will not fire"
# The global rule actually landed (Step 4):
grep -q '^## Worktree discipline' ~/.claude/CLAUDE.md && echo "rule: OK" || echo "CLAUDE.md rule MISSING"
# The superseded git-only hook is gone (Step 2):
jq -e '[.. | .command? // empty] | any(test("git-branch-discipline.sh"))' ~/.claude/settings.json >/dev/null \
  && echo "OLD HOOK STILL REGISTERED" || echo "old hook gone: OK"
```

For the exec-bit, drift (**STALE**), and registration checks in one command, run the `worktree-enforce status` skill — it already reports all three (installed / STALE / MISSING).

Empty output from an opted-in main checkout means the script isn't reachable (check the path/exec bit). Empty output from a worktree, a non-opted-in repo, or a non-repo dir is **expected** — that's the silent-allow path.

## Update the installed hook

Step 1 **copies** `worktree-discipline.sh` into `~/.claude/hooks/` rather than referencing it in place — that's deliberate (the rule then survives independently of the plugin). The cost: a plugin update does **not** refresh the copy. After upgrading the plugin, re-copy:

In Claude Code the bundled hook lives at `${CLAUDE_PLUGIN_ROOT}/skills/setup-worktree-discipline/worktree-discipline.sh`; if you installed via `install.sh`, use that copy's path instead.

```bash
cp "${CLAUDE_PLUGIN_ROOT}/skills/setup-worktree-discipline/worktree-discipline.sh" ~/.claude/hooks/worktree-discipline.sh
chmod +x ~/.claude/hooks/worktree-discipline.sh
```

No reload needed — the hook command re-reads the file on every tool call. `worktree-enforce status` detects this drift: it prints **STALE** (with the exact `cp` to run) when the installed copy differs from the plugin's bundled hook, **MISSING** if the registered file is gone, else plain **installed**.

> **This version's hook also exempts `worktree-config*.json`** (the config marker family used by `wt-new`/`wt-rm`). If you upgraded the plugin, re-run the `cp` above to pick up this change.

**Two independent staleness sources after you push a hook fix** — easy to conflate:

1. **The plugin cache** (the marketplace's copy of the plugin) only advances on a Claude Code **restart** with `autoUpdate` — `/reload-plugins` does **not** pull a new commit. And it only auto-updates at all for a **GitHub-source** marketplace with `autoUpdate: true` and no stray `path` on the source entry; a **directory-source** marketplace (`/plugin marketplace add /path/to/checkout`) is git-synced live, so local edits flow through immediately.
2. **The installed hook copy** in `~/.claude/hooks/` never advances automatically (Step 1 *copied* it) — re-run the `cp` above. This is the one `worktree-enforce status` flags as **STALE**.

## Removing it

This installs *outside* the plugin (a copied hook + a `settings.json` entry + a CLAUDE.md rule), so `/plugin uninstall` does **not** undo it — the hook keeps firing. To remove cleanly, run `/teardown-worktree-discipline` **before** uninstalling the plugin.

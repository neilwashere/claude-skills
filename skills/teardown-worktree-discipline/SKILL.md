---
name: teardown-worktree-discipline
description: Remove the worktree-discipline enforcement installed by setup-worktree-discipline — deregister the PreToolUse hook from ~/.claude/settings.json, delete the copied hook script, and strip the global CLAUDE.md rule. The clean exit; run it before /plugin uninstall.
disable-model-invocation: true
license: MIT
compatibility: "Claude Code only: reverses setup-worktree-discipline (PreToolUse hook + ~/.claude integration). No-op on other harnesses."
metadata:
  version: "1.0.0"
---

# Teardown Worktree Discipline

> **Claude Code only.** This removes a `PreToolUse` hook and `~/.claude` integration — mechanisms no other harness has. There is no portable equivalent; see `docs/SUPPORT-MATRIX.md`.

The exact reverse of `setup-worktree-discipline`, run deliberately by the human. Use it when you want the enforcement gone — whether you're uninstalling the plugin or just turning the discipline off globally.

**Why this skill exists:** `setup-worktree-discipline` deliberately *copies* its hook out of the plugin into `~/.claude/hooks/` and registers it in `~/.claude/settings.json` so it survives as a global rule. That means `/plugin uninstall git-worktree-skills` does **not** remove it — the hook keeps firing, denying writes in opted-in repos and pointing at `/create-and-enter-worktree`, a command the uninstall just deleted. This skill closes that gap.

**Run it BEFORE `/plugin uninstall`.** Once the plugin is gone so is this skill (and the `worktree-enforce` helper). The steps are also documented here on GitHub for anyone who already uninstalled.

This removes worktree-discipline **entirely** — it does not resurrect the older `git-branch-discipline.sh` that setup superseded. If you want that back, reinstall it separately.

## Remove it

**1. Opt your repos out first (optional but tidy).** While the `worktree-enforce` helper is still installed, run `worktree-enforce out` in each repo you opted in (it handles committed vs. local markers correctly). Skipping this is safe — the marker files become inert the moment the hook is gone — but it leaves `.claude/worktree-discipline*.json` behind in those repos. See **Per-repo markers** below.

**2. Run the teardown script.** This deregisters the hook from `~/.claude/settings.json`, deletes `~/.claude/hooks/worktree-discipline.sh`, and strips the `## Worktree discipline` section from `~/.claude/CLAUDE.md`. It is idempotent — safe to run even if nothing is installed:

```bash
# Claude Code (plugin): bash "${CLAUDE_PLUGIN_ROOT}/skills/teardown-worktree-discipline/scripts/teardown-worktree-discipline.sh"
# Otherwise:            bash <this-skill-dir>/scripts/teardown-worktree-discipline.sh
```

**3. Reload.** Open `/hooks` once (or start a fresh session) so the watcher drops the deregistered block. Until you do, the already-loaded hook may still fire this session.

## Per-repo markers

This skill only touches your **global** config. The per-repo opt-in markers are inert once the hook is gone (nothing reads them), but to remove them too:

- **Local/uncommitted** markers: `worktree-enforce out` (while installed) or just delete `.claude/worktree-discipline.json` / `.claude/worktree-discipline.local.json`.
- **Committed** markers (shared via git): `worktree-enforce out` writes a local disable override; to drop the policy for everyone, delete `.claude/worktree-discipline.json` and **commit** that removal.

Existing **worktrees** are untouched — dispose of them with `exit-and-dispose-worktree` (or `git worktree remove`) as usual.

## Validate

The teardown script prints what it did (or that nothing needed doing). For a manual audit:

```bash
# hook no longer registered:
jq '[.. | .command? // empty] | map(select(test("worktree-discipline.sh")))' ~/.claude/settings.json   # -> []
# script gone:
ls ~/.claude/hooks/worktree-discipline.sh 2>/dev/null && echo "STILL THERE" || echo "script removed"
# the global rule section was actually stripped:
grep -q '^## Worktree discipline' ~/.claude/CLAUDE.md \
  && echo "RULE STILL PRESENT — edit ~/.claude/CLAUDE.md by hand" || echo "rule removed: OK"
```

Then `/plugin uninstall git-worktree-skills` (or `/plugin marketplace remove neilwashere`) to drop the plugin itself.

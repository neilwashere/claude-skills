---
name: teardown-worktree-discipline
description: Remove the worktree-discipline enforcement installed by setup-worktree-discipline — deregister the PreToolUse hook from ~/.claude/settings.json, delete the copied hook script, and strip the global CLAUDE.md rule. The clean exit; run it before /plugin uninstall.
disable-model-invocation: true
---

# Teardown Worktree Discipline

The exact reverse of `setup-worktree-discipline`, run deliberately by the human. Use it when you want the enforcement gone — whether you're uninstalling the plugin or just turning the discipline off globally.

**Why this skill exists:** `setup-worktree-discipline` deliberately *copies* its hook out of the plugin into `~/.claude/hooks/` and registers it in `~/.claude/settings.json` so it survives as a global rule. That means `/plugin uninstall tss-git-skills` does **not** remove it — the hook keeps firing, denying writes in opted-in repos and pointing at `/create-and-enter-worktree`, a command the uninstall just deleted. This skill closes that gap.

**Run it BEFORE `/plugin uninstall`.** Once the plugin is gone so is this skill (and the `worktree-enforce` helper). The steps are also documented here on GitHub for anyone who already uninstalled.

This removes worktree-discipline **entirely** — it does not resurrect the older `git-branch-discipline.sh` that setup superseded. If you want that back, reinstall it separately.

## Remove it

**1. Opt your repos out first (optional but tidy).** While the `worktree-enforce` helper is still installed, run `worktree-enforce out` in each repo you opted in (it handles committed vs. local markers correctly). Skipping this is safe — the marker files become inert the moment the hook is gone — but it leaves `.claude/worktree-discipline*.json` behind in those repos. See **Per-repo markers** below.

**2. Deregister the hook from `~/.claude/settings.json`.** Back up first, then filter out every PreToolUse hook whose command references the script (this preserves any other hooks you've co-located, and drops a matcher group only once it's empty):

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq '
  if (.hooks.PreToolUse | type) == "array" then
      .hooks.PreToolUse |= (
          map(.hooks |= map(select((.command // "") | test("worktree-discipline.sh") | not)))
        | map(select((.hooks | length) > 0))
      )
    | (if (.hooks.PreToolUse | length) == 0 then .hooks |= del(.PreToolUse) else . end)
  else . end
' ~/.claude/settings.json.bak > ~/.claude/settings.json
```

Confirm it parsed and the entry is gone before deleting the backup:

```bash
jq -e '[.. | .command? // empty] | any(test("worktree-discipline.sh"))' ~/.claude/settings.json \
  && echo "STILL PRESENT — restore from ~/.claude/settings.json.bak and remove by hand" \
  || echo "removed from settings.json"
rm -f ~/.claude/settings.json.bak   # only after you've confirmed
```

**3. Delete the copied hook script:**

```bash
rm -f ~/.claude/hooks/worktree-discipline.sh
```

**4. Remove the global rule from `~/.claude/CLAUDE.md`.** Open it and delete the entire `## Worktree discipline` section — the heading and its body, up to the next `## ` heading (or end of file). Use the editor for this; it's prose and safest done by reading the file and editing. (Scriptable alternative, if the heading text is exactly `## Worktree discipline`:)

```bash
cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak
awk '
  /^## / { skip = ($0 ~ /^## Worktree discipline[[:space:]]*$/) }
  !skip
' ~/.claude/CLAUDE.md.bak > ~/.claude/CLAUDE.md
# review the diff, then: rm -f ~/.claude/CLAUDE.md.bak
```

**5. Reload.** Open `/hooks` once (or start a fresh session) so the watcher drops the deregistered block. Until you do, the already-loaded hook may still fire this session.

## Per-repo markers

This skill only touches your **global** config. The per-repo opt-in markers are inert once the hook is gone (nothing reads them), but to remove them too:

- **Local/uncommitted** markers: `worktree-enforce out` (while installed) or just delete `.claude/worktree-discipline.json` / `.claude/worktree-discipline.local.json`.
- **Committed** markers (shared via git): `worktree-enforce out` writes a local disable override; to drop the policy for everyone, delete `.claude/worktree-discipline.json` and **commit** that removal.

Existing **worktrees** are untouched — dispose of them with `exit-and-dispose-worktree` (or `git worktree remove`) as usual.

## Validate

```bash
# hook no longer registered:
jq '[.. | .command? // empty] | map(select(test("worktree-discipline.sh")))' ~/.claude/settings.json   # -> []
# script gone:
ls ~/.claude/hooks/worktree-discipline.sh 2>/dev/null && echo "STILL THERE" || echo "script removed"
# from the MAIN checkout of a previously-opted-in repo, a write is no longer denied —
# editing a file there should now just work.
```

Then `/plugin uninstall tss-git-skills` (or `/plugin marketplace remove neilwashere`) to drop the plugin itself.

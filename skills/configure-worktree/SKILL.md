---
name: configure-worktree
description: Guided setup for per-repo or global worktree creation config (where worktrees live, what to mirror into them, what to run after creating one, branch naming). Writes the worktree-config marker; does NOT change enforcement. Run it to tailor how create-and-enter-worktree builds worktrees.
disable-model-invocation: true
license: MIT
compatibility: "Requires git and a POSIX shell (bash, jq). Writes the worktree-config marker; fully portable. On harnesses without an interactive question tool, ask the questions in chat."
metadata:
  version: "1.0.0"
---

# configure-worktree

Interactive setup for the **worktree-config** marker family
(`worktree-config.json` / `.local.json` / `~/.claude/worktree-config.json`) that
`wt-new.sh` / `wt-rm.sh` read. This is separate from **enforcement** — use
`worktree-enforce` for `enforce`/`allowPaths`; this skill never touches them.

## How it works

Ask the questions below with the `AskUserQuestion` tool, assemble a JSON
object from the answers (include **only** fields the user actively set — omit a
field to keep its built-in default), then write it to the chosen tier:

```bash
printf '%s' '<assembled-json>' | bash "${CLAUDE_PLUGIN_ROOT}/skills/configure-worktree/scripts/configure-worktree.sh" <global|committed|local>
```

The script merges your fields over any existing tier file (your values win per
key), stages the committed file (commit it to share), or gitignores the local
one.

## The questions

1. **Location** (`worktreeDir`) — "Where should new worktrees be created?"
   - *Sibling (default)* — `<parent>/<repo>.worktrees/<branch>`. **Omit `worktreeDir`.**
   - *Central* — `~/worktrees/{repo}/{branch}`. Set `worktreeDir` to `"~/worktrees/{repo}/{branch}"`.
   - *Custom* — ask for a template (tokens `{parent}`/`{repo}`/`{branch}`); set `worktreeDir`.
2. **Stack** (`postCreate`) — "What should run after creating a worktree?"
   - *Nothing (default)* — **omit `postCreate`.**
   - *Node* — set `postCreate` to `"npm install"`.
   - *Custom* — ask for the command(s); set `postCreate` to a string or array.
3. **Mirror** (`worktreeLink`) — "Which gitignored files should be linked into each worktree?"
   - *Claude only (default)* — **omit `worktreeLink`.**
   - *Claude + env* — `[".claude/settings.local.json", ".claude/.credentials.json", ".env"]`.
   - *Custom* — ask for repo-root-relative paths; set `worktreeLink`.
4. **Branch naming** (`branchNaming.embedIssueId`) — "Embed the issue/ticket number in branch names?" (always write the explicit choice here — merging never deletes, so omitting can't turn a prior `false` back on)
   - *Yes (default)* — set `branchNaming` to `{"embedIssueId": true}`.
   - *No* — set `branchNaming` to `{"embedIssueId": false}`.
5. **Scope** — "Where should this config live?"
   - *Global* — `~/.claude/worktree-config.json` (all your repos). Scope = `global`.
   - *Committed (team)* — `.claude/worktree-config.json`, shared via git. Scope = `committed`.
   - *Just me (local)* — `.claude/worktree-config.local.json`, gitignored. Scope = `local`.

Omit any of **Location / Stack / Mirror** the user left at its default. **Always include the Branch-naming choice** explicitly — it must be written to override a prior or lower-tier `false` (this is the only field that is never omitted). So the assembled object always has at least `branchNaming`; if the user wants no change at all, cancel rather than write.

## Viewing current config

To see the resolved config (all tiers composed), run `status`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/configure-worktree/scripts/configure-worktree.sh" status
```

It prints each field's effective value and which tier it came from (local / committed / global / default).

## Notes

- Run it from inside the target repo (committed/local/status resolve to the main checkout root). Global works anywhere.
- This skill writes config only. For enforcement on/off, use `worktree-enforce in|out`.

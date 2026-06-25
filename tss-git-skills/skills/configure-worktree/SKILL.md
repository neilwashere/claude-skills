---
name: configure-worktree
description: Guided setup for per-repo or global worktree creation config (where worktrees live, what to mirror into them, what to run after creating one, branch naming). Writes the worktree-config marker; does NOT change enforcement. Run it to tailor how create-and-enter-worktree builds worktrees.
disable-model-invocation: true
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
4. **Branch naming** (`branchNaming.embedIssueId`) — "Embed the issue/ticket number in branch names?"
   - *Yes (default)* — **omit `branchNaming`** (the default is `embedIssueId: true`).
   - *No* — set `branchNaming` to `{"embedIssueId": false}`.
5. **Scope** — "Where should this config live?"
   - *Global* — `~/.claude/worktree-config.json` (all your repos). Scope = `global`.
   - *Committed (team)* — `.claude/worktree-config.json`, shared via git. Scope = `committed`.
   - *Just me (local)* — `.claude/worktree-config.local.json`, gitignored. Scope = `local`.

If the user kept every field at its default, say so and skip writing (nothing to set).

## Notes

- Run it from inside the target repo (committed/local write to the main checkout root). Global works anywhere.
- This skill writes config only. For enforcement on/off, use `worktree-enforce in|out`.

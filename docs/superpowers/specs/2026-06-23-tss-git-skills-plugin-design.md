# Design — `tss-git-skills`, the first domain plugin

**Date:** 2026-06-23
**Status:** Approved (brainstorming complete)

## Problem

The repo currently ships a single plugin, `threadsafe`, whose skills are
organized into **lifecycle buckets** (`engineering/`, `productivity/`, `misc/`,
…). We want **domain-scoped, curated skill sets** — a user installs the git
skills as a unit — without the namespace proliferation of one-skill-per-plugin
(`mycoolskill:mycoolskill`).

### Key mechanics that shape the design

- A skill's invocation namespace is **always the plugin name**, never the skill
  name. `threadsafe:tdd` (multi-skill plugin) vs `linear-cli:linear-cli`
  (single-skill plugin where the names coincide). The `name:name` doubling is
  just the degenerate single-skill case, not a requirement.
- **Installing a plugin installs all of its skills.** You cannot selectively
  install a subset. So the plugin *is* the unit of curation and installation —
  which makes "one plugin per domain" the natural mapping.
- Claude Code **always auto-scans** `<plugin-root>/skills/` (depth-1),
  `commands/`, and `hooks/hooks.json` regardless of the manifest. Manifest
  entries load *alongside* the scan (listing an auto-scanned path double-loads —
  see commit `909c689`). Two consequences:
  - A second plugin must live in its **own subtree** so `threadsafe`'s
    root-level scan never reaches it (no collision).
  - A plugin with a **flat** `skills/` needs **no `skills` array** in its
    manifest — depth-1 auto-discovery finds them all.

## Decision

Keep the repo as a **marketplace** hosting multiple plugins. `threadsafe`
remains the general-purpose catch-all at the repo root (`source: "."`,
unchanged). Every **other** domain becomes its own plugin, prefixed `tss-`
(threadsafe systems), living in a self-contained subtree with a flat `skills/`.

The first such plugin is **`tss-git-skills`**, invoked as
`tss-git-skills:<skill>`. It collects the existing worktree / branch-discipline
skills as a curated set.

### Naming & namespace convention (template for future domains)

| Plugin          | Role                      | Namespace                 |
|-----------------|---------------------------|---------------------------|
| `threadsafe`    | general catch-all (root)  | `threadsafe:<skill>`      |
| `tss-git-skills`| git / worktree domain     | `tss-git-skills:<skill>`  |
| `tss-<domain>`  | future domains            | `tss-<domain>:<skill>`    |

## Layout

```
claude-skills/                         # repo == marketplace "threadsafe"
  .claude-plugin/
    marketplace.json                   # lists threadsafe + tss-git-skills
    plugin.json                        # threadsafe (worktree skills removed)
  skills/  hooks/  commands/           # threadsafe's own (root depth-1 scan)
  docs/
  tss-git-skills/                      # NEW plugin, source "./tss-git-skills"
    .claude-plugin/plugin.json         # name: "tss-git-skills"
    skills/                            # flat — auto-discovered
      create-and-enter-worktree/
      exit-and-dispose-worktree/
      setup-worktree-discipline/
    README.md
```

- Install: `/plugin install tss-git-skills@threadsafe` (same marketplace,
  separate curated install).
- Invocation: `tss-git-skills:setup-worktree-discipline`, etc.

## Scope of the change

### Move (preserve bundled `scripts/`)

The three skills move wholesale out of `threadsafe` — **moved, not duplicated**:

- `skills/engineering/create-and-enter-worktree/`  (with `scripts/wt-new.sh`)
- `skills/engineering/exit-and-dispose-worktree/`  (with `scripts/wt-rm.sh`)
- `skills/engineering/setup-worktree-discipline/`  (with `worktree-discipline.sh`)

→ into `tss-git-skills/skills/`.

Verified safe to move: none of the three reference `${CLAUDE_PLUGIN_ROOT}` or
hard-coded plugin paths; their bundled scripts travel with the skill dir.

### "Branch discipline" stays as-is

Branch discipline is **not** carved into a new skill. It remains covered by
`setup-worktree-discipline` (the PreToolUse enforcement hook it installs, plus
the global `~/.claude/CLAUDE.md` rule it lays down). No new skill is created.

### New files

- `tss-git-skills/.claude-plugin/plugin.json` — `name: "tss-git-skills"`,
  description, author. **No** `skills` / `hooks` / `commands` keys:
  - flat `skills/` is auto-discovered;
  - `setup-worktree-discipline` installs its hook into `~/.claude/hooks` (a
    one-time installer), so there is no plugin-level hook to wire.
- `tss-git-skills/README.md` — lists the three skills, grouped **User-invoked**
  / **Model-invoked**, each name linked to its `SKILL.md` (mirrors the bucket
  README convention).

### Edited files

- `.claude-plugin/marketplace.json` — add
  `{ "name": "tss-git-skills", "description": "...", "source": "./tss-git-skills", "category": "development" }`.
- `.claude-plugin/plugin.json` (threadsafe) — remove the three
  `./skills/engineering/...worktree...` entries.
- `README.md` (top-level) — remove the three from threadsafe's listing; add a
  new plugin section for `tss-git-skills` with its own install line and skill
  links.
- `skills/engineering/README.md` — remove the three entries.
- `CLAUDE.md` (project) — replace the opening "This repo is a **single Claude
  Code plugin** named `threadsafe`" framing with: *this repo is a **marketplace**
  hosting `threadsafe` (the general catch-all at the root) plus one curated
  domain plugin per domain, each named `tss-<domain>`, living in a
  self-contained subtree (`./tss-<domain>/`) with a flat `skills/` and its own
  README.* Document the `tss-` namespace convention and the subtree-isolation
  rule (so the root scan never collides with a domain plugin).

## Verification

- `marketplace.json` and both `plugin.json` files are valid JSON.
- After move, `git status` shows the three skill dirs relocated (renames), not
  deleted+added with lost history where avoidable (`git mv`).
- No remaining repo references to the three skills under the old
  `skills/engineering/` path (grep `README.md`s + manifests).
- Re-installing the marketplace surfaces `tss-git-skills:*` skills and the
  worktree skills no longer appear under `threadsafe:*`.

## Out of scope

- Splitting any other domain out of `threadsafe` (PR skills, test skills, …).
  This change only establishes the pattern and migrates git/worktree.
- Editing the user's global `~/.claude/CLAUDE.md` (its `/create-and-enter-worktree`
  references are outside this repo; note as a follow-up, do not change here).

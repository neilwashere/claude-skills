# Worktree customisation & guided setup — design

- **Date:** 2026-06-25
- **Issue:** [#9](https://github.com/neilwashere/claude-skills/issues/9)
- **Status:** approved design (revised after codex review); implementation pending

## Context

The worktree skills hard-code several decisions that developers reasonably want
to vary — most visibly the worktree location (`wt-new.sh` always creates the
sibling layout `<repo-parent>/<repo>.worktrees/<branch>`), and the gitignored
file list mirrored into a worktree (duplicated independently in `wt-new.sh` and
`wt-rm.sh` — bug **B2**, drift orphans files). The `create-and-enter` SKILL also
hard-codes a JS assumption ("run `npm install`").

This feature makes those decisions configurable through a typed JSON config file,
adds a guided setup skill, and codifies the branch-naming convention — **without
touching the enforcement mechanism**.

## Goals

- Configurable worktree location, mirrored-file list, post-create command, and
  branch-naming preference.
- A single, unit-testable source of truth for that config (resolves B2 properly).
- A guided `configure-worktree` setup using `AskUserQuestion`.
- The repo's first automated tests + CI.

## Non-goals / boundaries

- **Enforcement is untouched.** `enforce`/`allowPaths` and the
  `worktree-discipline.sh` hook do not change. Config lives in **separate files**
  the hook never reads (see below), so there is no path by which configuring a
  worktree can alter deny behaviour.
- No shell-init / env-var configuration. All config lives in Claude-managed JSON
  files under `.claude/` and `~/.claude/`.
- No configurable hook matcher, no auto-commit of markers, no defeating the
  dirty/unpushed gates.

## Config model

Worktree config lives in its **own** marker family, distinct from the enforcement
marker — this is the key correction from the codex review: overloading the
enforcement marker would let a config-only local file silently flip `enforce`
off, because the hook selects one marker file wholesale.

**Two independent marker families:**

| family | files | owner | holds |
|---|---|---|---|
| **Enforcement** *(unchanged)* | `<repo>/.claude/worktree-discipline.json` + `.local.json` | the hook | `enforce`, `allowPaths` |
| **Config** *(new)* | `<repo>/.claude/worktree-config.local.json` → `<repo>/.claude/worktree-config.json` → `~/.claude/worktree-config.json` → built-in defaults | the resolver lib | `worktreeDir`, `worktreeLink`, `postCreate`, `branchNaming` |

**Resolution (config family) — field-level:** for each field, **probe local, then
committed, then global, then built-in default; the first tier that *defines* the
field wins.** A tier whose file is **absent or unparseable is skipped** — it
contributes nothing and does **not** reset lower tiers (a malformed local file
never discards committed/global values). Built-in defaults apply only when no
tier defines the field.

So a global `worktreeDir`, a committed `worktreeLink`, and a local `postCreate`
all compose. The config family has no global-vs-repo restrictions because it
never carries `enforce`/`allowPaths` (those stay repo-scoped in the enforcement
family).

### Config schema (`worktree-config.json`)

| field | type | default | consumer |
|---|---|---|---|
| `worktreeDir` | string template | `"{parent}/{repo}.worktrees/{branch}"` | wt-new, wt-rm |
| `worktreeLink` | string[] (repo-root paths) | `[".claude/settings.local.json", ".claude/.credentials.json"]` | wt-new (link), wt-rm (unlink) |
| `postCreate` | string \| string[] | *(none)* | wt-new (→stderr), create SKILL |
| `branchNaming` | `{ "embedIssueId": bool }` | `{ "embedIssueId": true }` | create SKILL / configure (prose only) |

**`worktreeDir` template & validation:**
- Tokens: `{parent}` (dir containing the main repo), `{repo}` (repo basename),
  `{branch}` (branch slug). An **unknown `{token}` is an error** (fail loud, don't
  emit a literal brace path).
- `{branch}` slug: `/`→`-` (preserves today's behaviour).
- A leading `~`/`$HOME` expands; a relative template resolves against `{parent}`.
- The expanded path is normalised and **rejected if empty, or if it equals or
  resolves inside the main checkout** (creating a worktree inside the main repo
  would be catastrophic). The default reproduces today's sibling layout exactly.

**`worktreeLink` rules:** entries are **repo-root-relative** (so `.env`,
`mcp.json`, etc. can be mirrored, not just `.claude/` files). Each entry is
normalised and **rejected if absolute, empty, or containing `..`**. On create:
`mkdir -p` the destination's parent, then symlink **only when the source exists
and the destination is absent**. On remove: delete **only a symlink whose target
points back into the main repo** (never a real file/dir). Default preserves
today's two `.claude/` files.

**`postCreate` output contract:** `wt-new.sh` emits **one `postCreate: <cmd>` line
to stderr per command** (a string → one line; an array → one line each), never
runs them (protects the stdout-is-the-path contract). Tests assert this shape.

**`branchNaming`** is **prose-only guidance**: `embedIssueId` changes how the
`create-and-enter` SKILL prompts/derives a branch name. No script validates or
enforces it.

## Architecture

A single shared resolver, sourced by both scripts and by the tests.

**`tss-git-skills/lib/worktree-config.sh`** — pure, sourceable functions:
`resolve_worktree_dir`, `resolve_worktree_link`, `resolve_post_create`,
`resolve_branch_naming`. Each implements the local→committed→global→built-in
field resolution via `jq`, skipping absent/unparseable tiers.

- Lives in a new top-level `lib/` (sibling to `skills/`), which Claude Code's
  depth-1 skill scan ignores.
- **Testable by design:** functions take the **repo root as an argument** and
  honour an **overridable `HOME`**, so tests sandbox all three tiers in temp dirs
  without touching the real `~/.claude`.
- Scripts locate the lib relative to **`${BASH_SOURCE[0]}`** (not `$0`, which is
  unreliable when sourced or wrapped). Sourcing a bundled plugin file is safe with
  respect to the chpwd hazard that motivated the scripts' self-containment — that
  was about `source ~/.zshrc` triggering interactive shell hooks; this is
  `source <plugin-lib>` inside a non-interactive `bash` script.
- **The lib is a hard dependency** (it ships with the plugin). If it cannot be
  sourced, the scripts **fail loud** with a clear "broken install" error — they do
  **not** silently fall back to built-in defaults, because that could make
  `wt-new` (configured) and `wt-rm` (defaulted) disagree on location. (Note
  `wt-rm` finds the tree via `git worktree list` by branch first, which is
  layout-independent; the `worktreeDir`-derived path is only a last-resort
  fallback — but fail-loud removes the disagreement risk entirely.) "Fall back to
  built-in defaults" applies only to **missing/empty config markers**, never to a
  missing lib.

### Components touched

| | File | Change |
|---|---|---|
| NEW | `lib/worktree-config.sh` | the resolver |
| NEW | `tests/run.sh` + `.github/workflows/test.yml` | bash harness + first CI |
| MOD | `skills/create-and-enter-worktree/scripts/wt-new.sh` | source lib; resolved `worktreeDir`/`worktreeLink`; emit `postCreate` to stderr |
| MOD | `skills/exit-and-dispose-worktree/scripts/wt-rm.sh` | source lib; resolved `worktreeDir` (fallback path) + `worktreeLink` (unlink) |
| MOD | `skills/create-and-enter-worktree/SKILL.md` | `postCreate` + branch-naming guidance |
| NEW | `skills/configure-worktree/SKILL.md` (+ script) | guided `AskUserQuestion` setup that writes a config-marker tier |
| MOD | setup SKILL + READMEs | document the config marker family + global tier; list the new skill |

## Threads (each its own PR)

### C1 — config resolver foundation (PR1)
- Create `lib/worktree-config.sh` with `resolve_worktree_dir` + `resolve_worktree_link`
  (field-level tier resolution; absent/unparseable tier skipped; `${BASH_SOURCE[0]}`
  anchor; fail-loud if lib missing).
- `wt-new.sh`: source lib; replace hard-coded `dir=…worktrees/{branch}` with
  resolved + validated `worktreeDir`; replace the hard-coded
  `for f in settings.local.json .credentials.json` link loop with resolved
  `worktreeLink` (repo-root-relative, with the link rules above).
- `wt-rm.sh`: source lib; resolved `worktreeDir` for the fallback path; resolved
  `worktreeLink` for the unlink loop (symlink-pointing-back-to-main check).
- Add `tests/` + CI. **Absorbs B2.**

### C2 — postCreate + de-bias npm (PR2)
- Add `resolve_post_create` to the lib; `wt-new.sh` emits one `postCreate: <cmd>`
  line to stderr per command, never runs them.
- `create-and-enter/SKILL.md`: replace the hard-coded "run `npm install`" in
  *After entering* with guidance to run whatever `wt-new.sh` printed in its
  `postCreate:` note(s), if any (default empty → no note → no stack assumption).

### C3 — `configure-worktree` skill (PR3)
- New user-invoked skill (`disable-model-invocation: true`, like the other config
  skills) that runs an `AskUserQuestion` flow and writes the chosen **config**
  fields to the chosen tier of the **config** marker family:
  - Q1 location → `worktreeDir`; Q2 stack → `postCreate`; Q3 mirror →
    `worktreeLink`; Q4 **scope: global (`~/.claude/worktree-config.json`) /
    committed (team) / local (just me)** — the three-way tier picker.
- It writes **only config files**. Enforcement (`enforce`/`allowPaths`) stays with
  the existing `worktree-enforce` skill; `configure-worktree` points the user
  there rather than touching the enforcement marker.
- Reuses `worktree-enforce`'s marker-writing/staging helpers where possible
  (committed file staged, local file gitignored).

### C4 — branch-naming (PR4)
- `create-and-enter/SKILL.md`: document the `<type>/<N>-<slug>` convention and slug
  resolution precedence (explicit → issue-id → infer → ask); `configure-worktree`
  captures `branchNaming.embedIssueId`. Prose-only; no script enforcement.
  **Closes #9.**

Branch-naming reference: conventional-commit types (`feat`/`fix` mandated;
`docs`/`chore`/`refactor`/`perf`/`test`/`build`/`ci`/`style`/`revert`
conventional — use `fix`, never `bug`), `{N}` = GitHub issue number embedded,
slug from issue title.

## Testing & CI

Plain bash (no `bats` dependency).

```
tests/run.sh                 # sources the lib, runs every test_* fn, prints PASS/FAIL, non-zero exit on failure
.github/workflows/test.yml   # on: pull_request → ubuntu-latest → ensure jq → bash tests/run.sh
```

Cases (unit tests, sourcing the lib directly):
- `worktreeDir` precedence: no markers → default; global-only → global; committed
  beats global; local beats committed.
- field-level merge: a field set only in global resolves when committed defines
  *other* fields.
- **malformed tier skipped:** an unparseable local file does not discard committed/
  global values for a field.
- `worktreeDir` token expansion: `{parent}`/`{repo}`/`{branch}`, `~` expansion,
  branch slug `/`→`-`; unknown token errors; expansion inside the main checkout is
  rejected.
- `worktreeLink`: default; override; repo-root-relative entry (e.g. `.env`);
  rejection of absolute/`..`/empty entries.
- `postCreate`: none / string (one line) / array (one line each).
- `branchNaming`: default `embedIssueId:true`; override.
- robustness: config marker absent → built-in defaults; **lib missing → fail loud**
  (distinct from missing markers).

(Shellcheck is intentionally deferred to keep #9 focused.)

## Build sequence

Four PRs off fresh `main`, dependency order, each via the harness-safe squash
flow. `<type>/9-<slug>` branches; PRs 1-3 "Part of #9", PR4 "Closes #9".

1. `feat/9-config-resolver` — **spec doc** + lib + wt-new/wt-rm wiring + tests/CI (absorbs B2). TDD + codex.
2. `feat/9-postcreate` — postCreate + npm de-bias. TDD + codex.
3. `feat/9-configure-worktree` — the guided skill. codex.
4. `feat/9-branch-naming` — branch-naming prose + `embedIssueId`. Closes #9.

TDD on the logic PRs (1, 2): failing lib tests first, then implement to green.
codex (gpt-5.5) review on PRs 1-3 before merge. A 4-item checklist on issue #9
tracks the sub-PRs.

## Risks

- **Regressing enforcement** — eliminated by design: config lives in a separate
  marker family the hook never reads; the hook and `enforce`/`allowPaths` logic
  are unchanged. CI + a manual deny-probe still confirm.
- **Script self-containment** — lib resolved via `${BASH_SOURCE[0]}`; lib is a
  bundled hard dependency that fails loud if absent (no silent default), so no
  shell-init dependency and no create/remove disagreement.
- **`worktreeDir`/`worktreeLink` drift between create and remove** — both read the
  same lib; tests assert identical resolution; `wt-rm` also finds the tree via
  `git worktree list` (layout-independent) before any path construction.
- **Unsafe `worktreeDir` expansion** — validated: unknown tokens error; path
  rejected if empty or inside the main checkout.

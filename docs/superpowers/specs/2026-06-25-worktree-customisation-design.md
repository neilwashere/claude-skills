# Worktree customisation & guided setup — design

- **Date:** 2026-06-25
- **Issue:** [#9](https://github.com/neilwashere/claude-skills/issues/9)
- **Status:** approved design; implementation pending

## Context

The worktree skills hard-code several decisions that developers reasonably want
to vary — most visibly the worktree location (`wt-new.sh` always creates the
sibling layout `<repo-parent>/<repo>.worktrees/<branch>`), and the gitignored
file list mirrored into a worktree (duplicated independently in `wt-new.sh` and
`wt-rm.sh` — bug **B2**, drift orphans files). The `create-and-enter` SKILL also
hard-codes a JS assumption ("run `npm install`").

This feature makes those decisions configurable through a typed JSON marker, adds
a guided setup skill, and codifies the branch-naming convention — without
touching the enforcement mechanism.

## Goals

- Configurable worktree location, mirrored-file list, post-create command, and
  branch-naming preference.
- A single, unit-testable source of truth for that config (resolves B2 properly).
- A guided `configure-worktree` setup using `AskUserQuestion`.
- The repo's first automated tests + CI.

## Non-goals / boundaries

- **Enforcement is untouched.** `enforce` and `allowPaths` remain repo-scoped and
  owned by the `worktree-discipline.sh` hook. The new resolver reads only config
  fields; there is zero change to deny behaviour.
- No shell-init / env-var configuration. All config lives in Claude-managed JSON
  files under `.claude/` and `~/.claude/`.
- No configurable hook matcher, no auto-commit of markers, no defeating the
  dirty/unpushed gates. (Out of scope by design.)

## Config model

Three tiers of the **same** JSON file, resolved **field-by-field** — each field is
taken from the first tier that defines it:

```
<repo>/.claude/worktree-discipline.local.json   per-checkout override (gitignored)
  → <repo>/.claude/worktree-discipline.json      per-repo, committed (team policy)
  → ~/.claude/worktree-discipline.json           user-global defaults
  → built-in script defaults
```

Field-level (not whole-file) resolution means a global `worktreeDir`, a repo's
committed `allowPaths`, and a local `enforce:false` all compose.

### Marker schema

| field | type | tiers read | default | consumer |
|---|---|---|---|---|
| `enforce` | bool | committed, local — **not global** | `false` | hook *(unchanged)* |
| `allowPaths` | string[] (repo-root globs) | committed, local — **not global** | `[]` | hook *(unchanged)* |
| `worktreeDir` | string template | global, committed, local | `"{parent}/{repo}.worktrees/{branch}"` | wt-new, wt-rm |
| `worktreeLink` | string[] (repo-root paths) | global, committed, local | `[".claude/settings.local.json", ".claude/.credentials.json"]` | wt-new (link), wt-rm (unlink) |
| `postCreate` | string \| string[] | global, committed, local | *(none)* | wt-new (→stderr), create SKILL |
| `branchNaming` | `{ "embedIssueId": bool }` | global, committed, local | `{ "embedIssueId": true }` | create SKILL / configure |

- **`worktreeDir` tokens:** `{parent}` (dir containing the main repo), `{repo}`
  (repo basename), `{branch}` (branch slug, `/`→`-`). A leading `~`/`$HOME`
  expands; a relative template resolves against `{parent}`. The default
  reproduces today's sibling layout exactly.
- **`worktreeLink` entries are repo-root-relative**, so `.env`, `mcp.json`, etc.
  can be mirrored, not just `.claude/` files. Default preserves today's two files.
- The global marker is **optional**; absent → built-in defaults.

## Architecture

A single shared resolver, sourced by both scripts and by the tests.

**`tss-git-skills/lib/worktree-config.sh`** — pure, sourceable functions:
`resolve_worktree_dir`, `resolve_worktree_link`, `resolve_post_create`,
`resolve_branch_naming`. Each implements the global→committed→local→built-in read
via `jq`, falling back to the built-in default when a marker or `jq` is absent or
unparseable.

- Lives in a new top-level `lib/` (sibling to `skills/`), which Claude Code's
  depth-1 skill scan ignores.
- **Testable by design:** functions take the **repo root as an argument** and
  honour an **overridable `HOME`**, so tests sandbox all three tiers in temp dirs
  without touching the real `~/.claude`.
- Sourcing a bundled plugin file is safe with respect to the chpwd hazard that
  motivated the scripts' self-containment — that was about `source ~/.zshrc`
  triggering interactive shell hooks; this is `source <plugin-lib>` inside a
  non-interactive `bash` script. Scripts resolve the lib relative to `$0` and
  **fall back to built-in defaults if the lib is missing**.

### Components touched

| | File | Change |
|---|---|---|
| NEW | `lib/worktree-config.sh` | the resolver |
| NEW | `tests/run.sh` + `.github/workflows/test.yml` | bash harness + first CI |
| MOD | `skills/create-and-enter-worktree/scripts/wt-new.sh` | source lib; resolved `worktreeDir`/`worktreeLink`; emit `postCreate` to stderr |
| MOD | `skills/exit-and-dispose-worktree/scripts/wt-rm.sh` | source lib; resolved `worktreeDir` (fallback path) + `worktreeLink` (unlink) |
| MOD | `skills/create-and-enter-worktree/SKILL.md` | `postCreate` + branch-naming guidance |
| NEW | `skills/configure-worktree/SKILL.md` (+ script) | guided `AskUserQuestion` setup that writes a marker tier |
| MOD | setup SKILL + READMEs | document the global tier; list the new skill |

## Threads (each its own PR)

### C1 — config resolver foundation (PR1)
- Create `lib/worktree-config.sh` with `resolve_worktree_dir` + `resolve_worktree_link`.
- `wt-new.sh`: source lib; replace hard-coded `dir=…worktrees/{branch}` with
  resolved `worktreeDir` + token expansion; replace the hard-coded
  `for f in settings.local.json .credentials.json` link loop with resolved
  `worktreeLink` (repo-root-relative).
- `wt-rm.sh`: source lib; resolved `worktreeDir` for the fallback path; resolved
  `worktreeLink` for the unlink loop.
- Add `tests/` + CI. **Absorbs B2.**

### C2 — postCreate + de-bias npm (PR2)
- Add `resolve_post_create` to the lib; `wt-new.sh` emits the resolved command(s)
  to **stderr** as a labelled note (e.g. `postCreate: npm install`), never runs
  them — protects the stdout-is-the-path contract.
- `create-and-enter/SKILL.md`: replace the hard-coded "run `npm install`" in
  *After entering* with guidance to run whatever `wt-new.sh` printed in its
  `postCreate:` note, if any (default empty → no note → no stack assumption).

### C3 — `configure-worktree` skill (PR3)
- New user-invoked skill (`disable-model-invocation: true`, like the other config
  skills) that runs an `AskUserQuestion` flow and writes the chosen fields to the
  chosen tier:
  - Q1 location → `worktreeDir`; Q2 stack → `postCreate`; Q3 mirror →
    `worktreeLink`; Q4 editable-on-main → `allowPaths`; Q5 **scope: global
    (`~/.claude`) / committed (team) / local (just me)** — the three-way tier
    picker.
- Reuses `worktree-enforce`'s marker-writing/staging logic where possible.

### C4 — branch-naming (PR4)
- `create-and-enter/SKILL.md`: document the `<type>/<N>-<slug>` convention and
  slug resolution precedence (explicit → issue-id → infer → ask);
  `configure-worktree` captures `branchNaming.embedIssueId`. **Closes #9.**

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
- `worktreeDir` token expansion: `{parent}`/`{repo}`/`{branch}`, `~` expansion,
  branch slug `/`→`-`.
- `worktreeLink`: default; override; repo-root-relative entry (e.g. `.env`).
- `postCreate`: none / string / array.
- `branchNaming`: default `embedIssueId:true`; override.
- robustness: marker absent or unparseable → built-in defaults (same guard as
  `jq` missing).

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

- **Regressing enforcement** — mitigated: the resolver never reads/writes
  `enforce`; the hook is unchanged; CI + manual deny-probe confirm.
- **Script self-containment** — mitigated: lib resolved relative to `$0` with a
  built-in-default fallback if absent; no shell-init dependency.
- **`worktreeDir`/`worktreeLink` drift between create and remove** — mitigated:
  both read the same lib; tests assert identical resolution.

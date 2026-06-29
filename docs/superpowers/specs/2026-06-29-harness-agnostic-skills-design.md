# Harness-agnostic skills — design

- **Status:** approved design, pre-implementation
- **Date:** 2026-06-29
- **Branch:** `feat/harness-agnostic-skills`
- **Supersedes naming:** repo `claude-skills` → `git-worktree-skills`; plugin `tss-git-skills` → `git-worktree-skills`

## 1. Problem & goal

This repo ships git/worktree workflow skills as a **Claude Code marketplace plugin**
(`tss-git-skills`). Every `SKILL.md` body, every script, and the distribution layer
assume Claude Code: tool names (`EnterWorktree`, `AskUserQuestion`, `Bash`), the
`$CLAUDE_PLUGIN_ROOT` env var, the `.claude-plugin/` manifests, `PreToolUse` hooks,
and `~/.claude/` paths.

The goal is to make the repo **agent/harness-agnostic**: authored once, loadable across
Claude Code, Codex CLI, Copilot CLI, Gemini CLI / Antigravity, Pi, Cursor, and Windsurf.

### The reframe that scopes the work

As of 2026, **`SKILL.md` is already a de-facto cross-vendor format** (open spec at
[agentskills.io/specification](https://agentskills.io/specification); read by all the
harnesses above). So "make it agnostic" is **not** mainly a format problem — the skills
would already *load* almost everywhere. The coupling that actually breaks portability
sits in three deeper layers:

1. **Frontmatter** — one Claude-only key (`disable-model-invocation`).
2. **Body tool vocabulary** — bodies name Claude Code tools and `/slash` commands that
   no other harness has.
3. **Mechanism** — two capabilities have *no uniform cross-harness equivalent*:
   - **Session relocation** (`EnterWorktree`/`ExitWorktree` physically move the session
     into another directory — a Claude Code primitive absent in Codex/Gemini/Copilot/Pi).
   - **Hook enforcement** (`PreToolUse` denial of writes to the main checkout — a Claude
     Code hook contract; other harnesses differ or lack it).

Full behaviour parity everywhere is therefore *partly impossible* with these specific
skills. That is a property of the skills, not a defect to fix.

## 2. Decisions (locked)

| # | Decision | Choice |
|---|---|---|
| 1 | What "agnostic" means here | **Format-portable + honest support matrix.** Every skill *loads* everywhere; behaviour degrades gracefully where a primitive is missing; degradation is documented per-skill × per-harness. |
| 2 | First-class target | **Claude Code only.** Other harnesses should load the skills (capability-language bodies, neutral paths) but stay best-effort / untested. Do **not** build Codex/Gemini/Copilot adapters now. |
| 3 | Rename | Repo + plugin + namespace → **`git-worktree-skills`**. Neutral skills pickup dir `.agents/skills/`. Drop `tss-`/`claude-` prefixes and `$CLAUDE_PLUGIN_ROOT`. |
| 4 | Distribution | **Dual.** Keep the Claude marketplace/plugin (`/plugin install`, namespacing) *and* ship a neutral `install.sh` that links `skills/` into `~/.agents/skills/` and `~/.claude/skills/`. |
| 5 | Layout | **Collapse** the `tss-git-skills/` subtree so repo root *is* the plugin root and `skills/` lives at the top level (subject to verify-gate #1). |

### Explicit non-goals

- Reimplementing session relocation or write-enforcement on non-Claude harnesses.
- A git pre-commit/pre-push enforcement fallback (noted as a future option, not built).
- Per-harness tool-map *adapters* for Codex/Gemini/Copilot/Pi (a single capability→tool
  reference doc is authored; it is authoritative for Claude, pointers-only for the rest).
- Testing on non-Claude harnesses beyond a single smoke-load if one is available.

## 3. Spec conformance — current vs. target

Reference: [agentskills.io/specification](https://agentskills.io/specification). Frontmatter
fields: `name` (required, ≤64 chars, lowercase + hyphens, no consecutive/leading/trailing
hyphens, **must match the directory name**), `description` (required, 1–1024 chars),
optional `license`, `compatibility` (≤500 chars), `metadata` (string→string map; `version`
lives here — there is no top-level `version`), `allowed-tools` (space-separated, **marked
experimental**, honoured mainly by Claude Code). Body budget for progressive disclosure
level 2 is ~5,000 tokens / ~500 lines. Validation tool: `skills-ref validate` (Python),
which checks frontmatter/naming **only** — it does *not* inspect bodies for non-portable
tool references.

| Aspect | Standard | Current | Target |
|---|---|---|---|
| `SKILL.md` at skill-dir root | required | ✅ | unchanged |
| `name` rules | required | ✅ all 6 comply | unchanged |
| `description` ≤1024, trigger-rich | required | ✅ | unchanged |
| `disable-model-invocation` | not in standard (Claude-only) | on 4 skills | **kept** (see §5) |
| `compatibility` | optional | ❌ absent | **added** to all 6 |
| `license`, `metadata.version` | optional | ❌ absent | **added** |
| Distribution | neutral `.agents/skills/` | `.claude-plugin/` + marketplace | **both** (dual) |
| Body language | capability-based (best practice) | Claude tool names throughout | **rewritten** (see §6) |

## 4. Target layout

```
git-worktree-skills/
├── .claude-plugin/
│   ├── marketplace.json          # Claude marketplace; the single plugin's source is "."
│   └── plugin.json               # moved up from the old tss-git-skills/ subtree
├── skills/                       # canonical, flat, auto-discovered by Claude at depth-1
│   ├── configure-worktree/        { SKILL.md, scripts/configure-worktree.sh }
│   ├── create-and-enter-worktree/ { SKILL.md, scripts/wt-new.sh }
│   ├── exit-and-dispose-worktree/ { SKILL.md, scripts/wt-rm.sh }
│   ├── setup-worktree-discipline/ { SKILL.md, worktree-discipline.sh }
│   ├── teardown-worktree-discipline/ { SKILL.md, scripts/teardown-worktree-discipline.sh }
│   └── worktree-enforce/          { SKILL.md, scripts/worktree-enforce.sh }
├── lib/worktree-config.sh        # shared resolver; scripts self-locate it (no env var)
├── install.sh                    # neutral installer/uninstaller (symlink | --copy)
├── tests/run.sh                  # plain bash; extended for paths + install.sh
├── docs/
│   ├── SUPPORT-MATRIX.md          # per-skill × per-harness, honest about degradation
│   ├── harness-tools.md           # capability → tool-name map (Claude authoritative)
│   └── contributing/closing-the-verification-loop.md
├── AGENTS.md                     # cross-vendor contributor instructions
├── CLAUDE.md                     # thin: imports AGENTS.md so Claude reads it
├── README.md                     # reframed: portable skills, both install paths
└── LICENSE
```

The `tss-git-skills/` subtree is removed; the old subtree rationale in `CLAUDE.md` no
longer applies. Extra root files (`tests/`, `docs/`, `install.sh`, `lib/`) are inert to
the Claude plugin loader, which only scans `skills/`.

## 5. Component: frontmatter

- **Keep `disable-model-invocation`** on the four user-invoked skills (configure, setup,
  teardown, enforce). Removing it would make destructive skills model-invocable *on
  Claude*, the regression we must avoid. Other harnesses ignore unknown keys, so it is
  inert there. **Verify-gate #2:** confirm `skills-ref validate` tolerates the extra key;
  fallback is to relocate the flag under `metadata:` (loses Claude enforcement → rejected
  unless validation forces it).
- **Add `compatibility`** (≤500 chars) to each skill, stating: requires `git` and a POSIX
  shell; and naming what is Claude-only (auto session-relocation for create/exit; PreToolUse
  enforcement for setup/teardown/enforce).
- **Add `license`** (MIT, matching `LICENSE`) and **`metadata.version`** (start `1.0.0`).

## 6. Component: body de-coupling (the core work)

Rewrite every `SKILL.md` body to name **capabilities**, with a parenthetical Claude hint
(Claude is first-class, so the exact tool stays visible):

| Today (Claude-locked) | Rewritten (portable) |
|---|---|
| "Use the `EnterWorktree` tool" | "Relocate your session into the worktree dir *(Claude Code: `EnterWorktree`; elsewhere `cd` in or start a session there)*" |
| "Use `AskUserQuestion`" | "Ask the user these questions *(Claude Code: `AskUserQuestion`; else prompt in chat)*" |
| `bash $CLAUDE_PLUGIN_ROOT/skills/.../wt-new.sh` | "Run the bundled `scripts/wt-new.sh`" |
| "Run `/plugin uninstall`" | "Uninstall the skill from your harness *(Claude Code: `/plugin uninstall`)*" |
| `/create-and-enter-worktree`, `/worktree-enforce …` | "the create-and-enter-worktree skill", "run `worktree-enforce …`" |

`docs/harness-tools.md` carries the full capability→tool map (Claude authoritative;
Codex/Gemini/Copilot/Pi as best-effort pointers, drawn from the research table). Bodies
remain **self-sufficient** — they read correctly without the map loaded, so progressive
disclosure is unaffected and an individually-copied skill still makes sense.

The setup/teardown/enforce skills stay honestly Claude-centric in mechanism. Their bodies
get capability framing where it helps, but `~/.claude/settings.json`, `PreToolUse`, and
`~/.claude/CLAUDE.md` are inherently the Claude adapter and are labelled as such, with a
forward-pointer to the support matrix.

## 7. Component: self-containment, `lib/` resolution, env-var removal

`$CLAUDE_PLUGIN_ROOT` is **eliminated**. Scripts self-locate:

- Resolve the script's own real path (through symlinks), portably — `readlink -f` is **not**
  on stock macOS, so use a fallback chain (`readlink -f` → `realpath` → a `cd`/`pwd -P`
  loop). *(Verify-gate #3.)*
- Walk **up** from there to the repo root by looking for a sentinel (`lib/worktree-config.sh`
  and/or `.claude-plugin/`), rather than a fixed `../../..` (skill scripts sit at varying
  depths — `skills/<s>/scripts/x.sh` vs `skills/setup-worktree-discipline/worktree-discipline.sh`).
- Source `lib/worktree-config.sh` from the resolved root.

This works for both installs because `install.sh` **symlinks** skill dirs (default): the
real path resolves back into the repo, so the walk-up finds `lib/`. For `--copy` mode the
skill dir is detached from the repo; the installer must preserve `lib/` reachability (exact
mechanism — vendor `lib/` per skill, or copy the tree and link — decided in the plan).
On Claude, the plugin install also yields a real on-disk path, so the same resolution holds
and `$CLAUDE_PLUGIN_ROOT` is no longer needed.

## 8. Component: `install.sh` (neutral installer)

Behaviour:
- For each `skills/<skill>`, create a symlink in **both** `~/.agents/skills/` (Codex / Gemini
  / Antigravity / Pi) and `~/.claude/skills/` (Claude / Copilot / Cursor / Windsurf / Pi).
- Flags: `--agents-dir <path>`, `--claude-dir <path>`, `--copy` (no-symlink environments),
  `--force`, `--uninstall`, `--list`.
- **Guard-then-act** (per the verification-loop guide's failure-path rule): idempotent;
  never clobber a non-symlink file or a link that does *not* point into this repo;
  `--uninstall` removes **only** links it owns (target resolves into this repo); on any
  precondition failure, report and skip rather than half-complete.
- Print a summary of which harnesses will now discover the skills.

## 9. Component: support matrix

`docs/SUPPORT-MATRIX.md`, per-skill × per-harness, levels **✔ full / ◐ degraded / ✖ n/a**,
each ◐/✖ annotated with *what* degrades:

| Skill | Claude | Codex / Gemini / Copilot / Pi |
|---|---|---|
| configure-worktree | ✔ | ✔ (questions asked in chat instead of a tool) |
| create-and-enter-worktree | ✔ | ◐ creates the worktree; **no auto session-relocate** (cd manually) |
| exit-and-dispose-worktree | ✔ | ◐ removal script works; **session-leave is manual** |
| worktree-enforce | ✔ | ◐ marker/in/out/status portable; **enforcement only bites on Claude** |
| setup-worktree-discipline | ✔ | ✖ PreToolUse hook + `~/.claude` integration is Claude-only |
| teardown-worktree-discipline | ✔ | ✖ reverses the Claude-only setup |

## 10. Component: repo-level agnosticism (`AGENTS.md`)

Contributor instructions move from `CLAUDE.md` into `AGENTS.md` (the Linux-Foundation-
stewarded cross-vendor instruction file read by Codex/Copilot/Gemini/Cursor). `CLAUDE.md`
shrinks to an import of `AGENTS.md` so Claude Code still picks it up. This makes the repo
agnostic *for contributors using any harness*, not only for consumers of the skills.

## 11. Component: tests / CI

- `tests/run.sh` (already plain bash, no framework): update for the new paths, `lib/`
  self-resolution, and removal of `$CLAUDE_PLUGIN_ROOT`.
- **New tests** for `install.sh`: symlink creation in both targets; idempotent re-run;
  `--uninstall` removes only owned links and leaves foreign files untouched; `--copy`
  produces a working skill; refusal to clobber a non-symlink.
- CI (`.github/workflows/test.yml`) keeps bash tests + shellcheck (pinned v0.11.0) and
  **adds**: (a) a frontmatter validator step (`skills-ref validate`, or a small bundled
  validator if `skills-ref` is unavailable — *verify-gate #4*); (b) an optional grep-lint
  flagging bare Claude tool names in `SKILL.md` bodies that lack the capability framing —
  this fills the gap the research flagged (no linter checks bodies for portability).

## 12. Migration sequence & verify-gates

Ordered so the riskiest assumptions are tested before the rename is irreversible:

1. **Scaffold** the collapsed layout in this worktree (move subtree → root, move
   `plugin.json` up, rename plugin/namespace).
2. **Verify-gate #1 — dual-manifest collapse.** Add the local marketplace, `/plugin install`,
   confirm **all 6 skills load** with `marketplace.json` + `plugin.json` in one
   `.claude-plugin/` and `source: "."`. *Fallback:* keep the plugin in a neutrally-named
   `plugin/` subtree (skills at `plugin/skills/`; installer adjusts).
3. **Rewrite** bodies (capability language) and scripts (`lib/` self-resolution, drop the
   env var). *Verify-gate #3* (portable real-path resolution incl. macOS) is exercised here.
4. **Build + test `install.sh`**; run the new install tests.
5. **Verify-gate #4 — validation.** Confirm `skills-ref validate` passes all 6 (and
   tolerates `disable-model-invocation` → *verify-gate #2*); otherwise apply the documented
   fallbacks.
6. **Smoke-load** one skill via `.agents/skills/` in a non-Claude harness if one is
   available; else record it as untested in the matrix (honest, not assumed).
7. **Docs**: `README.md`, `SUPPORT-MATRIX.md`, `harness-tools.md`, `AGENTS.md` + thin
   `CLAUDE.md`, update the contributing guide paths.
8. **GitHub rename** `claude-skills` → `git-worktree-skills` **last** (redirects preserved);
   update remote + install instructions; the marketplace handle `neilwashere` stays.

## 13. Risks / unverified assumptions

- **Dual-manifest collapse** (gate #1) — unverified that Claude accepts both manifests in
  one `.claude-plugin/`; fallback defined.
- **Unknown-key tolerance** (gate #2) — `disable-model-invocation` surviving `skills-ref
  validate` and non-Claude parsers is expected (lenient YAML) but unverified.
- **Portable real-path** (gate #3) — `readlink -f` absent on stock macOS; fallback chain
  required and must be tested on both Linux and macOS semantics.
- **`skills-ref` availability** (gate #4) — may need a bundled minimal validator.
- **`.agents/skills` pickup** by each non-Claude harness is documented per vendor but only
  smoke-tested at most once here; the matrix states support honestly rather than over-claiming.

## 14. Success criteria

- All 6 skills are spec-clean (`name`/`description`/`compatibility`/`license`/`metadata`),
  bodies free of *required* Claude tool references, scripts free of `$CLAUDE_PLUGIN_ROOT`.
- Claude Code still installs and runs all 6 fully via `/plugin install
  git-worktree-skills@neilwashere`.
- `./install.sh` makes every skill discoverable under `~/.agents/skills/` and
  `~/.claude/skills/`, idempotently, with a safe `--uninstall`.
- `docs/SUPPORT-MATRIX.md` truthfully states per-harness behaviour.
- CI is green: bash tests, shellcheck, frontmatter validation, body portability lint.
- Repo, plugin, and namespace are `git-worktree-skills`; no `tss-`/`claude-` coupling
  remains outside the intentional Claude packaging/adapter layer.

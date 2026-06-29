# Harness-Agnostic Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make this repo's git/worktree skills loadable across any agent harness (Claude Code first-class; Codex/Gemini/Copilot/Pi best-effort) by de-coupling format, paths, and tool vocabulary, and rename it `claude-skills` → `git-worktree-skills`.

**Architecture:** Collapse the `tss-git-skills/` plugin subtree so the repo root *is* the plugin root with a top-level `skills/`. Author skills to the open `SKILL.md` standard (capability-language bodies, portable frontmatter). Keep the Claude marketplace plugin *and* ship a neutral `install.sh` that links each skill into `~/.agents/skills/` and `~/.claude/skills/`. Document per-harness behaviour in a support matrix.

**Tech Stack:** Bash (POSIX-leaning), `jq`, `git`, GitHub Actions, shellcheck 0.11.0. No new runtime deps.

## Global Constraints

- **Names:** repo + plugin + namespace = `git-worktree-skills`. Marketplace handle stays `neilwashere`. Keep the marketplace `$schema` URL `https://anthropic.com/claude-code/marketplace.schema.json` (it is the Claude packaging layer, correctly Claude-specific).
- **Frontmatter (open standard):** `name` ≤64 chars, lowercase + hyphens, no consecutive/leading/trailing hyphens, **must equal the skill's directory name**. `description` 1–1024 chars. `compatibility` ≤500 chars. `version` lives under `metadata`, never top-level. `allowed-tools` is experimental — do not add it.
- **Keep `disable-model-invocation: true`** on the 4 user-invoked skills (configure, setup, teardown, enforce). Removing it would make destructive skills model-invocable on Claude. Other harnesses ignore unknown keys.
- **Bodies:** no *required* Claude tool names. Use capability language with a parenthetical `(Claude Code: <tool/command>)` hint. Never make `$CLAUDE_PLUGIN_ROOT` the only way to find a bundled script.
- **Scripts:** `set -euo pipefail`; shellcheck-clean under 0.11.0; resolve own dir with `cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`; fail loud on a missing lib; guard-then-act on every destructive op (never half-complete, never report success on a swallowed error).
- **Tests:** plain bash, no framework. Every new test must be watched to fail before it passes (a test's only value is its ability to fail).
- **Distribution:** dual — Claude plugin (`/plugin install git-worktree-skills@neilwashere`) and `./install.sh` (symlink default, `--copy` fallback) into `~/.agents/skills/` and `~/.claude/skills/`.
- **Commits:** Conventional Commits. End every commit message with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- **Workspace:** all work happens in the `feat/harness-agnostic-skills` worktree (already created). Do not write to the main checkout.
- **Leave historical docs untouched:** `docs/superpowers/plans/2026-06-25-*` and `docs/superpowers/specs/2026-06-25-*` describe past state; do not rewrite their `tss-git-skills` references.

## File Structure

| Path | Responsibility | Change |
|---|---|---|
| `skills/<skill>/SKILL.md` (×6) | skill definition | moved up from subtree; frontmatter + body edited |
| `skills/<skill>/scripts/*.sh`, `skills/setup-worktree-discipline/worktree-discipline.sh` | bundled scripts | moved; 3 lib-sourcing scripts edited |
| `lib/worktree-config.sh` | shared config resolver | moved up from subtree; unchanged content |
| `.claude-plugin/marketplace.json` | Claude marketplace | renamed plugin, `source: "."` |
| `.claude-plugin/plugin.json` | Claude plugin manifest | moved up; renamed |
| `install.sh` | neutral installer/uninstaller | **new** |
| `tools/validate-frontmatter.sh` | bundled frontmatter validator | **new** |
| `tools/lint-skill-portability.sh` | body portability lint | **new** |
| `docs/SUPPORT-MATRIX.md` | per-skill × per-harness behaviour | **new** |
| `docs/harness-tools.md` | capability → tool-name map | **new** |
| `AGENTS.md` | cross-vendor contributor guide | **new** (absorbs CLAUDE.md) |
| `CLAUDE.md` | thin import of AGENTS.md | rewritten |
| `README.md` | reframed, dual install | rewritten |
| `tests/run.sh` | test harness | paths updated; new tests appended |
| `.github/workflows/test.yml` | CI | validator + lint steps added |

---

## Task 1: Collapse the subtree, rename the plugin, keep tests green

**Files:**
- Move: `tss-git-skills/skills/` → `skills/`
- Move: `tss-git-skills/lib/` → `lib/`
- Move: `tss-git-skills/.claude-plugin/plugin.json` → `.claude-plugin/plugin.json`
- Delete: `tss-git-skills/` (incl. its `README.md`, absorbed into root README in Task 9)
- Modify: `.claude-plugin/marketplace.json`
- Modify: `tests/run.sh` (path references)

**Interfaces:**
- Produces: top-level `skills/` (auto-discovered by Claude at depth-1), `lib/worktree-config.sh`, a renamed plugin `git-worktree-skills` with marketplace `source: "."`.

- [ ] **Step 1: Move the tree with git (preserve history)**

```bash
git mv tss-git-skills/skills skills
git mv tss-git-skills/lib lib
git mv tss-git-skills/.claude-plugin/plugin.json .claude-plugin/plugin.json
git rm tss-git-skills/README.md
rmdir tss-git-skills/.claude-plugin tss-git-skills 2>/dev/null || true
```

- [ ] **Step 2: Rewrite `.claude-plugin/marketplace.json`**

Replace the whole file with:

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "neilwashere",
  "description": "Portable git/worktree workflow skills (SKILL.md) installable in any agent harness; ships as a Claude Code plugin.",
  "owner": {
    "name": "Neil Chambers",
    "email": "neil@threadsafe.systems"
  },
  "plugins": [
    {
      "name": "git-worktree-skills",
      "description": "Git/worktree workflow skills — branch discipline, worktree create/enter/dispose. Namespaced as git-worktree-skills:<skill>.",
      "source": ".",
      "category": "development"
    }
  ]
}
```

- [ ] **Step 3: Rewrite `.claude-plugin/plugin.json`**

```json
{
  "name": "git-worktree-skills",
  "description": "Portable git/worktree workflow skills — branch discipline, worktree create/enter/dispose. Namespaced as git-worktree-skills:<skill>.",
  "author": {
    "name": "Neil Chambers"
  }
}
```

- [ ] **Step 4: Repoint the test harness paths**

In `tests/run.sh`, replace the lib path and all script paths. Apply this exact edit at line 11:

```bash
# OLD:
LIB="$ROOT/tss-git-skills/lib/worktree-config.sh"
# NEW:
LIB="$ROOT/lib/worktree-config.sh"
```

Then replace every remaining occurrence of the string `$ROOT/tss-git-skills/skills/` with `$ROOT/skills/` (lines 132, 153, 154, 165, 184, 208, 237, 265, 278, 348, 355, 394, 400, 515, 798). Use:

```bash
sed -i 's#\$ROOT/tss-git-skills/skills/#$ROOT/skills/#g' tests/run.sh
```

- [ ] **Step 5: Fix the "missing lib fails loud" test (lines ~141-144)**

This test copies the whole plugin dir then deletes lib. After the collapse there is no `tss-git-skills/`. Replace the OLD block:

```bash
  cp -r "$ROOT/tss-git-skills" "$sb/plugin"
  rm -f "$sb/plugin/lib/worktree-config.sh"
```

with NEW:

```bash
  mkdir -p "$sb/plugin"
  cp -r "$ROOT/skills" "$sb/plugin/skills"
  cp -r "$ROOT/lib" "$sb/plugin/lib"
  rm -f "$sb/plugin/lib/worktree-config.sh"
  # also remove any vendored sibling fallback so the lib is truly absent
  rm -f "$sb/plugin/skills/create-and-enter-worktree/scripts/worktree-config.sh"
```

(The `$sb/plugin/skills/...` invocation path on line ~144 is already correct — it references `$sb/plugin`, not `$ROOT`.)

- [ ] **Step 6: Run the test suite — expect GREEN**

Run: `bash tests/run.sh`
Expected: all tests PASS (same count as before the move). If any path-not-found error mentions `tss-git-skills`, a reference was missed — grep `tests/run.sh` for `tss-git-skills` and fix.

- [ ] **Step 7: Shellcheck still clean**

Run: `find . -name '*.sh' -print0 | xargs -0 shellcheck`
Expected: no output (exit 0). (Uses your local shellcheck; CI pins 0.11.0.)

- [ ] **Step 8: VERIFY-GATE #1 (manual, blocking) — does the collapsed plugin load in Claude?**

This cannot be unit-tested. From a Claude Code session:

```
/plugin marketplace add /home/neil/code/threadsafe/claude-skills.worktrees/feat-harness-agnostic-skills
/plugin install git-worktree-skills@neilwashere
```

Confirm all **6** skills appear as `git-worktree-skills:<name>`. If the loader rejects `marketplace.json` + `plugin.json` in one `.claude-plugin/` with `source: "."`, apply the **fallback**: `git mv skills plugin/skills && git mv lib plugin/lib && git mv .claude-plugin/plugin.json plugin/.claude-plugin/plugin.json`, set marketplace `source: "./plugin"`, and update `tests/run.sh` paths to `$ROOT/plugin/...` and `install.sh`'s `SKILLS_SRC`/`LIB_SRC` (Task 7) accordingly. Record the outcome in the PR description.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: collapse plugin subtree to root and rename to git-worktree-skills

Move tss-git-skills/{skills,lib,.claude-plugin/plugin.json} to repo root so
the repo root is the plugin root with a top-level skills/. Rename plugin and
namespace to git-worktree-skills (marketplace handle neilwashere kept).
Repoint tests/run.sh; existing suite stays green.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Make script lib-resolution symlink-safe and copy-safe

**Files:**
- Modify: `skills/create-and-enter-worktree/scripts/wt-new.sh:34-40`
- Modify: `skills/exit-and-dispose-worktree/scripts/wt-rm.sh:15-21`
- Modify: `skills/configure-worktree/scripts/configure-worktree.sh:11-12`
- Test: `tests/run.sh` (append two tests)

**Interfaces:**
- Produces: each lib-sourcing script resolves its real dir with `pwd -P` and searches `[ ../../../lib/worktree-config.sh, <own-dir>/worktree-config.sh ]`, failing loud if neither exists. The second candidate is where `install.sh --copy` vendors the lib (Task 7).

- [ ] **Step 1: Write the failing tests**

Append to `tests/run.sh` (before the final summary/exit). Both build a real symlink/copy layout — exactly how `install.sh` will deploy:

```bash
# --- lib resolution under a symlinked install (install.sh default) ---
test_symlinked_skill_resolves_shared_lib() {
  local sb; sb="$(new_sandbox)"
  mkdir -p "$sb/agents/skills"
  ln -s "$ROOT/skills/configure-worktree" "$sb/agents/skills/configure-worktree"
  ( cd "$sb" && git init -q repo && cd repo \
      && git -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
    out="$(bash "$sb/agents/skills/configure-worktree/scripts/configure-worktree.sh" status 2>&1)" || true
    case "$out" in
      *"missing config lib"*) printf 'FAIL symlinked skill could not find shared lib\n'; FAILED=1 ;;
      *) printf 'PASS symlinked skill resolves shared lib\n' ;;
    esac )
}

# --- lib resolution when vendored beside the script (install.sh --copy) ---
test_vendored_lib_resolves_when_shared_absent() {
  local sb; sb="$(new_sandbox)"
  mkdir -p "$sb/skills"
  cp -r "$ROOT/skills/configure-worktree" "$sb/skills/configure-worktree"   # no lib/ at $sb
  cp "$ROOT/lib/worktree-config.sh" "$sb/skills/configure-worktree/scripts/worktree-config.sh"
  ( cd "$sb" && git init -q repo && cd repo \
      && git -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
    out="$(bash "$sb/skills/configure-worktree/scripts/configure-worktree.sh" status 2>&1)" || true
    case "$out" in
      *"missing config lib"*) printf 'FAIL vendored sibling lib not found\n'; FAILED=1 ;;
      *) printf 'PASS vendored sibling lib resolves\n' ;;
    esac )
}
```

- [ ] **Step 2: Run them — expect the symlink test to FAIL**

Run: `bash tests/run.sh 2>&1 | grep -E 'symlinked skill|vendored sibling'`
Expected: `FAIL symlinked skill could not find shared lib` (logical `pwd` resolves `../../../lib` into `$sb/agents/lib`, which doesn't exist). The vendored test may already pass — that's fine; it locks in the fallback.

- [ ] **Step 3: Patch the three scripts**

In `skills/create-and-enter-worktree/scripts/wt-new.sh`, replace lines 34-40:

```bash
# OLD:
_WTN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_WTC_LIB="$_WTN_DIR/../../../lib/worktree-config.sh"
if [ ! -f "$_WTC_LIB" ]; then
  echo "wt-new: missing config lib at $_WTC_LIB (broken plugin install)" >&2; exit 1
fi
# shellcheck source=/dev/null
. "$_WTC_LIB"
# NEW:
_WTN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
_WTC_LIB=""
for _cand in "$_WTN_DIR/../../../lib/worktree-config.sh" "$_WTN_DIR/worktree-config.sh"; do
  [ -f "$_cand" ] && { _WTC_LIB="$_cand"; break; }
done
[ -n "$_WTC_LIB" ] || { echo "wt-new: missing config lib (looked in ../../../lib and beside the script)" >&2; exit 1; }
# shellcheck source=/dev/null
. "$_WTC_LIB"
```

In `skills/exit-and-dispose-worktree/scripts/wt-rm.sh`, replace lines 15-21 the same way (prefix `_WTR_DIR`, message `wt-rm:`):

```bash
# NEW:
_WTR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
_WTC_LIB=""
for _cand in "$_WTR_DIR/../../../lib/worktree-config.sh" "$_WTR_DIR/worktree-config.sh"; do
  [ -f "$_cand" ] && { _WTC_LIB="$_cand"; break; }
done
[ -n "$_WTC_LIB" ] || { echo "wt-rm: missing config lib (looked in ../../../lib and beside the script)" >&2; exit 1; }
# shellcheck source=/dev/null
. "$_WTC_LIB"
```

In `skills/configure-worktree/scripts/configure-worktree.sh`, replace lines 11-12:

```bash
# OLD:
WTC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WTC_LIB="$WTC_DIR/../../../lib/worktree-config.sh"
# NEW:
WTC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WTC_LIB=""
for _cand in "$WTC_DIR/../../../lib/worktree-config.sh" "$WTC_DIR/worktree-config.sh"; do
  [ -f "$_cand" ] && { WTC_LIB="$_cand"; break; }
done
[ -n "$WTC_LIB" ] || WTC_LIB="$WTC_DIR/../../../lib/worktree-config.sh"   # keep a path for the error message below
```

(The existing `[ -f "$WTC_LIB" ] || { echo "...missing config lib at $WTC_LIB..."; exit 1; }` guard at the old line 18 stays and still fires when neither candidate exists.)

- [ ] **Step 4: Run tests — expect GREEN**

Run: `bash tests/run.sh 2>&1 | grep -E 'symlinked skill|vendored sibling'`
Expected: both `PASS`. Then run the full suite: `bash tests/run.sh` → all PASS.

- [ ] **Step 5: Shellcheck**

Run: `find . -name '*.sh' -print0 | xargs -0 shellcheck`
Expected: clean. (`_cand` is loop-local; if SC2034 fires on an unused var, it won't — `_cand` is used.)

- [ ] **Step 6: Commit**

```bash
git add skills tests/run.sh
git commit -m "fix: resolve bundled lib via pwd -P with a vendored fallback

Scripts now canonicalize their own dir (pwd -P) so a symlinked install
resolves ../../../lib into the real repo, and fall back to a lib copy
vendored beside the script (install.sh --copy). Adds falsifiable tests
for both layouts.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Portable frontmatter on all six skills + bundled validator

**Files:**
- Modify: all 6 `skills/*/SKILL.md` (frontmatter only)
- Create: `tools/validate-frontmatter.sh`
- Test: `tools/validate-frontmatter.sh` is the test

**Interfaces:**
- Produces: every SKILL.md carries `license: MIT`, `compatibility: <≤500 chars>`, and `metadata.version: "1.0.0"`, with `disable-model-invocation` preserved where present. `tools/validate-frontmatter.sh` exits non-zero if any skill violates the open-standard frontmatter rules.

- [ ] **Step 1: Write the validator (it is the failing test — it will fail until frontmatter is added)**

Create `tools/validate-frontmatter.sh`:

```bash
#!/usr/bin/env bash
# validate-frontmatter.sh — check every skills/*/SKILL.md against the open
# Agent Skills frontmatter rules (https://agentskills.io/specification):
#   - name: required, == dir name, lowercase + hyphens, no consecutive/edge hyphens, <=64
#   - description: required, 1..1024 chars
#   - compatibility: if present, <=500 chars
# No external deps (no python/jq needed for these checks).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
rc=0
fail() { printf 'FAIL %s: %s\n' "$1" "$2" >&2; rc=1; }

for skill_md in "$ROOT"/skills/*/SKILL.md; do
  dir="$(basename "$(dirname "$skill_md")")"

  # Extract the frontmatter block (between the first two '---' lines).
  fm="$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$skill_md")"
  [ -n "$fm" ] || { fail "$dir" "no YAML frontmatter"; continue; }

  name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  compat="$(printf '%s\n' "$fm" | sed -n 's/^compatibility:[[:space:]]*//p' | head -1)"

  [ -n "$name" ] || fail "$dir" "missing name"
  [ "$name" = "$dir" ] || fail "$dir" "name '$name' != dir '$dir'"
  printf '%s' "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' || fail "$dir" "name not lowercase/hyphen or has consecutive/edge hyphens"
  [ "${#name}" -le 64 ] || fail "$dir" "name >64 chars"

  [ -n "$desc" ] || fail "$dir" "missing description"
  dlen=${#desc}
  { [ "$dlen" -ge 1 ] && [ "$dlen" -le 1024 ]; } || fail "$dir" "description length $dlen not in 1..1024"

  if [ -n "$compat" ]; then
    # strip surrounding quotes for the length check
    c="${compat%\"}"; c="${c#\"}"
    [ "${#c}" -le 500 ] || fail "$dir" "compatibility >500 chars"
  fi
done

[ "$rc" -eq 0 ] && echo "frontmatter: all skills valid"
exit "$rc"
```

```bash
chmod +x tools/validate-frontmatter.sh
```

- [ ] **Step 2: Run it — expect PASS (current frontmatter already satisfies these rules)**

Run: `bash tools/validate-frontmatter.sh`
Expected: `frontmatter: all skills valid`. (The validator's job is to *stay* green as we add fields and to catch a future bad `name`/`description`. If it fails now, a current SKILL.md violates a rule — fix that first.)

- [ ] **Step 3: Add the new frontmatter fields to each SKILL.md**

For each skill, insert `license`, `compatibility`, `metadata` after the existing frontmatter keys (and after `disable-model-invocation` where present), keeping the closing `---`. Exact additions per skill:

`skills/configure-worktree/SKILL.md` — after `disable-model-invocation: true`:
```yaml
license: MIT
compatibility: "Requires git and a POSIX shell (bash, jq). Writes the worktree-config marker; fully portable. On harnesses without an interactive question tool, ask the questions in chat."
metadata:
  version: "1.0.0"
```

`skills/create-and-enter-worktree/SKILL.md` — after `description:`:
```yaml
license: MIT
compatibility: "Requires git and a POSIX shell. Claude Code relocates the session automatically (EnterWorktree); on other harnesses the bundled script creates the worktree but you must cd in / start a session there yourself."
metadata:
  version: "1.0.0"
```

`skills/exit-and-dispose-worktree/SKILL.md` — after `description:`:
```yaml
license: MIT
compatibility: "Requires git and a POSIX shell. Claude Code leaves the session via ExitWorktree; elsewhere leave the worktree session manually, then run the removal script from the main checkout."
metadata:
  version: "1.0.0"
```

`skills/setup-worktree-discipline/SKILL.md` — after `disable-model-invocation: true`:
```yaml
license: MIT
compatibility: "Claude Code only: installs a PreToolUse hook plus ~/.claude integration that make an opted-in main checkout read-only. No equivalent primitive on other harnesses."
metadata:
  version: "1.0.0"
```

`skills/teardown-worktree-discipline/SKILL.md` — after `disable-model-invocation: true`:
```yaml
license: MIT
compatibility: "Claude Code only: reverses setup-worktree-discipline (PreToolUse hook + ~/.claude integration). No-op on other harnesses."
metadata:
  version: "1.0.0"
```

`skills/worktree-enforce/SKILL.md` — after `disable-model-invocation: true`:
```yaml
license: MIT
compatibility: "Requires git and a POSIX shell. Marker management (in/out/status/doctor) is portable; the enforcement it toggles is applied only by the Claude Code PreToolUse hook from setup-worktree-discipline."
metadata:
  version: "1.0.0"
```

- [ ] **Step 4: Re-run the validator — expect PASS**

Run: `bash tools/validate-frontmatter.sh`
Expected: `frontmatter: all skills valid`.

- [ ] **Step 5: (Best-effort) cross-check with the reference validator if available**

Run: `command -v skills-ref >/dev/null && for d in skills/*/; do skills-ref validate "$d" || echo "skills-ref flagged $d"; done || echo "skills-ref not installed — bundled validator is authoritative (VERIFY-GATE #2 noted)"`
Expected: either all pass, or a clear note that `skills-ref` is absent. If `skills-ref` rejects `disable-model-invocation`, move that key under `metadata:` and note the regression in the PR (per spec verify-gate #2).

- [ ] **Step 6: Commit**

```bash
git add skills tools/validate-frontmatter.sh
git commit -m "feat: add portable frontmatter (license, compatibility, metadata) + validator

All six skills declare license/compatibility/metadata.version per the open
Agent Skills standard; disable-model-invocation kept on the four user-invoked
skills. tools/validate-frontmatter.sh enforces name/description/compatibility
rules with no external deps.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: De-couple the model-invoked bodies (create-and-enter, exit-and-dispose)

**Files:**
- Modify: `skills/create-and-enter-worktree/SKILL.md` (body)
- Modify: `skills/exit-and-dispose-worktree/SKILL.md` (body)

**Interfaces:**
- Consumes: the bundled scripts at `scripts/wt-new.sh`, `scripts/wt-rm.sh` (unchanged invocation contract).
- Produces: bodies that name capabilities with `(Claude Code: …)` hints and no *required* `$CLAUDE_PLUGIN_ROOT`.

- [ ] **Step 1: create-and-enter — add an "On non-Claude harnesses" note**

After the intro paragraph block (after line 13, before `## Why you cannot just \`cd\``), insert:

```markdown
> **Portability.** This skill is fully automatic in Claude Code, which has a session-relocation tool. Other harnesses have no such tool: there, run the bundled `scripts/wt-new.sh` to *create* the worktree, then open a session in / `cd` into the printed path yourself. See `docs/SUPPORT-MATRIX.md`.
```

- [ ] **Step 2: create-and-enter — frame the branch-naming snippet (line 36-38)**

Replace the fenced block:

```
. "${CLAUDE_PLUGIN_ROOT}/lib/worktree-config.sh"; wtc_branch_naming "$(git rev-parse --show-toplevel)"
```

with:

```
# Claude Code (plugin): the bundled resolver answers this directly —
. "${CLAUDE_PLUGIN_ROOT}/lib/worktree-config.sh"; wtc_branch_naming "$(git rev-parse --show-toplevel)"
# Elsewhere: source the bundled lib/worktree-config.sh by its installed path, then call wtc_branch_naming <repo-root>.
```

- [ ] **Step 3: create-and-enter — frame the wt-new.sh invocation (line 48-50)**

Replace:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/create-and-enter-worktree/scripts/wt-new.sh" <branch> [base]
```

with:

```
# Run the bundled scripts/wt-new.sh from the main checkout.
# Claude Code (plugin): bash "${CLAUDE_PLUGIN_ROOT}/skills/create-and-enter-worktree/scripts/wt-new.sh" <branch> [base]
# Otherwise: bash <this-skill-dir>/scripts/wt-new.sh <branch> [base]
```

- [ ] **Step 4: create-and-enter — frame Step 2 (relocation, lines 54-60)**

Replace the heading line 54 and its fenced `EnterWorktree({ path: ... })` block. New text for Step 2:

```markdown
**Step 2 — relocate the session into the worktree.** Use the single path line Step 1 printed.

- **Claude Code:** call the session-relocation tool — `EnterWorktree({ path: "<the path wt-new.sh printed>" })`.
- **Other harnesses:** there is usually no relocation tool. Start a session in that directory, or `cd` into it. Note some harnesses revert `cd` between commands — if so, open the path as a fresh working directory rather than relying on `cd`.

Pass the **exact single line** `wt-new.sh` wrote to stdout — don't reconstruct it from the branch name (the directory slug encodes `/` as `-`), and don't pipe `wt-new.sh` through anything that could prepend to its output.
```

- [ ] **Step 5: create-and-enter — soften remaining harness-specific phrasing**

- Line 11: change `The harness **\`EnterWorktree\` tool**` → `Claude Code's **\`EnterWorktree\` tool**`.
- Line 17 heading body: change `does **not** persist in this harness` → `does **not** persist in Claude Code (and several other harnesses)`.
- Lines 79-92 (`Already created…`, `Switching between worktrees`): keep the `EnterWorktree`/`ExitWorktree` examples but prefix each with `Claude Code:`. e.g. line 82 fenced block becomes a comment-led `# Claude Code:` then the call.

- [ ] **Step 6: exit-and-dispose — frame the wt-rm.sh invocation (line 31-34)**

Replace:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/exit-and-dispose-worktree/scripts/wt-rm.sh" <branch> [--force] \
  && git branch -d <branch>    # delete the merged branch — only if removal succeeded
```

with:

```
# Run the bundled scripts/wt-rm.sh from the main checkout, after you have left the worktree session.
# Claude Code (plugin): bash "${CLAUDE_PLUGIN_ROOT}/skills/exit-and-dispose-worktree/scripts/wt-rm.sh" <branch> [--force] \
# Otherwise:            bash <this-skill-dir>/scripts/wt-rm.sh <branch> [--force] \
  && git branch -d <branch>    # delete the merged branch — only if removal succeeded
```

- [ ] **Step 7: exit-and-dispose — frame the leave step (lines 21-27) and the intro**

- Line 10 intro bullet: prefix `The harness **\`ExitWorktree\` tool**` → `Claude Code's **\`ExitWorktree\` tool**`.
- Step 1 heading + block (lines 21-25): replace with:

```markdown
**Step 1 — leave the worktree session, returning to the main checkout.**

- **Claude Code:** `ExitWorktree({ action: "keep" })` (use `keep`, never `remove` — `remove` is a no-op on path-entered worktrees).
- **Other harnesses:** return to / open the main checkout directory yourself.
```

- Line 59 (`Just want to leave…`): prefix the `ExitWorktree({action: "keep"})` mention with `Claude Code:`.

- [ ] **Step 8: Validate — frontmatter still valid, no bare env-var left as the only path**

Run:
```bash
bash tools/validate-frontmatter.sh
grep -n 'CLAUDE_PLUGIN_ROOT' skills/create-and-enter-worktree/SKILL.md skills/exit-and-dispose-worktree/SKILL.md
```
Expected: validator PASS; every `CLAUDE_PLUGIN_ROOT` hit sits on a line that also says `Claude Code` (i.e. it's a hint, not the sole instruction).

- [ ] **Step 9: Commit**

```bash
git add skills/create-and-enter-worktree/SKILL.md skills/exit-and-dispose-worktree/SKILL.md
git commit -m "refactor: capability-language bodies for the worktree create/dispose skills

Lead with the capability and mark Claude-specific tools/paths as
(Claude Code: ...) hints; add an explicit non-Claude path. No required
\$CLAUDE_PLUGIN_ROOT.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: De-couple the configure-worktree body

**Files:**
- Modify: `skills/configure-worktree/SKILL.md` (body)

**Interfaces:**
- Consumes: `scripts/configure-worktree.sh` (stdin JSON + `<scope>` / `status`).
- Produces: a body that frames `AskUserQuestion` and the script path portably.

- [ ] **Step 1: Frame the question-asking + script invocation (lines 16-22)**

Replace the paragraph + fenced block:

```
Ask the questions below with the `AskUserQuestion` tool, assemble a JSON
object from the answers (include **only** fields the user actively set — omit a
field to keep its built-in default), then write it to the chosen tier:

```bash
printf '%s' '<assembled-json>' | bash "${CLAUDE_PLUGIN_ROOT}/skills/configure-worktree/scripts/configure-worktree.sh" <global|committed|local>
```
```

with:

```
Ask the questions below (Claude Code: the `AskUserQuestion` tool; other harnesses:
prompt in chat), assemble a JSON object from the answers (include **only** fields
the user actively set — omit a field to keep its built-in default), then write it
to the chosen tier by piping the JSON into the bundled `scripts/configure-worktree.sh`:

```bash
# Claude Code (plugin): bash "${CLAUDE_PLUGIN_ROOT}/skills/configure-worktree/scripts/configure-worktree.sh" <global|committed|local>
# Otherwise:            bash <this-skill-dir>/scripts/configure-worktree.sh <global|committed|local>
printf '%s' '<assembled-json>' | bash <configure-worktree.sh> <global|committed|local>
```
```

- [ ] **Step 2: Frame the status invocation (lines 56-58)**

Replace:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/configure-worktree/scripts/configure-worktree.sh" status
```

with:

```
# Claude Code (plugin): bash "${CLAUDE_PLUGIN_ROOT}/skills/configure-worktree/scripts/configure-worktree.sh" status
# Otherwise:            bash <this-skill-dir>/scripts/configure-worktree.sh status
```

- [ ] **Step 3: Validate**

Run:
```bash
bash tools/validate-frontmatter.sh
grep -n 'CLAUDE_PLUGIN_ROOT' skills/configure-worktree/SKILL.md
```
Expected: PASS; each `CLAUDE_PLUGIN_ROOT` line also contains `Claude Code`.

- [ ] **Step 4: Commit**

```bash
git add skills/configure-worktree/SKILL.md
git commit -m "refactor: capability-language body for configure-worktree

Frame AskUserQuestion and the script path with (Claude Code: ...) hints.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: De-couple the discipline trio (setup, teardown, enforce)

**Files:**
- Modify: `skills/setup-worktree-discipline/SKILL.md`
- Modify: `skills/teardown-worktree-discipline/SKILL.md`
- Modify: `skills/worktree-enforce/SKILL.md`

**Interfaces:**
- Produces: bodies that (a) state up front these three are Claude-Code-only in mechanism, (b) frame the `$CLAUDE_PLUGIN_ROOT` script paths, (c) rename the plugin string to `git-worktree-skills`.

These three are honestly Claude-centric (PreToolUse hooks + `~/.claude`), so the edit is lighter: a Claude-only banner + path framing + the plugin rename. Do **not** strip the `~/.claude/...` mechanics — they are the correct Claude adapter.

- [ ] **Step 1: setup — add the Claude-only banner**

After the frontmatter, before `# Setup Worktree Discipline`'s first paragraph (insert as the first body line under the H1):

```markdown
> **Claude Code only.** This installs a `PreToolUse` hook and `~/.claude` integration — mechanisms no other harness has. There is no portable equivalent; see `docs/SUPPORT-MATRIX.md`.
```

- [ ] **Step 2: setup — frame both `cp "${CLAUDE_PLUGIN_ROOT}/…"` lines (25, 115)**

On lines 25 and 115, the `cp "${CLAUDE_PLUGIN_ROOT}/skills/setup-worktree-discipline/worktree-discipline.sh" ~/.claude/hooks/...` stays (it *is* the Claude install), but precede each fenced block with a sentence: `In Claude Code the bundled hook lives at \`${CLAUDE_PLUGIN_ROOT}/skills/setup-worktree-discipline/worktree-discipline.sh\`; if you installed via \`install.sh\`, use that copy's path instead.` No code change to the `cp` itself.

- [ ] **Step 3: teardown — banner + plugin rename**

- Insert the same Claude-only banner as Step 1 under the H1.
- Line 11: `/plugin uninstall tss-git-skills` → `/plugin uninstall git-worktree-skills`.
- Line 52: `/plugin uninstall tss-git-skills` → `/plugin uninstall git-worktree-skills` and `/plugin marketplace remove neilwashere` stays.
- Line 24 fenced `bash "${CLAUDE_PLUGIN_ROOT}/skills/teardown-worktree-discipline/scripts/teardown-worktree-discipline.sh"`: precede with `Claude Code (plugin):` comment, and add an `# Otherwise: bash <this-skill-dir>/scripts/teardown-worktree-discipline.sh` line.

- [ ] **Step 4: enforce — banner-lite + path framing**

- Under the H1, insert: `> **Mostly Claude Code.** Marker management (in/out/status) works anywhere; the enforcement it toggles is applied only by the Claude Code hook from setup-worktree-discipline.`
- Line 25 fenced `bash "${CLAUDE_PLUGIN_ROOT}/skills/worktree-enforce/scripts/worktree-enforce.sh" <in|out|status|doctor>`: replace with the two-line hint form:
```
# Claude Code (plugin): bash "${CLAUDE_PLUGIN_ROOT}/skills/worktree-enforce/scripts/worktree-enforce.sh" <in|out|status|doctor>
# Otherwise:            bash <this-skill-dir>/scripts/worktree-enforce.sh <in|out|status|doctor>
```

- [ ] **Step 5: Validate**

Run:
```bash
bash tools/validate-frontmatter.sh
grep -rn 'tss-git-skills' skills/   # expect NO hits
grep -rln 'CLAUDE_PLUGIN_ROOT' skills/   # only inside (Claude Code: ...) framing
```
Expected: validator PASS; zero `tss-git-skills` in `skills/`.

- [ ] **Step 6: Commit**

```bash
git add skills/setup-worktree-discipline/SKILL.md skills/teardown-worktree-discipline/SKILL.md skills/worktree-enforce/SKILL.md
git commit -m "refactor: label discipline trio Claude-only, frame paths, rename plugin

Add Claude-only banners (PreToolUse + ~/.claude have no portable equivalent),
frame \$CLAUDE_PLUGIN_ROOT script paths, and rename the plugin string to
git-worktree-skills.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: The neutral installer (`install.sh`) + tests

**Files:**
- Create: `install.sh`
- Test: `tests/run.sh` (append an install-suite block)

**Interfaces:**
- Consumes: `skills/` (the source of truth), `lib/worktree-config.sh` (vendored in `--copy`).
- Produces: `install.sh` with `--copy`, `--uninstall`, `--list`, `--agents-dir`, `--claude-dir`, `--force`, `--help`. Default symlinks each skill into `~/.agents/skills/` and `~/.claude/skills/`. Never clobbers a path it does not own; `--uninstall` removes only owned entries.

- [ ] **Step 1: Write the installer**

Create `install.sh`:

```bash
#!/usr/bin/env bash
# install.sh — make git-worktree-skills discoverable by any agent harness.
#
# Links (default) or copies each skills/<skill> into the harness skill dirs:
#   ~/.agents/skills/   Codex, Gemini, Antigravity, Pi
#   ~/.claude/skills/   Claude Code (personal scope), Copilot, Cursor, Windsurf, Pi
# Claude Code users may instead install the plugin: /plugin install git-worktree-skills@neilwashere
#
# Safe by design: never clobbers a path it does not own; --uninstall removes
# only links/copies this script created (link target under skills/, or a
# copy stamped with .git-worktree-skills-installed).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS_SRC="$REPO_ROOT/skills"
LIB_SRC="$REPO_ROOT/lib/worktree-config.sh"
STAMP=".git-worktree-skills-installed"

AGENTS_DIR="$HOME/.agents/skills"
CLAUDE_DIR="$HOME/.claude/skills"
MODE="symlink"     # symlink | copy
ACTION="install"   # install | uninstall | list
FORCE=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  (default)          symlink every skill into ~/.agents/skills and ~/.claude/skills
  --copy             copy instead of symlink (vendors lib/ into each skill)
  --uninstall        remove only the links/copies this script created
  --list             print the skills that would be installed, then exit
  --agents-dir DIR   override ~/.agents/skills  (pass "" to skip this target)
  --claude-dir DIR   override ~/.claude/skills  (pass "" to skip this target)
  --force            replace an existing entry we own but that has drifted
  -h, --help         show this help

Claude Code users can instead run:  /plugin install git-worktree-skills@neilwashere
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --copy) MODE="copy" ;;
    --uninstall) ACTION="uninstall" ;;
    --list) ACTION="list" ;;
    --force) FORCE=1 ;;
    --agents-dir) AGENTS_DIR="${2-}"; shift ;;
    --claude-dir) CLAUDE_DIR="${2-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -d "$SKILLS_SRC" ] || { echo "install: no skills/ dir at $SKILLS_SRC" >&2; exit 1; }

list_skills() { find "$SKILLS_SRC" -mindepth 1 -maxdepth 1 -type d | sort | while read -r d; do basename "$d"; done; }

if [ "$ACTION" = "list" ]; then list_skills; exit 0; fi

targets() {
  [ -n "$AGENTS_DIR" ] && printf '%s\n' "$AGENTS_DIR"
  [ -n "$CLAUDE_DIR" ] && printf '%s\n' "$CLAUDE_DIR"
  return 0
}

dest_is_ours() { # <dest> -> 0 if a link into skills/ OR a stamped copy
  local dest="$1"
  if [ -L "$dest" ]; then
    case "$(readlink "$dest")" in "$SKILLS_SRC"/*) return 0 ;; *) return 1 ;; esac
  fi
  [ -e "$dest/$STAMP" ]
}

install_one() { # <skill> <destdir>
  local skill="$1" destdir="$2" src dest
  src="$SKILLS_SRC/$skill"; dest="$destdir/$skill"
  mkdir -p "$destdir"
  if [ -L "$dest" ] || [ -e "$dest" ]; then
    if [ "$MODE" = symlink ] && [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
      echo "  = $dest"; return 0
    fi
    if dest_is_ours "$dest"; then
      if [ "$FORCE" = 1 ]; then rm -rf "$dest"; else
        echo "  ! $dest exists (ours) — re-run with --force to replace"; return 0
      fi
    else
      echo "  ! $dest exists and is NOT ours — leaving untouched"; return 0
    fi
  fi
  if [ "$MODE" = symlink ]; then
    ln -s "$src" "$dest"; echo "  + $dest -> $src"
  else
    cp -R "$src" "$dest"; : > "$dest/$STAMP"
    if [ -f "$LIB_SRC" ] && [ -d "$dest/scripts" ]; then cp "$LIB_SRC" "$dest/scripts/worktree-config.sh"; fi
    echo "  + $dest (copy)"
  fi
}

uninstall_one() { # <skill> <destdir>
  local skill="$1" destdir="$2" dest
  dest="$destdir/$skill"
  { [ -L "$dest" ] || [ -e "$dest" ]; } || return 0
  if dest_is_ours "$dest"; then rm -rf "$dest"; echo "  - $dest"; else
    echo "  ! $dest is NOT ours — leaving untouched"
  fi
}

while read -r destdir; do
  [ -n "$destdir" ] || continue
  echo "$ACTION -> $destdir"
  while read -r skill; do
    [ -n "$skill" ] || continue
    if [ "$ACTION" = install ]; then install_one "$skill" "$destdir"; else uninstall_one "$skill" "$destdir"; fi
  done < <(list_skills)
done < <(targets)

echo "Done."
```

```bash
chmod +x install.sh
```

- [ ] **Step 2: Write the failing install tests**

Append to `tests/run.sh` (every test points both target dirs into the sandbox via `--agents-dir`/`--claude-dir`, never the real `$HOME`):

```bash
# --- install.sh: symlink into both targets, idempotent, uninstall owns-only ---
test_install_symlinks_both_targets() {
  local sb; sb="$(new_sandbox)"
  bash "$ROOT/install.sh" --agents-dir "$sb/agents" --claude-dir "$sb/claude" >/dev/null
  local n_a n_c
  n_a="$(find "$sb/agents" -maxdepth 1 -type l | wc -l | tr -d ' ')"
  n_c="$(find "$sb/claude" -maxdepth 1 -type l | wc -l | tr -d ' ')"
  local want; want="$(bash "$ROOT/install.sh" --list | wc -l | tr -d ' ')"
  { [ "$n_a" = "$want" ] && [ "$n_c" = "$want" ]; } \
    && printf 'PASS install symlinks all skills into both targets\n' \
    || { printf 'FAIL install: agents=%s claude=%s want=%s\n' "$n_a" "$n_c" "$want"; FAILED=1; }
  # link resolves to the real skill
  [ "$(readlink "$sb/agents/configure-worktree")" = "$ROOT/skills/configure-worktree" ] \
    && printf 'PASS link points at source\n' || { printf 'FAIL link target wrong\n'; FAILED=1; }
}

test_install_is_idempotent() {
  local sb; sb="$(new_sandbox)"
  bash "$ROOT/install.sh" --agents-dir "$sb/agents" --claude-dir "" >/dev/null
  out="$(bash "$ROOT/install.sh" --agents-dir "$sb/agents" --claude-dir "" 2>&1)"
  case "$out" in *"= $sb/agents/configure-worktree"*) printf 'PASS second run is a no-op\n' ;;
    *) printf 'FAIL idempotency: %s\n' "$out"; FAILED=1 ;; esac
}

test_install_refuses_foreign_path() {
  local sb; sb="$(new_sandbox)"
  mkdir -p "$sb/agents/configure-worktree"; echo mine > "$sb/agents/configure-worktree/keep.txt"
  bash "$ROOT/install.sh" --agents-dir "$sb/agents" --claude-dir "" >/dev/null
  [ -f "$sb/agents/configure-worktree/keep.txt" ] \
    && printf 'PASS install leaves a foreign dir untouched\n' \
    || { printf 'FAIL install clobbered a foreign dir\n'; FAILED=1; }
}

test_uninstall_owns_only() {
  local sb; sb="$(new_sandbox)"
  bash "$ROOT/install.sh" --agents-dir "$sb/agents" --claude-dir "" >/dev/null
  mkdir -p "$sb/agents/foreign-skill"; echo x > "$sb/agents/foreign-skill/x"
  bash "$ROOT/install.sh" --uninstall --agents-dir "$sb/agents" --claude-dir "" >/dev/null
  { [ ! -e "$sb/agents/configure-worktree" ] && [ -f "$sb/agents/foreign-skill/x" ]; } \
    && printf 'PASS uninstall removes ours, keeps foreign\n' \
    || { printf 'FAIL uninstall scope wrong\n'; FAILED=1; }
}

test_install_copy_is_self_contained() {
  local sb; sb="$(new_sandbox)"
  bash "$ROOT/install.sh" --copy --agents-dir "$sb/agents" --claude-dir "" >/dev/null
  [ -f "$sb/agents/configure-worktree/scripts/worktree-config.sh" ] \
    && [ -f "$sb/agents/configure-worktree/$( basename ".git-worktree-skills-installed" )" ] 2>/dev/null
  # vendored lib present + the copied skill runs without a shared lib/ nearby:
  ( cd "$sb" && git init -q r && cd r && git -c user.email=a@b -c user.name=a commit -q --allow-empty -m i
    o="$(bash "$sb/agents/configure-worktree/scripts/configure-worktree.sh" status 2>&1)" || true
    case "$o" in *"missing config lib"*) printf 'FAIL copied skill lost its lib\n'; FAILED=1 ;;
      *) printf 'PASS copy mode vendors a working lib\n' ;; esac )
}
```

- [ ] **Step 3: Run them — expect FAIL (install.sh untested / a bug or two will surface)**

Run: `bash tests/run.sh 2>&1 | grep -E 'install|uninstall|copy mode|link points|no-op|foreign'`
Expected: at least one FAIL before you trust them (e.g. before `chmod +x`, or if a guard is off). Watch them go red, then green in Step 4. If they are all green on the first run, deliberately break one guard (e.g. comment out the `dest_is_ours` check) to confirm `test_install_refuses_foreign_path`/`test_uninstall_owns_only` can fail, then restore.

- [ ] **Step 4: Run full suite — expect GREEN**

Run: `bash tests/run.sh`
Expected: all PASS.

- [ ] **Step 5: Shellcheck the installer**

Run: `shellcheck install.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/run.sh
git commit -m "feat: add neutral install.sh (symlink|copy) into ~/.agents and ~/.claude skills

Links or copies each skill into the cross-harness skill dirs; guard-then-act so
it never clobbers a foreign path and --uninstall removes only owned entries;
--copy vendors lib/ for self-contained skills. Falsifiable install tests added.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Support matrix + harness tool map

**Files:**
- Create: `docs/SUPPORT-MATRIX.md`
- Create: `docs/harness-tools.md`

**Interfaces:** documentation only; referenced by skill bodies (Tasks 4-6) and README (Task 9).

- [ ] **Step 1: Write `docs/SUPPORT-MATRIX.md`**

```markdown
# Support matrix

How each skill behaves per harness. **✔ full** · **◐ degraded** (loads and partly works) · **✖ n/a** (Claude-only mechanism). Claude Code is the only first-class, tested target; non-Claude columns are best-effort and, unless noted, smoke-tested at most once — treat them as "should load," not "verified."

| Skill | Claude Code | Codex | Gemini / Antigravity | Copilot | Pi |
|---|---|---|---|---|---|
| configure-worktree | ✔ | ✔ ¹ | ✔ ¹ | ✔ ¹ | ✔ ¹ |
| create-and-enter-worktree | ✔ | ◐ ² | ◐ ² | ◐ ² | ◐ ² |
| exit-and-dispose-worktree | ✔ | ◐ ³ | ◐ ³ | ◐ ³ | ◐ ³ |
| worktree-enforce | ✔ | ◐ ⁴ | ◐ ⁴ | ◐ ⁴ | ◐ ⁴ |
| setup-worktree-discipline | ✔ | ✖ ⁵ | ✖ ⁵ | ✖ ⁵ | ✖ ⁵ |
| teardown-worktree-discipline | ✔ | ✖ ⁵ | ✖ ⁵ | ✖ ⁵ | ✖ ⁵ |

1. Writes the worktree-config marker via a bundled script; the only difference off-Claude is the questions are asked in chat instead of a dedicated question tool.
2. Creates the worktree via `wt-new.sh`, but there is no session-relocation tool outside Claude Code — you `cd` in / open a session in the printed path yourself.
3. `wt-rm.sh` removes the tree with its dirty/unpushed guard, but you leave the worktree session manually (no `ExitWorktree`).
4. Marker management (`in`/`out`/`status`) is portable shell; the enforcement those markers toggle is applied only by the Claude Code `PreToolUse` hook from setup-worktree-discipline.
5. Pure Claude Code mechanism: a `PreToolUse` hook plus `~/.claude` integration. No other harness has an equivalent pre-write enforcement primitive. A git pre-commit/pre-push fallback is a possible future addition (out of scope here).

## Why some behaviour can't port

`SKILL.md` is a cross-vendor format, but two capabilities these skills use have no uniform equivalent: **session relocation** (moving the agent's working directory mid-session) and **pre-tool write enforcement** (denying writes before they happen). Claude Code provides both; most harnesses provide neither. The skills are authored so they still *load* everywhere and degrade to the portable subset.
```

- [ ] **Step 2: Write `docs/harness-tools.md`**

```markdown
# Harness tool map

Skill bodies speak in **capabilities**, not tool names. This is the lookup from capability to each harness's tool, so a reader can translate. Claude Code is authoritative (first-class target); other columns are best-effort pointers from public docs and may drift.

| Capability | Claude Code | Codex CLI | Gemini CLI | Copilot CLI |
|---|---|---|---|---|
| Run a shell command | `Bash` | `shell` | `run_shell_command` | `bash` |
| Read a file | `Read` | `shell` (cat) | `read_file` | `view` |
| Create a file | `Write` | `apply_patch` | `write_file` | `apply_patch` |
| Edit a file | `Edit` | `apply_patch` | `replace` | `apply_patch` |
| Ask the user a question | `AskUserQuestion` | (prompt in chat) | (prompt in chat) | (prompt in chat) |
| Invoke another skill | `Skill` | native / `$name` | `activate_skill` | `skill` |
| Relocate the session (cwd) | `EnterWorktree` / `ExitWorktree` | — (none; `cd`) | — (none; `cd`) | — (none; `cd`) |
| Track a checklist | `TodoWrite` | `update_plan` | `write_todos` | `update_todo` |

**The two rows that matter for this repo** are session relocation (no tool outside Claude Code) and pre-tool enforcement (a Claude Code `PreToolUse` hook, no row above because no harness exposes it as a callable tool). Everything else is reachable everywhere via *some* shell, which is why the bundled `scripts/*.sh` are the real portability layer.

Sources: per-vendor skill docs current to mid-2026; see the design spec `docs/superpowers/specs/2026-06-29-harness-agnostic-skills-design.md`.
```

- [ ] **Step 3: Commit**

```bash
git add docs/SUPPORT-MATRIX.md docs/harness-tools.md
git commit -m "docs: add support matrix and harness tool map

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: AGENTS.md, thin CLAUDE.md, README rewrite

**Files:**
- Create: `AGENTS.md`
- Modify: `CLAUDE.md` (replace contents)
- Modify: `README.md` (replace contents)

**Interfaces:** `CLAUDE.md` imports `AGENTS.md` so Claude Code still reads the contributor guidance; README documents both install paths.

- [ ] **Step 1: Write `AGENTS.md`**

```markdown
# Repository guide for agents

This repo hosts **git-worktree-skills** — portable git/worktree workflow skills authored to the open Agent Skills (`SKILL.md`) standard, loadable across Claude Code, Codex, Gemini, Copilot, and Pi.

## Layout

- `skills/<skill>/SKILL.md` — one skill each; bundled scripts under `scripts/`. The repo root *is* the Claude plugin root, so Claude auto-discovers `skills/` at depth-1.
- `lib/worktree-config.sh` — shared config resolver, sourced by the worktree scripts.
- `.claude-plugin/` — Claude marketplace + plugin manifests (the Claude packaging layer).
- `install.sh` — neutral installer for every other harness (symlinks/copies skills into `~/.agents/skills/` and `~/.claude/skills/`).
- `docs/SUPPORT-MATRIX.md` — per-skill × per-harness behaviour. `docs/harness-tools.md` — capability → tool-name map.

## Portability rules (when editing skills)

- Write SKILL.md **bodies in capabilities**, not tool names. Mark anything harness-specific as `(Claude Code: <tool/command>)`. Never make `$CLAUDE_PLUGIN_ROOT` the only way to find a bundled script.
- Keep frontmatter to the open standard: `name` (== dir name), `description` (≤1024), optional `license`/`compatibility` (≤500)/`metadata`. `disable-model-invocation` is Claude-only but kept on the four user-invoked skills.
- Bundled `scripts/*.sh` are the portability layer — push harness-specific behaviour into them; they self-locate `lib/` (`pwd -P`, with a vendored sibling fallback for `--copy`).

## Verification expectations

Follow [docs/contributing/closing-the-verification-loop.md](./docs/contributing/closing-the-verification-loop.md): make tests falsifiable (watch them fail first), verify behaviour by running it, treat tool versions / platform / CI semantics as inputs, and design the failure path of every destructive operation (guard-then-act, write-to-temp-then-rename, never half-complete or report success on a swallowed error). Before a PR: `bash tests/run.sh`, `bash tools/validate-frontmatter.sh`, `bash tools/lint-skill-portability.sh`, and shellcheck all `*.sh`.
```

- [ ] **Step 2: Replace `CLAUDE.md` with a thin import**

```markdown
@AGENTS.md

## Claude-specific notes

This repo ships as a Claude Code marketplace plugin (`.claude-plugin/`), installable with `/plugin install git-worktree-skills@neilwashere`. Claude Code is the first-class target: skills work fully here (session relocation via `EnterWorktree`/`ExitWorktree`, write-enforcement via the `PreToolUse` hook). See `docs/SUPPORT-MATRIX.md` for behaviour on other harnesses.
```

- [ ] **Step 3: Replace `README.md`**

```markdown
# git-worktree-skills

Portable git/worktree workflow skills — branch discipline and worktree create / enter / dispose — authored to the open [Agent Skills](https://agentskills.io/specification) (`SKILL.md`) standard. Loadable in Claude Code (first-class), and in Codex, Gemini, Copilot, and Pi (best-effort; see the [support matrix](./docs/SUPPORT-MATRIX.md)).

## Install

**Claude Code (plugin):**

```bash
/plugin marketplace add neilwashere/git-worktree-skills
/plugin install git-worktree-skills@neilwashere
```

For live, git-synced local development: `/plugin marketplace add /path/to/git-worktree-skills`.

**Any other harness (neutral):**

```bash
git clone https://github.com/neilwashere/git-worktree-skills
cd git-worktree-skills && ./install.sh        # symlinks into ~/.agents/skills and ~/.claude/skills
# ./install.sh --copy        # if your environment can't use symlinks
# ./install.sh --uninstall   # remove what it installed
```

Your harness then discovers the skills from `~/.agents/skills/` or `~/.claude/skills/`.

## Skills

**User-invoked** (reachable only when you type them — `disable-model-invocation: true`):

- **[setup-worktree-discipline](./skills/setup-worktree-discipline/SKILL.md)** — *Claude Code only:* install a `PreToolUse` hook making an opted-in main checkout read-only, plus the global CLAUDE.md rule.
- **[teardown-worktree-discipline](./skills/teardown-worktree-discipline/SKILL.md)** — *Claude Code only:* the clean reverse of setup; run before `/plugin uninstall`.
- **[worktree-enforce](./skills/worktree-enforce/SKILL.md)** — opt the current repo `in`/`out`, show `status`, or run `doctor`. Marker management is portable; enforcement is applied by the Claude hook.
- **[configure-worktree](./skills/configure-worktree/SKILL.md)** — guided setup of the worktree-config marker (location, mirrored files, post-create command, branch naming).

**Model-invoked** (model- or user-reachable):

- **[create-and-enter-worktree](./skills/create-and-enter-worktree/SKILL.md)** — create a sibling worktree off `origin/<default>` and relocate into it (auto on Claude Code; `cd` in elsewhere).
- **[exit-and-dispose-worktree](./skills/exit-and-dispose-worktree/SKILL.md)** — after a PR merges, leave the worktree session then remove the tree (refuses if dirty/unpushed).

## Contributing

Contributor guidance lives in **[AGENTS.md](./AGENTS.md)** (read by any harness). It points to **[docs/contributing/closing-the-verification-loop.md](./docs/contributing/closing-the-verification-loop.md)** — the verification habits this repo expects.
```

- [ ] **Step 4: Validate links and frontmatter**

Run:
```bash
bash tools/validate-frontmatter.sh
grep -rn 'tss-git-skills\|claude-skills' README.md CLAUDE.md AGENTS.md   # expect NO hits
```
Expected: validator PASS; no stale names in the top-level docs.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md CLAUDE.md README.md
git commit -m "docs: add AGENTS.md, thin CLAUDE.md to import it, reframe README for dual install

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: CI — wire in the validator and a portability lint

**Files:**
- Create: `tools/lint-skill-portability.sh`
- Modify: `.github/workflows/test.yml`
- Test: the lint script is its own test

**Interfaces:** CI runs `tests/run.sh`, `tools/validate-frontmatter.sh`, `tools/lint-skill-portability.sh`, and shellcheck.

- [ ] **Step 1: Write the portability lint**

Create `tools/lint-skill-portability.sh`:

```bash
#!/usr/bin/env bash
# lint-skill-portability.sh — heuristic guard: a SKILL.md body must not name a
# Claude-only tool OUTSIDE a "(Claude Code: ...)" hint. Scans body lines that are
# not inside ``` fenced blocks. Advisory but CI-enforced; relax by adding the
# hint or rephrasing in capability terms.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TOOLS_RE='EnterWorktree|ExitWorktree|AskUserQuestion|TodoWrite'
rc=0

for skill_md in "$ROOT"/skills/*/SKILL.md; do
  in_fm=0; seen_fm=0; in_fence=0; lineno=0
  while IFS= read -r line; do
    lineno=$((lineno+1))
    # skip frontmatter
    if [ "$seen_fm" -lt 2 ] && [ "$line" = "---" ]; then seen_fm=$((seen_fm+1)); in_fm=$((in_fm^1)); continue; fi
    [ "$seen_fm" -lt 2 ] && continue
    case "$line" in '```'*) in_fence=$((in_fence^1)); continue ;; esac
    [ "$in_fence" -eq 1 ] && continue
    if printf '%s' "$line" | grep -Eq "$TOOLS_RE"; then
      case "$line" in *"Claude Code"*) : ;; *)
        printf 'FAIL %s:%s names a Claude-only tool without a (Claude Code: ...) hint:\n  %s\n' \
          "${skill_md#"$ROOT"/}" "$lineno" "$line" >&2; rc=1 ;;
      esac
    fi
  done < "$skill_md"
done

[ "$rc" -eq 0 ] && echo "portability lint: clean"
exit "$rc"
```

```bash
chmod +x tools/lint-skill-portability.sh
```

- [ ] **Step 2: Run it — expect PASS (after Tasks 4-6)**

Run: `bash tools/lint-skill-portability.sh`
Expected: `portability lint: clean`. If it FAILS, a body from Tasks 4-6 still names a tool on a line lacking `Claude Code` — fix the body (the lint is doing its job).

- [ ] **Step 3: Prove the lint can fail**

Temporarily add a line `Use the EnterWorktree tool.` to any SKILL.md body (outside a fence, no "Claude Code"), run the lint, confirm it FAILS on that line, then remove the line.

Run: `bash tools/lint-skill-portability.sh; echo "exit=$?"`
Expected: a `FAIL ...EnterWorktree...` line and `exit=1`, then clean again after removal.

- [ ] **Step 4: Add CI steps to `.github/workflows/test.yml`**

After the `Run resolver tests` step (line 13-14) and before `Lint with shellcheck`, insert:

```yaml
      - name: Validate skill frontmatter
        run: bash tools/validate-frontmatter.sh
      - name: Lint skill body portability
        run: bash tools/lint-skill-portability.sh
```

(The existing `find . -name '*.sh' | xargs shellcheck` step already covers `install.sh` and `tools/*.sh` — no change needed there.)

- [ ] **Step 5: Run everything CI runs, locally**

Run:
```bash
bash tests/run.sh && bash tools/validate-frontmatter.sh && bash tools/lint-skill-portability.sh \
  && find . -name '*.sh' -print0 | xargs -0 shellcheck && echo ALL-GREEN
```
Expected: `ALL-GREEN`.

- [ ] **Step 6: Commit**

```bash
git add tools/lint-skill-portability.sh .github/workflows/test.yml
git commit -m "ci: validate frontmatter and lint body portability

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: GitHub rename + final verification (user-gated)

**Files:** none in-repo (remote + local git config).

**Interfaces:** terminal task — produces the renamed remote and the PR.

- [ ] **Step 1: Open the PR (still as `claude-skills` remote — redirects come later)**

```bash
git push -u origin feat/harness-agnostic-skills
gh pr create --title "feat: make the repo harness-agnostic (rename to git-worktree-skills)" \
  --body "Implements docs/superpowers/specs/2026-06-29-harness-agnostic-skills-design.md. Records verify-gate #1 (dual-manifest collapse) outcome. See docs/SUPPORT-MATRIX.md.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 2: Final verification checklist (paste results into the PR)**

```bash
bash tests/run.sh                       # all PASS
bash tools/validate-frontmatter.sh      # all valid
bash tools/lint-skill-portability.sh    # clean
find . -name '*.sh' -print0 | xargs -0 shellcheck   # clean
grep -rn 'tss-git-skills' skills/ install.sh tools/ README.md AGENTS.md CLAUDE.md .claude-plugin/   # NO hits
./install.sh --list                     # lists 6 skills
```
Plus the manual VERIFY-GATE #1 result from Task 1 Step 8.

- [ ] **Step 3: Rename the GitHub repo (OUTWARD-FACING — confirm with the user first)**

This is irreversible-ish and public. Do **not** run autonomously. With the user's go-ahead, after the PR merges:

```bash
gh repo rename git-worktree-skills --repo neilwashere/claude-skills
git remote set-url origin git@github.com:neilwashere/git-worktree-skills.git
```

GitHub preserves redirects from the old name, so existing `/plugin marketplace add neilwashere/claude-skills` keeps resolving — but update any docs/bookmarks. The marketplace handle `neilwashere` is unchanged.

- [ ] **Step 4: Dispose of the worktree after merge**

Use the exit-and-dispose-worktree skill (leave the session, then `wt-rm.sh feat/harness-agnostic-skills`).

---

## Self-Review

**Spec coverage** (each spec §, → task):
- §2.5 collapse → T1 (with verify-gate #1 in T1.S8). §2.3 rename → T1, T6, T9, T11. §3 frontmatter table → T3. §5 frontmatter detail → T3. §6 body de-coupling → T4/T5/T6. §7 lib/env-var → T2. §8 install.sh → T7. §9 support matrix → T8. §10 AGENTS.md → T9. §11 tests/CI → T2/T3/T7 tests + T10 CI. §12 migration sequence/gates → task order; gate #1 T1.S8, gate #2 T3.S5, gate #3 T2 (`pwd -P`), gate #4 T3.S1 (bundled validator removes the `skills-ref` dependency). §13 risks → addressed in the gate steps. §14 success criteria → T11.S2 checklist.

**Placeholder scan:** No "TBD"/"TODO". The `<this-skill-dir>` / `<assembled-json>` / `<branch>` tokens in skill-body edits are literal authored placeholders that ship in the SKILL.md (the agent fills them at runtime), not plan gaps. Every code/test step shows full content.

**Type/name consistency:** `dest_is_ours`, `install_one`, `uninstall_one`, `list_skills`, `targets`, `$STAMP`, `$SKILLS_SRC`, `$LIB_SRC` used consistently across `install.sh` and its tests. Vendored fallback path is `<script-dir>/worktree-config.sh` in both the script edits (T2) and the installer copy step (T7) and the copy test (T7.S2). The validator/lint script names match between their creation tasks and the CI wiring (T10.S4).

**Open decisions resolved in-plan (flagged for override):** `--copy` self-containment = vendor `lib/` beside the script + script-side fallback search (T2/T7), not a `~/.claude/lib` drop. Portability lint = CI-enforced heuristic (T10), proven falsifiable in T10.S3.

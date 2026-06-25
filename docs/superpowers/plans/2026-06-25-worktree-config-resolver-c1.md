# Worktree config resolver (C1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `wt-new.sh`/`wt-rm.sh` resolve the worktree location and mirrored-file list from a new 3-tier `worktree-config.json` marker family via a shared, unit-tested bash lib — and add the repo's first test harness + CI.

**Architecture:** A pure, sourceable resolver (`lib/worktree-config.sh`) reads config fields field-by-field across `local → committed → global → built-in default`, skipping absent/unparseable tiers. Both worktree scripts source it (via `${BASH_SOURCE[0]}`, fail-loud if absent) and use the resolved values. A one-line hook exemption lets the new config files be written on an enforced main checkout. This is C1 of issue [#9](https://github.com/neilwashere/claude-skills/issues/9); `postCreate` (C2), the `configure-worktree` skill (C3), and branch-naming (C4) build on this lib later.

**Tech Stack:** Bash, `jq`, GitHub Actions. No `bats` (plain-bash runner).

## Global Constraints

- **Enforcement behaviour is untouched:** the hook's deny logic and `enforce`/`allowPaths` resolution do not change. The only hook edit is extending `is_allowed_path` to exempt the two `worktree-config*.json` files.
- **Config files (this PR):** `<repo>/.claude/worktree-config.local.json` → `<repo>/.claude/worktree-config.json` → `~/.claude/worktree-config.json` → built-in default. Repo-level files are read from the **main checkout root** (`main_root` = first entry of `git worktree list`).
- **Config fields in C1:** `worktreeDir` (string template), `worktreeLink` (string[] repo-root-relative). `postCreate`/`branchNaming` are out of scope for C1.
- **`worktreeDir` default:** `"{parent}/{repo}.worktrees/{branch}"`. Tokens `{parent}`/`{repo}`/`{branch}` (branch slug `/`→`-`); `~`/`$HOME` expand; relative resolves against `{parent}`; unknown token = error; reject empty or inside-the-main-checkout.
- **`worktreeLink` default:** `[".claude/settings.local.json", ".claude/.credentials.json"]`. Entries repo-root-relative; reject absolute / `..` / empty.
- **Lib resolution:** scripts locate the lib relative to `${BASH_SOURCE[0]}`; a missing lib **fails loud** (broken install), never silently defaults.
- **Self-contained scripts:** the lib is the only new `source`; no `~/.zshrc`. Keep `set -euo pipefail`, stdout-is-the-path contract for `wt-new.sh`.
- Commit messages: conventional type, end with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Branch already exists: `feat/9-config-resolver`.

## File structure

- `tss-git-skills/lib/worktree-config.sh` — NEW, the resolver (`_wtc_field_raw`, `wtc_worktree_dir`, `wtc_worktree_link`).
- `tests/run.sh` — NEW, plain-bash runner + sandbox helpers + `test_*` cases.
- `.github/workflows/test.yml` — NEW, runs `tests/run.sh` on PRs.
- `tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh` — MOD, source lib + use resolved dir/link.
- `tss-git-skills/skills/exit-and-dispose-worktree/scripts/wt-rm.sh` — MOD, source lib + use resolved dir/link.
- `tss-git-skills/skills/setup-worktree-discipline/worktree-discipline.sh` — MOD, extend `is_allowed_path`.
- `tss-git-skills/skills/setup-worktree-discipline/SKILL.md` + READMEs — MOD, document config family + re-`cp`.

---

### Task 1: Test harness + tier-precedence resolver (`_wtc_field_raw`)

**Files:**
- Create: `tss-git-skills/lib/worktree-config.sh`
- Create: `tests/run.sh`

**Interfaces:**
- Produces: `_wtc_field_raw <repo_root> <field>` → prints the compact JSON value of `<field>` from the first tier that defines it (probe order: `$repo_root/.claude/worktree-config.local.json`, `$repo_root/.claude/worktree-config.json`, `$HOME/.claude/worktree-config.json`); skips absent/unparseable files; returns 1 and prints nothing if no tier defines it. Reads `$HOME` (tests override it).

- [ ] **Step 1: Write the failing test (harness + precedence cases)**

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
# tests/run.sh — plain-bash tests for the worktree config resolver.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/tss-git-skills/lib/worktree-config.sh"
# shellcheck source=/dev/null
source "$LIB"

FAILED=0
assert_eq() { # <actual> <expected> <msg>
  if [ "$1" = "$2" ]; then printf 'PASS: %s\n' "$3"
  else printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$3" "$2" "$1"; FAILED=1; fi
}
assert_fails() { # <msg> <cmd...>
  local msg="$1"; shift
  if "$@" >/dev/null 2>&1; then printf 'FAIL: %s (expected non-zero exit)\n' "$msg"; FAILED=1
  else printf 'PASS: %s\n' "$msg"; fi
}

# Make a sandbox: $SB/repo (repo root) and $SB/home (fake HOME). Echoes $SB.
new_sandbox() {
  local sb; sb="$(mktemp -d)"
  mkdir -p "$sb/repo/.claude" "$sb/home/.claude"
  printf '%s' "$sb"
}
wcfg() { printf '%s' "$2" > "$1/repo/.claude/worktree-config.json"; }        # committed
wcfg_local() { printf '%s' "$2" > "$1/repo/.claude/worktree-config.local.json"; }
wcfg_global() { printf '%s' "$2" > "$1/home/.claude/worktree-config.json"; }

test_field_raw_precedence() {
  local sb; sb="$(new_sandbox)"
  wcfg_global "$sb" '{"worktreeDir":"G"}'
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir)" '"G"' "global-only resolves"
  wcfg "$sb" '{"worktreeDir":"C"}'
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir)" '"C"' "committed beats global"
  wcfg_local "$sb" '{"worktreeDir":"L"}'
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir)" '"L"' "local beats committed"
  rm -rf "$sb"
}

test_field_raw_field_level() {
  local sb; sb="$(new_sandbox)"
  wcfg_global "$sb" '{"worktreeDir":"G"}'
  wcfg "$sb" '{"worktreeLink":["x"]}'           # committed defines a DIFFERENT field
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir)" '"G"' "field-level: worktreeDir falls through to global"
  rm -rf "$sb"
}

test_field_raw_skips_malformed() {
  local sb; sb="$(new_sandbox)"
  wcfg "$sb" '{"worktreeDir":"C"}'
  wcfg_local "$sb" 'this is not json'           # malformed local
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir)" '"C"' "malformed local skipped, committed used"
  rm -rf "$sb"
}

test_field_raw_absent() {
  local sb; sb="$(new_sandbox)"
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir; echo "rc=$?")" 'rc=1' "no tier defines field → rc 1, empty"
  rm -rf "$sb"
}

# Run every test_* function.
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do "$t"; done
exit "$FAILED"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `tss-git-skills/lib/worktree-config.sh` does not exist, so `source` errors / functions undefined.

- [ ] **Step 3: Implement the lib's precedence core**

Create `tss-git-skills/lib/worktree-config.sh`:

```bash
#!/usr/bin/env bash
# worktree-config.sh — resolve worktree CONFIG (not enforcement) from the 3-tier
# config marker family. Sourced by wt-new.sh / wt-rm.sh and by tests.
#
# Per field, the first tier that DEFINES it wins; absent/unparseable tiers are
# skipped. Repo-level files are read from <repo_root> = the MAIN checkout root.
#   <repo_root>/.claude/worktree-config.local.json   (gitignored, per-checkout)
#   <repo_root>/.claude/worktree-config.json          (committed, team)
#   $HOME/.claude/worktree-config.json                (user-global)
#   built-in default (handled by the per-field functions below)

# _wtc_field_raw <repo_root> <field>
# Print compact JSON value of <field> from the first defining tier; rc 1 if none.
_wtc_field_raw() {
  local repo_root="$1" field="$2" f
  for f in \
    "$repo_root/.claude/worktree-config.local.json" \
    "$repo_root/.claude/worktree-config.json" \
    "$HOME/.claude/worktree-config.json"
  do
    [ -f "$f" ] || continue
    jq empty "$f" >/dev/null 2>&1 || continue
    if jq -e --arg k "$field" 'has($k)' "$f" >/dev/null 2>&1; then
      jq -c --arg k "$field" '.[$k]' "$f"
      return 0
    fi
  done
  return 1
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh`
Expected: PASS for all four `test_field_raw_*`; exit 0.

- [ ] **Step 5: Commit**

```bash
git add tss-git-skills/lib/worktree-config.sh tests/run.sh
git commit -m "$(printf 'feat: add 3-tier config field resolver + test harness\n\nPart of #9\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 2: `wtc_worktree_dir` — template expansion + validation

**Files:**
- Modify: `tss-git-skills/lib/worktree-config.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Consumes: `_wtc_field_raw` (Task 1).
- Produces: `wtc_worktree_dir <repo_root> <branch>` → prints the resolved, expanded, normalised **absolute** worktree dir; rc 1 + stderr message on unknown token / empty / inside-main-checkout.

- [ ] **Step 1: Write the failing tests**

Append to `tests/run.sh` (before the run loop):

```bash
test_dir_default() {
  local sb; sb="$(new_sandbox)"; local repo="$sb/repo"
  local parent; parent="$(dirname "$repo")"; local name; name="$(basename "$repo")"
  assert_eq "$(HOME="$sb/home" wtc_worktree_dir "$repo" feat/x)" \
    "$parent/$name.worktrees/feat-x" "default template reproduces sibling layout + slug"
  rm -rf "$sb"
}
test_dir_global_template_tokens() {
  local sb; sb="$(new_sandbox)"; local repo="$sb/repo"; local name; name="$(basename "$repo")"
  wcfg_global "$sb" '{"worktreeDir":"~/wt/{repo}/{branch}"}'
  assert_eq "$(HOME="$sb/home" wtc_worktree_dir "$repo" feat/x)" \
    "$sb/home/wt/$name/feat-x" "~ + {repo}/{branch} expansion"
  rm -rf "$sb"
}
test_dir_relative_resolves_against_parent() {
  local sb; sb="$(new_sandbox)"; local repo="$sb/repo"; local parent; parent="$(dirname "$repo")"
  wcfg "$sb" '{"worktreeDir":"trees/{branch}"}'
  assert_eq "$(HOME="$sb/home" wtc_worktree_dir "$repo" main)" "$parent/trees/main" "relative resolves against {parent}"
  rm -rf "$sb"
}
test_dir_unknown_token_errors() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"worktreeDir":"/tmp/{bogus}/x"}'
  assert_fails "unknown token errors" bash -c 'HOME="'"$sb"'/home" wtc_worktree_dir "'"$sb"'/repo" main'
  rm -rf "$sb"
}
test_dir_inside_main_rejected() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"worktreeDir":"{parent}/'"$(basename "$sb/repo")"'/inside"}'
  assert_fails "dir inside main checkout rejected" bash -c 'HOME="'"$sb"'/home" wtc_worktree_dir "'"$sb"'/repo" main'
  rm -rf "$sb"
}
```

Note: `assert_fails` runs the resolver in a subshell that must `source` the lib; since `tests/run.sh` already sourced it, use the in-process function — replace the `bash -c` lines with a small wrapper:

```bash
_try_dir() { HOME="$2" wtc_worktree_dir "$1" "$3"; }
# then: assert_fails "unknown token errors" _try_dir "$sb/repo" "$sb/home" main
```

(Use `_try_dir` in both `assert_fails` cases so the already-sourced functions are visible.)

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/run.sh`
Expected: FAIL — `wtc_worktree_dir: command not found` / undefined.

- [ ] **Step 3: Implement `wtc_worktree_dir`**

Append to `tss-git-skills/lib/worktree-config.sh`:

```bash
# wtc_worktree_dir <repo_root> <branch> → absolute resolved worktree dir.
wtc_worktree_dir() {
  local repo_root="$1" branch="$2" tmpl
  tmpl="$(_wtc_field_raw "$repo_root" worktreeDir | jq -r '.' 2>/dev/null)" || tmpl=""
  [ -n "$tmpl" ] || tmpl='{parent}/{repo}.worktrees/{branch}'

  local repo parent slug
  repo="$(basename "$repo_root")"
  parent="$(dirname "$repo_root")"
  slug="${branch//\//-}"

  # Reject unknown {tokens} before substitution.
  local probe="$tmpl"
  probe="${probe//\{parent\}/}"; probe="${probe//\{repo\}/}"; probe="${probe//\{branch\}/}"
  case "$probe" in
    *'{'*'}'*) echo "worktree-config: unknown token in worktreeDir: $tmpl" >&2; return 1 ;;
  esac

  local out="$tmpl"
  out="${out//\{parent\}/$parent}"; out="${out//\{repo\}/$repo}"; out="${out//\{branch\}/$slug}"

  case "$out" in
    "~")    out="$HOME" ;;
    "~/"*)  out="$HOME/${out#\~/}" ;;
  esac
  out="${out//\$HOME/$HOME}"

  case "$out" in /*) ;; *) out="$parent/$out" ;; esac     # relative → against {parent}
  [ -n "$out" ] || { echo "worktree-config: worktreeDir resolved empty" >&2; return 1; }

  local norm main_norm
  norm="$(realpath -m "$out" 2>/dev/null || printf '%s' "$out")"
  main_norm="$(realpath -m "$repo_root" 2>/dev/null || printf '%s' "$repo_root")"
  case "$norm/" in
    "$main_norm/"*) echo "worktree-config: worktreeDir resolves inside the main checkout ($norm)" >&2; return 1 ;;
  esac

  printf '%s\n' "$norm"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/run.sh`
Expected: PASS for all `test_dir_*`; exit 0. (If `realpath` is unavailable the fallback keeps the raw path — acceptable; CI has it.)

- [ ] **Step 5: Commit**

```bash
git add tss-git-skills/lib/worktree-config.sh tests/run.sh
git commit -m "$(printf 'feat: resolve+validate worktreeDir template\n\nPart of #9\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 3: `wtc_worktree_link` — resolution + validation

**Files:**
- Modify: `tss-git-skills/lib/worktree-config.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Consumes: `_wtc_field_raw` (Task 1).
- Produces: `wtc_worktree_link <repo_root>` → prints resolved repo-root-relative link entries, one per line (default list if unset); rc 1 + stderr on absolute/`..`/empty entry.

- [ ] **Step 1: Write the failing tests**

Append to `tests/run.sh`:

```bash
test_link_default() {
  local sb; sb="$(new_sandbox)"
  assert_eq "$(HOME="$sb/home" wtc_worktree_link "$sb/repo" | paste -sd, -)" \
    ".claude/settings.local.json,.claude/.credentials.json" "default link list"
  rm -rf "$sb"
}
test_link_override_with_env() {
  local sb; sb="$(new_sandbox)"
  wcfg "$sb" '{"worktreeLink":[".claude/settings.local.json",".env"]}'
  assert_eq "$(HOME="$sb/home" wtc_worktree_link "$sb/repo" | paste -sd, -)" \
    ".claude/settings.local.json,.env" "override includes repo-root .env"
  rm -rf "$sb"
}
_try_link() { HOME="$2" wtc_worktree_link "$1"; }
test_link_rejects_absolute() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"worktreeLink":["/etc/passwd"]}'
  assert_fails "absolute link entry rejected" _try_link "$sb/repo" "$sb/home"; rm -rf "$sb"
}
test_link_rejects_dotdot() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"worktreeLink":["../secret"]}'
  assert_fails "'..' link entry rejected" _try_link "$sb/repo" "$sb/home"; rm -rf "$sb"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/run.sh`
Expected: FAIL — `wtc_worktree_link` undefined.

- [ ] **Step 3: Implement `wtc_worktree_link`**

Append to `tss-git-skills/lib/worktree-config.sh`:

```bash
# wtc_worktree_link <repo_root> → repo-root-relative link entries, one per line.
wtc_worktree_link() {
  local repo_root="$1" raw
  raw="$(_wtc_field_raw "$repo_root" worktreeLink)" \
    || raw='[".claude/settings.local.json",".claude/.credentials.json"]'
  local entries e
  mapfile -t entries < <(printf '%s' "$raw" | jq -r '.[]') || return 1
  for e in "${entries[@]}"; do
    case "$e" in
      "")     echo "worktree-config: empty worktreeLink entry" >&2; return 1 ;;
      /*)     echo "worktree-config: absolute worktreeLink entry not allowed: $e" >&2; return 1 ;;
      *..*)   echo "worktree-config: '..' not allowed in worktreeLink entry: $e" >&2; return 1 ;;
    esac
    printf '%s\n' "$e"
  done
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/run.sh`
Expected: PASS for all `test_link_*`; exit 0.

- [ ] **Step 5: Commit**

```bash
git add tss-git-skills/lib/worktree-config.sh tests/run.sh
git commit -m "$(printf 'feat: resolve+validate worktreeLink list\n\nPart of #9\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 4: Wire `wt-new.sh` to the lib (source-guard + resolved dir/link)

**Files:**
- Modify: `tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh`
- Modify: `tests/run.sh` (integration test)

**Interfaces:**
- Consumes: `wtc_worktree_dir`, `wtc_worktree_link`.
- Produces: `wt-new.sh` creates the worktree at the resolved dir and links the resolved files; stdout still exactly the path; errors loudly if the lib is missing.

- [ ] **Step 1: Write the failing integration test**

Append to `tests/run.sh`:

```bash
test_wtnew_uses_configured_dir() {
  local sb; sb="$(mktemp -d)"
  local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"worktreeDir":"%s/trees/{branch}"}' "$sb" > "$repo/.claude/worktree-config.json"
  local out
  out="$( cd "$repo" && HOME="$sb/home" bash "$ROOT/tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main 2>/dev/null )"
  assert_eq "$out" "$sb/trees/feat-x" "wt-new creates worktree at configured dir"
  [ -d "$sb/trees/feat-x" ] && printf 'PASS: %s\n' "configured worktree dir exists" || { printf 'FAIL: configured dir missing\n'; FAILED=1; }
  rm -rf "$sb"
}
test_wtnew_fails_loud_without_lib() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  cp -r "$ROOT/tss-git-skills" "$sb/plugin"
  rm -f "$sb/plugin/lib/worktree-config.sh"
  assert_fails "wt-new fails loud when lib missing" bash -c \
    'cd "'"$repo"'" && HOME="'"$sb"'/home" bash "'"$sb"'/plugin/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main'
  rm -rf "$sb"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/run.sh`
Expected: FAIL — `wt-new.sh` still uses its hard-coded `dir=…` and ignores config; configured-dir test mismatches.

- [ ] **Step 3: Implement the wiring**

In `tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh`, after `set -euo pipefail` (line 30), add the source guard:

```bash
# Resolve the shared config lib relative to THIS script (fail loud if absent —
# it ships with the plugin; a missing copy means a broken install).
_WTN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_WTC_LIB="$_WTN_DIR/../../../lib/worktree-config.sh"
if [ ! -f "$_WTC_LIB" ]; then
  echo "wt-new: missing config lib at $_WTC_LIB (broken plugin install)" >&2; exit 1
fi
# shellcheck source=/dev/null
. "$_WTC_LIB"
```

Replace the hard-coded dir (line 67 `dir="${parent}/${repo}.worktrees/${branch//\//-}"`) with:

```bash
dir="$(wtc_worktree_dir "$main_root" "$branch")" || exit 1
```

Replace the hard-coded link loop inside `link_claude` (lines 53-57, `for f in settings.local.json .credentials.json; do … ln -s "$main_abs/.claude/$f" "$wt_abs/.claude/$f" …`) with a resolved, repo-root-relative loop:

```bash
    local rel src dst
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      src="$main_abs/$rel"; dst="$wt_abs/$rel"
      if [ -e "$src" ] && [ ! -e "$dst" ]; then
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst" && echo "$rel linked to main repo" >&2
      fi
    done < <(wtc_worktree_link "$main_abs")
```

(Keep the surrounding `if [[ -d "$main_abs/.claude" ]]; then mkdir -p "$wt_abs/.claude"; … fi` guard, but the loop now handles arbitrary repo-root-relative paths and makes parent dirs itself, so the entries drive the structure.)

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/run.sh`
Expected: PASS for `test_wtnew_uses_configured_dir`, `configured worktree dir exists`, and `test_wtnew_fails_loud_without_lib`; all earlier tests still PASS; exit 0.

- [ ] **Step 5: Commit**

```bash
git add tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh tests/run.sh
git commit -m "$(printf 'feat: wt-new.sh resolves worktreeDir/worktreeLink via shared lib\n\nPart of #9\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 5: Wire `wt-rm.sh` to the lib (resolved fallback dir + unlink list)

**Files:**
- Modify: `tss-git-skills/skills/exit-and-dispose-worktree/scripts/wt-rm.sh`
- Modify: `tests/run.sh` (integration test)

**Interfaces:**
- Consumes: `wtc_worktree_dir`, `wtc_worktree_link`.
- Produces: `wt-rm.sh` finds the tree (git-list-first, unchanged) and unlinks the resolved link entries; its path-construction fallback uses the resolved `worktreeDir`. Fail-loud if lib missing.

- [ ] **Step 1: Write the failing integration test**

Append to `tests/run.sh`:

```bash
test_wtrm_removes_configured_dir() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"worktreeDir":"%s/trees/{branch}"}' "$sb" > "$repo/.claude/worktree-config.json"
  ( cd "$repo" && HOME="$sb/home" bash "$ROOT/tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main ) >/dev/null 2>&1
  ( cd "$repo" && HOME="$sb/home" bash "$ROOT/tss-git-skills/skills/exit-and-dispose-worktree/scripts/wt-rm.sh" feat/x ) >/dev/null 2>&1
  [ ! -d "$sb/trees/feat-x" ] && printf 'PASS: %s\n' "wt-rm removed configured-dir worktree" \
    || { printf 'FAIL: configured-dir worktree still present\n'; FAILED=1; }
  rm -rf "$sb"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/run.sh`
Expected: PASS already IF git-list lookup finds it regardless of layout — but to guard the fallback path and the unlink list, proceed to wire the lib. (If it passes pre-change, the wiring below still adds the fail-loud guard and resolved unlink; keep the test as a regression guard.)

- [ ] **Step 3: Implement the wiring**

In `tss-git-skills/skills/exit-and-dispose-worktree/scripts/wt-rm.sh`, after `set -euo pipefail` (line 13), add the same source guard (path is identical depth):

```bash
_WTR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_WTC_LIB="$_WTR_DIR/../../../lib/worktree-config.sh"
if [ ! -f "$_WTC_LIB" ]; then
  echo "wt-rm: missing config lib at $_WTC_LIB (broken plugin install)" >&2; exit 1
fi
# shellcheck source=/dev/null
. "$_WTC_LIB"
```

Replace the fallback path construction (lines 37-38, `repo="$(basename "$main_root")"; parent="$(dirname "$main_root")"; dir="${parent}/${repo}.worktrees/${branch//\//-}"`) with:

```bash
    dir="$(wtc_worktree_dir "$main_root" "$branch")" || exit 1
```

Replace the hard-coded unlink loop (lines 60-61, `for f in settings.local.json .credentials.json; do [[ -L "$dir/.claude/$f" ]] && rm "$dir/.claude/$f"; done`) with a resolved loop that removes only symlinks pointing back into the main repo:

```bash
main_real="$(cd "$main_root" && pwd -P)"
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  local_dst="$dir/$rel"
  if [ -L "$local_dst" ]; then
    tgt="$(readlink "$local_dst")"
    case "$tgt" in "$main_real"/*|"$main_root"/*) rm "$local_dst" ;; esac
  fi
done < <(wtc_worktree_link "$main_root")
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/run.sh`
Expected: PASS for `test_wtrm_removes_configured_dir`; all earlier tests PASS; exit 0.

- [ ] **Step 5: Commit**

```bash
git add tss-git-skills/skills/exit-and-dispose-worktree/scripts/wt-rm.sh tests/run.sh
git commit -m "$(printf 'feat: wt-rm.sh resolves worktreeDir/worktreeLink via shared lib\n\nPart of #9\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 6: Hook exemption for the config files

**Files:**
- Modify: `tss-git-skills/skills/setup-worktree-discipline/worktree-discipline.sh:103`
- Modify: `tests/run.sh` (hook-exemption test)

**Interfaces:**
- Produces: the hook's `is_allowed_path` returns 0 (allow) for `.claude/worktree-config.json` and `.claude/worktree-config.local.json`, so writes to them on an enforced main checkout are permitted. Deny logic otherwise unchanged.

- [ ] **Step 1: Write the failing test**

Append to `tests/run.sh`:

```bash
test_hook_exempts_config_markers() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"enforce":true}' > "$repo/.claude/worktree-discipline.json"   # enforced main checkout
  local hook="$ROOT/tss-git-skills/skills/setup-worktree-discipline/worktree-discipline.sh"
  local ev
  for name in worktree-config.json worktree-config.local.json; do
    ev="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/%s"}}' "$repo" "$name")"
    out="$( cd "$repo" && printf '%s' "$ev" | bash "$hook" 2>/dev/null )"
    case "$out" in
      *'"permissionDecision":"deny"'*|*'"permissionDecision": "deny"'*)
        printf 'FAIL: hook denied .claude/%s on enforced main\n' "$name"; FAILED=1 ;;
      *) printf 'PASS: hook allows .claude/%s\n' "$name" ;;
    esac
  done
  rm -rf "$sb"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/run.sh`
Expected: FAIL — the hook currently denies a Write to `.claude/worktree-config.json` (not yet exempted).

- [ ] **Step 3: Implement the exemption**

In `tss-git-skills/skills/setup-worktree-discipline/worktree-discipline.sh`, line 103, extend the `is_allowed_path` case:

```bash
    .claude/worktree-discipline.json|.claude/worktree-discipline.local.json|.claude/worktree-config.json|.claude/worktree-config.local.json) return 0 ;;
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/run.sh`
Expected: PASS for both config markers; all earlier tests PASS; exit 0.

- [ ] **Step 5: Commit**

```bash
git add tss-git-skills/skills/setup-worktree-discipline/worktree-discipline.sh tests/run.sh
git commit -m "$(printf 'feat: exempt worktree-config markers from the discipline hook\n\nDeny logic unchanged; only the self-exemption allow-list grows.\n\nPart of #9\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 7: CI workflow + docs

**Files:**
- Create: `.github/workflows/test.yml`
- Modify: `tss-git-skills/skills/setup-worktree-discipline/SKILL.md`
- Modify: `tss-git-skills/README.md` and `README.md`

**Interfaces:** none (CI + docs).

- [ ] **Step 1: Add the CI workflow**

Create `.github/workflows/test.yml`:

```yaml
name: tests
on:
  pull_request:
  push:
    branches: [main]
jobs:
  bash-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Ensure jq
        run: jq --version || (sudo apt-get update && sudo apt-get install -y jq)
      - name: Run resolver tests
        run: bash tests/run.sh
```

- [ ] **Step 2: Verify the suite runs green locally (proxy for CI)**

Run: `bash tests/run.sh; echo "exit=$?"`
Expected: every line `PASS:`, final `exit=0`.

- [ ] **Step 3: Document the config marker family + re-cp**

In `tss-git-skills/skills/setup-worktree-discipline/SKILL.md`, under *Update the installed hook*, add a line noting that after this change the installed hook must be re-copied (it now exempts `worktree-config*.json`); and under the marker docs note the separate **config** marker family (`worktree-config.json` / `.local.json` / `~/.claude/worktree-config.json`) read by `wt-new`/`wt-rm`, distinct from the enforcement marker. Add to both READMEs a one-line pointer that worktree creation reads `worktree-config.json` (see the #9 spec).

```bash
# (prose edits — keep them short; the spec is the source of truth)
```

- [ ] **Step 4: Final full-suite run**

Run: `bash tests/run.sh; echo "exit=$?"`
Expected: all `PASS`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/test.yml tss-git-skills/skills/setup-worktree-discipline/SKILL.md tss-git-skills/README.md README.md
git commit -m "$(printf 'ci: run resolver test suite on PRs; document config marker family\n\nPart of #9\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Self-review

- **Spec coverage:** `worktreeDir` resolution+validation (T2), `worktreeLink` repo-root-relative+validation (T3), field-level 3-tier precedence + skip-malformed (T1), main-checkout-root reads (resolver takes `main_root`; T4/T5 pass `$main_root`), `${BASH_SOURCE[0]}` + fail-loud lib (T4/T5), hook exemption (T6), tests + first CI (T1-T7). `postCreate`/`branchNaming`/`configure-worktree` are explicitly **C2-C4**, not this plan. ✓
- **Placeholders:** none — every code step has complete bash/yaml. The only prose-only step is T7/Step 3 (doc edits), which points at the spec rather than inventing copy. ✓
- **Type/name consistency:** `_wtc_field_raw`, `wtc_worktree_dir`, `wtc_worktree_link` used identically across T1-T6; lib path `../../../lib/worktree-config.sh` identical from both script dirs (both are `skills/<name>/scripts/`, three levels under the plugin root). ✓
- **Known limitation:** `realpath -m` is assumed present (GNU coreutils; ubuntu CI has it). Fallback keeps the raw path so non-GNU dev machines still function for the common absolute-path case.

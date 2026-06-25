# configure-worktree skill (C3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a user-invoked `configure-worktree` skill that runs an `AskUserQuestion` flow and writes the chosen worktree-config fields to a chosen tier (`global`/`committed`/`local`) of the `worktree-config.json` marker family.

**Architecture:** A bundled `configure-worktree.sh` does the file work — it reads a JSON object of fields from stdin and merges it (stdin wins per key) into the chosen tier file, staging the committed file or gitignoring the local one. The `SKILL.md` drives the interactive part: Claude asks the questions, assembles the JSON from the answers, and pipes it to the script. Builds on C1/C2 (merged).

**Tech Stack:** Bash, `jq`, the harness `AskUserQuestion` tool. Tests via existing `tests/run.sh`; CI from C1.

## Global Constraints

- Config marker family (C1): `worktree-config.local.json` / `worktree-config.json` / `~/.claude/worktree-config.json`. Fields: `worktreeDir`, `worktreeLink`, `postCreate`, `branchNaming`. The resolver reads committed/local from the **main checkout root**, so configure WRITES committed/local there too (resolve `main_root` = first `git worktree list` entry).
- Enforcement is untouched; the hook already exempts `worktree-config*.json` (C1), so writing them on an enforced main checkout is permitted.
- `configure-worktree` is **user-invoked** (`disable-model-invocation: true`), like the other config/enforce skills.
- Merge semantics: new fields override existing same-name keys in the target tier; other existing keys are preserved (`jq '$a * $b'`, b = stdin).
- Only write fields the user actively chose; leave a field unset (so the built-in default applies) when the user picks the default/"no change" option — don't write the default value literally.
- Commit messages: conventional type; end with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Branch: `feat/9-configure-worktree`.

## File structure

- `tss-git-skills/skills/configure-worktree/scripts/configure-worktree.sh` — NEW, the tier writer.
- `tss-git-skills/skills/configure-worktree/SKILL.md` — NEW, the AskUserQuestion flow.
- `tests/run.sh` — MOD, add `test_configure_*`.
- `tss-git-skills/README.md` + repo-root `README.md` — MOD, list the new skill.

---

### Task 1: `configure-worktree.sh` tier writer

**Files:**
- Create: `tss-git-skills/skills/configure-worktree/scripts/configure-worktree.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Produces: `configure-worktree.sh <global|committed|local>` reads a JSON object from stdin and merges it into the chosen tier of `worktree-config*.json` (committed/local under `main_root/.claude/`, global under `$HOME/.claude/`). Stages the committed file; gitignores the local file. Exits non-zero on a bad scope or non-object stdin.

- [ ] **Step 1: Write the failing tests** — append BEFORE the run loop in `tests/run.sh`:

```bash
_cfg_repo() { # echo a fresh temp repo path with git initialised
  local sb="$1"; mkdir -p "$sb/repo"
  ( cd "$sb/repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '%s' "$sb/repo"
}
CFG="$ROOT/tss-git-skills/skills/configure-worktree/scripts/configure-worktree.sh"

test_configure_committed_writes_and_stages() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfg_repo "$sb")"
  ( cd "$repo" && printf '{"worktreeDir":"X/{branch}"}' | HOME="$sb/home" bash "$CFG" committed ) >/dev/null 2>&1
  assert_eq "$(jq -r '.worktreeDir' "$repo/.claude/worktree-config.json")" "X/{branch}" "committed worktreeDir written"
  ( cd "$repo" && git diff --cached --name-only ) | grep -qx ".claude/worktree-config.json" \
    && printf 'PASS: %s\n' "committed file staged" || { printf 'FAIL: committed file not staged\n'; FAILED=1; }
  rm -rf "$sb"
}
test_configure_merges_existing() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfg_repo "$sb")"
  mkdir -p "$repo/.claude"; printf '{"worktreeLink":[".env"]}' > "$repo/.claude/worktree-config.json"
  ( cd "$repo" && printf '{"worktreeDir":"X"}' | HOME="$sb/home" bash "$CFG" committed ) >/dev/null 2>&1
  assert_eq "$(jq -r '.worktreeLink[0]' "$repo/.claude/worktree-config.json")" ".env" "existing key preserved on merge"
  assert_eq "$(jq -r '.worktreeDir' "$repo/.claude/worktree-config.json")" "X" "new key added on merge"
  rm -rf "$sb"
}
test_configure_local_gitignores() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfg_repo "$sb")"
  ( cd "$repo" && printf '{"postCreate":"npm install"}' | HOME="$sb/home" bash "$CFG" local ) >/dev/null 2>&1
  assert_eq "$(jq -r '.postCreate' "$repo/.claude/worktree-config.local.json")" "npm install" "local file written"
  grep -qx ".claude/worktree-config.local.json" "$repo/.gitignore" \
    && printf 'PASS: %s\n' "local file gitignored" || { printf 'FAIL: local not gitignored\n'; FAILED=1; }
  rm -rf "$sb"
}
test_configure_global() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfg_repo "$sb")"
  ( cd "$repo" && printf '{"worktreeDir":"G/{branch}"}' | HOME="$sb/home" bash "$CFG" global ) >/dev/null 2>&1
  assert_eq "$(jq -r '.worktreeDir' "$sb/home/.claude/worktree-config.json")" "G/{branch}" "global file written under HOME"
  rm -rf "$sb"
}
_cfg_try() { printf '%s' "$3" | HOME="$2" bash "$CFG" "$1"; }
test_configure_bad_scope() {
  local sb; sb="$(mktemp -d)"
  assert_fails "bad scope rejected" _cfg_try bogus "$sb/home" '{"worktreeDir":"X"}'
  rm -rf "$sb"
}
test_configure_bad_json() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfg_repo "$sb")"
  assert_fails "non-object stdin rejected" bash -c 'cd "'"$repo"'" && printf "notjson" | HOME="'"$sb"'/home" bash "'"$CFG"'" committed'
  rm -rf "$sb"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/run.sh`
Expected: FAIL — `configure-worktree.sh` does not exist.

- [ ] **Step 3: Implement the script** — create `tss-git-skills/skills/configure-worktree/scripts/configure-worktree.sh`:

```bash
#!/usr/bin/env bash
# configure-worktree.sh — write worktree CONFIG to a chosen tier of the
# worktree-config marker family. Reads a JSON object of fields from stdin and
# merges it (stdin wins per key) over any existing tier file. Companion to the
# configure-worktree skill. Does NOT touch enforcement (worktree-discipline.json).
#
# Usage:  <json-object-on-stdin> | configure-worktree.sh <global|committed|local>
set -euo pipefail

scope="${1:?usage: configure-worktree.sh <global|committed|local>  (JSON object on stdin)}"
case "$scope" in
  global|committed|local) ;;
  *) echo "configure-worktree: scope must be global|committed|local" >&2; exit 2 ;;
esac

payload="$(cat)"
printf '%s' "$payload" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || { echo "configure-worktree: stdin must be a JSON object" >&2; exit 2; }

# committed/local land at the MAIN checkout root (where the resolver reads them).
main_root="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
if [ "$scope" != "global" ] && [ -z "$main_root" ]; then
  echo "configure-worktree: not inside a git repository" >&2; exit 1
fi

case "$scope" in
  global)    target="$HOME/.claude/worktree-config.json" ;;
  committed) target="$main_root/.claude/worktree-config.json" ;;
  local)     target="$main_root/.claude/worktree-config.local.json" ;;
esac

mkdir -p "$(dirname "$target")"
existing='{}'
if [ -f "$target" ] && jq empty "$target" >/dev/null 2>&1; then
  existing="$(cat "$target")"
fi
merged="$(jq -n --argjson a "$existing" --argjson b "$payload" '$a * $b')"
printf '%s\n' "$merged" > "$target"
echo "configure-worktree: wrote $scope config -> $target" >&2

if [ "$scope" = "committed" ]; then
  git -C "$main_root" add "$target" >/dev/null 2>&1 || true
  echo "  staged — commit it to share the policy" >&2
elif [ "$scope" = "local" ]; then
  gi="$main_root/.gitignore"; rel=".claude/worktree-config.local.json"
  if [ ! -f "$gi" ] || ! grep -qxF "$rel" "$gi"; then
    printf '%s\n' "$rel" >> "$gi"; echo "  gitignored $rel" >&2
  fi
fi
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/run.sh`
Expected: PASS for all `test_configure_*`; all C1/C2 tests still pass; exit 0.

- [ ] **Step 5: Commit**

```bash
chmod +x tss-git-skills/skills/configure-worktree/scripts/configure-worktree.sh
git add tss-git-skills/skills/configure-worktree/scripts/configure-worktree.sh tests/run.sh
git commit -m "$(printf 'feat: configure-worktree.sh writes config to a chosen tier\n\nPart of #9\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 2: `configure-worktree` SKILL.md + READMEs

**Files:**
- Create: `tss-git-skills/skills/configure-worktree/SKILL.md`
- Modify: `tss-git-skills/README.md`, repo-root `README.md`

**Interfaces:**
- Consumes: `configure-worktree.sh` (Task 1).

- [ ] **Step 1: Create the SKILL.md**

Create `tss-git-skills/skills/configure-worktree/SKILL.md` with exactly:

````markdown
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

Ask the four questions below with the `AskUserQuestion` tool, assemble a JSON
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
4. **Scope** — "Where should this config live?"
   - *Global* — `~/.claude/worktree-config.json` (all your repos). Scope = `global`.
   - *Committed (team)* — `.claude/worktree-config.json`, shared via git. Scope = `committed`.
   - *Just me (local)* — `.claude/worktree-config.local.json`, gitignored. Scope = `local`.

If the user kept every field at its default, say so and skip writing (nothing to set).

## Notes

- `branchNaming.embedIssueId` can also be set here if the user asks; default is `true`.
- Run it from inside the target repo (committed/local write to the main checkout root). Global works anywhere.
- This skill writes config only. For enforcement on/off, use `worktree-enforce in|out`.
````

- [ ] **Step 2: List the skill in the plugin README** — in `tss-git-skills/README.md`, under the **User-invoked** section, add a bullet (match the existing bullet style):

```markdown
- **[configure-worktree](./skills/configure-worktree/SKILL.md)** — Guided `AskUserQuestion` setup for the worktree-config marker family (worktree location, files to mirror, post-create command, branch naming) at global / committed / local scope. Config only — enforcement stays with `worktree-enforce`.
```

- [ ] **Step 3: Mention it in the root README** — in `README.md`, under the **User-invoked** list, add a matching one-line bullet linking to `./tss-git-skills/skills/configure-worktree/SKILL.md`.

- [ ] **Step 4: Verify suite still green** (no code changed, but confirm nothing broke)

Run: `bash tests/run.sh; echo "exit=$?"`
Expected: all PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tss-git-skills/skills/configure-worktree/SKILL.md tss-git-skills/README.md README.md
git commit -m "$(printf 'feat: add configure-worktree guided setup skill + READMEs\n\nPart of #9\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Self-review

- **Spec coverage:** new user-invoked skill (T2) with the Q1-Q4 flow incl. the three-way scope picker; `configure-worktree.sh` writes committed (staged) / local (gitignored) / global tiers and merges (T1); reuses worktree-enforce's stage+gitignore patterns; writes config only (enforcement untouched). branchNaming.embedIssueId noted (C4 will lean on it). ✓
- **Placeholders:** none — full script + full SKILL.md + README bullets given verbatim. ✓
- **Consistency:** `configure-worktree.sh <scope>` + stdin-JSON contract identical across script, tests, and SKILL invocation; tier paths match C1's resolver (main_root for committed/local, $HOME for global). ✓

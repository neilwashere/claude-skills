# Worktree postCreate (C2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make the post-create command configurable via `postCreate` in the worktree-config marker, surfaced (not auto-run) by `wt-new.sh`, replacing the hard-coded `npm install` assumption in the create skill.

**Architecture:** Add `wtc_post_create` to the existing `lib/worktree-config.sh` (same 3-tier resolution). `wt-new.sh` prints one `postCreate: <cmd>` line to stderr per command — never executes them (protects the stdout-is-the-path contract). The create-and-enter SKILL tells the human/agent to run whatever `wt-new` printed. Builds on C1 (merged).

**Tech Stack:** Bash, `jq`. Tests via existing `tests/run.sh`; CI already in place from C1.

## Global Constraints

- Config family + resolution are C1's (`local → committed → global → built-in default`, field-level, skip absent/unparseable). `postCreate` reads from `<main_root>/.claude/worktree-config.{local.,}json` and `~/.claude/worktree-config.json`.
- `postCreate` type: string OR string[]. Default: none (absent → no output, no note).
- **wt-new emits one `postCreate: <cmd>` line to stderr per command** (string → 1 line; array → 1 per element); empty entries skipped; NEVER executed. stdout stays exactly the worktree path.
- Resolution reads from the **main checkout root** (`main_root`).
- Lib sourced via `${BASH_SOURCE[0]}`, fail-loud if missing (already wired in C1).
- Commit messages: conventional type; end with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Branch: `feat/9-postcreate`.

## File structure

- `tss-git-skills/lib/worktree-config.sh` — MOD, add `wtc_post_create`.
- `tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh` — MOD, emit postCreate notes to stderr.
- `tss-git-skills/skills/create-and-enter-worktree/SKILL.md` — MOD, de-bias npm prose.
- `tests/run.sh` — MOD, add `test_postcreate_*` + a wt-new emission test.

---

### Task 1: `wtc_post_create` resolver

**Files:**
- Modify: `tss-git-skills/lib/worktree-config.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Consumes: `_wtc_field_raw` (C1).
- Produces: `wtc_post_create <repo_root>` → prints each post-create command on its own line (string → 1 line, array → 1 per element); prints nothing and returns 0 when `postCreate` is absent.

- [ ] **Step 1: Write the failing tests** — append BEFORE the run loop in `tests/run.sh`:

```bash
test_postcreate_absent() {
  local sb; sb="$(new_sandbox)"
  assert_eq "$(HOME="$sb/home" wtc_post_create "$sb/repo")" "" "absent postCreate → no output"
  rm -rf "$sb"
}
test_postcreate_string() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"postCreate":"npm install"}'
  assert_eq "$(HOME="$sb/home" wtc_post_create "$sb/repo")" "npm install" "string postCreate → one line"
  rm -rf "$sb"
}
test_postcreate_array() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"postCreate":["npm ci","npm run build"]}'
  assert_eq "$(HOME="$sb/home" wtc_post_create "$sb/repo" | paste -sd'|' -)" "npm ci|npm run build" "array postCreate → one line each"
  rm -rf "$sb"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/run.sh`
Expected: FAIL — `wtc_post_create` undefined.

- [ ] **Step 3: Implement `wtc_post_create`** — append to `tss-git-skills/lib/worktree-config.sh`:

```bash
# wtc_post_create <repo_root> → each post-create command on its own line.
# Prints nothing (rc 0) when postCreate is absent. Never executes anything.
wtc_post_create() {
  local repo_root="$1" raw
  raw="$(_wtc_field_raw "$repo_root" postCreate)" || return 0
  printf '%s' "$raw" | jq -r 'if type=="array" then .[] else . end'
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/run.sh`
Expected: PASS for all `test_postcreate_*`; all C1 tests still pass; exit 0.

- [ ] **Step 5: Commit**

```bash
git add tss-git-skills/lib/worktree-config.sh tests/run.sh
git commit -m "$(printf 'feat: resolve postCreate (string|array) from worktree config\n\nPart of #9\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 2: wt-new emits postCreate notes + de-bias npm prose

**Files:**
- Modify: `tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh`
- Modify: `tss-git-skills/skills/create-and-enter-worktree/SKILL.md`
- Modify: `tests/run.sh`

**Interfaces:**
- Consumes: `wtc_post_create` (Task 1).
- Produces: `wt-new.sh` prints `postCreate: <cmd>` lines to **stderr** after creating the worktree; stdout still exactly the path.

- [ ] **Step 1: Write the failing test** — append BEFORE the run loop:

```bash
test_wtnew_emits_postcreate_to_stderr() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"worktreeDir":"%s/trees/{branch}","postCreate":"npm install"}' "$sb" > "$repo/.claude/worktree-config.json"
  local out err
  out="$( cd "$repo" && HOME="$sb/home" bash "$ROOT/tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main 2>"$sb/err" )"
  err="$(cat "$sb/err")"
  assert_eq "$out" "$sb/trees/feat-x" "stdout is exactly the path (no postCreate leak)"
  case "$err" in *"postCreate: npm install"*) printf 'PASS: %s\n' "postCreate note on stderr" ;; *) printf 'FAIL: postCreate note missing from stderr\n'; FAILED=1 ;; esac
  rm -rf "$sb"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/run.sh`
Expected: FAIL — no `postCreate:` note emitted yet.

- [ ] **Step 3: Implement the emission** — in `tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh`, after `link_claude "$dir" "$main_root"` and the `echo "Worktree ready at ..." >&2` line, but BEFORE the final `echo "$dir"` (the stdout path), add:

```bash
# Surface (do NOT run) configured post-create commands, one per line, to stderr.
pc="$(wtc_post_create "$main_root")" || true
if [ -n "$pc" ]; then
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    echo "postCreate: $cmd" >&2
  done <<< "$pc"
fi
```

(Place the same surfacing for the early "existing worktree" return path too — after its `echo "Existing worktree: ..." >&2`, before `echo "$existing"` — so resuming a worktree also prints the note. Use `wtc_post_create "$main_root"`.)

- [ ] **Step 4: De-bias the npm prose** — in `tss-git-skills/skills/create-and-enter-worktree/SKILL.md`, replace the *After entering* paragraph:

Old:
```
A fresh worktree does NOT share `node_modules` (npm workspaces). If your repo uses workspaces, run `npm install` in the worktree before relying on a local build or test run.
```
New:
```
A fresh worktree starts clean — it does not share `node_modules`, build caches, or other gitignored artifacts. If your repo configures `postCreate` (in `worktree-config.json`), `wt-new.sh` prints those commands on stderr as `postCreate: <cmd>` notes; run them in the worktree before relying on a local build or test run. (No `postCreate` configured → no notes; e.g. a Node repo would set `postCreate: "npm install"`.)
```

- [ ] **Step 5: Run to verify pass**

Run: `bash tests/run.sh`
Expected: PASS for `test_wtnew_emits_postcreate_to_stderr` (both assertions) and all prior tests; exit 0.

- [ ] **Step 6: Commit**

```bash
git add tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh tss-git-skills/skills/create-and-enter-worktree/SKILL.md tests/run.sh
git commit -m "$(printf 'feat: surface postCreate notes from wt-new; de-bias npm prose\n\nPart of #9\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Self-review

- **Spec coverage:** `wtc_post_create` string|array|absent (T1); wt-new stderr emission one-line-per-command + stdout-contract preserved (T2); npm de-bias (T2). `postCreate` is printed-not-run per spec. ✓
- **Placeholders:** none — complete code in every code step; the one prose step is the SKILL paragraph, given verbatim. ✓
- **Consistency:** `wtc_post_create` signature identical across T1/T2; reads `main_root`; capture-then-iterate avoids the process-substitution swallow pattern (C1 lesson). ✓

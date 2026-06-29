# Multi-model review → learning loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a new `tss-review-skills` plugin with two skills — `review-changes` (dispatch a variable panel of reviewer models → a canonical JSON findings ledger → an address-loop) and `synthesize-review-learnings` (ledgers → an anonymised, self-converging lesson library) — and seed the library by decomposing the existing verification essay.

**Architecture:** A JSON findings ledger is the stable interface: reviewers write per-reviewer files, a shipped `merge-findings.sh` collapses them into `ledger.json`; an optional `post-to-pr.sh` renders the ledger to GitHub inline comments. `synthesize-review-learnings` harvests ledgers into `docs/contributing/lessons/*.md` + `INDEX.md`, deduping-and-strengthening so the corpus converges. Skill prose is portable; reviewer dispatch is delegated to the host harness.

**Tech Stack:** Bash (`set -euo pipefail`, shellcheck 0.11.0-clean), `jq`, Claude Code plugin/marketplace JSON manifests, markdown SKILL.md skills. Tests are `test_*` functions in `tests/run.sh`.

## Global Constraints

- **Source spec:** `docs/superpowers/specs/2026-06-29-multi-model-review-and-learn-design.md` — authoritative for all prose content.
- **Plugin name:** `tss-review-skills`; skills `review-changes`, `synthesize-review-learnings`; namespaced `tss-review-skills:<skill>`.
- **10 fixed dimension keys** (one vocabulary, no drift): `logic`, `error-handling`, `testing`, `architecture`, `abstractions`, `conciseness`, `maintainability`, `documentation`, `security`, `conventions`.
- **Severity values:** `high`, `low`, `medium`; display `🔴 HIGH` / `🟠 MEDIUM` / `🟢 LOW`.
- **Ledger status values:** `open`, `addressed`, `wontfix`, `disputed`.
- **Anonymisation boundary** is the ledger→lesson step: lessons carry PR sources but **no model names**.
- **Every shell file** must be shellcheck-0.11.0-clean (CI gate over `find . -name '*.sh'`). Embed `# shellcheck disable=SC2016` in scripts whose jq programs reference `$jqvars` in single quotes.
- **All scripts:** `#!/usr/bin/env bash`, `set -euo pipefail`, guard-then-act, write-to-temp-then-`mv` for any file they produce, abort loudly (never write a partial artifact, never swallow an error).
- **TDD:** every test must be watched to FAIL before its implementation lands.
- **Work happens in the `feat/review-skills` worktree;** commit after every task.

### Plan convention — code vs prose

For **scripts, tests, schemas, and manifests** this plan gives complete, runnable
content. For **prose deliverables** (`SKILL.md`, `reviewer-charter.md`, lesson
bodies) it gives exact frontmatter, the required section list, and the
load-bearing content each must carry, with the instruction to draw the prose from
the cited design-spec section. That is deliberate: copying a 300-line skill body
verbatim into the plan would make the plan the deliverable. Acceptance for prose
files is a structural test (frontmatter keys, referenced files resolve).

### Deviation from spec (surface to user)

- **Dedup key.** The spec describes dedup on *overlapping line-range*. v1
  `merge-findings.sh` implements exact `(dimension, file, line)` tuple dedup
  (transitive range-overlap merge is union-find, impractical in pure `jq`). This is
  a documented simplification, not a silent cap; overlapping-range is logged as a
  refinement in the skill README. Reviewers typically anchor the same primary line,
  so exact-tuple catches the common case.

---

### Task 1: Plugin scaffold + marketplace wiring

**Files:**
- Create: `tss-review-skills/.claude-plugin/plugin.json`
- Create: `tss-review-skills/README.md`
- Modify: `.claude-plugin/marketplace.json` (add second plugin to `plugins` array)
- Modify: `CLAUDE.md` (the "single plugin" line)
- Test: `tests/run.sh` (new `test_marketplace_*`)

**Interfaces:**
- Produces: the plugin subtree root `tss-review-skills/` and a marketplace entry named `tss-review-skills` with `source: ./tss-review-skills`.

- [ ] **Step 1: Write the failing test**

Add near the other path vars at the top of `tests/run.sh` (after the `LIB=`/`source` lines):

```bash
RS_ROOT="$ROOT/tss-review-skills"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
```

Append these functions before the dispatch loop (`# Run every test_* function.`):

```bash
test_marketplace_lists_review_plugin() {
  jq empty "$MARKETPLACE" 2>/dev/null \
    && printf 'PASS: %s\n' "marketplace.json is valid JSON" \
    || { printf 'FAIL: marketplace.json invalid JSON\n'; FAILED=1; }
  assert_eq "$(jq -r '[.plugins[].name] | index("tss-review-skills") | type' "$MARKETPLACE")" "number" \
    "marketplace lists tss-review-skills"
  assert_eq "$(jq -r '.plugins[] | select(.name=="tss-review-skills") | .source' "$MARKETPLACE")" \
    "./tss-review-skills" "review plugin source path"
}

test_review_plugin_manifest_valid() {
  jq empty "$RS_ROOT/.claude-plugin/plugin.json" 2>/dev/null \
    && printf 'PASS: %s\n' "review plugin.json is valid JSON" \
    || { printf 'FAIL: review plugin.json invalid JSON\n'; FAILED=1; }
  assert_eq "$(jq -r '.name' "$RS_ROOT/.claude-plugin/plugin.json")" "tss-review-skills" \
    "plugin.json name"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `marketplace lists tss-review-skills` (index is `null`/not a number) and the plugin.json test fails (file absent → `jq empty` errors).

- [ ] **Step 3: Create the plugin manifest**

`tss-review-skills/.claude-plugin/plugin.json`:

```json
{
  "name": "tss-review-skills",
  "description": "Multi-model PR/diff review that produces a learning corpus — dispatch a reviewer panel into a canonical findings ledger, then synthesise anonymised lessons. Namespaced as tss-review-skills:<skill>.",
  "author": {
    "name": "Neil Chambers"
  }
}
```

- [ ] **Step 4: Create the plugin README skeleton**

`tss-review-skills/README.md` — mirror `tss-git-skills/README.md`'s shape: title, one-line purpose, an Install pointer to the marketplace README, and a **Reference** section split **User-invoked** / **Model-invoked**. Populate with the two skills (links may point at SKILL.md paths created later):

- Model-invoked: `[review-changes](./skills/review-changes/SKILL.md)` — dispatch a panel of reviewer models against a diff/PR + spec; findings land in a canonical JSON ledger; drive the address-loop to no-open-HIGH/MEDIUM.
- User-invoked: `[synthesize-review-learnings](./skills/synthesize-review-learnings/SKILL.md)` — harvest converged ledgers into anonymised, self-converging lessons under `docs/contributing/lessons/`.

Include a short note on the v1 dedup simplification (exact `(dimension,file,line)`).

- [ ] **Step 5: Add the marketplace entry**

In `.claude-plugin/marketplace.json`, append to `plugins` (after the `tss-git-skills` object):

```json
    {
      "name": "tss-review-skills",
      "description": "Multi-model review → learning corpus, namespaced as tss-review-skills:<skill>.",
      "source": "./tss-review-skills",
      "category": "development"
    }
```

(Also broaden the manifest's top-level `description` if it still says "git/worktree skills" only — make it "git/worktree and review workflow skills".)

- [ ] **Step 6: Fix the CLAUDE.md "single plugin" line**

In `CLAUDE.md`, the opening sentence says the repo hosts "a single plugin, `tss-git-skills`". Replace with wording that names **two** plugins — `tss-git-skills` (git/worktree) and `tss-review-skills` (review → learning) — each in its own subtree with a flat `skills/`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: PASS for all four new assertions; existing tests still green.

- [ ] **Step 8: Commit**

```bash
git add tss-review-skills/.claude-plugin/plugin.json tss-review-skills/README.md \
        .claude-plugin/marketplace.json CLAUDE.md tests/run.sh
git commit -m "feat: scaffold tss-review-skills plugin + marketplace entry"
```

---

### Task 2: Shared interface — rubric + ledger schema

**Files:**
- Create: `tss-review-skills/skills/review-changes/references/rubric.md`
- Create: `tss-review-skills/skills/review-changes/references/ledger-schema.json`
- Test: `tests/run.sh` (new `test_ledger_schema_*`, `test_rubric_*`)

**Interfaces:**
- Produces: `ledger-schema.json` with `$defs.finding.properties.dimension.enum` = the 10 keys; `rubric.md` documenting all 10 dimensions + severity. Consumed by every later task and by `synthesize-review-learnings`.

- [ ] **Step 1: Write the failing test**

Add path var at top of `tests/run.sh`:

```bash
SCHEMA="$RS_ROOT/skills/review-changes/references/ledger-schema.json"
RUBRIC="$RS_ROOT/skills/review-changes/references/rubric.md"
```

Append functions:

```bash
test_ledger_schema_valid() {
  jq empty "$SCHEMA" 2>/dev/null \
    && printf 'PASS: %s\n' "ledger-schema.json is valid JSON" \
    || { printf 'FAIL: ledger-schema.json invalid JSON\n'; FAILED=1; }
  assert_eq "$(jq '.["$defs"].finding.properties.dimension.enum | length' "$SCHEMA")" "10" \
    "schema enumerates 10 dimensions"
  assert_eq "$(jq -r '.["$defs"].finding.properties.severity.enum | sort | join(",")' "$SCHEMA")" \
    "high,low,medium" "schema severity enum"
}

test_rubric_lists_all_dimensions() {
  local k rc=0
  for k in logic error-handling testing architecture abstractions conciseness \
           maintainability documentation security conventions; do
    grep -q "\`$k\`" "$RUBRIC" || { printf 'FAIL: rubric missing dimension %s\n' "$k"; rc=1; }
  done
  [ "$rc" -eq 0 ] && printf 'PASS: %s\n' "rubric documents all 10 dimensions" || FAILED=1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — schema/rubric files absent.

- [ ] **Step 3: Create the ledger schema**

`tss-review-skills/skills/review-changes/references/ledger-schema.json`:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Review findings ledger",
  "type": "array",
  "items": { "$ref": "#/$defs/finding" },
  "$defs": {
    "finding": {
      "type": "object",
      "required": ["id", "dimension", "severity", "file", "title", "detail", "raised_by", "status"],
      "additionalProperties": false,
      "properties": {
        "id": { "type": "string" },
        "dimension": { "enum": ["logic", "error-handling", "testing", "architecture", "abstractions", "conciseness", "maintainability", "documentation", "security", "conventions"] },
        "severity": { "enum": ["high", "medium", "low"] },
        "file": { "type": "string" },
        "line": { "type": ["integer", "null"] },
        "end_line": { "type": ["integer", "null"] },
        "side": { "enum": ["LEFT", "RIGHT"] },
        "title": { "type": "string" },
        "detail": { "type": "string" },
        "suggestion": { "type": ["string", "null"] },
        "raised_by": { "type": "array", "items": { "type": "string" } },
        "status": { "enum": ["open", "addressed", "wontfix", "disputed"] },
        "resolution": { "type": ["string", "null"] },
        "round": { "type": "integer" }
      }
    }
  }
}
```

- [ ] **Step 4: Create the rubric reference**

`tss-review-skills/skills/review-changes/references/rubric.md` — draw content from **design spec §1**. Required content:
- A table of the **10 core dimensions**, each with its backtick `key`, the question a reviewer asks, and what "good" looks like (verbatim from spec §1).
- The **conditional lenses** list (`type-design`, `performance`, `backward-compat`, `accessibility`) with the "apply only when the change touches that surface" rule.
- The **severity** scale (`high`/`medium`/`low` + emoji) and the note that "is it a bug?" is the severity ceiling, *not* a dimension.
- The **repo-supplies-the-bar** principle: reviewers read `CLAUDE.md`/`CONTRIBUTING.md`/`README.md` + repo review agents first and treat them as authoritative, especially for `conventions` and `security`.

Each of the 10 keys must appear wrapped in backticks (the test greps `` `key` ``).

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: PASS for schema + rubric assertions.

- [ ] **Step 6: Commit**

```bash
git add tss-review-skills/skills/review-changes/references/ tests/run.sh
git commit -m "feat: review rubric + canonical ledger schema (shared interface)"
```

---

### Task 3: `merge-findings.sh` (per-reviewer files → ledger)

**Files:**
- Create: `tss-review-skills/skills/review-changes/scripts/merge-findings.sh`
- Test: `tests/run.sh` (new `test_merge_*`)

**Interfaces:**
- Consumes: a run dir containing `findings.<reviewer>.json` files (each a JSON array of findings with at least `dimension`, `severity`, `file`, `title`, `detail`; optional `line`, `end_line`, `side`, `suggestion`).
- Produces: `<run-dir>/ledger.json` — merged array; each finding gains `id`, `raised_by` (unique reviewer labels from filenames), `status:"open"`, `resolution:null`, `round`. Dedup on exact `(dimension, file, line)`.

- [ ] **Step 1: Write the failing tests**

Add path var at top of `tests/run.sh`:

```bash
MERGE="$RS_ROOT/skills/review-changes/scripts/merge-findings.sh"
```

Append:

```bash
test_merge_dedup_unions_raised_by() {
  local d; d="$(mktemp -d)"
  printf '%s' '[{"dimension":"logic","severity":"high","file":"a.sh","line":10,"title":"x","detail":"d"}]' > "$d/findings.opus.json"
  printf '%s' '[{"dimension":"logic","severity":"high","file":"a.sh","line":10,"title":"x","detail":"d"}]' > "$d/findings.kimi.json"
  bash "$MERGE" "$d" >/dev/null 2>&1
  assert_eq "$(jq -r 'length' "$d/ledger.json")" "1" "duplicate findings collapse to one"
  assert_eq "$(jq -r '.[0].raised_by | sort | join(",")' "$d/ledger.json")" "kimi,opus" "raised_by unions reviewers"
  assert_eq "$(jq -r '.[0].status' "$d/ledger.json")" "open" "merged finding starts open"
  rm -rf "$d"
}

test_merge_keeps_distinct() {
  local d; d="$(mktemp -d)"
  printf '%s' '[{"dimension":"logic","severity":"high","file":"a.sh","line":10,"title":"x","detail":"d"}]' > "$d/findings.opus.json"
  printf '%s' '[{"dimension":"security","severity":"low","file":"a.sh","line":10,"title":"y","detail":"d"}]' > "$d/findings.kimi.json"
  bash "$MERGE" "$d" >/dev/null 2>&1
  assert_eq "$(jq -r 'length' "$d/ledger.json")" "2" "distinct dimensions stay separate"
  rm -rf "$d"
}

test_merge_round_arg() {
  local d; d="$(mktemp -d)"
  printf '%s' '[{"dimension":"logic","severity":"low","file":"a.sh","line":1,"title":"x","detail":"d"}]' > "$d/findings.opus.json"
  bash "$MERGE" "$d" --round 3 >/dev/null 2>&1
  assert_eq "$(jq -r '.[0].round' "$d/ledger.json")" "3" "merge stamps the round"
  rm -rf "$d"
}

test_merge_aborts_on_malformed() {
  local d; d="$(mktemp -d)"
  printf '%s' 'not json' > "$d/findings.opus.json"
  assert_fails "merge aborts on malformed input" bash "$MERGE" "$d"
  if [ ! -f "$d/ledger.json" ]; then printf 'PASS: %s\n' "no ledger written on abort"
  else printf 'FAIL: ledger written despite malformed input\n'; FAILED=1; fi
  rm -rf "$d"
}

test_merge_aborts_on_empty() {
  local d; d="$(mktemp -d)"
  assert_fails "merge aborts when no findings files" bash "$MERGE" "$d"
  rm -rf "$d"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh`
Expected: FAIL — `$MERGE` does not exist (`bash: ... No such file`), assertions fail.

- [ ] **Step 3: Implement `merge-findings.sh`**

```bash
#!/usr/bin/env bash
# merge-findings.sh — merge per-reviewer findings into a canonical ledger.
# Usage: merge-findings.sh <run-dir> [--round N]
#   <run-dir> holds findings.<reviewer>.json files (each a JSON array of findings).
#   Writes <run-dir>/ledger.json atomically. Dedup key: (dimension, file, line).
# shellcheck disable=SC2016  # jq programs reference $-vars passed via --arg/--argjson
set -euo pipefail

die() { printf 'merge-findings: %s\n' "$1" >&2; exit 1; }
command -v jq >/dev/null || die "jq required"

run_dir="${1:-}"
[ -n "$run_dir" ] || die "usage: merge-findings.sh <run-dir> [--round N]"
[ -d "$run_dir" ] || die "no such run dir: $run_dir"

round=1
if [ "${2:-}" = "--round" ]; then
  round="${3:-}"
  [ -n "$round" ] || die "--round needs a value"
fi

shopt -s nullglob
files=( "$run_dir"/findings.*.json )
shopt -u nullglob
[ "${#files[@]}" -gt 0 ] || die "no findings.*.json in $run_dir"

# Guard: validate every input is a JSON array BEFORE writing anything.
for f in "${files[@]}"; do
  jq -e 'type == "array"' "$f" >/dev/null 2>&1 || die "not a JSON array: $f"
done

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT

# Tag each finding with its reviewer (from the filename), concat, group + merge.
{
  for f in "${files[@]}"; do
    base="$(basename "$f")"; reviewer="${base#findings.}"; reviewer="${reviewer%.json}"
    jq --arg r "$reviewer" '[ .[] | . + {reviewer:$r} ]' "$f"
  done
} | jq -s --argjson round "$round" '
    add
    | group_by([.dimension, .file, (.line // 0)])
    | to_entries
    | map(
        .key as $i | .value as $g
        | $g[0] + {
            id: ("f" + (($i + 1) | tostring)),
            raised_by: ($g | map(.reviewer) | unique),
            status: "open",
            resolution: null,
            round: $round
          }
        | del(.reviewer)
      )
  ' > "$tmp"

mv "$tmp" "$run_dir/ledger.json"
trap - EXIT
printf 'merged %d reviewer file(s) -> %s\n' "${#files[@]}" "$run_dir/ledger.json" >&2
```

- [ ] **Step 4: Make it executable + run tests**

```bash
chmod +x tss-review-skills/skills/review-changes/scripts/merge-findings.sh
bash tests/run.sh
```
Expected: PASS for all `test_merge_*`; existing tests green.

- [ ] **Step 5: Shellcheck the new script**

Run: `shellcheck tss-review-skills/skills/review-changes/scripts/merge-findings.sh`
Expected: no output (clean). Fix any finding before committing.

- [ ] **Step 6: Commit**

```bash
git add tss-review-skills/skills/review-changes/scripts/merge-findings.sh tests/run.sh
git commit -m "feat: merge-findings.sh — per-reviewer files into canonical ledger"
```

---

### Task 4: `post-to-pr.sh` (ledger → GitHub inline review)

**Files:**
- Create: `tss-review-skills/skills/review-changes/scripts/post-to-pr.sh`
- Test: `tests/run.sh` (new `test_post_*`)

**Interfaces:**
- Consumes: `ledger.json` + a `commit-sha`.
- Produces: on `--dry-run`, prints the GitHub reviews-API payload (`{commit_id, event:"COMMENT", comments:[{path,line,side,body}]}`) to stdout; without `--dry-run`, POSTs it via `gh api repos/<owner/repo>/pulls/<n>/reviews`. `body` = `**<emoji SEV> — <title>**\n\n<detail>` (+ `\n\n*Suggested:* <suggestion>` when present).

- [ ] **Step 1: Write the failing tests**

Add path var at top of `tests/run.sh`:

```bash
POST="$RS_ROOT/skills/review-changes/scripts/post-to-pr.sh"
```

Append:

```bash
test_post_payload_shape() {
  local d; d="$(mktemp -d)"
  printf '%s' '[{"dimension":"error-handling","severity":"high","file":"x.sh","line":5,"title":"jq truncates","detail":"write temp then mv"}]' > "$d/ledger.json"
  local out; out="$(bash "$POST" --dry-run "$d/ledger.json" deadbeef)"
  assert_eq "$(echo "$out" | jq -r '.commit_id')" "deadbeef" "payload carries commit_id"
  assert_eq "$(echo "$out" | jq -r '.event')" "COMMENT" "payload event is COMMENT"
  assert_eq "$(echo "$out" | jq -r '.comments[0].path')" "x.sh" "comment path from finding.file"
  assert_eq "$(echo "$out" | jq -r '.comments[0].side')" "RIGHT" "comment side defaults RIGHT"
  if echo "$out" | jq -r '.comments[0].body' | grep -q '🔴 HIGH — jq truncates'; then
    printf 'PASS: %s\n' "body renders severity + title"
  else printf 'FAIL: body missing severity/title\n'; FAILED=1; fi
  rm -rf "$d"
}

test_post_renders_suggestion() {
  local d; d="$(mktemp -d)"
  printf '%s' '[{"dimension":"logic","severity":"medium","file":"y.sh","line":2,"title":"t","detail":"d","suggestion":"do X"}]' > "$d/ledger.json"
  bash "$POST" --dry-run "$d/ledger.json" abc123 | jq -r '.comments[0].body' | grep -q 'Suggested:\* do X' \
    && printf 'PASS: %s\n' "body renders suggestion when present" \
    || { printf 'FAIL: suggestion not rendered\n'; FAILED=1; }
  rm -rf "$d"
}

test_post_aborts_on_bad_ledger() {
  local d; d="$(mktemp -d)"
  printf '%s' 'nope' > "$d/ledger.json"
  assert_fails "post aborts on malformed ledger" bash "$POST" --dry-run "$d/ledger.json" deadbeef
  rm -rf "$d"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh`
Expected: FAIL — `$POST` missing.

- [ ] **Step 3: Implement `post-to-pr.sh`**

```bash
#!/usr/bin/env bash
# post-to-pr.sh — render a ledger into a GitHub review; optionally post it.
# Usage:
#   post-to-pr.sh --dry-run <ledger.json> <commit-sha>            # print payload only
#   post-to-pr.sh <ledger.json> <commit-sha> <owner/repo> <pr#>   # post via gh
# shellcheck disable=SC2016  # jq program references $commit (passed via --arg)
set -euo pipefail

die() { printf 'post-to-pr: %s\n' "$1" >&2; exit 1; }
command -v jq >/dev/null || die "jq required"

build_payload() { # <ledger> <commit>
  local ledger="$1" commit="$2"
  jq -e 'type == "array"' "$ledger" >/dev/null 2>&1 || die "ledger not a JSON array: $ledger"
  jq --arg commit "$commit" '
    def sev: {high:"🔴 HIGH", medium:"🟠 MEDIUM", low:"🟢 LOW"}[.severity] // .severity;
    {
      commit_id: $commit,
      event: "COMMENT",
      comments: [ .[] | {
        path: .file,
        line: .line,
        side: (.side // "RIGHT"),
        body: ("**" + sev + " — " + .title + "**\n\n" + .detail
               + (if .suggestion then "\n\n*Suggested:* " + .suggestion else "" end))
      } ]
    }' "$ledger"
}

mode="${1:-}"
if [ "$mode" = "--dry-run" ]; then
  ledger="${2:-}"; commit="${3:-}"
  { [ -n "$ledger" ] && [ -n "$commit" ]; } || die "usage: post-to-pr.sh --dry-run <ledger> <commit>"
  [ -f "$ledger" ] || die "no such ledger: $ledger"
  build_payload "$ledger" "$commit"
  exit 0
fi

ledger="${1:-}"; commit="${2:-}"; repo="${3:-}"; pr="${4:-}"
{ [ -n "$ledger" ] && [ -n "$commit" ] && [ -n "$repo" ] && [ -n "$pr" ]; } \
  || die "usage: post-to-pr.sh <ledger> <commit> <owner/repo> <pr#>"
[ -f "$ledger" ] || die "no such ledger: $ledger"
command -v gh >/dev/null || die "gh required to post (use --dry-run to preview)"

build_payload "$ledger" "$commit" \
  | gh api "repos/$repo/pulls/$pr/reviews" --method POST --input - >/dev/null \
  || die "gh api call failed"
printf 'posted review to %s#%s\n' "$repo" "$pr" >&2
```

- [ ] **Step 4: Make executable + run tests**

```bash
chmod +x tss-review-skills/skills/review-changes/scripts/post-to-pr.sh
bash tests/run.sh
```
Expected: PASS for all `test_post_*`.

- [ ] **Step 5: Shellcheck**

Run: `shellcheck tss-review-skills/skills/review-changes/scripts/post-to-pr.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add tss-review-skills/skills/review-changes/scripts/post-to-pr.sh tests/run.sh
git commit -m "feat: post-to-pr.sh — render ledger to GitHub inline review"
```

---

### Task 5: `review-changes` reviewer charter + SKILL.md

**Files:**
- Create: `tss-review-skills/skills/review-changes/references/reviewer-charter.md`
- Create: `tss-review-skills/skills/review-changes/SKILL.md`
- Test: `tests/run.sh` (new `test_review_changes_skill_*`)

**Interfaces:**
- Consumes: `rubric.md`, `ledger-schema.json`, `merge-findings.sh`, `post-to-pr.sh` (all from Tasks 2-4).
- Produces: the orchestration playbook a driving agent follows, and the charter template handed to each reviewer.

- [ ] **Step 1: Write the failing test**

Add path var:

```bash
RC_SKILL="$RS_ROOT/skills/review-changes/SKILL.md"
CHARTER="$RS_ROOT/skills/review-changes/references/reviewer-charter.md"
```

Append:

```bash
test_review_changes_skill_frontmatter() {
  head -8 "$RC_SKILL" | grep -q '^name: review-changes' \
    && printf 'PASS: %s\n' "review-changes SKILL has name" \
    || { printf 'FAIL: review-changes SKILL name\n'; FAILED=1; }
  # model-invokable: must NOT disable model invocation
  if head -8 "$RC_SKILL" | grep -q '^disable-model-invocation: true'; then
    printf 'FAIL: review-changes must be model-invokable\n'; FAILED=1
  else printf 'PASS: %s\n' "review-changes is model-invokable"; fi
}

test_review_changes_charter_has_guardrails() {
  local rc=0
  grep -qi 'read-only' "$CHARTER" || { printf 'FAIL: charter missing read-only discipline\n'; rc=1; }
  grep -qi 'recurrence\|previously-taught\|lessons' "$CHARTER" || { printf 'FAIL: charter missing recurrence check\n'; rc=1; }
  grep -q 'findings\.' "$CHARTER" || { printf 'FAIL: charter missing output-file contract\n'; rc=1; }
  [ "$rc" -eq 0 ] && printf 'PASS: %s\n' "charter carries the load-bearing guardrails" || FAILED=1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — SKILL.md / charter absent.

- [ ] **Step 3: Create the reviewer charter**

`reviewer-charter.md` — draw from **design spec §3 "Reviewer charter"**. It is a *template* (with `[PLACEHOLDERS]` for the driver to fill). Required content:
- Role + **read-only discipline, stated hard** (no moving HEAD, no branch switch, no tree mutation; use `git show`/`git diff` or a throwaway worktree). The test greps `read-only`.
- `[CHANGE]` (diff/PR ref or SHAs) and `[SPEC]` (the plan/requirements the author built from) placeholders.
- Inlined rubric pointer: review along the 10 dimensions; apply conditional lenses only when relevant; calibrate severity.
- **Discover the bar:** read `CLAUDE.md`/`CONTRIBUTING.md`/`README.md` + repo review agents first.
- **Recurrence check** against the lessons index `[LESSONS_INDEX]` (test greps `lessons`/`recurrence`).
- **False-positive guard:** skip pre-existing issues, linter-catchable nits, and lines the change didn't touch; acknowledge strengths; never mark a nitpick critical.
- **Output contract:** write **only** `findings.<reviewer-label>.json` (a JSON array conforming to `ledger-schema.json`) to the run dir — nothing else, no shared-file writes. The test greps `findings.`.

- [ ] **Step 4: Create the SKILL.md**

`SKILL.md` — frontmatter then body from **design spec §3**.

Frontmatter (exact):
```markdown
---
name: review-changes
description: Dispatch a panel of reviewer models against a diff or PR (plus the spec the author built from), collect their critiques into a canonical JSON findings ledger, and drive an address-loop until no HIGH/MEDIUM remains. Use when a change is ready for review and you want multi-model coverage feeding a learning corpus.
---
```

Required body sections:
- **Flow** (the 6 steps from spec §3: resolve inputs → compose charter → dispatch panel → `merge-findings.sh` → optional `post-to-pr.sh` → address-loop), with the **convergence rule**: loop until no `open` HIGH or MEDIUM (every MEDIUM fixed or explicitly `wontfix` with rationale; LOW advisory).
- **Panel = config + invocation override:** `review-panel.json` three-tier (`.claude/` → `.local.json` → `~/.claude/`); invocation override is primary; empty-panel-safe (error clearly if no panel).
- **Dispatch is harness-pluggable:** for each panel model, spawn a reviewer on that model via the host harness (pi model-targeted dispatch / Claude Code `Agent` `model` override / external CLI template), handing it `reviewer-charter.md` + its `findings.<model>.json` output path. Uniform contract regardless of mechanism.
- **The ledger** is canonical and gitignored under `.reviews/<run-id>/`; reference `ledger-schema.json`.
- **Scripts:** how to call `merge-findings.sh <run-dir> [--round N]` and `post-to-pr.sh` (with the `--dry-run` preview).
- A short **v1 dedup note** (exact `(dimension,file,line)`).

- [ ] **Step 5: Add `.reviews/` to `.gitignore`**

Append to the repo root `.gitignore` (if not already ignored):
```
.reviews/
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: PASS for `test_review_changes_skill_*`.

- [ ] **Step 7: Commit**

```bash
git add tss-review-skills/skills/review-changes/SKILL.md \
        tss-review-skills/skills/review-changes/references/reviewer-charter.md \
        .gitignore tests/run.sh
git commit -m "feat: review-changes skill — charter + orchestration playbook"
```

---

### Task 6: Corpus migration — decompose the essay into seed lessons

**Files:**
- Create: `docs/contributing/lessons/INDEX.md`
- Create: `docs/contributing/lessons/<dimension>-<slug>.md` (the seed lessons, listed below)
- Create: `tss-review-skills/skills/synthesize-review-learnings/scripts/check-index.sh`
- Delete: `docs/contributing/closing-the-verification-loop.md`
- Modify: `README.md`, `CLAUDE.md` (repoint essay links → `docs/contributing/lessons/INDEX.md`)
- Test: `tests/run.sh` (new `test_lessons_*`, `test_check_index_*`)

**Interfaces:**
- Consumes: the retired essay's content (its four principles + taste items) as source material.
- Produces: `check-index.sh <lessons-dir>` (exit non-zero on any lesson/index inconsistency), the seeded `lessons/` dir, and an `INDEX.md` linking every lesson by filename `(<file>.md)`.

**Seed lessons** (filename → dimension → source essay section):
- `testing-watch-it-fail.md` → `testing` → "A test's only value is its ability to fail"
- `documentation-observe-dont-describe.md` → `documentation` → "Observe behaviour — don't describe it"
- `environment-is-an-input.md` → `conventions` → "The environment is an input, not a constant"
- `error-handling-design-the-failure-path.md` → `error-handling` → "Design the failure path of every destructive operation"
- `abstractions-reuse-over-reimplement.md` → `abstractions` → taste: reuse vs re-implement
- `abstractions-no-lossy-round-trip.md` → `abstractions` → taste: lossy round-trip
- `conciseness-lean-entry-defers.md` → `conciseness` → taste: lean entry-point defers
- `architecture-fix-at-the-altitude-that-scales.md` → `architecture` → taste: fix at the scaling altitude

- [ ] **Step 1: Write the failing tests**

Add path vars:

```bash
CHECK_INDEX="$RS_ROOT/skills/synthesize-review-learnings/scripts/check-index.sh"
LESSONS="$ROOT/docs/contributing/lessons"
```

Append:

```bash
test_check_index_catches_unlisted_lesson() {
  local d; d="$(mktemp -d)"
  printf -- '---\ntitle: t\ndimension: logic\nseverity: low\noccurrences: 1\nfirst_seen: 2026-01-01\nlast_seen: 2026-01-01\nstatus: active\n---\nbody\n' > "$d/logic-orphan.md"
  printf '# Lessons index\n' > "$d/INDEX.md"   # lesson present but not linked
  assert_fails "check-index flags an unlisted lesson" bash "$CHECK_INDEX" "$d"
  rm -rf "$d"
}

test_check_index_catches_missing_frontmatter_key() {
  local d; d="$(mktemp -d)"
  printf -- '---\ntitle: t\ndimension: logic\n---\nbody\n' > "$d/logic-thin.md"   # missing keys
  printf '# Lessons index\n\n- [t](logic-thin.md)\n' > "$d/INDEX.md"
  assert_fails "check-index flags missing frontmatter keys" bash "$CHECK_INDEX" "$d"
  rm -rf "$d"
}

test_seed_lessons_pass_integrity() {
  bash "$CHECK_INDEX" "$LESSONS" >/dev/null 2>&1 \
    && printf 'PASS: %s\n' "shipped lessons/ pass index integrity" \
    || { printf 'FAIL: shipped lessons/ fail index integrity\n'; FAILED=1; }
}

test_essay_retired() {
  if [ -f "$ROOT/docs/contributing/closing-the-verification-loop.md" ]; then
    printf 'FAIL: retired essay still present\n'; FAILED=1
  else printf 'PASS: %s\n' "verification essay retired"; fi
}

test_readme_points_at_lessons() {
  grep -q 'docs/contributing/lessons' "$ROOT/README.md" \
    && printf 'PASS: %s\n' "README links the lessons index" \
    || { printf 'FAIL: README does not link lessons index\n'; FAILED=1; }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh`
Expected: FAIL — `$CHECK_INDEX` missing; essay still present; README not yet repointed.

- [ ] **Step 3: Implement `check-index.sh`**

```bash
#!/usr/bin/env bash
# check-index.sh — verify lessons/ and INDEX.md are mutually consistent.
# Usage: check-index.sh <lessons-dir>
#   - every lessons/*.md (bar INDEX.md) has all required frontmatter keys
#   - every lesson is linked from INDEX.md as (<filename>.md)
#   - every INDEX.md lesson link resolves to a file
set -euo pipefail
die() { printf 'check-index: %s\n' "$1" >&2; exit 1; }

dir="${1:-}"
[ -n "$dir" ] || die "usage: check-index.sh <lessons-dir>"
[ -d "$dir" ] || die "no such dir: $dir"
index="$dir/INDEX.md"
[ -f "$index" ] || die "missing INDEX.md in $dir"

req=(title dimension severity occurrences first_seen last_seen status)
rc=0

shopt -s nullglob
for f in "$dir"/*.md; do
  base="$(basename "$f")"
  [ "$base" = "INDEX.md" ] && continue
  if ! head -1 "$f" | grep -qx -- '---'; then
    printf 'check-index: %s missing frontmatter\n' "$base" >&2; rc=1; continue
  fi
  fm="$(awk 'NR>1 && /^---[[:space:]]*$/{exit} NR>1{print}' "$f")"
  for k in "${req[@]}"; do
    printf '%s\n' "$fm" | grep -q "^$k:" \
      || { printf 'check-index: %s missing frontmatter key: %s\n' "$base" "$k" >&2; rc=1; }
  done
  grep -q "($base)" "$index" \
    || { printf 'check-index: %s not linked from INDEX.md\n' "$base" >&2; rc=1; }
done
shopt -u nullglob

while IFS= read -r link; do
  [ "$link" = "INDEX.md" ] && continue
  [ -f "$dir/$link" ] || { printf 'check-index: INDEX.md links missing file: %s\n' "$link" >&2; rc=1; }
done < <(grep -oE '\(([a-z0-9-]+\.md)\)' "$index" | tr -d '()')

[ "$rc" -eq 0 ] && printf 'check-index: OK\n' >&2
exit "$rc"
```

- [ ] **Step 4: Make executable, write the seed lessons + INDEX**

```bash
chmod +x tss-review-skills/skills/synthesize-review-learnings/scripts/check-index.sh
mkdir -p docs/contributing/lessons
```

For each seed lesson file, write frontmatter then a `principle → trap → fix → habit` body **reshaped from the cited essay section** (content is in `docs/contributing/closing-the-verification-loop.md` until it's deleted in Step 5). Frontmatter template (fill per lesson; seed `occurrences: 1`, dates `2026-06-28`, the seed cycle):

```yaml
---
title: "Watch every new test fail before you trust it"
dimension: testing
severity: high
occurrences: 1
first_seen: 2026-06-28
last_seen: 2026-06-28
sources: ["seed: closing-the-verification-loop"]
status: active
---
```

`INDEX.md` — a heading plus a table; every lesson linked by filename, e.g.:

```markdown
# Lessons index

Anonymised, self-converging review lessons. One file per lesson; `occurrences`
tracks recurrence (a persistent blind spot). Grown by
`tss-review-skills:synthesize-review-learnings`.

| Lesson | Dimension | Severity | Seen |
|---|---|---|---|
| [Watch every new test fail before you trust it](testing-watch-it-fail.md) | testing | high | 1 |
| … one row per lesson … |
```

Every lesson file must be linked as `(<filename>.md)` so `check-index.sh` passes.

- [ ] **Step 5: Retire the essay + repoint links**

```bash
git rm docs/contributing/closing-the-verification-loop.md
```
In `README.md` and `CLAUDE.md`, replace the link/path
`docs/contributing/closing-the-verification-loop.md` with
`docs/contributing/lessons/INDEX.md` (keep the surrounding sentence; update the
link text to "the lessons index" / "contributor lessons" as fits). The `CLAUDE.md`
*Contributor guidance* paragraph keeps its four habits but now points at the index.

- [ ] **Step 6: Run tests + shellcheck + integrity**

```bash
bash tests/run.sh
shellcheck tss-review-skills/skills/synthesize-review-learnings/scripts/check-index.sh
bash tss-review-skills/skills/synthesize-review-learnings/scripts/check-index.sh docs/contributing/lessons
```
Expected: tests PASS; shellcheck clean; `check-index: OK`.

- [ ] **Step 7: Commit**

```bash
git add docs/contributing/lessons/ README.md CLAUDE.md tests/run.sh \
        tss-review-skills/skills/synthesize-review-learnings/scripts/check-index.sh
git add -u docs/contributing/   # stage the essay deletion
git commit -m "feat: seed lessons library from the verification essay; retire the essay"
```

---

### Task 7: `synthesize-review-learnings` SKILL.md

**Files:**
- Create: `tss-review-skills/skills/synthesize-review-learnings/SKILL.md`
- Test: `tests/run.sh` (new `test_synthesize_skill_*`)

**Interfaces:**
- Consumes: `.reviews/*/ledger.json`, `ledger-schema.json` (dimension keys), `check-index.sh`, the `lessons/` library.
- Produces: the harvest playbook (distillation pipeline → lessons + INDEX update).

- [ ] **Step 1: Write the failing test**

Add path var:

```bash
SY_SKILL="$RS_ROOT/skills/synthesize-review-learnings/SKILL.md"
```

Append:

```bash
test_synthesize_skill_is_user_invoked() {
  head -8 "$SY_SKILL" | grep -q '^name: synthesize-review-learnings' \
    && printf 'PASS: %s\n' "synthesize SKILL has name" \
    || { printf 'FAIL: synthesize SKILL name\n'; FAILED=1; }
  head -8 "$SY_SKILL" | grep -q '^disable-model-invocation: true' \
    && printf 'PASS: %s\n' "synthesize is user-invoked" \
    || { printf 'FAIL: synthesize must set disable-model-invocation: true\n'; FAILED=1; }
}

test_synthesize_skill_covers_pipeline() {
  local rc=0
  grep -qi 'teachability\|severity.*MEDIUM\|multi-model\|recurr' "$SY_SKILL" || { printf 'FAIL: missing teachability filter\n'; rc=1; }
  grep -qi 'strengthen\|occurrences\|dedup' "$SY_SKILL" || { printf 'FAIL: missing dedup/strengthen step\n'; rc=1; }
  grep -q 'check-index.sh' "$SY_SKILL" || { printf 'FAIL: missing index-integrity check\n'; rc=1; }
  grep -qi 'no model names\|anonymis\|anonymiz' "$SY_SKILL" || { printf 'FAIL: missing anonymisation rule\n'; rc=1; }
  [ "$rc" -eq 0 ] && printf 'PASS: %s\n' "synthesize SKILL covers the pipeline" || FAILED=1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — SKILL.md absent.

- [ ] **Step 3: Create the SKILL.md**

Frontmatter (exact):
```markdown
---
name: synthesize-review-learnings
description: Harvest converged review ledgers (.reviews/*/ledger.json) into the anonymised, self-converging lessons library under docs/contributing/lessons/. Run after one or more reviews to distil foundational, recurring weaknesses into durable contributor guidance.
disable-model-invocation: true
---
```

Required body sections — draw from **design spec §4**:
- **Inputs:** read only `.reviews/*/ledger.json` (never scrape GitHub); single or batched.
- **Distillation pipeline** (the 6 steps): load → **teachability filter** (`severity ≥ MEDIUM OR multi-round OR raised_by ≥ 2 OR recurs a known lesson`) → cluster by `dimension` + principle → **dedup against the index** (exists → *strengthen*: bump `occurrences`, update `last_seen`, add source; new → draft) → update `INDEX.md` → **report the harvest** (added / strengthened / dropped-and-why — no silent caps).
- **Anonymisation rule:** model identity from `raised_by` is signal only; lessons record PR sources but **no model names**.
- **Lesson schema:** the frontmatter keys (`title`, `dimension`, `severity`, `occurrences`, `first_seen`, `last_seen`, `sources`, `status`) + body shape `principle → trap → fix → habit`, generalised snippets.
- **Corpus path:** default `docs/contributing/lessons/`, overridable.
- **Integrity gate:** after writing, run `check-index.sh <lessons-dir>` and fix any failure before finishing.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: PASS for `test_synthesize_skill_*`.

- [ ] **Step 5: Commit**

```bash
git add tss-review-skills/skills/synthesize-review-learnings/SKILL.md tests/run.sh
git commit -m "feat: synthesize-review-learnings skill — ledgers into the lessons corpus"
```

---

### Task 8: Final integration — README, full suite, shellcheck

**Files:**
- Modify: `tss-review-skills/README.md` (finalise both skill links now that SKILL.md paths exist)
- Verify: full `bash tests/run.sh` + shellcheck over all `*.sh`

**Interfaces:**
- Consumes: every prior task's output.

- [ ] **Step 1: Finalise the plugin README**

Confirm `tss-review-skills/README.md` links resolve to the now-existing
`./skills/review-changes/SKILL.md` and `./skills/synthesize-review-learnings/SKILL.md`,
groups them User-/Model-invoked, and documents the `.reviews/` working dir + the v1
dedup note. Match `tss-git-skills/README.md`'s tone.

- [ ] **Step 2: Run the full test suite**

Run: `bash tests/run.sh; echo "exit=$?"`
Expected: all PASS, `exit=0`. No FAIL lines.

- [ ] **Step 3: Shellcheck every shell file (mirror CI exactly)**

Run: `find . -name '*.sh' -print0 | xargs -0 shellcheck && echo CLEAN`
Expected: `CLEAN`. (If local shellcheck ≠ 0.11.0, note the version-skew caveat from the verification lessons; the CI gate is authoritative.)

- [ ] **Step 4: Verify the plugin tree scans (depth-1 skills)**

Run: `ls tss-review-skills/skills/*/SKILL.md`
Expected: both `review-changes/SKILL.md` and `synthesize-review-learnings/SKILL.md` listed (flat `skills/` is what Claude Code auto-discovers).

- [ ] **Step 5: Commit**

```bash
git add tss-review-skills/README.md
git commit -m "docs: finalise tss-review-skills README; full suite + shellcheck green"
```

---

## Self-Review

**1. Spec coverage:**
- §1 Rubric → Task 2 (`rubric.md`) + the 10-key enum in Task 2 schema.
- §2 Ledger → Task 2 (schema), Task 3 (merge produces it), `.reviews/` gitignored in Task 5.
- §3 `review-changes` → Tasks 3-5 (scripts + charter + SKILL.md); panel/dispatch/convergence in Task 5 body.
- §4 `synthesize-review-learnings` → Task 7 (SKILL.md) + Task 6 (`check-index.sh`).
- §5 Corpus migration → Task 6 (decompose, retire, repoint).
- §6 Packaging → Task 1 (plugin + marketplace + CLAUDE.md).
- §7 Testing → tests embedded per task; integrity in Task 6; final gate in Task 8.
All sections covered.

**2. Placeholder scan:** Prose deliverables intentionally specify structure + required content + the source spec section (see "Plan convention"), each with a structural acceptance test — not free-floating TODOs. Scripts, tests, schema, and manifests are complete and runnable.

**3. Type consistency:** Path vars (`RS_ROOT`, `SCHEMA`, `MERGE`, `POST`, `RC_SKILL`, `CHARTER`, `CHECK_INDEX`, `LESSONS`, `SY_SKILL`) are defined once at the top of `tests/run.sh` and reused. Dimension keys, severity values, and status values match the Global Constraints and the schema enum everywhere. `merge-findings.sh` output fields (`id`, `raised_by`, `status`, `resolution`, `round`) match the schema `required`/`properties`. `post-to-pr.sh` payload keys (`commit_id`, `event`, `comments[].{path,line,side,body}`) match the GitHub reviews API used by `post-to-pr.sh` consumers.

**Known deviation (surface to user):** v1 dedup is exact `(dimension,file,line)`, not overlapping-range (documented, not silent).

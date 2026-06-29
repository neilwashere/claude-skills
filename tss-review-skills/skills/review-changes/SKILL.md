---
name: review-changes
description: Dispatch a panel of reviewer models against a diff or PR (plus the spec the author built from), collect their critiques into a canonical JSON findings ledger, and drive an address-loop until no HIGH/MEDIUM remains. Use when a change is ready for review and you want multi-model coverage feeding a learning corpus.
---

# review-changes

Orchestrate a multi-model code review: resolve inputs, compose a reviewer charter,
dispatch a panel of models in parallel, merge their findings into a canonical JSON
ledger, optionally post to a GitHub PR, and drive an address loop until the change
converges.

The ledger is the stable interface. Reviewers write it; the driver addresses against
it; `synthesize-review-learnings` harvests it into the lessons corpus. Everything
else — dispatch mechanism, post adapter, PR platform — is pluggable on top.

---

## Flow

### Step 1 — Resolve inputs

Identify:

- **The change** — one of:
  - `base..head` SHA range (`git diff base..head`)
  - A PR reference (`gh pr view <num>`)
  - The current working-tree diff (`git diff HEAD`)
- **The spec** — the plan, requirements doc, or task brief the author built from.
  If the author had no spec, note that; the absence is itself a review signal.
- **The lessons index** — `docs/contributing/lessons/INDEX.md` in the repo under
  review (or a configured override path). Pass this to reviewers so they can detect
  recurrences of known weaknesses.

Create the run directory:

```
.reviews/<run-id>/
```

`<run-id>` is a short, unique identifier — use `<YYYY-MM-DD>-<slug>` or a short
SHA. The ledger is gitignored; it persists until explicitly archived or harvested.

### Step 2 — Compose the charter

Fill the placeholders in `references/reviewer-charter.md`:

| Placeholder | Value |
|---|---|
| `[CHANGE]` | The diff/PR ref resolved in Step 1 |
| `[SPEC]` | Path or inline text of the spec |
| `[LESSONS_INDEX]` | Path to `docs/contributing/lessons/INDEX.md` |
| `[RUN_DIR]` | The `.reviews/<run-id>/` path |
| `[REVIEWER_LABEL]` | Each reviewer's model label (filled per-reviewer at dispatch) |

The charter inlines the rubric dimensions, the read-only discipline, the recurrence
check against the lessons index, and the output contract. It is the complete
context a reviewer agent needs — do not split it across multiple files or prompts.

### Step 3 — Dispatch the panel

For each model in the configured panel, spawn a reviewer agent on that model,
handing it the composed charter and its output path
(`.reviews/<run-id>/findings.<model>.json`).

Dispatch all panel models in parallel. Reviewers are stateless and write only their
own file — there is no shared-file race.

**Dispatch mechanism is harness-pluggable** (see *Harness-pluggable dispatch*
below). The contract is uniform regardless of mechanism: the reviewer reads the
charter and writes `findings.<model>.json`.

### Step 4 — Merge

After all reviewers complete:

```
bash scripts/merge-findings.sh .reviews/<run-id> [--round N]
```

`merge-findings.sh` reads every `findings.*.json` in the run directory, deduplicates
(see *v1 dedup note* below), unions `raised_by`, stamps each finding with the round
number, and writes `.reviews/<run-id>/ledger.json`. The script aborts loudly if any
input file is malformed or if no findings files are present.

`--round N` stamps findings with round N (default: 1 on first run, increment each
address loop).

### Step 5 — Post (optional)

To render findings as inline GitHub PR comments:

```
bash scripts/post-to-pr.sh --dry-run .reviews/<run-id>/ledger.json <commit-sha>
```

To POST to the GitHub API, run the live form with `<owner/repo>` and `<pr#>`:

```
bash scripts/post-to-pr.sh .reviews/<run-id>/ledger.json <commit-sha> <owner/repo> <pr#>
```

`post-to-pr.sh` builds a structured payload (commit ref, file path, line, side, body
with severity emoji + title + detail + suggestion) for each finding in the ledger.

Always preview with `--dry-run` first.

### Step 6 — Address loop

The driver (you) works through `open` findings in the ledger:

1. For each `high` or `medium` finding: fix it, then set `status: "addressed"` and
   `resolution: "<what was done>"` in the ledger.
2. For findings you will not fix: set `status: "wontfix"` and `resolution: "<rationale>"`.
   The rationale is synthesis signal — a wontfix with a weak rationale is a red flag.
3. Re-run `merge-findings.sh` with `--round N+1` to merge a second round of
   reviewer output against the updated diff.

**Convergence rule:** the loop exits when no `open` finding is `high` or `medium`.
Every `medium` must be either `addressed` or `wontfix` with a written rationale.
`low` findings are advisory — they inform the author but do not block convergence.

---

## Panel = config + invocation override

### Configuration — three-tier lookup

Reviewer models are configured in `review-panel.json`, resolved in this order
(most-specific wins, field by field):

1. `.claude/review-panel.json` — committed repo config (recommends a panel for this repo)
2. `.claude/review-panel.local.json` — local override (gitignored, user-specific)
3. `~/.claude/review-panel.json` — global user config (what models the user can target)

```json
{
  "panel": [
    { "model": "opus",     "effort": "high" },
    { "model": "kimi",     "effort": "medium" },
    { "model": "deepseek", "command": "llm -m deepseek-coder {charter_file}" }
  ]
}
```

Per-model entries may carry:
- `effort` — a hint for harnesses that support effort levels.
- `command` — an external command template for CLI-only models (see *Harness-pluggable dispatch*).

### Invocation override — primary

If the caller names models at invocation ("review with opus and kimi"), the
invocation override wins over all config tiers. Parse the named models from the
request and build the panel from them.

### Empty-panel guard

If no panel is configured or named at invocation, error clearly:

```
review-changes: no panel configured. Name models at invocation ("review with opus,
kimi") or set up review-panel.json (see skill docs).
```

Do not silently skip review with a single model — the multi-model coverage is the
point.

---

## Harness-pluggable dispatch

The dispatch mechanism is determined by the host harness. The contract is uniform:
each reviewer receives the charter (with its `[REVIEWER_LABEL]` filled) and writes
`findings.<model>.json` to the run directory.

| Harness | Mechanism |
|---|---|
| **pi** | pi's model-targeted task dispatch |
| **Claude Code** | `Agent` tool with `model` override per panel entry |
| **CLI-only model** | External command template from panel config (`command` field) |

For Claude Code:

```
Agent({
  model: "<panel-model>",
  prompt: "<filled charter>",
  description: "Review: <model> pass"
})
```

For a CLI-only model with a `command` template:

```
<command with {charter_file} replaced by the path to the written charter>
```

Cross-family agreement in `raised_by` (e.g. `["opus", "kimi"]`) is the strongest
review signal and falls out naturally from the uniform output contract — no special
handling needed.

---

## The ledger

The canonical ledger lives at `.reviews/<run-id>/ledger.json` and is gitignored.

Its schema is defined in `references/ledger-schema.json`. Key fields per finding:

| Field | Role |
|---|---|
| `id` | Driver-assigned unique ID (e.g. `r1-001`) |
| `dimension` | One of the 10 rubric keys |
| `severity` | `high`, `medium`, or `low` |
| `file` | Repo-relative path |
| `line` / `end_line` | Line range |
| `raised_by` | Array of model labels — populated at merge |
| `status` | `open`, `addressed`, `wontfix`, or `disputed` |
| `resolution` | Driver-written; required when status is not `open` |
| `round` | First round in which the finding appeared |

The ledger is the source of truth. Never edit it manually while a review is active —
use `merge-findings.sh` for merge operations and update `status`/`resolution`
directly in the JSON between rounds.

Ledgers persist until harvested by `synthesize-review-learnings`. They are not
auto-deleted after convergence — an explicit synthesis step reads `.reviews/*/ledger.json`.

---

## Scripts reference

### `merge-findings.sh`

```
bash scripts/merge-findings.sh <run-dir> [--round N]
```

- Reads all `findings.*.json` in `<run-dir>`.
- Deduplicates across reviewer files (see *v1 dedup note* below).
- Writes `.reviews/<run-id>/ledger.json` atomically (write-to-temp-then-rename).
- Aborts with a non-zero exit and no ledger written if any input file is malformed
  or if no `findings.*.json` files are present.

### `post-to-pr.sh`

```
bash scripts/post-to-pr.sh --dry-run <ledger-path> <commit-sha>
```

```
bash scripts/post-to-pr.sh <ledger-path> <commit-sha> <owner/repo> <pr#>
```

- `--dry-run` — prints the structured payload to stdout; does not POST.
- Without `--dry-run` — POSTs each finding as a GitHub inline comment via `gh api`.
- Payload fields: `commit_id`, `event: "COMMENT"`, per-finding `path`/`line`/`side`/`body`.
- Body renders: severity emoji + title + detail + suggestion (when present).

Always preview with `--dry-run` before posting to a live PR.

---

## v1 dedup note

`merge-findings.sh` deduplicates on the exact triple `(dimension, file, line)`. Two
findings from different reviewers collide when all three values match; their reviewer
labels are unioned into `raised_by` and the finding passes through once.

Findings that share `dimension` and `file` but differ on `line` (even by one) are
kept as separate entries. Title-similarity tie-breaking is not implemented in v1 —
findings at overlapping but non-identical line ranges are both retained. If a
reviewer raises a multi-line finding (`line`–`end_line`) and another raises a
point finding at a line within that range, they will not be deduped in v1.

This keeps the merge logic simple and auditable. Cross-family agreement
(`raised_by` length ≥ 2) is the most reliable convergence signal and works
correctly under v1 dedup semantics.

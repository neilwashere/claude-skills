---
name: synthesize-review-learnings
description: Harvest converged review ledgers (.reviews/*/ledger.json) into the anonymised, self-converging lessons library under docs/contributing/lessons/. Run after one or more reviews to distil foundational, recurring weaknesses into durable contributor guidance.
disable-model-invocation: true
---

# synthesize-review-learnings

Run this skill after one or more `review-changes` cycles have converged. It reads
the findings ledgers those cycles produced and distils recurring, teachable patterns
into the lessons library — an anonymised, self-converging corpus of contributor
guidance.

## Inputs

Read only `.reviews/*/ledger.json` (produced by `review-changes`). A single run
can harvest one ledger or batch-harvest all ledgers in `.reviews/`. Never scrape
GitHub — the ledger is the canonical source of record.

Default ledger glob: `.reviews/*/ledger.json`. Pass a specific path to target one
run.

## Distillation pipeline

Work through the six steps below in order.

### Step 1 — Load

Read all findings from the target ledger(s) into memory. For each finding note:
`dimension`, `severity`, `raised_by` (the list of reviewer models that flagged it),
`round` (first appearance), and `status` + `resolution` (how it was addressed).

### Step 2 — Teachability filter

Keep a finding only if it represents a *class* of mistake, not a one-off incident.
Pass a finding when **any** of the following hold:

- `severity ≥ MEDIUM` (i.e. `medium` or `high`)
- The finding persisted across multiple rounds — the driver had to revisit it (its
  `resolution` was filled in a later round than its `round`)
- Multiple models flagged it (`raised_by` has 2 or more entries — multi-model
  agreement is the strongest teachability signal)
- It recurs a known lesson (the principle already appears in `INDEX.md`)

Everything else is **dropped**. Record *why* each dropped finding was excluded —
the harvest report must account for every finding (no silent caps).

Model identity from `raised_by` is used here as a signal only: multi-model
agreement raises a finding's teachability and confidence. It is **never carried
into the lesson**. The anonymisation boundary is the ledger → lesson step: lessons
record PR sources but no model names.

### Step 3 — Cluster

Group surviving findings by `dimension` (the 10 fixed keys from
`review-changes/references/rubric.md`) and underlying principle. Clustering is
semantic — group findings that teach the same lesson, regardless of which file or
line they appeared on. The goal is one lesson per *class* of mistake, not one
lesson per PR finding.

### Step 4 — Dedup against the index

For each cluster, check `INDEX.md` in the lessons corpus:

**Lesson already exists** → *strengthen* it:
- Bump `occurrences` by 1 per harvest in which the lesson's class recurs (even if
  that harvest surfaced several instances of it), so the counter tracks how many
  harvests hit the weakness — its persistence — not raw finding count.
- Update `last_seen` to today's date.
- Add the new PR source(s) to `sources` (no model names — PR refs only).
- Sharpen the example snippet if the new instance is clearer.
- Do **not** create a duplicate file.

**No matching lesson** → draft a new lesson file:
- Name it `<dimension>-<slug>.md` (e.g. `error-handling-temp-then-rename.md`).
- Populate the frontmatter (see schema below) and write the body in the
  `principle → trap → fix → habit` shape.
- Set `occurrences: 1`, `first_seen` and `last_seen` to today.
- Generalise the snippet — teach the class, do not fingerprint the specific PR.

### Step 5 — Update INDEX.md

After all lessons are written or strengthened, regenerate (or update) the index
table in `INDEX.md`:

```
# Lessons index

| Lesson | Dimension | Severity | Seen |
|---|---|---|---|
| [Write-to-temp-then-rename for any in-place file edit](error-handling-temp-then-rename.md) | error-handling | high | 3 |
```

New lessons are APPENDED as rows; existing rows are left in place so the harvest
produces a minimal diff. Every lesson file must have exactly one row; every row must
point to an existing file.

### Step 6 — Report the harvest

Print a human-readable summary covering:

- **Added:** new lessons (title, dimension, severity).
- **Strengthened:** existing lessons whose `occurrences` were bumped (title,
  old → new count).
- **Dropped:** findings excluded by the teachability filter, with the reason for
  each (`low severity + single reviewer + no recurrence`, etc.).

No silent caps. The harvest is auditable: a reader should be able to reconstruct
exactly which ledger findings produced which lessons.

## Anonymisation rule

Model identity from `raised_by` is a signal during steps 2–4 (multi-model
agreement elevates teachability and confidence). It is **never carried into a
lesson**. Lessons record only PR sources (e.g. `"PR#36"`) — no model names. The
anonymisation boundary sits at the ledger → lesson step.

This keeps the corpus codebase-scoped rather than model-scoped, and means the same
lesson strengthens regardless of which reviewer model raises the finding.

## Lesson file schema

Each lesson lives at `<corpus-dir>/<dimension>-<slug>.md`.

**Frontmatter:**

```yaml
---
title: "Write-to-temp-then-rename for any in-place file edit"
dimension: error-handling          # one of the 10 fixed rubric keys
severity: high                     # typical landing severity for this class
occurrences: 3                     # recurrence counter — the persistent-weakness signal
first_seen: 2026-06-28             # ISO date: first time this class appeared
last_seen: 2026-07-15              # ISO date: most recent occurrence
sources: ["PR#36", "PR#41"]        # PR refs — NO model names (anonymised)
status: active                     # active | retired
---
```

**Body shape:** `principle → trap → fix → habit`

1. **Principle** — the general rule in one sentence.
2. **Trap** — the concrete mistake pattern (generalised, not PR-specific).
3. **Fix** — what the correct implementation looks like; include a generalised
   snippet if it aids clarity.
4. **Habit** — the checklist cue a contributor should apply before shipping.

Keep snippets generalised. The goal is to teach the *class* of mistake so that a
contributor reading the lesson before writing new code avoids it entirely.

## Corpus path

Default: `docs/contributing/lessons/` (relative to the repo root where the skill
runs). This is overridable — point the skill at a different path when the target
repo uses a different lessons location.

Synthesis writes into whatever repo it is run in: the lessons corpus lives
alongside the code it governs.

## Integrity gate

After writing or updating any lesson file and `INDEX.md`, run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/synthesize-review-learnings/scripts/check-index.sh" <lessons-dir>
```

This script verifies:
- Every `*.md` file (except `INDEX.md`) has all required frontmatter keys.
- Every lesson file has exactly one matching row in `INDEX.md`, and vice versa
  (no orphan files, no dead links).

If `check-index.sh` exits non-zero, fix the reported problem **before** finishing.
Do not report the harvest as complete while the integrity check fails.

## Example invocation

```
/tss-review-skills:synthesize-review-learnings
```

Or with a specific ledger:

```
/tss-review-skills:synthesize-review-learnings .reviews/r3/ledger.json
```

The skill reads the ledger(s), runs the pipeline, updates the corpus, and prints
the harvest report. Run it after each review cycle, or batch it across several
ledgers at once to catch patterns that span multiple PRs.

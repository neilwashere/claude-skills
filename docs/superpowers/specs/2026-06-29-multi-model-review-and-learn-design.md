# Multi-model review → learning loop — design

**Status:** approved (brainstorm) — pending implementation plan
**Date:** 2026-06-29
**Plugin:** `tss-review-skills` (new, second plugin in the `neilwashere` marketplace)

## Why this exists

Human review is reducing. As more code is produced by LLM drivers, the scarce
resource is *judgement applied to the diff* — and the durable record of "what
good looks like" for a codebase.

A PR review is a clean signal of an LLM's weaknesses. This design turns each
review into two outputs at once:

1. **Immediate** — inline critique a driving agent fixes, iterating until a
   panel of reviewers is satisfied (lightweight, in-the-moment correction).
2. **Durable** — a synthesised, anonymised *lesson* added to a contributor
   corpus, so the same class of mistake is taught once and caught forever
   (lightweight "training" across the dimensions a model is weak at).

The corpus then feeds *back* into review (reviewers detect recurrence) and into
authoring (the driver reads it before writing), closing the loop.

This generalises a one-off cycle already run in this repo: several rounds of
multi-round PR review whose findings were hand-categorised into
`docs/contributing/closing-the-verification-loop.md`. That essay is the seed; this
makes the pattern repeatable and self-growing.

## Goals

- Two skills: `review-changes` (the review engine) and
  `synthesize-review-learnings` (ledgers → corpus).
- A **stable interface** — a JSON findings ledger — between review, the
  address-loop, and synthesis, so all three are model- and harness-agnostic.
- A **structured, self-converging lesson library** that doubles as a
  persistent-weakness tracker.
- Portable: the panel of reviewer models is variable input; dispatch is
  pluggable across harnesses (pi, Claude Code, bare CLIs).

## Non-goals

- Not a GitHub-coupled tool. Posting to a PR is an optional adapter; the
  findings report is the source of truth.
- Not a per-model report card. Lessons are anonymised codebase standards.
- No type-design / performance / accessibility / backward-compat as *core*
  dimensions — they are conditional lenses applied only when a change touches
  that surface.

## Four load-bearing decisions

1. **New plugin** `tss-review-skills` in this marketplace (keeps `tss-git-skills`
   git-scoped).
2. **Structured lesson library + index** as the corpus shape (one file per
   lesson, append-and-strengthen, not an ever-growing essay).
3. **Fully anonymised** lessons — codebase standards, no model attribution in
   metadata or prose.
4. **Findings-report-first** — a structured JSON ledger is canonical; posting to
   a GitHub PR is an optional adapter on top.

## Architecture — the loop

```
spec/diff ─▶ review-changes ─▶ ledger.json ─▶ address-loop ─▶ (converged ledger)
                  ▲                                                   │
                  │ charter feeds reviewers the lessons index          ▼
            lessons/ ◀──────────── synthesize-review-learnings ◀───────┘
            (corpus)                  (ledgers → anonymised lessons)
```

The ledger is the spine. Reviewers write it; the driver addresses against it;
synthesis harvests it. The corpus it produces is fed back to reviewers (recurrence
detection) and to authors (guidance) — that feedback is what makes the signal
"training".

---

## Section 1 — The review rubric

The rubric is the **portable lens set**. The **bar** for each lens comes from the
repo under review: reviewers read `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, and
any repo-local review agents/skills first and treat those as authoritative —
especially for Conventions and Security & safety, which are inherently
repo-specific. This keeps the rubric from going stale: a repo tightens its own bar
without editing the skill.

### Core dimensions (10) — always applied

| Key | Dimension | The question | "Good" looks like |
|---|---|---|---|
| `logic` | Logic & edge cases | Right result on normal + boundary inputs? | No off-by-one/wrong-branch; empty/null/large handled. |
| `error-handling` | Error handling & failure modes | What happens when something *fails*? | Errors raised not swallowed; fails loudly; no silent wrong-fallback; **destructive ops fail safe** (guard-then-act, write-temp-then-rename, no half-completion). |
| `testing` | Testing & verification | Could these tests actually fail? Claims run or reasoned? | Tests proven to go red; behaviour observed, not described. |
| `architecture` | Architecture | Right seams; fits the system grain? | Logic at the altitude that scales; clean coupling. |
| `abstractions` | Abstractions | Right level — reuse vs reinvent; leaky? | Existing helpers reused; no lossy round-trips; boundaries you can change behind. |
| `conciseness` | Conciseness | Anything carrying no weight? | No dead code/duplication; YAGNI respected. |
| `maintainability` | Maintainability | Will the next reader safely change it? | Clear names; no hidden coupling. |
| `documentation` | Documentation & comments | Are comments/docs *accurate*, useful, not superfluous? | Comments match code; no rot; docs back claims with run output. |
| `security` | Security & safety | Can crafted input make it do harm? | Untrusted input handled; no injection/unescaped interpolation; secrets safe; safe FS/permissions. |
| `conventions` | Conventions | Matches stated + de-facto repo patterns? | Follows CLAUDE.md, file/skill structure, naming idioms. |

Notes on the cut (rationale captured so it isn't re-litigated):

- **No "Correctness" dimension.** Published tools (pr-review-toolkit, the official
  `code-review`, superpowers' reviewer template) never name one — "is it a bug" is
  the **severity ceiling**, not a lens. The old catch-all "Correctness" was split
  into `logic` (rightness when it works) and `error-handling` (behaviour when it
  fails); `error-handling` absorbs the `silent-failure-hunter` lens and the
  destructive-op failure-path material.
- **`documentation` is first-class** — validated by the dedicated
  `comment-analyzer` agent, and the dominant artifact in a skills repo (skills
  *are* prose). Distinct from `maintainability`: a comment can be clear yet wrong.

### Conditional lenses — applied only when the change touches that surface

`type-design`, `performance`, `backward-compat`, `accessibility`. Reviewers apply
these like the published tools fire specialised agents: only when relevant.

### Severity (orthogonal to dimension)

`high` 🔴 (must fix — wrong/unsafe/data-loss) · `medium` 🟠 (should fix — real, not
blocking) · `low` 🟢 (nit/taste — author's call). "Is it a bug?" lands a finding at
`high`; it is not itself a dimension.

The rubric lives once in `review-changes/references/rubric.md`;
`synthesize-review-learnings` imports the same 10 keys, so a reviewer's finding
category and a lesson's `dimension` tag share one vocabulary — no drift.

---

## Section 2 — The findings ledger (the stable interface)

**Canonical format: JSON.** Written by reviewers, read by the address-loop and by
synthesis — all machine consumers. A human-readable render is a throwaway view,
never a second stored copy (avoids the lossy-round-trip / drift trap the corpus
itself warns about).

### Write-isolation

Reviewers run as parallel agents sharing the repo filesystem. One shared file
would race, so each reviewer writes **only its own** file; the driver merges:

```
.reviews/<run-id>/
  findings.<reviewer>.json     ← each reviewer writes only its own
  ledger.json                  ← driver MERGES them; canonical; carries status
```

`.reviews/` is **gitignored** (ephemeral working state). Path is configurable;
this is the default. Ledgers persist until harvested by synthesis (they are not
auto-deleted), so a deliberate `synthesize` step never loses data.

### Per-finding schema (`ledger-schema.json`, shared with synthesis)

```json
{
  "id": "r2-004",
  "dimension": "error-handling",
  "severity": "high",
  "file": "skills/teardown/SKILL.md",
  "line": 42, "end_line": 47, "side": "RIGHT",
  "title": "jq failure leaves config truncated",
  "detail": "the critique + what 'good' looks like",
  "suggestion": "write-to-temp-then-mv; guard jq -e first",
  "raised_by": ["opus", "kimi"],
  "status": "open",
  "resolution": null,
  "round": 1
}
```

- `line`/`end_line`/`side`/`commit` — range; `side`/`commit` needed only by the PR
  adapter.
- `raised_by` — which **models** flagged it. Cross-family agreement = strongest
  signal; populated at merge by dedup.
- `status` ∈ `open | addressed | wontfix | disputed`; `resolution` filled by the
  driver when addressed; `round` = first appearance. `resolution` + `round` are
  prime synthesis signal (a finding that took three rounds is a real weakness).

### Lifecycle

`created → addressed (status + resolution) → re-review (confirm/close or reopen) →
converged → retained → synthesised → optionally archived/cleared`.

---

## Section 3 — `review-changes` skill (the review engine)

Model- and user-invokable. The skill owns the **portable** parts (charter,
contract, merge, post); the harness owns the dispatch **mechanism**.

### Layout

```
review-changes/
  SKILL.md                      ← orchestration playbook
  references/
    rubric.md                   ← the 10 dimensions + severity (shared vocab)
    reviewer-charter.md         ← prompt template handed to each reviewer
    ledger-schema.json          ← schema + example (shared with synthesis)
  scripts/
    merge-findings.sh           ← per-reviewer files → ledger.json (dedup, raised_by)
    post-to-pr.sh               ← optional: ledger.json → gh inline comments
```

The two scripts make the fiddly bits deterministic and testable (this repo's
"bundle the fiddly thing as a shipped script" culture). `post-to-pr.sh` is where
the gh-api inline-comment dance lives — called, not reconstructed each time.

### Flow (driver runs this)

1. **Resolve inputs** — the change (`base..head` SHAs, a PR ref, or working-tree
   diff) + the **spec/plan** the agent built from. Create `.reviews/<run-id>/`.
2. **Compose the charter** from `reviewer-charter.md` (rubric inlined + the change
   + the spec + the lessons-library index).
3. **Dispatch the panel** — one reviewer per panel model, in parallel; each writes
   only `findings.<model>.json`.
4. **Merge** — `merge-findings.sh` → `ledger.json`. Dedup key is
   `(dimension, file, overlapping line-range)` with title similarity as a
   tie-breaker; on a match the findings collapse to one and their reviewer labels
   union into `raised_by`. Non-matching findings pass through untouched.
5. **(Optional) post** — `post-to-pr.sh` renders each finding as an inline comment.
6. **Address loop** — driver fixes, sets `status`/`resolution`, re-dispatches round
   N+1 against open findings + new diff. **Converges when no `open` finding is
   HIGH or MEDIUM** (every MEDIUM fixed or explicitly `wontfix` with rationale;
   the `wontfix` rationale is itself synthesis signal). LOW findings are advisory.

### Reviewer charter — load-bearing parts

- **Read-only discipline, stated hard.** Reviewers are agents on the shared
  checkout; they must not move HEAD, switch branches, or mutate the tree (use
  `git show`/`git diff`, or a throwaway worktree for another rev). Encodes a hazard
  hit in the seed cycle (review agents switched the shared checkout's branch).
- **Discover the bar.** Read `CLAUDE.md`/`CONTRIBUTING.md`/`README.md` + repo
  review agents first; treat as authoritative.
- **Check for recurrence.** Given the lessons-library index, flag when a finding
  repeats a previously-taught lesson — highest-value synthesis signal.
- **False-positive guard** (from the official Anthropic tool): skip pre-existing
  issues, linter/compiler-catchable nits, and anything on lines the change didn't
  touch. Acknowledge strengths; never mark a nitpick critical.
- **Output contract:** write findings matching `ledger-schema.json`; calibrate
  severity; cite `file:line`.

### Panel = config + invocation override

- **`review-panel.json`**, three-tier like `worktree-config.json`
  (`.claude/` committed → `.local.json` → `~/.claude/` global). Repo *recommends* a
  panel; user-global says what models they can target; **invocation override is
  primary** ("review with opus, kimi, deepseek" wins).
- Per-model entries may carry dispatch hints (effort; an external command template
  for CLI-only models).
- The skill is **empty-panel-safe**: errors clearly if no panel is configured or
  named.

### Dispatch is harness-pluggable; the contract is uniform

The SKILL.md says, harness-neutrally: *for each panel model, spawn a reviewer on
that model using your harness's mechanism; hand it the charter + its output path.*

- **pi** → pi's model-targeted task dispatch
- **Claude Code** → `Agent` tool with a `model` override
- **CLI-only** → external command template (`codex -m gpt-5.5 …`, `llm -m deepseek …`)

Every reviewer honors the same contract (read charter, write
`findings.<model>.json`). `raised_by` carries model names, so cross-family
agreement falls out for free — and `merge-findings.sh`, the ledger, and synthesis
stay fully model- and harness-agnostic.

---

## Section 4 — `synthesize-review-learnings` skill

User-invoked (you choose when to harvest; single ledger or batched). Reads only
the canonical ledgers in `.reviews/*/ledger.json` — never scrapes GitHub.

### Distillation pipeline

1. **Load** all findings from the target ledger(s).
2. **Teachability filter** — keep a finding only if it's a *class*, not an
   incident: `severity ≥ MEDIUM`, **or** it took multiple rounds, **or** multiple
   models flagged it (`raised_by ≥ 2`), **or** it recurs a known lesson. Everything
   else is reported-but-dropped.
3. **Cluster** survivors by `dimension` + underlying principle (semantic, not by
   file).
4. **Dedup against the index** — for each cluster, does a lesson of this class
   already exist?
   - **Yes →** *strengthen* it: bump `occurrences`, update `last_seen`, add the
     source, sharpen the example if clearer. No duplicate file.
   - **No →** draft a new lesson.
5. **Update `INDEX.md`.**
6. **Report the harvest** — what was added, what was strengthened, and *what was
   dropped and why* (the corpus's own "no silent caps" principle, applied to the
   tool — the harvest is auditable).

Model identity from `raised_by` is used only as a *signal* in steps 2-4
(multi-model agreement raises a finding's teachability and confidence); it is
**never carried into the lesson**. Lessons record PR sources but no model names —
the anonymisation boundary sits at the ledger→lesson step.

Step 4 makes the library **converge** instead of bloat, and turns `occurrences`
into a **persistent-weakness tracker**: `occurrences: 5, last_seen: 3 months later`
= a blind spot that isn't closing. That is the durable, anonymised training signal.

### Lesson file schema

```
docs/contributing/lessons/
  INDEX.md                              ← index: title · dimension · severity · occurrences · link
  error-handling-temp-then-rename.md    ← one lesson per file
```

```yaml
---
title: "Write-to-temp-then-rename for any in-place file edit"
dimension: error-handling          # one of the 10 fixed keys
severity: high                     # typical landing severity for this class
occurrences: 3                     # recurrence counter — the weakness signal
first_seen: 2026-06-28
last_seen: 2026-07-15
sources: ["PR#36", "PR#41"]        # PR refs ok; NO model names (anonymised)
status: active                     # active | retired
---
```

Body follows the seed essay's proven shape: **principle → trap → fix → habit**,
with *generalised* snippets (teach the class, don't fingerprint the PR).

### Corpus path

Default `docs/contributing/lessons/`, overridable per-repo. Synthesis writes into
whatever repo it runs in.

---

## Section 5 — Corpus migration (retire & decompose the essay)

`docs/contributing/closing-the-verification-loop.md` is **retired** and decomposed
into atomic lessons under `docs/contributing/lessons/`:

- Four principle lessons: `testing-watch-it-fail`, `documentation-observe-dont-describe`,
  `environment-is-an-input`, `error-handling-design-the-failure-path`.
- Taste items become short lessons under `abstractions` / `conciseness`
  (reuse-over-reimplement, no-lossy-round-trip, lean-entry-defers,
  fix-at-the-altitude-that-scales).
- Seed `occurrences`/`first_seen` from the seed cycle; `INDEX.md` lists them.

`lessons/` becomes the **only** corpus (single source, zero drift). `README.md` and
the root `CLAUDE.md` repoint from the essay to `lessons/INDEX.md`. This migration
doubles as dogfooding the lesson schema and seeding the library on day one.

---

## Section 6 — Packaging, naming, layout

Two separable work-streams.

**(a) The reusable plugin** — new subtree mirroring `tss-git-skills/`:

```
tss-review-skills/
  README.md                       ← lists both skills, User-/Model-invoked grouping
  .claude-plugin/plugin.json      ← name, description, author (no skills array — flat skills/ auto-scanned)
  skills/
    review-changes/               ← model- + user-invokable
    synthesize-review-learnings/  ← user-invoked (disable-model-invocation: true)
```

Add a second entry to `.claude-plugin/marketplace.json` (`name: tss-review-skills`,
`source: ./tss-review-skills`, `category: development`). Update the root `CLAUDE.md`
line that says the repo hosts a *single* plugin.

**(b) This-repo content** — the Section 5 migration (decompose essay, repoint
links). Independent of (a) but ships alongside as the dogfood.

Naming: plugin `tss-review-skills`; skills `review-changes`,
`synthesize-review-learnings`; namespaced `tss-review-skills:<skill>`.

---

## Section 7 — Testing (dogfood the verification guide)

Scripts are the testable surface; prose follows the repo's "watch it fail first"
discipline. Extend the existing root `tests/run.sh` harness (consistent with CI) +
the shellcheck gate.

| Target | Test |
|---|---|
| `merge-findings.sh` | Fixture per-reviewer files → assert merged ledger: dedup works, `raised_by` aggregates, malformed/empty input aborts loudly (not silently). |
| `post-to-pr.sh` | Split payload-builder from the `gh` call; unit-test the builder against fixtures. Live POST is integration — skipped in CI. |
| `ledger-schema.json` | Schema is itself valid; fixtures validate against it. |
| Lesson/index integrity | Every `lessons/*.md` has required frontmatter + a matching `INDEX.md` row, and vice-versa. Mechanically enforces "no drift". |

All new scripts shellcheck-clean and written to their own corpus principles
(guard-then-act, temp-then-rename for `ledger.json`, `jq -e` validation, no
swallowed errors). Each new test must be watched to fail before it is trusted.

---

## Open questions / future extensions (not v1)

- **`configure-review` skill** — guided `AskUserQuestion` setup of `review-panel.json`
  (mirrors `configure-worktree`). v1 ships file + invocation override only.
- **Author-side read-back** — a CONTRIBUTING/CLAUDE.md pointer (or a tiny pre-author
  step) that has the driver read relevant lessons before writing. v1 closes the
  loop on the reviewer side (charter feeds the index); author-side is a doc pointer.
- **`post-to-pr.sh` graduation** — if the adapter proves independently useful, it
  becomes its own `post-review-to-pr` skill with no rework (decomposition B).
- **Lesson `retired` automation** — auto-retire a lesson whose class stops
  recurring over N harvests.

## The throughline

Don't tell me the model is weak — *show me, and teach it back*. The ledger captures
the evidence; synthesis turns evidence into a converging, anonymised standard; the
standard re-enters review and authoring. Every PR review becomes one increment of
durable, lightweight training across the dimensions the model is weak at.

# Review rubric

The rubric is the **portable lens set**. The **bar** for each lens comes from the
repo under review: reviewers read `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, and
any repo-local review agents/skills first and treat those as authoritative —
especially for Conventions and Security & safety, which are inherently
repo-specific. This keeps the rubric from going stale: a repo tightens its own bar
without editing the skill.

## Core dimensions (10) — always applied

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

Notes on the cut:

- **No "Correctness" dimension.** "Is it a bug?" is the **severity ceiling**, not a
  lens. `logic` (rightness when it works) and `error-handling` (behaviour when it
  fails) together replace the old catch-all "Correctness". `error-handling` absorbs
  the silent-failure-hunter lens and the destructive-op failure-path material.
- **`documentation` is first-class** — a comment can be clear yet wrong. Distinct
  from `maintainability`.

## Conditional lenses — applied only when the change touches that surface

`type-design`, `performance`, `backward-compat`, `accessibility`. Apply these like
specialised agents: only when the change touches the relevant surface.

## Severity (orthogonal to dimension)

`high` 🔴 (must fix — wrong/unsafe/data-loss) · `medium` 🟠 (should fix — real, not
blocking) · `low` 🟢 (nit/taste — author's call).

"Is it a bug?" lands a finding at `high`; it is **not** itself a dimension.

The converge condition: no `open` finding is `high` or `medium`. Every `medium` is
either fixed or explicitly `wontfix` with rationale. `low` findings are advisory.

## Repo-supplies-the-bar principle

Reviewers read `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, and any repo-local
review agents/skills **first** and treat them as authoritative — especially for
`conventions` and `security`, which are inherently repo-specific.

This keeps the rubric from going stale: a repo tightens its own bar without editing
the skill. The rubric defines the lens vocabulary; the repo defines what "good"
means for each lens in its context.

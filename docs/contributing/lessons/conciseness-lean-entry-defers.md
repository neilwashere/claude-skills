---
title: "A lean entry-point defers; it doesn't re-explain"
dimension: conciseness
severity: low
occurrences: 1
first_seen: 2026-06-28
last_seen: 2026-06-28
sources: ["seed: closing-the-verification-loop"]
status: active
---

## Principle

When you split a document into "overview" and "reference," the overview should
*point at* the reference, not duplicate a paragraph of it. Two copies of the
same explanation will disagree within a month.

## Trap

An entry-point document — a README, a skill preamble, a short guide — that
repeats the substance of a reference document it links to. The duplication
feels helpful at first: the reader doesn't have to follow a link. But the two
copies drift as one is updated and the other is forgotten, and readers end up
with contradictory information.

```markdown
## Overview

The tool accepts a JSON ledger with the following fields:
- `dimension`: one of logic, testing, error-handling, ...
- `severity`: high, medium, or low
- `file`: the path to the file

See [ledger-schema.json](./references/ledger-schema.json) for the full schema.
```

The three bullet points are already in the schema. Once the schema gains a
fourth field, the overview is wrong.

## Fix

Point, don't duplicate. The entry-point explains *what* and *why*; the reference
defines *how*.

```markdown
## Overview

The tool accepts a JSON ledger validated against
[ledger-schema.json](./references/ledger-schema.json).
```

## Habit

Before adding detail to an entry-point, ask: is this already captured in the
reference it links to? If yes, link to it instead. A lean entry-point that
defers to a single source of truth stays correct longer than one that tries to
summarise it.

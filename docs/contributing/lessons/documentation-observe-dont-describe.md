---
title: "Observe behaviour — don't describe it"
dimension: documentation
severity: high
occurrences: 1
first_seen: 2026-06-28
last_seen: 2026-06-28
sources: ["seed: closing-the-verification-loop"]
status: active
---

## Principle

It is remarkably easy to write a confident, precise, **wrong** description of
what code does, because the description is generated from what the code *looks
like it should do* rather than from what it actually does. Documentation and
code comments are the usual victims; the failure is invisible until someone runs
it.

## Trap

Plausible reasoning that inverts the truth — both halves of the sentence can be
wrong simultaneously, and the sentence *sounds* authoritative, which is exactly
why it survives review by a reader who also reasons forward instead of running it.

```markdown
<!-- describing a heuristic parser's behaviour -->
Note: `tool -i.bak FILE` is **missed** by the scanner (it extracts `.bak`,
not `FILE`), but the write is still caught by the separate Write/Edit guard.
```

Both claims can be false: the scanner may catch `FILE` perfectly, and the
"separate guard" may not cover this path at all. One command would reveal it.

## Fix

Run the thing. Capture the real output. Paste *that* into the doc.

```console
$ printf '{"command":"tool -i.bak ./in-repo-file"}' | scanner; echo "decision=$?"
decision=denied        # the doc's claim was backwards — the truth is one command away
```

## Habit

A claim about behaviour must be backed by an execution you ran, not by a
reading of the source. If you're documenting an edge case, the proof of that
edge case is a transcript. "I traced the regex" is weaker than "I ran it and
here's what came out."

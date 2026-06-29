# Final-fix report

## RED evidence (four new tests failing against old stateless script)

Four new tests added to `tests/run.sh` above the dispatch loop. Against the
pre-fix `merge-findings.sh` the following FAILs were observed:

```
FAIL: merge aborts on malformed prior ledger (expected non-zero exit)
FAIL: merged finding keeps MAX severity     expected:[high]   actual:[low]
FAIL: merged finding keeps max-severity member fields  expected:[opus-high] actual:[kimi-low]
FAIL: re-flagged finding keeps first-appearance round  expected:[1]  actual:[2]
FAIL: unflagged addressed finding preserved expected:[addressed] actual:[]
FAIL: unflagged finding keeps resolution    expected:[fixed B]   actual:[]
FAIL: ledger reconciles to 3 findings       expected:[3]  actual:[2]
FAIL: wontfix survives re-flag              expected:[wontfix]   actual:[open]
```

All four test functions set FAILED=1; overall suite exited 1 (RED confirmed).

## jq bug found in reference implementation

The reference script's `$incKeys | index(k)` filter applies `k` to `$incKeys`
(an array of strings) rather than to each prior finding, producing the jq error
"Cannot index array with string 'dimension'" and silently leaving the ledger
unchanged. Fixed by binding the key first: `k as $pk | ($incKeys | index($pk)) == null`.

## GREEN evidence (all tests passing)

After applying the fixed `merge-findings.sh`, `reviewer-charter.md` edit, and
`SKILL.md` prose update:

```
bash tests/run.sh → 100% PASS, exit 0
```

All four new tests pass. All previously-passing tests still pass.

## shellcheck result

```
shellcheck tss-review-skills/skills/review-changes/scripts/merge-findings.sh
→ exit 0 (no findings)
```

## recurrence_of check

```
grep -c recurrence_of tss-review-skills/skills/review-changes/references/reviewer-charter.md
→ 0
```

## Per-fix summary

- **Fix 1 (max-severity dedup):** Incoming dedup now uses `max_by(sevrank)` so
  the highest-severity member's fields survive; `raised_by` is still unioned.
- **Fix 2 (round-aware reconciliation):** Script reads the existing `ledger.json`
  before writing; reconciles per policy (re-flagged keeps first-appearance round +
  id, reopens unless wontfix; unflagged kept verbatim; new = open at round N;
  malformed prior aborts). jq scoping fix applied to `$incKeys | index` line.
- **Fix 3 (schema-foreign charter field):** `recurrence_of` removed from the
  optional fields JSON block in `reviewer-charter.md`; `recurrence_of` count = 0.
  SKILL.md Step 6 rewritten to describe the round-aware address loop with the
  four-bullet reconciliation policy; `id` example updated to `r1-1` scheme.

---
title: "Design the failure path of every destructive operation"
dimension: error-handling
severity: high
occurrences: 1
first_seen: 2026-06-28
last_seen: 2026-06-28
sources: ["seed: closing-the-verification-loop"]
status: active
---

## Principle

Most code is written happy-path first, and for most code that's fine — a wrong
read is recoverable. It is **not** fine for operations that delete, overwrite,
or truncate. There, the failure path *is* the feature, and "I didn't think about
that input" becomes data loss.

## Trap

Three classic failure-path bugs often appear together:

```bash
set -e
# Truncate-before-transform: > opens and empties the file before jq produces
# its replacement. If jq fails, the file is now empty.
jq 'del(.registration)' "$CONFIG" > "$CONFIG"

# Swallowed errors: the broad else treats parse failure as "nothing to do",
# then falls through and still runs the destructive steps.
if [ -f "$CONFIG" ] && jq -e . "$CONFIG" >/dev/null 2>&1; then
  :
else
  echo "already clean"   # reached on PARSE FAILURE too
fi

# Partial completion: deletes the targets while leaving the pointer to them.
rm -f "$HOOK_FILE"
strip_section "$DOC"
```

Patching the *instance* you noticed ("handle a missing binary") doesn't fix the
*class* ("any path where the transform doesn't succeed must not proceed to
delete").

## Fix

Guard every dependency, write to a temp file and swap atomically, never
half-complete.

```bash
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }
jq -e . "$CONFIG" >/dev/null || { echo "config not valid JSON; aborting" >&2; exit 1; }

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT   # never leak the temp
jq 'del(.registration)' "$CONFIG" > "$tmp"  # write to temp...
mv "$tmp" "$CONFIG"                         # ...atomic swap only on success
rm -f "$HOOK_FILE"; strip_section "$DOC"    # delete only after the rewrite stuck
```

## Habit

For any irreversible step, enumerate the non-happy inputs *first* — tool
missing, input malformed, command exits non-zero, partial run interrupted —
and decide each one's behaviour before writing the success path. Two rules that
prevent most of the damage: **write-to-temp-then-rename** (never edit a file
in place by truncating it), and **guard, then act** (validate everything you
depend on, abort loudly — never half-complete and never report success on a
swallowed error).

---
title: "Reuse helpers rather than re-implementing them inline"
dimension: abstractions
severity: medium
occurrences: 1
first_seen: 2026-06-28
last_seen: 2026-06-28
sources: ["seed: closing-the-verification-loop"]
status: active
---

## Principle

If a helper already resolves precedence, parses config, or formats output,
call it. A second inline copy works today and silently drifts from the original
tomorrow.

## Trap

Duplicating logic because it's faster to copy-paste than to locate the
existing helper. The copy is correct at the moment it's written, but the two
implementations diverge as one is updated and the other is forgotten. The
divergence is usually silent — both paths look correct in isolation.

```bash
# Original helper already handles tier precedence and type coercion.
_wtc_field_raw() { ... }

# Inline re-implementation in a new script — subtly misses the local-tier check.
val="$(jq -r ".myField // empty" "$REPO/.claude/worktree-config.json" 2>/dev/null)"
```

## Fix

Find and call the existing helper. If it doesn't expose the exact interface you
need, extend it there rather than duplicating its body elsewhere.

```bash
# source the library that owns this concern
# shellcheck source=/dev/null
source "$LIB"
val="$(_wtc_field_raw "$REPO" myField)"
```

## Habit

Before writing a new implementation of something, ask: does this functionality
already exist somewhere in this codebase? Reuse over re-implement. When you
find yourself copying a block of logic, that's a signal to extract or call,
not paste.

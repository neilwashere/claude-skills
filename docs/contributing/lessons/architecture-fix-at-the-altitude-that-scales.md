---
title: "Put a fix at the altitude that scales"
dimension: architecture
severity: medium
occurrences: 1
first_seen: 2026-06-28
last_seen: 2026-06-28
sources: ["seed: closing-the-verification-loop"]
status: active
---

## Principle

Suppressing a problem per-instance at the ten sites you happened to touch is a
patch; promoting it to a single policy is a fix. Ask whether your change
handles the *next* occurrence too, or just the ones in front of you.

## Trap

Fixing a recurring issue locally at each occurrence rather than at the level
that owns the concern. The pattern looks like forward progress — each instance
is resolved — but the underlying cause is untouched and will surface again
wherever it hasn't been patched yet.

```bash
# Shellcheck warning SC2317 fires on every test_* function invoked dynamically.
# Silencing it per function:
# shellcheck disable=SC2317
test_field_raw_precedence() { ... }
# shellcheck disable=SC2317
test_dir_default() { ... }
# ... repeated for every test function
```

Each suppression is correct in isolation, but it doesn't explain *why* the
pattern is intentional, and the next test function added will need another one.

## Fix

Apply the policy once, at the file level, with an explanation.

```bash
# shellcheck disable=SC2317,SC2329
#   SC2317 / SC2329: test_* functions invoked dynamically via declare -F | grep
#     (SC2317 is the 0.9.x name; SC2329 is 0.10+. Both suppressed.)
```

The single annotation covers all current and future occurrences, and the
comment records the reasoning.

## Habit

When you find yourself applying the same fix to multiple sites, ask: what is
the right altitude for this change? A per-instance fix is sometimes correct
(the instances are genuinely different), but often the right move is to find
the level that owns the concern and fix it there — once, visibly, with an
explanation that covers every future occurrence.

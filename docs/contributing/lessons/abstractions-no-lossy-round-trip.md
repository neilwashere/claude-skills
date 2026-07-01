---
title: "Don't round-trip data through a lossy representation"
dimension: abstractions
severity: medium
occurrences: 1
first_seen: 2026-06-28
last_seen: 2026-06-28
sources: ["seed: closing-the-verification-loop"]
status: active
---

## Principle

Don't round-trip data through a representation that can't faithfully carry it.
If you already have structured data, emit from it directly.

## Trap

Joining a list on a delimiter character and then splitting it back corrupts any
element that contains that character. The bug is latent — it only surfaces when
an element happens to include the separator.

```bash
# Join an array of paths on | for transport, then re-split.
joined="$(printf '%s|' "${paths[@]}")"
# ...passed through an env var or command substitution...
IFS='|' read -ra restored <<< "$joined"
# Any path containing | is now silently split into multiple elements.
```

## Fix

Keep the structured form throughout. If you must cross a boundary (env var,
file, argument list), use a representation that preserves the structure — JSON,
NUL-delimited, or a positional argument per element.

```bash
# Pass each path as a separate argument — no delimiter, no corruption.
process_paths "${paths[@]}"

# Or if crossing a boundary, use JSON.
printf '%s\n' "${paths[@]}" | jq -R . | jq -s .  # proper JSON array
```

## Habit

When you find yourself joining structured data to pass it somewhere and then
splitting it back, ask: does the delimiter appear in any element? If the answer
is "probably not," that's the wrong bar. Use a representation that is
structurally safe, not one that works for today's inputs.

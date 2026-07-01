#!/usr/bin/env bash
# check-index.sh — verify lessons/ and INDEX.md are mutually consistent.
# Usage: check-index.sh <lessons-dir>
#   - every lessons/*.md (bar INDEX.md) has all required frontmatter keys
#   - every lesson is linked from INDEX.md EXACTLY once as (<filename>.md)
#     (an optional ./ prefix is accepted; the match is exact, not a regex)
#   - every INDEX.md lesson link resolves to a file
set -euo pipefail
die() { printf 'check-index: %s\n' "$1" >&2; exit 1; }

dir="${1:-}"
[ -n "$dir" ] || die "usage: check-index.sh <lessons-dir>"
[ -d "$dir" ] || die "no such dir: $dir"
index="$dir/INDEX.md"
[ -f "$index" ] || die "missing INDEX.md in $dir"

req=(title dimension severity occurrences first_seen last_seen sources status)
rc=0

# Normalized markdown-link basenames from INDEX.md (optional ./ prefix stripped).
links_norm="$(grep -oE '\((\./)?[A-Za-z0-9._-]+\.md\)' "$index" | sed -E 's/^\(//; s/\)$//; s#^\./##' || true)"

shopt -s nullglob
for f in "$dir"/*.md; do
  base="$(basename "$f")"
  [ "$base" = "INDEX.md" ] && continue
  if ! head -1 "$f" | grep -qx -- '---'; then
    printf 'check-index: %s missing frontmatter\n' "$base" >&2; rc=1; continue
  fi
  fm="$(awk 'NR>1 && /^---[[:space:]]*$/{exit} NR>1{print}' "$f")"
  for k in "${req[@]}"; do
    printf '%s\n' "$fm" | grep -q "^$k:" \
      || { printf 'check-index: %s missing frontmatter key: %s\n' "$base" "$k" >&2; rc=1; }
  done
  n="$(printf '%s\n' "$links_norm" | grep -Fxc -- "$base" || true)"
  [ "$n" = "1" ] \
    || { printf 'check-index: %s must be linked from INDEX.md exactly once (found %s)\n' "$base" "$n" >&2; rc=1; }
done
shopt -u nullglob

while IFS= read -r link; do
  [ -z "$link" ] && continue
  [ "$link" = "INDEX.md" ] && continue
  [ -f "$dir/$link" ] || { printf 'check-index: INDEX.md links missing file: %s\n' "$link" >&2; rc=1; }
done <<< "$links_norm"

[ "$rc" -eq 0 ] && printf 'check-index: OK\n' >&2
exit "$rc"

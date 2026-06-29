#!/usr/bin/env bash
# validate-frontmatter.sh — check every skills/*/SKILL.md against the open
# Agent Skills frontmatter rules (https://agentskills.io/specification):
#   - name: required, == dir name, lowercase + hyphens, no consecutive/edge hyphens, <=64
#   - description: required, 1..1024 chars
#   - compatibility: if present, <=500 chars
# No external deps (no python/jq needed for these checks).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
rc=0
fail() { printf 'FAIL %s: %s\n' "$1" "$2" >&2; rc=1; }

for skill_md in "$ROOT"/skills/*/SKILL.md; do
  dir="$(basename "$(dirname "$skill_md")")"

  # Extract the frontmatter block (between the first two '---' lines).
  fm="$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$skill_md")"
  [ -n "$fm" ] || { fail "$dir" "no YAML frontmatter"; continue; }

  name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  compat="$(printf '%s\n' "$fm" | sed -n 's/^compatibility:[[:space:]]*//p' | head -1)"

  [ -n "$name" ] || fail "$dir" "missing name"
  [ "$name" = "$dir" ] || fail "$dir" "name '$name' != dir '$dir'"
  printf '%s' "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' || fail "$dir" "name not lowercase/hyphen or has consecutive/edge hyphens"
  [ "${#name}" -le 64 ] || fail "$dir" "name >64 chars"

  [ -n "$desc" ] || fail "$dir" "missing description"
  dlen=${#desc}
  { [ "$dlen" -ge 1 ] && [ "$dlen" -le 1024 ]; } || fail "$dir" "description length $dlen not in 1..1024"

  if [ -n "$compat" ]; then
    # strip surrounding quotes for the length check
    c="${compat%\"}"; c="${c#\"}"
    [ "${#c}" -le 500 ] || fail "$dir" "compatibility >500 chars"
  fi
done

[ "$rc" -eq 0 ] && echo "frontmatter: all skills valid"
exit "$rc"

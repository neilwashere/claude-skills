#!/usr/bin/env bash
# merge-findings.sh — merge per-reviewer findings into a canonical ledger.
# Usage: merge-findings.sh <run-dir> [--round N]
#   <run-dir> holds findings.<reviewer>.json files (each a JSON array of findings).
#   Writes <run-dir>/ledger.json atomically. Dedup key: (dimension, file, line).
# shellcheck disable=SC2016  # jq programs reference $-vars passed via --arg/--argjson
set -euo pipefail

die() { printf 'merge-findings: %s\n' "$1" >&2; exit 1; }
command -v jq >/dev/null || die "jq required"

run_dir="${1:-}"
[ -n "$run_dir" ] || die "usage: merge-findings.sh <run-dir> [--round N]"
[ -d "$run_dir" ] || die "no such run dir: $run_dir"

round=1
if [ "${2:-}" = "--round" ]; then
  round="${3:-}"
  [ -n "$round" ] || die "--round needs a value"
fi

shopt -s nullglob
files=( "$run_dir"/findings.*.json )
shopt -u nullglob
[ "${#files[@]}" -gt 0 ] || die "no findings.*.json in $run_dir"

# Guard: validate every input is a JSON array BEFORE writing anything.
for f in "${files[@]}"; do
  jq -e 'type == "array"' "$f" >/dev/null 2>&1 || die "not a JSON array: $f"
done

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT

# Tag each finding with its reviewer (from the filename), concat, group + merge.
{
  for f in "${files[@]}"; do
    base="$(basename "$f")"; reviewer="${base#findings.}"; reviewer="${reviewer%.json}"
    jq --arg r "$reviewer" '[ .[] | . + {reviewer:$r} ]' "$f"
  done
} | jq -s --argjson round "$round" '
    add
    | group_by([.dimension, .file, (.line // 0)])
    | to_entries
    | map(
        .key as $i | .value as $g
        | $g[0] + {
            id: ("f" + (($i + 1) | tostring)),
            raised_by: ($g | map(.reviewer) | unique),
            status: "open",
            resolution: null,
            round: $round
          }
        | del(.reviewer)
      )
  ' > "$tmp"

mv "$tmp" "$run_dir/ledger.json"
trap - EXIT
printf 'merged %d reviewer file(s) -> %s\n' "${#files[@]}" "$run_dir/ledger.json" >&2

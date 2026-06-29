#!/usr/bin/env bash
# merge-findings.sh — merge per-reviewer findings into a canonical ledger.
# Usage: merge-findings.sh <run-dir> [--round N]
#   <run-dir> holds findings.<reviewer>.json files (each a JSON array of findings).
#   Writes <run-dir>/ledger.json atomically.
#   Dedup key: (dimension, file, line). On a tie the MAX-severity finding's
#   fields survive; raised_by unions the reviewers.
#   Round-aware: if <run-dir>/ledger.json already exists it is reconciled with
#   this round's findings — a re-flagged finding keeps its first-appearance
#   round, id, and resolution (and reopens unless it was wontfix); a prior
#   finding not re-flagged this round keeps the driver's status/resolution; a
#   new finding is added as open at --round N.
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

ledger="$run_dir/ledger.json"
tmp="$(mktemp)"; tmp_inc="$(mktemp)"; tmp_pri="$(mktemp)"
trap 'rm -f "$tmp" "$tmp_inc" "$tmp_pri"' EXIT

# Incoming: this round's findings, deduped by (dimension,file,line). On a tie the
# max-severity member's fields win; raised_by unions the reviewers.
{
  for f in "${files[@]}"; do
    base="$(basename "$f")"; reviewer="${base#findings.}"; reviewer="${reviewer%.json}"
    jq --arg r "$reviewer" '[ .[] | . + {reviewer:$r} ]' "$f"
  done
} | jq -s '
    def sevrank: {high:3, medium:2, low:1}[.severity] // 0;
    add
    | group_by([.dimension, .file, (.line // 0)])
    | map( (max_by(sevrank)) + {raised_by: (map(.reviewer) | unique)} | del(.reviewer) )
  ' > "$tmp_inc"

# Prior ledger: validate if present (never clobber a malformed one), else empty.
if [ -f "$ledger" ]; then
  jq -e 'type == "array"' "$ledger" >/dev/null 2>&1 || die "existing ledger is not a JSON array: $ledger"
  cp "$ledger" "$tmp_pri"
else
  printf '[]' > "$tmp_pri"
fi

# Reconcile incoming against prior.
jq -n --argjson round "$round" --slurpfile inc "$tmp_inc" --slurpfile pri "$tmp_pri" '
  def k: [.dimension, .file, (.line // 0)] | @json;
  def sevrank: {high:3, medium:2, low:1}[.severity] // 0;
  ($inc[0]) as $incoming |
  ($pri[0]) as $prior |
  ($prior | map({ (k): . }) | add // {}) as $pmap |
  ($incoming | map(k)) as $incKeys |
  ( $incoming
    | to_entries
    | map(
        .key as $i | .value as $c |
        ($pmap[($c | k)]) as $p |
        if $p then
          (if ($c | sevrank) >= ($p | sevrank) then $c else $p end)
          + {
              id: $p.id,
              round: $p.round,
              raised_by: (($p.raised_by // []) + ($c.raised_by // []) | unique),
              status: (if $p.status == "wontfix" then "wontfix" else "open" end),
              resolution: $p.resolution
            }
        else
          $c + {
            id: ("r" + ($round | tostring) + "-" + (($i + 1) | tostring)),
            round: $round,
            status: "open",
            resolution: null
          }
        end
      )
  ) as $reconciled |
  ( $prior | map(select( k as $pk | ($incKeys | index($pk)) == null )) ) as $untouched |
  $reconciled + $untouched
' > "$tmp"

mv "$tmp" "$ledger"
trap - EXIT
printf 'merged %d reviewer file(s), round %s -> %s\n' "${#files[@]}" "$round" "$ledger" >&2

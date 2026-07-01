#!/usr/bin/env bash
# merge-findings.sh — merge per-reviewer findings into a canonical ledger.
# Usage: merge-findings.sh <run-dir> [--round N]
#   <run-dir> holds findings.<reviewer>.json files, each a JSON array of
#   reviewer findings (ledger-schema.json#/$defs/reviewerFinding).
#   Writes <run-dir>/ledger.json atomically (temp created IN the run dir so the
#   rename is same-filesystem atomic; mktemp -p is GNU-only so a template path is
#   used instead).
#   Dedup key: (dimension, file, line, side); null line stays distinct from 0,
#   and two null-line findings are disambiguated by title. Max-severity member's
#   fields survive; raised_by unions the reviewers.
#   Round-aware: reconciles this round against an existing ledger.
# shellcheck disable=SC2016
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
[[ "$round" =~ ^[1-9][0-9]*$ ]] || die "--round must be a positive integer: $round"

shopt -s nullglob
files=( "$run_dir"/findings.*.json )
shopt -u nullglob
[ "${#files[@]}" -gt 0 ] || die "no findings.*.json in $run_dir"

# Guard: validate each input is an array of well-shaped findings BEFORE writing.
dims='["logic","error-handling","testing","architecture","abstractions","conciseness","maintainability","documentation","security","conventions"]'
for f in "${files[@]}"; do
  jq -e 'type == "array"' "$f" >/dev/null 2>&1 || die "not a JSON array: $f"
  err="$(jq -r --argjson dims "$dims" '
    def bad($i;$why): "element \($i): \($why)";
    [ to_entries[] | .key as $i | .value as $e
      | if ($e|type) != "object" then bad($i;"not an object")
        elif ($e.dimension == null) then bad($i;"missing dimension")
        elif ($dims | index($e.dimension) | not) then bad($i;"invalid dimension: \($e.dimension)")
        elif ($e.severity == null) then bad($i;"missing severity")
        elif (["high","medium","low"] | index($e.severity) | not) then bad($i;"invalid severity: \($e.severity)")
        elif ($e.file == null) then bad($i;"missing file")
        elif ($e.title == null) then bad($i;"missing title")
        elif ($e.detail == null) then bad($i;"missing detail")
        else empty end ]
    | (.[0] // "")' "$f")"
  [ -z "$err" ] || die "$f: $err"
done

ledger="$run_dir/ledger.json"
tmp="$(mktemp "$run_dir/.merge.out.XXXXXX")"
tmp_inc="$(mktemp "$run_dir/.merge.inc.XXXXXX")"
tmp_pri="$(mktemp "$run_dir/.merge.pri.XXXXXX")"
trap 'rm -f "$tmp" "$tmp_inc" "$tmp_pri"' EXIT

# Incoming: this round's findings, deduped. Key includes side; null line stays
# null; two null-line findings differ by title. Max-severity fields win.
{
  for f in "${files[@]}"; do
    base="$(basename "$f")"; reviewer="${base#findings.}"; reviewer="${reviewer%.json}"
    jq --arg r "$reviewer" '[ .[] | . + {reviewer:$r} ]' "$f"
  done
} | jq -s '
    def sevrank: {high:3, medium:2, low:1}[.severity] // 0;
    add
    | group_by([.dimension, .file, .line, (.side // "RIGHT"), (if .line == null then .title else null end)])
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
  def k: [.dimension, .file, .line, (.side // "RIGHT"), (if .line == null then .title else null end)] | @json;
  def sevrank: {high:3, medium:2, low:1}[.severity] // 0;
  ($inc[0]) as $incoming |
  ($pri[0]) as $prior |
  ($prior | map({ (k): . }) | add // {}) as $pmap |
  ($incoming | map(k)) as $incKeys |
  ( [ $prior[] | .id // ""
      | select(test("^r" + ($round|tostring) + "-[0-9]+$"))
      | sub("^r[0-9]+-"; "") | tonumber ] | max // 0 ) as $maxN |
  ( [ $incoming[] | . as $c | select($pmap[($c|k)] != null) ] ) as $matched |
  ( [ $incoming[] | . as $c | select($pmap[($c|k)] == null) ] ) as $fresh |
  ( $matched | map(
      . as $c | ($pmap[($c|k)]) as $p |
      (if ($c|sevrank) >= ($p|sevrank) then $c else $p end)
      + {
          id: $p.id,
          round: $p.round,
          raised_by: (($p.raised_by // []) + ($c.raised_by // []) | unique),
          status: (if ($p.status == "wontfix" or $p.status == "disputed") then $p.status else "open" end),
          resolution: (if ($p.status == "wontfix" or $p.status == "disputed") then $p.resolution else null end)
        }
    ) ) as $reconciled |
  ( $fresh | to_entries | map(
      .key as $i | .value
      + {
          id: ("r" + ($round|tostring) + "-" + (($maxN + $i + 1)|tostring)),
          round: $round,
          status: "open",
          resolution: null
        }
    ) ) as $added |
  ( $prior | map( k as $pk | select(($incKeys | index($pk)) == null) ) ) as $untouched |
  $reconciled + $added + $untouched
' > "$tmp"

mv "$tmp" "$ledger"
printf 'merged %d reviewer file(s), round %s -> %s\n' "${#files[@]}" "$round" "$ledger" >&2

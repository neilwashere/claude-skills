#!/usr/bin/env bash
#
# wt-rm.sh - self-contained worktree removal (the cleanup tail, run only AFTER
# the feature's PR has merged). Run from the main checkout, after you have left
# the worktree session via ExitWorktree({action: "keep"}).
#
# Bundled into the exit-and-dispose-worktree skill so it needs NO `source
# ~/.zshrc`. Plain bash, no chpwd hooks. Mirrors the `wt-rm` zsh helper: refuses
# to remove a dirty or unpushed worktree unless --force, unlinks the Claude
# context, then runs `git worktree remove`.
#
# Usage: wt-rm.sh <branch-or-path> [--force]
set -euo pipefail

_WTR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
_WTC_LIB=""
for _cand in "$_WTR_DIR/../../../lib/worktree-config.sh" "$_WTR_DIR/worktree-config.sh"; do
  [ -f "$_cand" ] && { _WTC_LIB="$_cand"; break; }
done
[ -n "$_WTC_LIB" ] || { echo "wt-rm: missing config lib (looked in ../../../lib and beside the script)" >&2; exit 1; }
# shellcheck source=/dev/null
. "$_WTC_LIB"

target="${1:?usage: wt-rm.sh <branch-or-path> [--force]}"; shift || true
force=0
for a in "$@"; do [[ "$a" == "--force" || "$a" == "-f" ]] && force=1; done

encode_path() { printf '%s' "$1" | tr '/.' '-'; }

main_root="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
[[ -n "$main_root" ]] || { echo "wt-rm: not inside a git repository" >&2; exit 1; }

# Resolve the worktree dir. Look up by BRANCH first: a branch name like
# `spike/foo` can collide with a same-named relative dir once the worktree's
# files merge into main (e.g. a `spike/foo/` harness dir), so a naive
# `[[ $target == */* && -d $target ]]` would mistake the branch for that path
# (observed 2026-06-16). Only treat target as a path when no registered
# worktree matches the branch AND it is itself a worktree checkout.
branch="${target#origin/}"
dir="$(git -C "$main_root" worktree list --porcelain \
  | awk -v b="refs/heads/$branch" '/^worktree /{p=$2} $0=="branch "b{print p; exit}')"
if [[ -z "$dir" ]]; then
  if [[ -d "$target" ]] && git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    dir="$(cd "$target" && pwd)"            # explicit existing worktree path
  else
    dir="$(wtc_worktree_dir "$main_root" "$branch")" || exit 1
  fi
fi
[[ -d "$dir" ]] || { echo "wt-rm: no worktree at $dir" >&2; exit 1; }

# Safety gates (skip with --force).
if (( ! force )); then
  if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
    echo "wt-rm: '$dir' has uncommitted changes. Pass --force to remove anyway." >&2
    git -C "$dir" status --short
    exit 1
  fi
  ahead="$(git -C "$dir" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  if [[ -n "$ahead" && "$ahead" != "0" ]]; then
    echo "wt-rm: '$dir' has $ahead unpushed commit(s). Pass --force to remove anyway." >&2
    exit 1
  fi
fi

# Unlink Claude context symlink + creds so `git worktree remove` does not balk.
wt_link="$HOME/.claude/projects/$(encode_path "$dir")"
[[ -L "$wt_link" ]] && rm "$wt_link" && echo "Claude context symlink removed"
main_real="$(cd "$main_root" && pwd -P)"
links=""
if ! links="$(wtc_worktree_link "$main_root")"; then
  echo "wt-rm: invalid worktreeLink config" >&2; exit 1
fi
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  local_dst="$dir/$rel"
  if [ -L "$local_dst" ]; then
    tgt="$(readlink "$local_dst")"
    case "$tgt" in "$main_real"/*|"$main_root"/*) rm "$local_dst" ;; esac
  fi
done <<< "$links"

git -C "$main_root" worktree remove ${force:+--force} "$dir"
echo "Worktree removed: $dir"

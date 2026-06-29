#!/usr/bin/env bash
#
# wt-new.sh - self-contained worktree CREATE (it does not, and cannot, enter).
#
# Bundled into the create-and-enter-worktree skill so it needs NO `source
# ~/.zshrc` and is immune to interactive zsh chpwd hooks (e.g. auto_vrun) that
# broke the .claude link step when the `wt-new` function was sourced into the
# non-interactive tool shell (observed 2026-06-16: a hook failure made an
# internal `cd` return non-zero, leaving the worktree path empty and turning
# `mkdir -p "$wt/.claude"` into `mkdir /.claude`).
#
# OUTPUT CONTRACT:
#   * stdout  = the worktree absolute path, and NOTHING ELSE - exactly one line.
#   * stderr  = all human-facing progress ("Worktree ready at ...", link notes).
#
# This script ONLY creates the worktree and prints its path. It does NOT move
# the session — `cd` does not persist in the Claude Code harness (cwd is
# reverted after every Bash call). To relocate the session into the worktree,
# the caller passes this script's stdout to the EnterWorktree tool:
#
#     EnterWorktree({ path: "<stdout of wt-new.sh>" })
#
# Usage: wt-new.sh <branch> [base]
#   <branch>  feature branch to create/attach (e.g. spike/code-knowledge-brain)
#   [base]    base branch (default: origin's default branch, else main)
#
# Mirrors the `wt-new` zsh helper: a sibling worktree at
# <repo-parent>/<repo>.worktrees/<branch-with-slashes-as-dashes>, with Claude
# project context + gitignored creds linked back to the main repo.
set -euo pipefail

# Resolve the shared config lib relative to THIS script (fail loud if absent —
# it ships with the plugin; a missing copy means a broken install).
_WTN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_WTC_LIB="$_WTN_DIR/../../../lib/worktree-config.sh"
if [ ! -f "$_WTC_LIB" ]; then
  echo "wt-new: missing config lib at $_WTC_LIB (broken plugin install)" >&2; exit 1
fi
# shellcheck source=/dev/null
. "$_WTC_LIB"

branch="${1:?usage: wt-new.sh <branch> [base]}"
branch="${branch#origin/}"

# Encode an absolute path the way Claude Code names ~/.claude/projects entries:
# BOTH '/' and '.' translate to '-'.
encode_path() { printf '%s' "$1" | tr '/.' '-'; }

# Link Claude project context (memory/settings) + mirror gitignored .claude
# creds from the main repo into the worktree. Pure string paths, no cd.
# All notes go to stderr so stdout stays a clean single path line.
link_claude() {
  local wt_abs="$1" main_abs="$2"
  local base="$HOME/.claude/projects"
  local main_link wt_link
  main_link="$base/$(encode_path "$main_abs")"
  wt_link="$base/$(encode_path "$wt_abs")"
  if [[ -d "$main_link" && ! -e "$wt_link" ]]; then
    ln -s "$main_link" "$wt_link" && echo "Claude context linked to main repo" >&2
  fi
  local rel src dst links
  if ! links="$(wtc_worktree_link "$main_abs")"; then
    echo "wt-new: invalid worktreeLink config" >&2; exit 1
  fi
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    src="$main_abs/$rel"; dst="$wt_abs/$rel"
    if [ -e "$src" ] && [ ! -e "$dst" ]; then
      mkdir -p "$(dirname "$dst")"
      ln -s "$src" "$dst" && echo "$rel linked to main repo" >&2
    fi
  done <<< "$links"
}

# Resolve the MAIN repo root (first worktree in the list is always the main
# checkout), regardless of where this script is invoked from.
main_root="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
[[ -n "$main_root" ]] || { echo "wt-new: not inside a git repository" >&2; exit 1; }
dir="$(wtc_worktree_dir "$main_root" "$branch")" || exit 1

# Pre-validate worktreeLink config before touching the filesystem — fail loud
# here so we never create a partial worktree with a broken link config.
_wtnew_links="$(wtc_worktree_link "$main_root")" \
  || { echo "wt-new: invalid worktreeLink config" >&2; exit 1; }

# Already registered for this branch? Ensure links, report, done.
existing="$(git -C "$main_root" worktree list --porcelain \
  | awk -v b="refs/heads/$branch" '/^worktree /{p=$2} $0=="branch "b{print p; exit}')"
if [[ -n "$existing" && -d "$existing" ]]; then
  link_claude "$existing" "$main_root"
  echo "Existing worktree: $existing" >&2
  # Surface (do NOT run) configured post-create commands, one per line, to stderr.
  pc="$(wtc_post_create "$main_root")" || true
  if [ -n "$pc" ]; then
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      echo "postCreate: $cmd" >&2
    done <<< "$pc"
  fi
  echo "$existing"
  exit 0
fi

# Determine base ref: origin/<base> if fetchable, else local <base>.
# The `|| true` is load-bearing: when origin/HEAD is not a symbolic ref (a fresh
# clone, or a remote whose HEAD was never set locally), symbolic-ref exits
# non-zero, and under `set -euo pipefail` that aborts the script BEFORE the
# `|| default_base=main` fallback can run (observed 2026-06-16). Rescuing the
# command substitution lets the empty-string fallback do its job.
default_base="$(git -C "$main_root" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null \
  | sed 's@^refs/remotes/origin/@@' || true)"
[[ -n "$default_base" ]] || default_base=main
base="${2:-$default_base}"
base_ref="origin/$base"
if ! git -C "$main_root" fetch origin "$base" 2>/dev/null; then
  if git -C "$main_root" rev-parse --verify "$base" >/dev/null 2>&1; then
    echo "wt-new: fetch failed; using local '$base'" >&2
    base_ref="$base"
  else
    echo "wt-new: cannot fetch origin and no local '$base' branch found" >&2
    exit 1
  fi
fi

# If the branch already exists (local or remote) but has no worktree, check it
# out; otherwise create it fresh off the base ref. git worktree add chatters on
# stdout, so route its output to stderr to keep our stdout contract.
if git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$main_root" worktree add "$dir" "$branch" >&2
elif git -C "$main_root" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  git -C "$main_root" worktree add "$dir" -b "$branch" "origin/$branch" >&2
else
  git -C "$main_root" worktree add "$dir" -b "$branch" "$base_ref" >&2
fi

link_claude "$dir" "$main_root"
echo "Worktree ready at $dir (based on $base_ref)" >&2
# Surface (do NOT run) configured post-create commands, one per line, to stderr.
pc="$(wtc_post_create "$main_root")" || true
if [ -n "$pc" ]; then
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    echo "postCreate: $cmd" >&2
  done <<< "$pc"
fi
echo "$dir"

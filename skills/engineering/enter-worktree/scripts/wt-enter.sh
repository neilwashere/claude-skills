#!/usr/bin/env bash
#
# wt-enter.sh - self-contained worktree create/enter for Skillet epics.
#
# Bundled into the enter-worktree skill so it needs NO `source ~/.zshrc` and
# is immune to interactive zsh chpwd hooks (e.g. auto_vrun) that broke the
# .claude link step when the `wt-new` function was sourced into the
# non-interactive tool shell (observed 2026-06-16: a hook failure made an
# internal `cd` return non-zero, leaving the worktree path empty and turning
# `mkdir -p "$wt/.claude"` into `mkdir /.claude`).
#
# OUTPUT CONTRACT (the bit that makes "cwd ends up in the worktree" reliable):
#   * stdout  = the worktree absolute path, and NOTHING ELSE - exactly one line.
#   * stderr  = all human-facing progress ("Worktree ready at ...", link notes).
# A child process cannot cd the calling shell, but the caller CAN with command
# substitution, because stdout is clean:
#
#     cd "$(bash /home/neil/code/threadsafe/claude-skills/skills/engineering/enter-worktree/scripts/wt-enter.sh <branch> [base])"
#
# In the Claude Code Bash tool that single call lands the persistent session cwd
# inside the worktree; every later Bash call then runs from there. The script
# still does no cd of its own, so chpwd hooks are sidestepped entirely.
#
# Usage: wt-enter.sh <branch> [base]
#   <branch>  feature branch to create/attach (e.g. spike/code-knowledge-brain)
#   [base]    base branch (default: origin's default branch, else main)
#
# Mirrors the behaviour of the wt-new/wt-go/wt-review zsh helpers: a sibling
# worktree at <repo-parent>/<repo>.worktrees/<branch-with-slashes-as-dashes>,
# with Claude project context + gitignored creds linked back to the main repo.
set -euo pipefail

branch="${1:?usage: wt-enter.sh <branch> [base]}"
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
  local main_link="$base/$(encode_path "$main_abs")"
  local wt_link="$base/$(encode_path "$wt_abs")"
  if [[ -d "$main_link" && ! -e "$wt_link" ]]; then
    ln -s "$main_link" "$wt_link" && echo "Claude context linked to main repo" >&2
  fi
  if [[ -d "$main_abs/.claude" ]]; then
    mkdir -p "$wt_abs/.claude"
    local f
    for f in settings.local.json .credentials.json; do
      if [[ -e "$main_abs/.claude/$f" && ! -e "$wt_abs/.claude/$f" ]]; then
        ln -s "$main_abs/.claude/$f" "$wt_abs/.claude/$f" && echo ".claude/$f linked to main repo" >&2
      fi
    done
  fi
}

# Resolve the MAIN repo root (first worktree in the list is always the main
# checkout), regardless of where this script is invoked from.
main_root="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
[[ -n "$main_root" ]] || { echo "wt-enter: not inside a git repository" >&2; exit 1; }
repo="$(basename "$main_root")"
parent="$(dirname "$main_root")"
dir="${parent}/${repo}.worktrees/${branch//\//-}"

# Already registered for this branch? Ensure links, report, done.
existing="$(git -C "$main_root" worktree list --porcelain \
  | awk -v b="refs/heads/$branch" '/^worktree /{p=$2} $0=="branch "b{print p; exit}')"
if [[ -n "$existing" && -d "$existing" ]]; then
  link_claude "$existing" "$main_root"
  echo "Existing worktree: $existing" >&2
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
    echo "wt-enter: fetch failed; using local '$base'" >&2
    base_ref="$base"
  else
    echo "wt-enter: cannot fetch origin and no local '$base' branch found" >&2
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
echo "$dir"

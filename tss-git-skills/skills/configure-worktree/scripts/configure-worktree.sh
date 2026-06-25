#!/usr/bin/env bash
# configure-worktree.sh — write worktree CONFIG to a chosen tier of the
# worktree-config marker family. Reads a JSON object of fields from stdin and
# merges it (stdin wins per key) over any existing tier file. Companion to the
# configure-worktree skill. Does NOT touch enforcement (worktree-discipline.json).
#
# Usage:  <json-object-on-stdin> | configure-worktree.sh <global|committed|local>
set -euo pipefail

scope="${1:?usage: configure-worktree.sh <global|committed|local>  (JSON object on stdin)}"
case "$scope" in
  global|committed|local) ;;
  *) echo "configure-worktree: scope must be global|committed|local" >&2; exit 2 ;;
esac

payload="$(cat)"
printf '%s' "$payload" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || { echo "configure-worktree: stdin must be a JSON object" >&2; exit 2; }

# committed/local land at the MAIN checkout root (where the resolver reads them).
main_root="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
if [ "$scope" != "global" ] && [ -z "$main_root" ]; then
  echo "configure-worktree: not inside a git repository" >&2; exit 1
fi

case "$scope" in
  global)    target="$HOME/.claude/worktree-config.json" ;;
  committed) target="$main_root/.claude/worktree-config.json" ;;
  local)     target="$main_root/.claude/worktree-config.local.json" ;;
esac

mkdir -p "$(dirname "$target")"
existing='{}'
if [ -f "$target" ] && jq empty "$target" >/dev/null 2>&1; then
  existing="$(cat "$target")"
fi
merged="$(jq -n --argjson a "$existing" --argjson b "$payload" '$a * $b')"
printf '%s\n' "$merged" > "$target"
echo "configure-worktree: wrote $scope config -> $target" >&2

if [ "$scope" = "committed" ]; then
  git -C "$main_root" add "$target" >/dev/null 2>&1 || true
  echo "  staged — commit it to share the policy" >&2
elif [ "$scope" = "local" ]; then
  gi="$main_root/.gitignore"; rel=".claude/worktree-config.local.json"
  if [ ! -f "$gi" ] || ! grep -qxF "$rel" "$gi"; then
    printf '%s\n' "$rel" >> "$gi"; echo "  gitignored $rel" >&2
  fi
fi

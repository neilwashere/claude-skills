#!/usr/bin/env bash
# configure-worktree.sh — write or show worktree CONFIG.
# Companion to the configure-worktree skill.
# Does NOT touch enforcement (worktree-discipline.json).
#
# Usage:
#   <json-object-on-stdin> | configure-worktree.sh <global|committed|local>
#   configure-worktree.sh status
set -euo pipefail

WTC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WTC_LIB=""
for _cand in "$WTC_DIR/../../../lib/worktree-config.sh" "$WTC_DIR/worktree-config.sh"; do
  [ -f "$_cand" ] && { WTC_LIB="$_cand"; break; }
done
[ -n "$WTC_LIB" ] || WTC_LIB="$WTC_DIR/../../../lib/worktree-config.sh"   # keep a path for the error message below

scope="${1:?usage: configure-worktree.sh <global|committed|local|status>}"

# ---- status ----
if [ "$scope" = "status" ]; then
  [ -f "$WTC_LIB" ] || { echo "configure-worktree: missing config lib at $WTC_LIB" >&2; exit 1; }
  # shellcheck source=/dev/null
  . "$WTC_LIB"

  main_root="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')" || true
  [ -n "$main_root" ] || { echo "configure-worktree: not inside a git repository" >&2; exit 1; }
  main_root="$(cd "$main_root" && pwd -P)"

  # Resolve each field and report its source tier.
  for field in worktreeDir postCreate worktreeLink branchNaming; do
    src="default"; val=""
    for tier_f in "$main_root/.claude/worktree-config.local.json" "$main_root/.claude/worktree-config.json" "$HOME/.claude/worktree-config.json"; do
      if [ -f "$tier_f" ]; then
        if ! jq empty "$tier_f" >/dev/null 2>&1; then
          echo "configure-worktree: warning: $tier_f is not valid JSON, skipping" >&2
        elif jq -e --arg k "$field" 'has($k)' "$tier_f" >/dev/null 2>&1; then
          src="$tier_f"
          case "$src" in "$main_root/.claude/worktree-config.local.json") src="local" ;;
            "$main_root/.claude/worktree-config.json") src="committed" ;;
            "$HOME/.claude/worktree-config.json") src="global" ;; esac
          break
        fi
      fi
    done

    case "$field" in
      worktreeDir)
        val="$(wtc_worktree_dir "$main_root" main || echo "<error>")"
        echo "worktreeDir:      $val"
        echo "  source:         $src"
        echo "  template:       $(_wtc_field_raw "$main_root" worktreeDir 2>/dev/null | jq -r '.' 2>/dev/null || echo "{parent}/{repo}.worktrees/{branch} (default)")"
        ;;
      postCreate)
        echo "postCreate:"
        val="$(wtc_post_create "$main_root" 2>/dev/null || true)"
        if [ -z "$val" ]; then
          echo "  (none)"
        else
          printf '%s\n' "$val" | sed 's/^/  /'
        fi
        echo "  source:         $src"
        ;;
      worktreeLink)
        val="$(wtc_worktree_link "$main_root" | paste -sd',' - 2>/dev/null || true)"
        echo "worktreeLink:     $val"
        echo "  source:         $src"
        ;;
      branchNaming)
        val="$(wtc_branch_naming "$main_root" 2>/dev/null || echo "<error>")"
        echo "branchNaming.embedIssueId: $val"
        echo "  source:         $src"
        ;;
    esac
    echo ""
  done
  exit 0
fi

# ---- write ----
case "$scope" in
  global|committed|local) ;;
  *) echo "configure-worktree: scope must be global|committed|local|status" >&2; exit 2 ;;
esac

payload="$(cat)"
printf '%s' "$payload" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || { echo "configure-worktree: stdin must be a JSON object" >&2; exit 2; }

# committed/local land at the MAIN checkout root (where the resolver reads them).
# Resolve only when needed — global config works anywhere, including outside a
# git repo, so don't let the (failing) git call abort under `set -e` there.
main_root=""
if [ "$scope" != "global" ]; then
  main_root="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')" || true
  [ -n "$main_root" ] || { echo "configure-worktree: not inside a git repository" >&2; exit 1; }
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

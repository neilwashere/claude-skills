#!/usr/bin/env bash
# worktree-enforce.sh — opt the current repo IN/OUT of worktree-discipline
# enforcement, or show its STATUS. Operates on the git repo containing $PWD.
#
# It manages the two markers the worktree-discipline PreToolUse hook reads
# (see the setup-worktree-discipline skill):
#   <repo>/.claude/worktree-discipline.json        committed, shared policy
#   <repo>/.claude/worktree-discipline.local.json  gitignored, per-checkout override (wins)
#
# Usage: worktree-enforce.sh <in|out|status>   (default: status)
#   in      Opt this repo IN. Write the committed marker {"enforce": true}
#           (preserving any existing allowPaths) and clear a local override that
#           would disable it. Stages the marker; commit it to share the policy.
#   out     Opt OUT (smart). If the committed marker is tracked in git, write a
#           gitignored local override {"enforce": false} so shared policy is left
#           intact; otherwise remove the local/untracked markers so the repo
#           falls back to the default (off).
#   status  Print whether enforcement is active here, from which marker, the
#           allowPaths, the checkout type, and whether the global hook is installed.
set -euo pipefail

CMD="${1:-status}"
case "$CMD" in
  in|out|status) ;;
  *) echo "usage: worktree-enforce.sh <in|out|status>" >&2; exit 2 ;;
esac

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "worktree-enforce: not inside a git repository" >&2; exit 1; }
MARKER="$TOP/.claude/worktree-discipline.json"
LOCAL="$TOP/.claude/worktree-discipline.local.json"
LOCAL_REL=".claude/worktree-discipline.local.json"

# "shared" == the marker is committed to HEAD (not merely staged), so opting out
# must not rewrite it; a staged-but-uncommitted marker is still local and `out`
# can just remove it.
committed()  { git -C "$TOP" cat-file -e "HEAD:.claude/worktree-discipline.json" 2>/dev/null; }
enforce_of() { jq -r '.enforce // false' "$1" 2>/dev/null || echo false; }

ensure_gitignore() {
  local gi="$TOP/.gitignore"
  if [ ! -f "$gi" ] || ! grep -qxF "$LOCAL_REL" "$gi"; then
    printf '%s\n' "$LOCAL_REL" >> "$gi"
    echo "  gitignored $LOCAL_REL"
  fi
}

case "$CMD" in
  in)
    mkdir -p "$TOP/.claude"
    if [ -f "$MARKER" ]; then
      updated=$(jq '.enforce = true | .allowPaths = (.allowPaths // [])' "$MARKER")
    else
      updated=$(jq -n '{enforce: true, allowPaths: []}')
    fi
    printf '%s\n' "$updated" > "$MARKER"
    if [ -f "$LOCAL" ] && [ "$(enforce_of "$LOCAL")" != "true" ]; then
      rm -f "$LOCAL"
      echo "  removed disabling override $LOCAL_REL"
    fi
    git -C "$TOP" add "$MARKER" >/dev/null 2>&1 || true
    echo "worktree-enforce: ON for $TOP"
    echo "  marker staged at .claude/worktree-discipline.json — commit it to share the policy."
    ;;

  out)
    if [ -f "$MARKER" ] && committed; then
      mkdir -p "$TOP/.claude"
      jq -n '{enforce: false}' > "$LOCAL"
      ensure_gitignore
      echo "worktree-enforce: OFF locally for $TOP"
      echo "  wrote $LOCAL_REL (committed policy left intact). Run 'in' to re-enable."
    else
      removed=0
      if [ -f "$MARKER" ]; then
        git -C "$TOP" reset -q -- "$MARKER" >/dev/null 2>&1 || true   # unstage if staged
        rm -f "$MARKER"; echo "  removed .claude/worktree-discipline.json"; removed=1
      fi
      [ -f "$LOCAL" ] && { rm -f "$LOCAL"; echo "  removed $LOCAL_REL"; removed=1; }
      [ "$removed" = 0 ] && echo "  (no markers present — already off)"
      echo "worktree-enforce: OFF for $TOP"
    fi
    ;;

  status)
    gd=$(git rev-parse --git-dir 2>/dev/null || echo "")
    gc=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
    gda=$( (cd "$gd" 2>/dev/null && pwd -P) || echo "$gd")
    gca=$( (cd "$gc" 2>/dev/null && pwd -P) || echo "$gc")
    if [ "$gda" != "$gca" ]; then
      kind="worktree (writes always allowed here)"
    else
      kind="main checkout"
    fi

    active=""; src=""
    if   [ -f "$LOCAL" ];  then active="$LOCAL";  src="local override (${LOCAL_REL})"
    elif [ -f "$MARKER" ]; then active="$MARKER"; src="repo marker (.claude/worktree-discipline.json)"
    fi

    echo "repo:        $TOP"
    echo "checkout:    $kind"
    if [ -z "$active" ]; then
      echo "enforcement: OFF (no marker)"
    else
      if [ "$(enforce_of "$active")" = "true" ]; then state="ON"; else state="OFF"; fi
      echo "enforcement: $state (from $src)"
      ap=$(jq -r '(.allowPaths // []) | join(", ")' "$active" 2>/dev/null || echo "")
      [ -n "$ap" ] && echo "allowPaths:  $ap"
      if [ -f "$LOCAL" ] && [ -f "$MARKER" ]; then
        echo "note:        committed marker enforce=$(enforce_of "$MARKER"), overridden by local override"
      fi
    fi

    settings="$HOME/.claude/settings.json"
    if [ -f "$settings" ] && jq -e '[.. | .command? // empty] | any(test("worktree-discipline.sh"))' "$settings" >/dev/null 2>&1; then
      echo "global hook:  installed"
    else
      echo "global hook:  NOT installed — run /setup-worktree-discipline (enforcement won't fire without it)"
    fi
    ;;
esac

#!/usr/bin/env bash
# worktree-enforce.sh — opt the current repo IN/OUT of worktree-discipline
# enforcement, show its STATUS, or run a DOCTOR health check. Operates on the
# git repo containing $PWD.
#
# It manages the two markers the worktree-discipline PreToolUse hook reads
# (see the setup-worktree-discipline skill):
#   <repo>/.claude/worktree-discipline.json        committed, shared policy
#   <repo>/.claude/worktree-discipline.local.json  gitignored, per-checkout override (wins)
#
# Usage: worktree-enforce.sh <in|out|status|doctor>   (default: status)
#   in      Opt this repo IN. Write the committed marker {"enforce": true}
#           (preserving any existing allowPaths) and clear a local override that
#           would disable it. Stages the marker; commit it to share the policy.
#   out     Opt OUT (smart). If the committed marker is tracked in git, write a
#           gitignored local override {"enforce": false} so shared policy is left
#           intact; otherwise remove the local/untracked markers so the repo
#           falls back to the default (off).
#   status  Print whether enforcement is active here, from which marker, the
#           allowPaths, the checkout type, and whether the global hook is installed.
#   doctor  Everything status shows, plus a full global-wiring audit (registered,
#           installed, executable, fresh, old hook gone, CLAUDE.md rule) and a
#           live-deny smoke test that proves the installed hook actually fires.
set -euo pipefail

CMD="${1:-status}"
case "$CMD" in
  in|out|status|doctor) ;;
  *) echo "usage: worktree-enforce.sh <in|out|status|doctor>" >&2; exit 2 ;;
esac

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "worktree-enforce: not inside a git repository" >&2; exit 1; }
MARKER="$TOP/.claude/worktree-discipline.json"
LOCAL="$TOP/.claude/worktree-discipline.local.json"
LOCAL_REL=".claude/worktree-discipline.local.json"

settings="$HOME/.claude/settings.json"
installed_hook="$HOME/.claude/hooks/worktree-discipline.sh"
# Source of truth: the hook bundled next to this skill in the plugin. setup
# COPIES it to ~/.claude/hooks (so it survives independently of the plugin),
# which means a plugin update leaves the copy stale — detect that drift here.
# $0 is the absolute script path, so the sibling skill resolves relative to it.
src_hook="$(dirname "$0")/../../setup-worktree-discipline/worktree-discipline.sh"

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

hook_registered() {  # 0 if the worktree-discipline hook is registered in settings.json
  [ -f "$settings" ] && jq -e '[.. | .command? // empty] | any(test("worktree-discipline.sh"))' "$settings" >/dev/null 2>&1
}

# report_repo — the per-repo section (shared by status and doctor).
report_repo() {
  local gd gc gda gca kind active src state ap
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
}

# report_hook_line — the concise one-line global-hook status (status only).
report_hook_line() {
  if hook_registered; then
    if [ ! -f "$installed_hook" ]; then
      echo "global hook:  registered but MISSING at $installed_hook — re-run /setup-worktree-discipline"
    elif [ -f "$src_hook" ] && ! cmp -s "$src_hook" "$installed_hook"; then
      echo "global hook:  installed (STALE — differs from the plugin's bundled hook)"
      echo "             update: cp \"$src_hook\" \"$installed_hook\""
    else
      echo "global hook:  installed"
    fi
  else
    echo "global hook:  NOT installed — run /setup-worktree-discipline (enforcement won't fire without it)"
  fi
}

# report_global — detailed global-wiring audit (doctor only), one line per check.
report_global() {
  echo "── global wiring ──"
  if hook_registered; then echo "  hook registered:   PASS"
  else echo "  hook registered:   FAIL — run /setup-worktree-discipline"; fi

  if [ -f "$installed_hook" ]; then echo "  hook installed:    PASS ($installed_hook)"
  else echo "  hook installed:    FAIL — MISSING at $installed_hook"; fi

  if [ -x "$installed_hook" ]; then echo "  hook executable:   PASS"
  else echo "  hook executable:   FAIL — chmod +x $installed_hook"; fi

  if [ -f "$src_hook" ] && [ -f "$installed_hook" ]; then
    if cmp -s "$src_hook" "$installed_hook"; then echo "  hook fresh:        PASS"
    else echo "  hook fresh:        STALE — cp \"$src_hook\" \"$installed_hook\""; fi
  else
    echo "  hook fresh:        SKIP (bundled or installed hook missing)"
  fi

  if [ -f "$settings" ] && jq -e '[.. | .command? // empty] | any(test("git-branch-discipline.sh"))' "$settings" >/dev/null 2>&1; then
    echo "  old hook gone:     WARN — superseded git-branch-discipline.sh still registered"
  else
    echo "  old hook gone:     PASS"
  fi

  if [ -f "$HOME/.claude/CLAUDE.md" ] && grep -q '^## Worktree discipline' "$HOME/.claude/CLAUDE.md"; then
    echo "  CLAUDE.md rule:    PASS"
  else
    echo "  CLAUDE.md rule:    FAIL — add the '## Worktree discipline' section (see /setup-worktree-discipline)"
  fi
}

# live_deny_check <hook> — 0 if <hook> denies a Write to an enforced main
# checkout (constructs a throwaway enforced repo and pipes a synthetic event).
live_deny_check() {
  local hook="$1" t out
  [ -f "$hook" ] || return 2
  t="$(mktemp -d)"
  ( cd "$t" && git init -q ) >/dev/null 2>&1 || true
  mkdir -p "$t/.claude"
  printf '{"enforce":true}' > "$t/.claude/worktree-discipline.json"
  out="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/probe.txt"}}' "$t" \
    | (cd "$t" && bash "$hook") 2>/dev/null || true)"
  rm -rf "$t"
  case "$out" in *'"permissionDecision"'*deny*) return 0 ;; *) return 1 ;; esac
}

# report_live_deny — the end-to-end proof that enforcement actually fires.
report_live_deny() {
  echo "── live behavior ──"
  if [ ! -f "$installed_hook" ]; then
    echo "  live deny:         SKIP (hook not installed)"
    return
  fi
  if live_deny_check "$installed_hook"; then
    echo "  live deny:         PASS (installed hook denies a write to an enforced main checkout)"
  else
    echo "  live deny:         FAIL (installed hook did NOT deny — enforcement is not firing)"
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
    report_repo
    report_hook_line
    ;;

  doctor)
    echo "── this repo ──"
    report_repo
    report_global
    report_live_deny
    ;;
esac

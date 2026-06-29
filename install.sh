#!/usr/bin/env bash
# install.sh — make git-worktree-skills discoverable by any agent harness.
#
# Links (default) or copies each skills/<skill> into the harness skill dirs:
#   ~/.agents/skills/   Codex, Gemini, Antigravity, Pi
#   ~/.claude/skills/   Claude Code (personal scope), Copilot, Cursor, Windsurf, Pi
# Claude Code users may instead install the plugin: /plugin install git-worktree-skills@neilwashere
#
# Safe by design: never clobbers a path it does not own; --uninstall removes
# only links/copies this script created (link target under skills/, or a
# copy stamped with .git-worktree-skills-installed).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS_SRC="$REPO_ROOT/skills"
LIB_SRC="$REPO_ROOT/lib/worktree-config.sh"
STAMP=".git-worktree-skills-installed"

AGENTS_DIR="$HOME/.agents/skills"
CLAUDE_DIR="$HOME/.claude/skills"
MODE="symlink"     # symlink | copy
ACTION="install"   # install | uninstall | list
FORCE=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  (default)          symlink every skill into ~/.agents/skills and ~/.claude/skills
  --copy             copy instead of symlink (vendors lib/ into each skill)
  --uninstall        remove only the links/copies this script created
  --list             print the skills that would be installed, then exit
  --agents-dir DIR   override ~/.agents/skills  (pass "" to skip this target)
  --claude-dir DIR   override ~/.claude/skills  (pass "" to skip this target)
  --force            replace an existing entry we own but that has drifted
  -h, --help         show this help

Claude Code users can instead run:  /plugin install git-worktree-skills@neilwashere
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --copy) MODE="copy" ;;
    --uninstall) ACTION="uninstall" ;;
    --list) ACTION="list" ;;
    --force) FORCE=1 ;;
    --agents-dir) AGENTS_DIR="${2-}"; shift ;;
    --claude-dir) CLAUDE_DIR="${2-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -d "$SKILLS_SRC" ] || { echo "install: no skills/ dir at $SKILLS_SRC" >&2; exit 1; }

list_skills() { find "$SKILLS_SRC" -mindepth 1 -maxdepth 1 -type d | sort | while read -r d; do basename "$d"; done; }

if [ "$ACTION" = "list" ]; then list_skills; exit 0; fi

targets() {
  [ -n "$AGENTS_DIR" ] && printf '%s\n' "$AGENTS_DIR"
  [ -n "$CLAUDE_DIR" ] && printf '%s\n' "$CLAUDE_DIR"
  return 0
}

dest_is_ours() { # <dest> -> 0 if a link into skills/ OR a stamped copy
  local dest="$1"
  if [ -L "$dest" ]; then
    case "$(readlink "$dest")" in "$SKILLS_SRC"/*) return 0 ;; *) return 1 ;; esac
  fi
  [ -e "$dest/$STAMP" ]
}

install_one() { # <skill> <destdir>
  local skill="$1" destdir="$2" src dest
  src="$SKILLS_SRC/$skill"; dest="$destdir/$skill"
  mkdir -p "$destdir"
  if [ -L "$dest" ] || [ -e "$dest" ]; then
    if [ "$MODE" = symlink ] && [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
      echo "  = $dest"; return 0
    fi
    if dest_is_ours "$dest"; then
      if [ "$FORCE" = 1 ]; then rm -rf "$dest"; else
        echo "  ! $dest exists (ours) — re-run with --force to replace"; return 0
      fi
    else
      echo "  ! $dest exists and is NOT ours — leaving untouched"; return 0
    fi
  fi
  if [ "$MODE" = symlink ]; then
    ln -s "$src" "$dest"; echo "  + $dest -> $src"
  else
    cp -R "$src" "$dest"; : > "$dest/$STAMP"
    if [ -f "$LIB_SRC" ] && [ -d "$dest/scripts" ]; then cp "$LIB_SRC" "$dest/scripts/worktree-config.sh"; fi
    echo "  + $dest (copy)"
  fi
}

uninstall_one() { # <skill> <destdir>
  local skill="$1" destdir="$2" dest
  dest="$destdir/$skill"
  { [ -L "$dest" ] || [ -e "$dest" ]; } || return 0
  if dest_is_ours "$dest"; then rm -rf "$dest"; echo "  - $dest"; else
    echo "  ! $dest is NOT ours — leaving untouched"
  fi
}

while read -r destdir; do
  [ -n "$destdir" ] || continue
  echo "$ACTION -> $destdir"
  while read -r skill; do
    [ -n "$skill" ] || continue
    if [ "$ACTION" = install ]; then install_one "$skill" "$destdir"; else uninstall_one "$skill" "$destdir"; fi
  done < <(list_skills)
done < <(targets)

echo "Done."

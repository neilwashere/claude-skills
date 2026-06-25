#!/usr/bin/env bash
# worktree-config.sh — resolve worktree CONFIG (not enforcement) from the 3-tier
# config marker family. Sourced by wt-new.sh / wt-rm.sh and by tests.
#
# Per field, the first tier that DEFINES it wins; absent/unparseable tiers are
# skipped. Repo-level files are read from <repo_root> = the MAIN checkout root.
#   <repo_root>/.claude/worktree-config.local.json   (gitignored, per-checkout)
#   <repo_root>/.claude/worktree-config.json          (committed, team)
#   $HOME/.claude/worktree-config.json                (user-global)
#   built-in default (handled by the per-field functions below)

# _wtc_field_raw <repo_root> <field>
# Print compact JSON value of <field> from the first defining tier; rc 1 if none.
_wtc_field_raw() {
  local repo_root="$1" field="$2" f
  for f in \
    "$repo_root/.claude/worktree-config.local.json" \
    "$repo_root/.claude/worktree-config.json" \
    "$HOME/.claude/worktree-config.json"
  do
    [ -f "$f" ] || continue
    jq empty "$f" >/dev/null 2>&1 || continue
    if jq -e --arg k "$field" 'has($k)' "$f" >/dev/null 2>&1; then
      jq -c --arg k "$field" '.[$k]' "$f"
      return 0
    fi
  done
  return 1
}

# wtc_worktree_dir <repo_root> <branch> → absolute resolved worktree dir.
wtc_worktree_dir() {
  local repo_root="$1" branch="$2" tmpl raw
  if raw="$(_wtc_field_raw "$repo_root" worktreeDir)"; then
    tmpl="$(printf '%s' "$raw" | jq -r '.')"
    [ -n "$tmpl" ] || { echo "worktree-config: worktreeDir is empty" >&2; return 1; }
  else
    tmpl='{parent}/{repo}.worktrees/{branch}'
  fi

  local repo parent slug
  repo="$(basename "$repo_root")"
  parent="$(dirname "$repo_root")"
  slug="${branch//\//-}"

  # Reject unknown {tokens} before substitution.
  local probe="$tmpl"
  probe="${probe//\{parent\}/}"; probe="${probe//\{repo\}/}"; probe="${probe//\{branch\}/}"
  case "$probe" in
    *'{'*'}'*) echo "worktree-config: unknown token in worktreeDir: $tmpl" >&2; return 1 ;;
  esac

  local out="$tmpl"
  out="${out//\{parent\}/$parent}"; out="${out//\{repo\}/$repo}"; out="${out//\{branch\}/$slug}"

  case "$out" in
    "~")    out="$HOME" ;;
    "~/"*)  out="$HOME/${out#\~/}" ;;
  esac
  out="${out//\$HOME/$HOME}"

  case "$out" in /*) ;; *) out="$parent/$out" ;; esac     # relative → against {parent}
  [ -n "$out" ] || { echo "worktree-config: worktreeDir resolved empty" >&2; return 1; }

  local norm main_norm
  norm="$(realpath -m "$out" 2>/dev/null || printf '%s' "$out")"
  main_norm="$(realpath -m "$repo_root" 2>/dev/null || printf '%s' "$repo_root")"
  case "$norm/" in
    "$main_norm/"*) echo "worktree-config: worktreeDir resolves inside the main checkout ($norm)" >&2; return 1 ;;
  esac

  printf '%s\n' "$norm"
}

# wtc_worktree_link <repo_root> → repo-root-relative link entries, one per line.
wtc_worktree_link() {
  local repo_root="$1" raw
  raw="$(_wtc_field_raw "$repo_root" worktreeLink)" \
    || raw='[".claude/settings.local.json",".claude/.credentials.json"]'
  local entries e
  mapfile -t entries < <(printf '%s' "$raw" | jq -r '.[]') || return 1
  for e in "${entries[@]}"; do
    case "$e" in
      "")     echo "worktree-config: empty worktreeLink entry" >&2; return 1 ;;
      /*)     echo "worktree-config: absolute worktreeLink entry not allowed: $e" >&2; return 1 ;;
      *..*)   echo "worktree-config: '..' not allowed in worktreeLink entry: $e" >&2; return 1 ;;
    esac
    printf '%s\n' "$e"
  done
}

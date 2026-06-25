#!/usr/bin/env bash
# tests/run.sh — plain-bash tests for the worktree config resolver.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/tss-git-skills/lib/worktree-config.sh"
# shellcheck source=/dev/null
source "$LIB"

FAILED=0
assert_eq() { # <actual> <expected> <msg>
  if [ "$1" = "$2" ]; then printf 'PASS: %s\n' "$3"
  else printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$3" "$2" "$1"; FAILED=1; fi
}
assert_fails() { # <msg> <cmd...>
  local msg="$1"; shift
  if "$@" >/dev/null 2>&1; then printf 'FAIL: %s (expected non-zero exit)\n' "$msg"; FAILED=1
  else printf 'PASS: %s\n' "$msg"; fi
}

# Make a sandbox: $SB/repo (repo root) and $SB/home (fake HOME). Echoes $SB.
new_sandbox() {
  local sb; sb="$(mktemp -d)"
  mkdir -p "$sb/repo/.claude" "$sb/home/.claude"
  printf '%s' "$sb"
}
wcfg() { printf '%s' "$2" > "$1/repo/.claude/worktree-config.json"; }        # committed
wcfg_local() { printf '%s' "$2" > "$1/repo/.claude/worktree-config.local.json"; }
wcfg_global() { printf '%s' "$2" > "$1/home/.claude/worktree-config.json"; }

test_field_raw_precedence() {
  local sb; sb="$(new_sandbox)"
  wcfg_global "$sb" '{"worktreeDir":"G"}'
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir)" '"G"' "global-only resolves"
  wcfg "$sb" '{"worktreeDir":"C"}'
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir)" '"C"' "committed beats global"
  wcfg_local "$sb" '{"worktreeDir":"L"}'
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir)" '"L"' "local beats committed"
  rm -rf "$sb"
}

test_field_raw_field_level() {
  local sb; sb="$(new_sandbox)"
  wcfg_global "$sb" '{"worktreeDir":"G"}'
  wcfg "$sb" '{"worktreeLink":["x"]}'           # committed defines a DIFFERENT field
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir)" '"G"' "field-level: worktreeDir falls through to global"
  rm -rf "$sb"
}

test_field_raw_skips_malformed() {
  local sb; sb="$(new_sandbox)"
  wcfg "$sb" '{"worktreeDir":"C"}'
  wcfg_local "$sb" 'this is not json'           # malformed local
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir)" '"C"' "malformed local skipped, committed used"
  rm -rf "$sb"
}

test_field_raw_absent() {
  local sb; sb="$(new_sandbox)"
  assert_eq "$(HOME="$sb/home" _wtc_field_raw "$sb/repo" worktreeDir; echo "rc=$?")" 'rc=1' "no tier defines field → rc 1, empty"
  rm -rf "$sb"
}

# Run every test_* function.
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do "$t"; done
exit "$FAILED"

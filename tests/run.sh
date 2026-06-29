#!/usr/bin/env bash
# tests/run.sh — plain-bash tests for the worktree config resolver.
# shellcheck disable=SC2317,SC2329,SC2016,SC2015
#   SC2317 / SC2329: test_* functions invoked dynamically via declare -F | grep
#     (SC2317 is the 0.9.x name; SC2329 is 0.10+. Both suppressed.)
#   SC2016: literal $HOME in printf strings (writing JSON settings files)
#   SC2015: A && printf PASS || { printf FAIL } pattern is intentional —
#     the printf always succeeds so the || branch is correct
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/worktree-config.sh"
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

_try_dir() { HOME="$2" wtc_worktree_dir "$1" "$3"; }

test_dir_default() {
  local sb; sb="$(new_sandbox)"; local repo="$sb/repo"
  local parent; parent="$(dirname "$repo")"; local name; name="$(basename "$repo")"
  assert_eq "$(HOME="$sb/home" wtc_worktree_dir "$repo" feat/x)" \
    "$parent/$name.worktrees/feat-x" "default template reproduces sibling layout + slug"
  rm -rf "$sb"
}
test_dir_global_template_tokens() {
  local sb; sb="$(new_sandbox)"; local repo="$sb/repo"; local name; name="$(basename "$repo")"
  wcfg_global "$sb" '{"worktreeDir":"~/wt/{repo}/{branch}"}'
  assert_eq "$(HOME="$sb/home" wtc_worktree_dir "$repo" feat/x)" \
    "$sb/home/wt/$name/feat-x" "~ + {repo}/{branch} expansion"
  rm -rf "$sb"
}
test_dir_relative_resolves_against_parent() {
  local sb; sb="$(new_sandbox)"; local repo="$sb/repo"; local parent; parent="$(dirname "$repo")"
  wcfg "$sb" '{"worktreeDir":"trees/{branch}"}'
  assert_eq "$(HOME="$sb/home" wtc_worktree_dir "$repo" main)" "$parent/trees/main" "relative resolves against {parent}"
  rm -rf "$sb"
}
test_dir_unknown_token_errors() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"worktreeDir":"/tmp/{bogus}/x"}'
  assert_fails "unknown token errors" _try_dir "$sb/repo" "$sb/home" main
  rm -rf "$sb"
}
test_dir_inside_main_rejected() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"worktreeDir":"{parent}/'"$(basename "$sb/repo")"'/inside"}'
  assert_fails "dir inside main checkout rejected" _try_dir "$sb/repo" "$sb/home" main
  rm -rf "$sb"
}

test_link_default() {
  local sb; sb="$(new_sandbox)"
  assert_eq "$(HOME="$sb/home" wtc_worktree_link "$sb/repo" | paste -sd, -)" \
    ".claude/settings.local.json,.claude/.credentials.json" "default link list"
  rm -rf "$sb"
}
test_link_override_with_env() {
  local sb; sb="$(new_sandbox)"
  wcfg "$sb" '{"worktreeLink":[".claude/settings.local.json",".env"]}'
  assert_eq "$(HOME="$sb/home" wtc_worktree_link "$sb/repo" | paste -sd, -)" \
    ".claude/settings.local.json,.env" "override includes repo-root .env"
  rm -rf "$sb"
}
_try_link() { HOME="$2" wtc_worktree_link "$1"; }
test_link_rejects_absolute() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"worktreeLink":["/etc/passwd"]}'
  assert_fails "absolute link entry rejected" _try_link "$sb/repo" "$sb/home"; rm -rf "$sb"
}
test_link_rejects_dotdot() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"worktreeLink":["../secret"]}'
  assert_fails "'..' link entry rejected" _try_link "$sb/repo" "$sb/home"; rm -rf "$sb"
}

test_wtnew_uses_configured_dir() {
  local sb; sb="$(mktemp -d)"
  local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"worktreeDir":"%s/trees/{branch}"}' "$sb" > "$repo/.claude/worktree-config.json"
  local out
  out="$( cd "$repo" && HOME="$sb/home" bash "$ROOT/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main 2>/dev/null )"
  assert_eq "$out" "$sb/trees/feat-x" "wt-new creates worktree at configured dir"
  [ -d "$sb/trees/feat-x" ] && printf 'PASS: %s\n' "configured worktree dir exists" || { printf 'FAIL: configured dir missing\n'; FAILED=1; }
  rm -rf "$sb"
}
test_wtnew_fails_loud_without_lib() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  mkdir -p "$sb/plugin"
  cp -r "$ROOT/skills" "$sb/plugin/skills"
  cp -r "$ROOT/lib" "$sb/plugin/lib"
  rm -f "$sb/plugin/lib/worktree-config.sh"
  # also remove any vendored sibling fallback so the lib is truly absent
  rm -f "$sb/plugin/skills/create-and-enter-worktree/scripts/worktree-config.sh"
  assert_fails "wt-new fails loud when lib missing" bash -c \
    'cd "'"$repo"'" && HOME="'"$sb"'/home" bash "'"$sb"'/plugin/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main'
  rm -rf "$sb"
}

test_wtrm_removes_configured_dir() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"worktreeDir":"%s/trees/{branch}"}' "$sb" > "$repo/.claude/worktree-config.json"
  ( cd "$repo" && HOME="$sb/home" bash "$ROOT/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main ) >/dev/null 2>&1
  ( cd "$repo" && HOME="$sb/home" bash "$ROOT/skills/exit-and-dispose-worktree/scripts/wt-rm.sh" feat/x ) >/dev/null 2>&1
  [ ! -d "$sb/trees/feat-x" ] && printf 'PASS: %s\n' "wt-rm removed configured-dir worktree" \
    || { printf 'FAIL: configured-dir worktree still present\n'; FAILED=1; }
  rm -rf "$sb"
}

test_hook_exempts_config_markers() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"enforce":true}' > "$repo/.claude/worktree-discipline.json"   # enforced main checkout
  local hook="$ROOT/skills/setup-worktree-discipline/worktree-discipline.sh"
  local ev
  for name in worktree-config.json worktree-config.local.json; do
    ev="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/%s"}}' "$repo" "$name")"
    out="$( cd "$repo" && printf '%s' "$ev" | bash "$hook" 2>/dev/null )"
    case "$out" in
      *'"permissionDecision":"deny"'*|*'"permissionDecision": "deny"'*)
        printf 'FAIL: hook denied .claude/%s on enforced main\n' "$name"; FAILED=1 ;;
      *) printf 'PASS: hook allows .claude/%s\n' "$name" ;;
    esac
  done
  rm -rf "$sb"
}

test_hook_denies_new_subdir_write() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"enforce":true}' > "$repo/.claude/worktree-discipline.json"   # enforced main checkout
  local hook="$ROOT/skills/setup-worktree-discipline/worktree-discipline.sh"
  # The target file's parent dir (newdir/) does NOT exist yet.
  local ev out
  ev="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/newdir/x.txt"}}' "$repo")"
  out="$( cd "$repo" && printf '%s' "$ev" | bash "$hook" 2>/dev/null )"
  case "$out" in
    *'"permissionDecision":"deny"'*|*'"permissionDecision": "deny"'*)
      printf 'PASS: %s\n' "new-subdir write denied on enforced main" ;;
    *) printf 'FAIL: new-subdir write NOT denied (enforcement bypass)\n'; FAILED=1 ;;
  esac
  rm -rf "$sb"
}

test_wtnew_links_without_claude_dir() {
  local sb; sb="$(mktemp -d)"
  local repo="$sb/repo"; mkdir -p "$repo"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  # No .claude/ dir in the repo — configure via the global tier only.
  printf 'content' > "$repo/.env"
  mkdir -p "$sb/home/.claude"
  printf '{"worktreeDir":"%s/trees/{branch}","worktreeLink":[".env"]}' "$sb" \
    > "$sb/home/.claude/worktree-config.json"
  local wt="$sb/trees/feat-x"
  ( cd "$repo" && HOME="$sb/home" bash "$ROOT/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main ) >/dev/null 2>&1
  if [ -L "$wt/.env" ]; then
    local target; target="$(readlink "$wt/.env")"
    if [ "$target" = "$repo/.env" ]; then
      printf 'PASS: %s\n' "wtnew_links_without_claude_dir: .env symlink points at main repo"
    else
      printf 'FAIL: wtnew_links_without_claude_dir: .env symlink target wrong: %s\n' "$target"; FAILED=1
    fi
  else
    printf 'FAIL: wtnew_links_without_claude_dir: .env not symlinked in worktree\n'; FAILED=1
  fi
  rm -rf "$sb"
}

test_dir_empty_value_errors() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"worktreeDir":""}'
  assert_fails "empty worktreeDir value errors" _try_dir "$sb/repo" "$sb/home" main
  rm -rf "$sb"
}

test_wtnew_invalid_link_fails_loud() {
  local sb; sb="$(mktemp -d)"
  local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  mkdir -p "$sb/home/.claude"
  printf '{"worktreeDir":"%s/trees/{branch}","worktreeLink":["/etc/passwd"]}' "$sb" \
    > "$sb/home/.claude/worktree-config.json"
  assert_fails "wt-new fails on invalid worktreeLink config" bash -c \
    'cd "'"$repo"'" && HOME="'"$sb/home"'" bash "'"$ROOT"'/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main 2>/dev/null'
  [ ! -d "$sb/trees/feat-x" ] && printf 'PASS: %s\n' "wt-new did not create worktree dir on invalid link config" \
    || { printf 'FAIL: worktree dir was created despite invalid link config\n'; FAILED=1; }
  rm -rf "$sb"
}

test_postcreate_absent() {
  local sb; sb="$(new_sandbox)"
  assert_eq "$(HOME="$sb/home" wtc_post_create "$sb/repo")" "" "absent postCreate → no output"
  rm -rf "$sb"
}
test_postcreate_string() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"postCreate":"npm install"}'
  assert_eq "$(HOME="$sb/home" wtc_post_create "$sb/repo")" "npm install" "string postCreate → one line"
  rm -rf "$sb"
}
test_postcreate_array() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"postCreate":["npm ci","npm run build"]}'
  assert_eq "$(HOME="$sb/home" wtc_post_create "$sb/repo" | paste -sd'|' -)" "npm ci|npm run build" "array postCreate → one line each"
  rm -rf "$sb"
}

test_wtnew_emits_postcreate_to_stderr() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"worktreeDir":"%s/trees/{branch}","postCreate":"npm install"}' "$sb" > "$repo/.claude/worktree-config.json"
  local out err
  out="$( cd "$repo" && HOME="$sb/home" bash "$ROOT/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main 2>"$sb/err" )"
  err="$(cat "$sb/err")"
  assert_eq "$out" "$sb/trees/feat-x" "stdout is exactly the path (no postCreate leak)"
  case "$err" in *"postCreate: npm install"*) printf 'PASS: %s\n' "postCreate note on stderr" ;; *) printf 'FAIL: postCreate note missing from stderr\n'; FAILED=1 ;; esac
  rm -rf "$sb"
}

_cfg_repo() { # echo a fresh temp repo path with git initialised
  local sb="$1"; mkdir -p "$sb/repo"
  ( cd "$sb/repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '%s' "$sb/repo"
}
CFG="$ROOT/skills/configure-worktree/scripts/configure-worktree.sh"

test_configure_committed_writes_and_stages() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfg_repo "$sb")"
  ( cd "$repo" && printf '{"worktreeDir":"X/{branch}"}' | HOME="$sb/home" bash "$CFG" committed ) >/dev/null 2>&1
  assert_eq "$(jq -r '.worktreeDir' "$repo/.claude/worktree-config.json")" "X/{branch}" "committed worktreeDir written"
  ( cd "$repo" && git diff --cached --name-only ) | grep -qx ".claude/worktree-config.json" \
    && printf 'PASS: %s\n' "committed file staged" || { printf 'FAIL: committed file not staged\n'; FAILED=1; }
  rm -rf "$sb"
}
test_configure_merges_existing() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfg_repo "$sb")"
  mkdir -p "$repo/.claude"; printf '{"worktreeLink":[".env"]}' > "$repo/.claude/worktree-config.json"
  ( cd "$repo" && printf '{"worktreeDir":"X"}' | HOME="$sb/home" bash "$CFG" committed ) >/dev/null 2>&1
  assert_eq "$(jq -r '.worktreeLink[0]' "$repo/.claude/worktree-config.json")" ".env" "existing key preserved on merge"
  assert_eq "$(jq -r '.worktreeDir' "$repo/.claude/worktree-config.json")" "X" "new key added on merge"
  rm -rf "$sb"
}
test_configure_local_gitignores() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfg_repo "$sb")"
  ( cd "$repo" && printf '{"postCreate":"npm install"}' | HOME="$sb/home" bash "$CFG" local ) >/dev/null 2>&1
  assert_eq "$(jq -r '.postCreate' "$repo/.claude/worktree-config.local.json")" "npm install" "local file written"
  grep -qx ".claude/worktree-config.local.json" "$repo/.gitignore" \
    && printf 'PASS: %s\n' "local file gitignored" || { printf 'FAIL: local not gitignored\n'; FAILED=1; }
  rm -rf "$sb"
}
test_configure_global() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfg_repo "$sb")"
  ( cd "$repo" && printf '{"worktreeDir":"G/{branch}"}' | HOME="$sb/home" bash "$CFG" global ) >/dev/null 2>&1
  assert_eq "$(jq -r '.worktreeDir' "$sb/home/.claude/worktree-config.json")" "G/{branch}" "global file written under HOME"
  rm -rf "$sb"
}
test_configure_global_outside_repo() {
  local sb; sb="$(mktemp -d)"; mkdir -p "$sb/nongit" "$sb/home"
  ( cd "$sb/nongit" && printf '{"worktreeDir":"G/{branch}"}' | HOME="$sb/home" bash "$CFG" global ) >/dev/null 2>&1
  local rc=$?
  assert_eq "$rc" "0" "global config succeeds outside a git repo"
  assert_eq "$(jq -r '.worktreeDir' "$sb/home/.claude/worktree-config.json")" "G/{branch}" "global config written outside a git repo"
  rm -rf "$sb"
}
_cfg_try() { printf '%s' "$3" | HOME="$2" bash "$CFG" "$1"; }
test_configure_bad_scope() {
  local sb; sb="$(mktemp -d)"
  assert_fails "bad scope rejected" _cfg_try bogus "$sb/home" '{"worktreeDir":"X"}'
  rm -rf "$sb"
}
test_configure_bad_json() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfg_repo "$sb")"
  assert_fails "non-object stdin rejected" bash -c 'cd "'"$repo"'" && printf "notjson" | HOME="'"$sb"'/home" bash "'"$CFG"'" committed'
  rm -rf "$sb"
}

test_branchnaming_default_true() {
  local sb; sb="$(new_sandbox)"
  assert_eq "$(HOME="$sb/home" wtc_branch_naming "$sb/repo")" "true" "branchNaming default → true"
  rm -rf "$sb"
}
test_branchnaming_false_honored() {
  local sb; sb="$(new_sandbox)"; wcfg "$sb" '{"branchNaming":{"embedIssueId":false}}'
  assert_eq "$(HOME="$sb/home" wtc_branch_naming "$sb/repo")" "false" "configured embedIssueId false honored"
  rm -rf "$sb"
}
test_branchnaming_local_overrides_committed() {
  local sb; sb="$(new_sandbox)"
  wcfg "$sb" '{"branchNaming":{"embedIssueId":false}}'
  wcfg_local "$sb" '{"branchNaming":{"embedIssueId":true}}'
  assert_eq "$(HOME="$sb/home" wtc_branch_naming "$sb/repo")" "true" "local branchNaming overrides committed"
  rm -rf "$sb"
}

WTE="$ROOT/skills/worktree-enforce/scripts/worktree-enforce.sh"

# A sandbox HOME fully wired for worktree-discipline (hook copied + registered +
# CLAUDE.md rule), and a repo opted in. Echoes "$sb".
_doctor_wired_sandbox() {
  local sb; sb="$(mktemp -d)"
  mkdir -p "$sb/home/.claude/hooks"
  cp "$ROOT/skills/setup-worktree-discipline/worktree-discipline.sh" "$sb/home/.claude/hooks/worktree-discipline.sh"
  chmod +x "$sb/home/.claude/hooks/worktree-discipline.sh"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Write|Edit|NotebookEdit|Bash","hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/worktree-discipline.sh"}]}]}}' > "$sb/home/.claude/settings.json"
  printf '## Worktree discipline\n\nrule\n' > "$sb/home/.claude/CLAUDE.md"
  mkdir -p "$sb/repo/.claude"
  ( cd "$sb/repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"enforce":true}' > "$sb/repo/.claude/worktree-discipline.json"
  printf '%s' "$sb"
}

test_doctor_all_pass_when_wired() {
  local sb; sb="$(_doctor_wired_sandbox)"
  local out; out="$( cd "$sb/repo" && HOME="$sb/home" bash "$WTE" doctor 2>&1 )"
  echo "$out" | grep -Eq 'live deny:.*PASS'   && printf 'PASS: %s\n' "doctor live-deny PASS when wired" || { printf 'FAIL: doctor live-deny not PASS\n%s\n' "$out"; FAILED=1; }
  echo "$out" | grep -Eq 'hook fresh:.*PASS'  && printf 'PASS: %s\n' "doctor hook-fresh PASS when wired" || { printf 'FAIL: doctor hook-fresh not PASS\n'; FAILED=1; }
  echo "$out" | grep -Eq 'CLAUDE.md rule:.*PASS' && printf 'PASS: %s\n' "doctor CLAUDE.md-rule PASS when wired" || { printf 'FAIL: doctor CLAUDE.md-rule not PASS\n'; FAILED=1; }
  rm -rf "$sb"
}

test_doctor_flags_problems_in_bare_home() {
  local sb; sb="$(mktemp -d)"; mkdir -p "$sb/home/.claude" "$sb/repo"
  ( cd "$sb/repo" && git init -q ) >/dev/null 2>&1
  local out rc
  out="$( cd "$sb/repo" && HOME="$sb/home" bash "$WTE" doctor 2>&1 )"; rc=$?
  assert_eq "$rc" "0" "doctor exits 0 even with nothing wired"
  echo "$out" | grep -Eq 'hook registered:.*FAIL' && printf 'PASS: %s\n' "doctor flags unregistered hook" || { printf 'FAIL: doctor did not flag missing registration\n%s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_doctor_detects_stale_hook() {
  local sb; sb="$(_doctor_wired_sandbox)"
  printf '\n# drift\n' >> "$sb/home/.claude/hooks/worktree-discipline.sh"   # make installed differ from bundled
  local out; out="$( cd "$sb/repo" && HOME="$sb/home" bash "$WTE" doctor 2>&1 )"
  echo "$out" | grep -Eq 'hook fresh:.*STALE' && printf 'PASS: %s\n' "doctor detects a stale installed hook" || { printf 'FAIL: doctor did not detect stale hook\n%s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

# ---- teardown script ----
TD="$ROOT/skills/teardown-worktree-discipline/scripts/teardown-worktree-discipline.sh"

# Sandbox with everything wired: settings.json, hook file, CLAUDE.md rule.
_wired_teardown_sandbox() {
  local sb; sb="$(mktemp -d)"
  mkdir -p "$sb/home/.claude/hooks"
  cp "$ROOT/skills/setup-worktree-discipline/worktree-discipline.sh" "$sb/home/.claude/hooks/worktree-discipline.sh"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Write|Edit|NotebookEdit|Bash","hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/worktree-discipline.sh"}]}]}}' > "$sb/home/.claude/settings.json"
  printf '## Worktree discipline\n\nrule\n' > "$sb/home/.claude/CLAUDE.md"
  printf '%s' "$sb"
}

test_teardown_removes_everything() {
  local sb; sb="$(_wired_teardown_sandbox)"
  HOME="$sb/home" bash "$TD" >/dev/null 2>&1
  # Hook no longer registered.
  jq -e '[.. | .command? // empty] | any(test("worktree-discipline.sh"))' "$sb/home/.claude/settings.json" >/dev/null 2>&1 \
    && { printf 'FAIL: teardown: hook still registered\n'; FAILED=1; } \
    || printf 'PASS: %s\n' "teardown deregisters hook"
  # Script gone.
  [ ! -f "$sb/home/.claude/hooks/worktree-discipline.sh" ] \
    && printf 'PASS: %s\n' "teardown deletes hook script" \
    || { printf 'FAIL: teardown: hook script still present\n'; FAILED=1; }
  # CLAUDE.md rule gone.
  grep -q '^## Worktree discipline' "$sb/home/.claude/CLAUDE.md" \
    && { printf 'FAIL: teardown: CLAUDE.md rule still present\n'; FAILED=1; } \
    || printf 'PASS: %s\n' "teardown strips CLAUDE.md rule"
  rm -rf "$sb"
}

test_teardown_is_idempotent() {
  local sb; sb="$(_wired_teardown_sandbox)"
  HOME="$sb/home" bash "$TD" >/dev/null 2>&1  # first run
  local out; out="$(HOME="$sb/home" bash "$TD" 2>&1)"  # second run
  echo "$out" | grep -q 'already clean' \
    && printf 'PASS: %s\n' "teardown idempotent: reports already clean" \
    || { printf 'FAIL: teardown not idempotent\n%s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_teardown_handles_nothing_installed() {
  local sb; sb="$(mktemp -d)"; mkdir -p "$sb/home/.claude"
  local out; out="$(HOME="$sb/home" bash "$TD" 2>&1)"
  echo "$out" | grep -q 'nothing to remove' \
    && printf 'PASS: %s\n' "teardown handles nothing installed" \
    || { printf 'FAIL: teardown failed on clean home\n%s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_teardown_handles_missing_settings_json() {
  local sb; sb="$(mktemp -d)"; mkdir -p "$sb/home/.claude"
  printf '## Worktree discipline\n\nrule\n' > "$sb/home/.claude/CLAUDE.md"
  # settings.json doesn't exist — should still clean up CLAUDE.md.
  HOME="$sb/home" bash "$TD" >/dev/null 2>&1
  grep -q '^## Worktree discipline' "$sb/home/.claude/CLAUDE.md" \
    && { printf 'FAIL: teardown: CLAUDE.md rule still present (no settings.json)\n'; FAILED=1; } \
    || printf 'PASS: %s\n' "teardown strips CLAUDE.md even without settings.json"
  rm -rf "$sb"
}

test_teardown_preserves_other_hooks() {
  local sb; sb="$(mktemp -d)"; mkdir -p "$sb/home/.claude"
  # settings.json with an OTHER hook + the worktree-discipline hook
  cat > "$sb/home/.claude/settings.json" <<'SETEOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash $HOME/.claude/hooks/other-hook.sh" }
        ]
      },
      {
        "matcher": "Write|Edit|NotebookEdit|Bash",
        "hooks": [
          { "type": "command", "command": "bash $HOME/.claude/hooks/worktree-discipline.sh" }
        ]
      }
    ]
  }
}
SETEOF
  HOME="$sb/home" bash "$TD" >/dev/null 2>&1
  # Other hook still registered.
  jq -e '[.. | .command? // empty] | any(test("other-hook.sh"))' "$sb/home/.claude/settings.json" >/dev/null 2>&1 \
    && printf 'PASS: %s\n' "teardown preserves other hooks" \
    || { printf 'FAIL: teardown removed other hooks\n'; FAILED=1; }
  # Worktree hook gone.
  jq -e '[.. | .command? // empty] | any(test("worktree-discipline.sh"))' "$sb/home/.claude/settings.json" >/dev/null 2>&1 \
    && { printf 'FAIL: teardown: worktree hook still registered with other hooks present\n'; FAILED=1; } \
    || printf 'PASS: %s\n' "teardown removes only worktree hook"
  rm -rf "$sb"
}

test_teardown_handles_malformed_settings() {
  local sb; sb="$(mktemp -d)"; mkdir -p "$sb/home/.claude/hooks"
  # Malformed JSON WITH the registration string AND a hook file present.
  # The script must abort BEFORE deleting the hook, leaving it intact.
  printf '{"hooks":{"PreToolUse":[{"matcher":"x","hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/worktree-discipline.sh"}]}]}
' > "$sb/home/.claude/settings.json"
  touch "$sb/home/.claude/hooks/worktree-discipline.sh"
  printf '## Worktree discipline\n\nrule\n' > "$sb/home/.claude/CLAUDE.md"
  local out rc=0
  out="$(HOME="$sb/home" bash "$TD" 2>&1)" || rc=$?
  # The script should exit non-zero (malformed JSON guard).
  [ "$rc" != "0" ] \
    && printf 'PASS: %s\n' "teardown exits non-zero on malformed settings" \
    || { printf 'FAIL: teardown should exit non-zero on malformed JSON (got rc=%s)\n' "$rc"; FAILED=1; }
  # The hook file should NOT have been deleted.
  [ -f "$sb/home/.claude/hooks/worktree-discipline.sh" ] \
    && printf 'PASS: %s\n' "teardown preserves hook file on malformed settings" \
    || { printf 'FAIL: teardown deleted hook despite malformed settings\n'; FAILED=1; }
  # The CLAUDE.md rule should NOT have been stripped.
  grep -q '^## Worktree discipline' "$sb/home/.claude/CLAUDE.md" \
    && printf 'PASS: %s\n' "teardown preserves CLAUDE.md rule on malformed settings" \
    || { printf 'FAIL: teardown stripped CLAUDE.md despite malformed settings\n'; FAILED=1; }
  rm -rf "$sb"
}

# ---- hook Bash command detection ----
HOOK="$ROOT/skills/setup-worktree-discipline/worktree-discipline.sh"
mkdir -p "$ROOT/tests/.sandboxes"

# Pipe a Bash tool event through the hook from inside a sandbox repo.
# $1 = sandbox dir (contains repo/ with .claude/worktree-discipline.json {"enforce":true})
# $2 = the Bash command string
# Echoes the hook's stdout (empty = allow, JSON with deny = deny).
_hook_bash() {
  local sb="$1" cmd="$2" ev
  # Use jq for proper JSON escaping (printf %s on raw commands can produce
  # invalid JSON when the command contains double quotes, e.g. echo "x -> y").
  ev="$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}' 2>/dev/null || echo '{}')"
  ( cd "$sb/repo" && printf '%s' "$ev" | bash "$HOOK" 2>/dev/null ) || true
}

# True if the hook denied.
_is_deny() { case "$1" in *'"permissionDecision"'*deny*) return 0 ;; *) return 1 ;; esac }

# Make a sandbox with an enforced repo (marker enforce:true, no allowPaths).
# Uses a sandbox dir that is NOT under /tmp/, /dev/, or /var/tmp/ because the
# hook exempts those prefixes (redirects into them are always allowed).
_hook_sandbox() {
  local sb
  sb="$(mkdir -p "$ROOT/tests/.sandboxes" && mktemp -d "$ROOT/tests/.sandboxes/XXXXXX" 2>/dev/null)"
  # Verify sandbox is not under an exempt prefix (mktemp -p is GNU-only;
  # the fallback above uses a template which is portable to BSD/macOS).
  case "$sb" in /tmp/*|/var/tmp/*|/dev/*) echo "FATAL: sandbox under exempt prefix: $sb" >&2; exit 1 ;; esac
  mkdir -p "$sb/repo/.claude"
  ( cd "$sb/repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"enforce":true}' > "$sb/repo/.claude/worktree-discipline.json"
  printf '%s' "$sb"
}

test_hook_bash_denies_gt_redirect_into_repo() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" "echo foo > $sb/repo/bar")"
  _is_deny "$out" \
    && printf 'PASS: %s\n' "hook denies > redirect into repo" \
    || { printf 'FAIL: hook did not deny > redirect\n  hook: %s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_hook_bash_denies_append_redirect_into_repo() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" "echo foo >> $sb/repo/bar")"
  _is_deny "$out" \
    && printf 'PASS: %s\n' "hook denies >> append into repo" \
    || { printf 'FAIL: hook did not deny >> append\n  hook: %s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_hook_bash_denies_tee_into_repo() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" "echo foo | tee $sb/repo/bar")"
  _is_deny "$out" \
    && printf 'PASS: %s\n' "hook denies tee into repo" \
    || { printf 'FAIL: hook did not deny tee\n  hook: %s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_hook_bash_denies_tee_a_into_repo() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" "echo foo | tee -a $sb/repo/bar")"
  _is_deny "$out" \
    && printf 'PASS: %s\n' "hook denies tee -a into repo" \
    || { printf 'FAIL: hook did not deny tee -a\n  hook: %s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_hook_bash_denies_sed_i_into_repo() {
  local sb; sb="$(_hook_sandbox)"
  touch "$sb/repo/bar"
  local out; out="$(_hook_bash "$sb" "sed -i 's/x/y/' $sb/repo/bar")"
  _is_deny "$out" \
    && printf 'PASS: %s\n' "hook denies sed -i into repo" \
    || { printf 'FAIL: hook did not deny sed -i\n  hook: %s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_hook_bash_allows_redirect_to_tmp() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" "echo foo > /tmp/bar")"
  _is_deny "$out" \
    && { printf 'FAIL: hook wrongly denied redirect to /tmp\n  hook: %s\n' "$out"; FAILED=1; } \
    || printf 'PASS: %s\n' "hook allows > /tmp/"
  rm -rf "$sb"
}

test_hook_bash_allows_redirect_to_dev_null() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" "echo foo > /dev/null")"
  _is_deny "$out" \
    && { printf 'FAIL: hook wrongly denied redirect to /dev/null\n  hook: %s\n' "$out"; FAILED=1; } \
    || printf 'PASS: %s\n' "hook allows > /dev/null"
  rm -rf "$sb"
}

test_hook_bash_allows_tee_to_tmp() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" "echo foo | tee /tmp/bar")"
  _is_deny "$out" \
    && { printf 'FAIL: hook wrongly denied tee to /tmp\n  hook: %s\n' "$out"; FAILED=1; } \
    || printf 'PASS: %s\n' "hook allows tee /tmp/"
  rm -rf "$sb"
}

test_hook_bash_allows_sed_i_to_tmp() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" "sed -i 's/x/y/' /tmp/bar")"
  _is_deny "$out" \
    && { printf 'FAIL: hook wrongly denied sed -i to /tmp\n  hook: %s\n' "$out"; FAILED=1; } \
    || printf 'PASS: %s\n' "hook allows sed -i /tmp/"
  rm -rf "$sb"
}

test_hook_bash_allows_arrow_operator() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" 'echo "x -> y"')"
  _is_deny "$out" \
    && { printf 'FAIL: hook wrongly denied arrow operator\n  hook: %s\n' "$out"; FAILED=1; } \
    || printf 'PASS: %s\n' "hook allows arrow operator (->)"
  rm -rf "$sb"
}

test_hook_bash_allows_fat_arrow_operator() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" 'echo "x => y"')"
  _is_deny "$out" \
    && { printf 'FAIL: hook wrongly denied fat arrow\n  hook: %s\n' "$out"; FAILED=1; } \
    || printf 'PASS: %s\n' "hook allows fat arrow operator (=>)"
  rm -rf "$sb"
}

test_hook_bash_denies_quoted_gt_false_positive() {
  # The hook parses a quoted > as a redirect — it denies echo "a > b" even
  # though this is a string literal. This documents the limitation.
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" 'echo "a > b"')"
  _is_deny "$out" \
    && printf 'PASS: %s\n' "hook denies quoted > (known false positive)" \
    || { printf 'FAIL: hook unexpectedly allowed quoted >\n  hook: %s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_hook_bash_denies_branch_creation() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" "git checkout -b newbranch")"
  _is_deny "$out" \
    && printf 'PASS: %s\n' "hook denies git checkout -b" \
    || { printf 'FAIL: hook did not deny branch creation\n  hook: %s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_hook_bash_denies_switch_c() {
  local sb; sb="$(_hook_sandbox)"
  local out; out="$(_hook_bash "$sb" "git switch -c newbranch")"
  _is_deny "$out" \
    && printf 'PASS: %s\n' "hook denies git switch -c" \
    || { printf 'FAIL: hook did not deny switch -c\n  hook: %s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_hook_bash_allows_grep_to_dev_null() {
  local sb; sb="$(_hook_sandbox)"
  # Redirect to /dev/null should be allowed even with > present.
  local out; out="$(_hook_bash "$sb" "grep foo file > /dev/null 2>&1")"
  _is_deny "$out" \
    && { printf 'FAIL: hook wrongly denied grep > /dev/null\n  hook: %s\n' "$out"; FAILED=1; } \
    || printf 'PASS: %s\n' "hook allows grep > /dev/null"
  rm -rf "$sb"
}

# ---- worktree-enforce in / out ----
# (WTE is already defined above, next to the doctor tests)

# Create a repo with a COMMITTED marker (marker is in HEAD).
_enforce_committed_repo() {
  local sb="$1"
  mkdir -p "$sb/repo/.claude"
  ( cd "$sb/repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"enforce":true,"allowPaths":["CHANGELOG.md"]}' > "$sb/repo/.claude/worktree-discipline.json"
  ( cd "$sb/repo" && git add .claude/worktree-discipline.json && git commit -q -m "add marker" ) >/dev/null 2>&1
  printf '%s' "$sb/repo"
}

# Create a repo with a STAGED-ONLY marker (on disk, not in HEAD).
_enforce_staged_repo() {
  local sb="$1"
  mkdir -p "$sb/repo/.claude"
  ( cd "$sb/repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"enforce":true}' > "$sb/repo/.claude/worktree-discipline.json"
  ( cd "$sb/repo" && git add .claude/worktree-discipline.json ) >/dev/null 2>&1
  printf '%s' "$sb/repo"
}

test_enforce_in_fresh_writes_and_stages() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_enforce_staged_repo "$sb")"
  # Remove the staged marker first, so we test 'in' on a truly fresh slate.
  rm -f "$repo/.claude/worktree-discipline.json"
  ( cd "$repo" && git reset -q -- .claude/worktree-discipline.json ) >/dev/null 2>&1 || true
  ( cd "$repo" && HOME="$sb/home" bash "$WTE" in ) >/dev/null 2>&1
  assert_eq "$(jq -r '.enforce' "$repo/.claude/worktree-discipline.json")" "true" "in fresh: enforce=true"
  assert_eq "$(jq -r '.allowPaths | length' "$repo/.claude/worktree-discipline.json")" "0" "in fresh: allowPaths empty"
  ( cd "$repo" && git diff --cached --name-only ) | grep -qx '.claude/worktree-discipline.json' \
    && printf 'PASS: %s\n' "in fresh: marker staged" || { printf 'FAIL: in fresh: marker not staged\n'; FAILED=1; }
  rm -rf "$sb"
}

test_enforce_in_preserves_allowPaths() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_enforce_committed_repo "$sb")"
  # The committed repo already has enforce:true with allowPaths=["CHANGELOG.md"].
  # Running 'in' again should preserve allowPaths.
  ( cd "$repo" && HOME="$sb/home" bash "$WTE" in ) >/dev/null 2>&1
  assert_eq "$(jq -r '.enforce' "$repo/.claude/worktree-discipline.json")" "true" "in preserves: enforce=true"
  assert_eq "$(jq -rc '.allowPaths' "$repo/.claude/worktree-discipline.json")" '["CHANGELOG.md"]' "in preserves: allowPaths kept"
  rm -rf "$sb"
}

test_enforce_in_clears_local_disable_override() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_enforce_committed_repo "$sb")"
  # Add a local override that disables enforcement.
  printf '{"enforce":false}' > "$repo/.claude/worktree-discipline.local.json"
  ( cd "$repo" && HOME="$sb/home" bash "$WTE" in ) >/dev/null 2>&1
  [ ! -f "$repo/.claude/worktree-discipline.local.json" ] \
    && printf 'PASS: %s\n' "in clears local disable override" \
    || { printf 'FAIL: in did not clear local disable override\n'; FAILED=1; }
  rm -rf "$sb"
}

test_enforce_out_committed_writes_local_override() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_enforce_committed_repo "$sb")"
  ( cd "$repo" && HOME="$sb/home" bash "$WTE" out ) >/dev/null 2>&1
  assert_eq "$(jq -r '.enforce' "$repo/.claude/worktree-discipline.local.json")" "false" "out committed: local override enforce=false"
  # Committed marker unchanged.
  assert_eq "$(jq -r '.enforce' "$repo/.claude/worktree-discipline.json")" "true" "out committed: committed marker untouched"
  grep -qx '.claude/worktree-discipline.local.json' "$repo/.gitignore" \
    && printf 'PASS: %s\n' "out committed: local override gitignored" \
    || { printf 'FAIL: out committed: local override not gitignored\n'; FAILED=1; }
  rm -rf "$sb"
}

test_enforce_out_staged_only_removes_markers() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_enforce_staged_repo "$sb")"
  # Also add a local override for good measure.
  printf '{"enforce":false}' > "$repo/.claude/worktree-discipline.local.json"
  ( cd "$repo" && HOME="$sb/home" bash "$WTE" out ) >/dev/null 2>&1
  [ ! -f "$repo/.claude/worktree-discipline.json" ] \
    && printf 'PASS: %s\n' "out staged-only: staged marker removed" \
    || { printf 'FAIL: out staged-only: staged marker still present\n'; FAILED=1; }
  [ ! -f "$repo/.claude/worktree-discipline.local.json" ] \
    && printf 'PASS: %s\n' "out staged-only: local override removed" \
    || { printf 'FAIL: out staged-only: local override still present\n'; FAILED=1; }
  rm -rf "$sb"
}

test_enforce_out_no_markers_is_noop() {
  local sb; sb="$(mktemp -d)"; local repo
  mkdir -p "$sb/repo"
  ( cd "$sb/repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  repo="$sb/repo"
  local out; out="$( cd "$repo" && HOME="$sb/home" bash "$WTE" out 2>&1 )"
  echo "$out" | grep -q 'already off' \
    && printf 'PASS: %s\n' "out no markers: reports already off" \
    || { printf 'FAIL: out no markers: did not report already off\n%s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_enforce_in_does_not_clear_local_enable_override() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_enforce_committed_repo "$sb")"
  # A local override that ALSO says enforce:true — it should survive 'in'.
  printf '{"enforce":true,"allowPaths":["docs/**"]}' > "$repo/.claude/worktree-discipline.local.json"
  ( cd "$repo" && HOME="$sb/home" bash "$WTE" in ) >/dev/null 2>&1
  [ -f "$repo/.claude/worktree-discipline.local.json" ] \
    && printf 'PASS: %s\n' "in keeps local enable override" \
    || { printf 'FAIL: in wrongly removed local enable override\n'; FAILED=1; }
  rm -rf "$sb"
}

# ---- configure-worktree status ----
CFG_STATUS="$ROOT/skills/configure-worktree/scripts/configure-worktree.sh"

_cfgstatus_repo() {
  local sb="$1"
  mkdir -p "$sb/repo/.claude" "$sb/home/.claude"
  ( cd "$sb/repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '%s' "$sb/repo"
}

test_cfgstatus_all_default() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfgstatus_repo "$sb")"
  local out; out="$( cd "$repo" && HOME="$sb/home" bash "$CFG_STATUS" status 2>&1 )"
  echo "$out" | grep -q 'source:.*default' \
    && printf 'PASS: %s\n' "cfg-status shows defaults" \
    || { printf 'FAIL: cfg-status did not show defaults\n%s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_cfgstatus_global_only() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfgstatus_repo "$sb")"
  printf '{"branchNaming":{"embedIssueId":false}}' > "$sb/home/.claude/worktree-config.json"
  local out; out="$( cd "$repo" && HOME="$sb/home" bash "$CFG_STATUS" status 2>&1 )"
  echo "$out" | grep -q 'branchNaming.embedIssueId: false' \
    && printf 'PASS: %s\n' "cfg-status picks up global branchNaming" \
    || { printf 'FAIL: cfg-status missed global config\n%s\n' "$out"; FAILED=1; }
  echo "$out" | grep -A1 'branchNaming' | grep -q 'source:.*global' \
    && printf 'PASS: %s\n' "cfg-status reports global source" \
    || { printf 'FAIL: cfg-status did not report global source\n%s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_cfgstatus_committed_beats_global() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfgstatus_repo "$sb")"
  printf '{"branchNaming":{"embedIssueId":false}}' > "$sb/home/.claude/worktree-config.json"
  printf '{"branchNaming":{"embedIssueId":true}}' > "$repo/.claude/worktree-config.json"
  local out; out="$( cd "$repo" && HOME="$sb/home" bash "$CFG_STATUS" status 2>&1 )"
  echo "$out" | grep -q 'branchNaming.embedIssueId: true' \
    && printf 'PASS: %s\n' "cfg-status committed beats global" \
    || { printf 'FAIL: cfg-status committed did not beat global\n%s\n' "$out"; FAILED=1; }
  echo "$out" | grep -A1 'branchNaming' | grep -q 'source:.*committed' \
    && printf 'PASS: %s\n' "cfg-status reports committed source" \
    || { printf 'FAIL: cfg-status did not report committed source\n%s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_cfgstatus_field_composition() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfgstatus_repo "$sb")"
  # global: worktreeDir, committed: worktreeLink, local: postCreate
  printf '{"worktreeDir":"~/g/{branch}"}' > "$sb/home/.claude/worktree-config.json"
  printf '{"worktreeLink":[".env"]}' > "$repo/.claude/worktree-config.json"
  printf '{"postCreate":"npm ci"}' > "$repo/.claude/worktree-config.local.json"
  local out; out="$( cd "$repo" && HOME="$sb/home" bash "$CFG_STATUS" status 2>&1 )"
  echo "$out" | grep -q 'worktreeLink:.*\.env' \
    && printf 'PASS: %s\n' "cfg-status worktreeLink from committed" \
    || { printf 'FAIL: worktreeLink wrong\n%s\n' "$out"; FAILED=1; }
  echo "$out" | grep -q 'npm ci' \
    && printf 'PASS: %s\n' "cfg-status postCreate from local" \
    || { printf 'FAIL: postCreate wrong\n%s\n' "$out"; FAILED=1; }
  echo "$out" | grep -A2 'worktreeDir' | grep -q 'template:.*~/g/{branch}' \
    && printf 'PASS: %s\n' "cfg-status worktreeDir template from global" \
    || { printf 'FAIL: worktreeDir template wrong\n%s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_cfgstatus_warns_on_malformed_tier() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfgstatus_repo "$sb")"
  printf 'this is not json' > "$repo/.claude/worktree-config.json"
  local out; out="$( cd "$repo" && HOME="$sb/home" bash "$CFG_STATUS" status 2>&1 )"
  echo "$out" | grep -q 'warning.*not valid JSON' \
    && printf 'PASS: %s\n' "cfg-status warns on malformed tier" \
    || { printf 'FAIL: cfg-status did not warn on malformed tier\n%s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

test_cfgstatus_branchNaming_non_object() {
  local sb; sb="$(mktemp -d)"; local repo; repo="$(_cfgstatus_repo "$sb")"
  # branchNaming as a string, not an object — should not crash.
  printf '{"branchNaming":"yes"}' > "$repo/.claude/worktree-config.json"
  local out rc
  out="$( cd "$repo" && HOME="$sb/home" bash "$CFG_STATUS" status 2>&1 )"; rc=$?
  assert_eq "$rc" "0" "cfg-status exits 0 on malformed branchNaming"
  echo "$out" | grep -q '<error>' \
    && printf 'PASS: %s\n' "cfg-status shows <error> for bad branchNaming" \
    || { printf 'FAIL: cfg-status did not handle bad branchNaming\n%s\n' "$out"; FAILED=1; }
  rm -rf "$sb"
}

# --- lib resolution under a symlinked install (install.sh default) ---
test_symlinked_skill_resolves_shared_lib() {
  local sb; sb="$(new_sandbox)"
  mkdir -p "$sb/agents/skills"
  ln -s "$ROOT/skills/configure-worktree" "$sb/agents/skills/configure-worktree"
  git init -q "$sb/repo"
  git -C "$sb/repo" -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
  local out
  out="$(cd "$sb/repo" && bash "$sb/agents/skills/configure-worktree/scripts/configure-worktree.sh" status 2>&1)" || true
  case "$out" in
    *"missing config lib"*) printf 'FAIL symlinked skill could not find shared lib\n'; FAILED=1 ;;
    *) printf 'PASS symlinked skill resolves shared lib\n' ;;
  esac
}

# --- lib resolution when vendored beside the script (install.sh --copy) ---
test_vendored_lib_resolves_when_shared_absent() {
  local sb; sb="$(new_sandbox)"
  mkdir -p "$sb/skills"
  cp -r "$ROOT/skills/configure-worktree" "$sb/skills/configure-worktree"   # no lib/ at $sb
  cp "$ROOT/lib/worktree-config.sh" "$sb/skills/configure-worktree/scripts/worktree-config.sh"
  git init -q "$sb/repo"
  git -C "$sb/repo" -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
  local out
  out="$(cd "$sb/repo" && bash "$sb/skills/configure-worktree/scripts/configure-worktree.sh" status 2>&1)" || true
  case "$out" in
    *"missing config lib"*) printf 'FAIL vendored sibling lib not found\n'; FAILED=1 ;;
    *) printf 'PASS vendored sibling lib resolves\n' ;;
  esac
}

# --- neither candidate present → fail loud (guards the fallback search) ---
test_missing_both_candidates_fails_loud() {
  local sb; sb="$(new_sandbox)"
  mkdir -p "$sb/skills"
  cp -r "$ROOT/skills/configure-worktree" "$sb/skills/configure-worktree"   # no ../../../lib at $sb
  rm -f "$sb/skills/configure-worktree/scripts/worktree-config.sh"          # and no vendored sibling
  git init -q "$sb/repo"
  git -C "$sb/repo" -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
  local out rc
  out="$(cd "$sb/repo" && bash "$sb/skills/configure-worktree/scripts/configure-worktree.sh" status 2>&1)"; rc=$?
  { [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "missing config lib"; } \
    && printf 'PASS missing lib fails loud\n' \
    || { printf 'FAIL missing lib did not fail loud (rc=%s)\n' "$rc"; FAILED=1; }
}

# --- install.sh: symlink into both targets, idempotent, uninstall owns-only ---
test_install_symlinks_both_targets() {
  local sb; sb="$(new_sandbox)"
  bash "$ROOT/install.sh" --agents-dir "$sb/agents" --claude-dir "$sb/claude" >/dev/null
  local n_a n_c
  n_a="$(find "$sb/agents" -maxdepth 1 -type l | wc -l | tr -d ' ')"
  n_c="$(find "$sb/claude" -maxdepth 1 -type l | wc -l | tr -d ' ')"
  local want; want="$(bash "$ROOT/install.sh" --list | wc -l | tr -d ' ')"
  { [ "$n_a" = "$want" ] && [ "$n_c" = "$want" ]; } \
    && printf 'PASS install symlinks all skills into both targets\n' \
    || { printf 'FAIL install: agents=%s claude=%s want=%s\n' "$n_a" "$n_c" "$want"; FAILED=1; }
  # link resolves to the real skill
  [ "$(readlink "$sb/agents/configure-worktree")" = "$ROOT/skills/configure-worktree" ] \
    && printf 'PASS link points at source\n' || { printf 'FAIL link target wrong\n'; FAILED=1; }
  rm -rf "$sb"
}

test_install_is_idempotent() {
  local sb; sb="$(new_sandbox)"
  bash "$ROOT/install.sh" --agents-dir "$sb/agents" --claude-dir "" >/dev/null
  local out
  out="$(bash "$ROOT/install.sh" --agents-dir "$sb/agents" --claude-dir "" 2>&1)"
  case "$out" in *"= $sb/agents/configure-worktree"*) printf 'PASS second run is a no-op\n' ;;
    *) printf 'FAIL idempotency: %s\n' "$out"; FAILED=1 ;; esac
  rm -rf "$sb"
}

test_install_refuses_foreign_path() {
  local sb; sb="$(new_sandbox)"
  mkdir -p "$sb/agents/configure-worktree"; echo mine > "$sb/agents/configure-worktree/keep.txt"
  bash "$ROOT/install.sh" --agents-dir "$sb/agents" --claude-dir "" >/dev/null
  [ -f "$sb/agents/configure-worktree/keep.txt" ] \
    && printf 'PASS install leaves a foreign dir untouched\n' \
    || { printf 'FAIL install clobbered a foreign dir\n'; FAILED=1; }
  rm -rf "$sb"
}

test_uninstall_owns_only() {
  local sb; sb="$(new_sandbox)"
  bash "$ROOT/install.sh" --agents-dir "$sb/agents" --claude-dir "" >/dev/null
  mkdir -p "$sb/agents/foreign-skill"; echo x > "$sb/agents/foreign-skill/x"
  bash "$ROOT/install.sh" --uninstall --agents-dir "$sb/agents" --claude-dir "" >/dev/null
  { [ ! -e "$sb/agents/configure-worktree" ] && [ -f "$sb/agents/foreign-skill/x" ]; } \
    && printf 'PASS uninstall removes ours, keeps foreign\n' \
    || { printf 'FAIL uninstall scope wrong\n'; FAILED=1; }
  rm -rf "$sb"
}

# Restructured from the brief's version:
# - stamp-file existence is a real assertion that sets FAILED=1 on miss
# - lib self-containment check sets FAILED=1 in the outer shell (no subshell)
test_install_copy_is_self_contained() {
  local sb; sb="$(new_sandbox)"
  bash "$ROOT/install.sh" --copy --agents-dir "$sb/agents" --claude-dir "" >/dev/null
  # Vendored lib is present beside the script.
  [ -f "$sb/agents/configure-worktree/scripts/worktree-config.sh" ] \
    && printf 'PASS copy mode vendors worktree-config.sh\n' \
    || { printf 'FAIL copy mode missing vendored lib\n'; FAILED=1; }
  # Stamp file is present.
  [ -f "$sb/agents/configure-worktree/.git-worktree-skills-installed" ] \
    && printf 'PASS copy mode writes stamp file\n' \
    || { printf 'FAIL copy mode missing stamp file\n'; FAILED=1; }
  # The copied skill runs without a shared lib/ nearby — FAILED=1 in outer shell.
  git init -q "$sb/repo"
  git -C "$sb/repo" -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
  local out
  out="$(cd "$sb/repo" && bash "$sb/agents/configure-worktree/scripts/configure-worktree.sh" status 2>&1)" || true
  case "$out" in
    *"missing config lib"*) printf 'FAIL copied skill lost its lib\n'; FAILED=1 ;;
    *) printf 'PASS copy mode vendors a working lib\n' ;;
  esac
  rm -rf "$sb"
}

# Run every test_* function.
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do "$t"; done
exit "$FAILED"

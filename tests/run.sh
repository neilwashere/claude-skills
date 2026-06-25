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
  out="$( cd "$repo" && HOME="$sb/home" bash "$ROOT/tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main 2>/dev/null )"
  assert_eq "$out" "$sb/trees/feat-x" "wt-new creates worktree at configured dir"
  [ -d "$sb/trees/feat-x" ] && printf 'PASS: %s\n' "configured worktree dir exists" || { printf 'FAIL: configured dir missing\n'; FAILED=1; }
  rm -rf "$sb"
}
test_wtnew_fails_loud_without_lib() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  cp -r "$ROOT/tss-git-skills" "$sb/plugin"
  rm -f "$sb/plugin/lib/worktree-config.sh"
  assert_fails "wt-new fails loud when lib missing" bash -c \
    'cd "'"$repo"'" && HOME="'"$sb"'/home" bash "'"$sb"'/plugin/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main'
  rm -rf "$sb"
}

test_wtrm_removes_configured_dir() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"worktreeDir":"%s/trees/{branch}"}' "$sb" > "$repo/.claude/worktree-config.json"
  ( cd "$repo" && HOME="$sb/home" bash "$ROOT/tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main ) >/dev/null 2>&1
  ( cd "$repo" && HOME="$sb/home" bash "$ROOT/tss-git-skills/skills/exit-and-dispose-worktree/scripts/wt-rm.sh" feat/x ) >/dev/null 2>&1
  [ ! -d "$sb/trees/feat-x" ] && printf 'PASS: %s\n' "wt-rm removed configured-dir worktree" \
    || { printf 'FAIL: configured-dir worktree still present\n'; FAILED=1; }
  rm -rf "$sb"
}

test_hook_exempts_config_markers() {
  local sb; sb="$(mktemp -d)"; local repo="$sb/repo"; mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q && git config user.email a@b.c && git config user.name a \
      && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
  printf '{"enforce":true}' > "$repo/.claude/worktree-discipline.json"   # enforced main checkout
  local hook="$ROOT/tss-git-skills/skills/setup-worktree-discipline/worktree-discipline.sh"
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
  local hook="$ROOT/tss-git-skills/skills/setup-worktree-discipline/worktree-discipline.sh"
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
  ( cd "$repo" && HOME="$sb/home" bash "$ROOT/tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main ) >/dev/null 2>&1
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
    'cd "'"$repo"'" && HOME="'"$sb/home"'" bash "'"$ROOT"'/tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main 2>/dev/null'
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
  out="$( cd "$repo" && HOME="$sb/home" bash "$ROOT/tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh" feat/x main 2>"$sb/err" )"
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
CFG="$ROOT/tss-git-skills/skills/configure-worktree/scripts/configure-worktree.sh"

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

WTE="$ROOT/tss-git-skills/skills/worktree-enforce/scripts/worktree-enforce.sh"

# A sandbox HOME fully wired for worktree-discipline (hook copied + registered +
# CLAUDE.md rule), and a repo opted in. Echoes "$sb".
_doctor_wired_sandbox() {
  local sb; sb="$(mktemp -d)"
  mkdir -p "$sb/home/.claude/hooks"
  cp "$ROOT/tss-git-skills/skills/setup-worktree-discipline/worktree-discipline.sh" "$sb/home/.claude/hooks/worktree-discipline.sh"
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

# Run every test_* function.
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do "$t"; done
exit "$FAILED"

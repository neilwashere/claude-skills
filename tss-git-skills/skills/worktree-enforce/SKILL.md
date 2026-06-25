---
name: worktree-enforce
description: Opt the current repo in or out of worktree-discipline enforcement, show its status, or run a doctor health check. `worktree-enforce in` requires all work here to go through worktrees; `worktree-enforce out` stops enforcing (local override if the marker is committed, else removes it); `worktree-enforce status` shows whether enforcement is active, from which marker, and whether the global hook is installed; `worktree-enforce doctor` audits the global wiring and runs a live-deny smoke test proving the hook actually fires. Manages the .claude/worktree-discipline.json marker the setup-worktree-discipline hook reads.
disable-model-invocation: true
---

# worktree-enforce

Per-repo control over worktree-discipline enforcement. It manages the two markers
the `setup-worktree-discipline` hook reads in the repo containing your current
directory:

- `.claude/worktree-discipline.json` — committed, shared policy (`{"enforce": true, "allowPaths": [...]}`)
- `.claude/worktree-discipline.local.json` — gitignored, per-checkout override that **wins** over the committed marker

This skill does not install the hook — that is the one-time `setup-worktree-discipline`
step. Without the global hook installed, the markers exist but nothing enforces them
(`status` will tell you).

## Run it

Pass the subcommand the user gave (`in`, `out`, `status`, or `doctor`; default `status`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/worktree-enforce/scripts/worktree-enforce.sh" <in|out|status|doctor>
```

## What each arg does

- **`in`** — opt this repo **in**. Writes the committed marker with `{"enforce": true}`
  (preserving any existing `allowPaths`) and clears a local override that would
  disable it. The marker is **staged**, not committed — commit it to share the policy.

- **`out`** — opt **out**, smartly:
  - if the marker is **committed** (in `HEAD`), write the gitignored local override
    `{"enforce": false}` so shared policy is left intact (and add it to `.gitignore`);
  - otherwise (marker uncommitted or absent) remove the local/staged markers so the
    repo falls back to the default — off. This cleanly reverts an `in` you hadn't
    committed yet.

- **`status`** — print, for the current repo: the effective enforcement (ON/OFF) and
  which marker it came from, any `allowPaths`, whether you're in a main checkout or a
  worktree, and whether the global hook is installed — flagging **STALE** if the
  installed copy has drifted from the plugin's bundled hook, or **MISSING** if the
  registered file is gone.

- **`doctor`** — everything `status` shows for this repo, plus a consolidated
  health check (replacing the prose Validate blocks in the setup/teardown skills):
  - **global wiring**, one PASS/FAIL/WARN line each — hook registered in
    `settings.json`, installed file present, executable, **fresh** vs the bundled
    hook, the superseded `git-branch-discipline.sh` gone, and the
    `## Worktree discipline` rule present in `~/.claude/CLAUDE.md`;
  - **live deny** — constructs a throwaway enforced repo and pipes a synthetic
    `Write` through the *installed* hook, asserting it denies. This is the only
    end-to-end proof the chain actually fires, not just that files are in place.

## Notes

- Run it from anywhere inside the target repo; it resolves the repo root itself.
- Writing/removing the marker files is always permitted even in an enforced main
  checkout — the hook exempts the marker paths — so you can toggle without entering a
  worktree.
- After `in`, commit `.claude/worktree-discipline.json` so the policy travels with the repo.

---
title: "The environment is an input, not a constant"
dimension: conventions
severity: medium
occurrences: 1
first_seen: 2026-06-28
last_seen: 2026-06-28
sources: ["seed: closing-the-verification-loop"]
status: active
---

## Principle

"It works" and "the warnings are fixed" are statements about a *specific*
environment: a tool version, a platform, a file scope, a particular commit.
Treat any of those as a fixed background and the same command will behave
differently where it actually runs — CI, a colleague's machine with a different
OS, the post-merge tree.

## Trap

**Version skew:** CI installs the distro's version of a linter while you tested
against a newer one locally. Older and newer versions can disagree on which
rules fire, and many linters exit non-zero even on "info" findings — green
locally, red in CI, or worse, the inverse.

```yaml
- run: apt-get install -y some-linter        # gets distro v0.9...
- run: some-linter $(find . -name '*.sh')    # ...you tested against v0.11 locally
```

**Platform-only flags:**

```bash
sandbox="$(mktemp -d -p "$BASE")"   # -p is GNU-only; fails silently on BSD/macOS
```

**CI merge semantics:** pull-request CI usually lints the *merge result* (your
branch merged with the target), not your branch tip. Code that landed on the
target after you branched is now in scope. A fix scoped to "the lines I touched"
can be defeated by lines you've never seen.

## Fix

Pin tool versions explicitly, define the pass/fail bar, and use portable flags.

```yaml
- run: |
    VER=0.11.0
    curl -fsSL ".../shellcheck-v$VER.tar.xz" | tar -xJ   # pin it
    ./shellcheck-v$VER/shellcheck --version
- run: shellcheck --severity=warning $(find . -name '*.sh')  # explicit bar
```

## Habit

Before declaring a gate green, ask three questions: *what tool version runs it,
on what input (which files? which commit — my tip or the merge?), and what exit
condition counts as failure?* Pin versions so local equals CI. Prefer portable
flags or feature-detect. When in doubt, reproduce the gate against the
merge-with-target, not just your branch.

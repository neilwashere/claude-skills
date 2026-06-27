# Closing the Verification Loop — a field guide for shell tooling, tests, and CI

## Why this guide exists

This is not a list of bugs. It's a small set of **habits** drawn from a batch of
otherwise-strong work. The architecture was sound, the test *suites* were well
structured (good sandbox isolation; in places, complementary tests that pinned
both branches of a conditional), and most changes were correct on the first pass.

The issues that *recurred* all shared one root cause, and it isn't an
architecture problem. It's a **verification** problem: building the right thing,
then reasoning *forward* that it works ("this should be fine") instead of
verifying *backward* ("it did — and here's how I'd know if it hadn't").

Four principles below close that loop. Each is cheap. Each would have caught a
whole class of problem before review.

---

## 1. A test's only value is its ability to fail

A test that passes when the code is correct **and** when it's broken is not a
test — it's a comment shaped like one. The most common way this happens is a
setup bug that disables the thing under test *before the assertion runs*, so the
assertion never actually exercises it.

**The trap — a harness that no-ops the system under test:**

```bash
# Feed a command to a tool that reads a JSON event on stdin.
run_tool() {
  local cmd="$1"
  # printf-splicing a raw command into JSON: fine until the command
  # contains a quote, then this emits INVALID json.
  printf '{"command":"%s"}' "$cmd" | my_tool
}

test_allows_arrow() {
  out="$(run_tool 'echo "x -> y"')"   # the quotes break the JSON...
  is_denied "$out" \
    && { echo "FAIL"; FAILED=1; } \
    || echo "PASS: tool allows ->"     # ...so my_tool sees garbage,
}                                       #    bails early, and this ALWAYS passes
```

`my_tool` receives malformed JSON, can't parse a command, and exits "allow"
before the logic you meant to test ever runs. Green forever, including against a
completely broken tool.

**A subtler variant — an assertion that can't be false:**

```bash
test_exits_nonzero_on_bad_input() {
  local rc                              # declared empty, never initialised
  out="$(run_thing)" || rc=$?           # only set when run_thing FAILS
  [ "$rc" != "0" ] && echo "PASS" || { echo "FAIL"; FAILED=1; }
  # On a clean exit, rc stays "" and [ "" != "0" ] is TRUE -> spurious PASS.
}
```

This "passes" even against a program that exits `0` while doing the wrong thing —
the exact case it was written to catch.

**The fix — and the habit:**

```bash
run_tool() { jq -nc --arg c "$1" '{command:$c}' | my_tool; }  # robust escaping
test_exits_nonzero_on_bad_input() {
  local rc=0                            # initialise, so a 0-exit is observable
  out="$(run_thing)" || rc=$?
  [ "$rc" != 0 ] && echo "PASS" || { echo "FAIL"; FAILED=1; }
}
```

> **Habit: watch every new test fail before you trust it.** Break the code on
> purpose — invert the condition, delete the guard, stub the function to return
> the wrong thing — and confirm the test goes red. A test you've only ever seen
> green has not been tested itself. (This is the whole point of red-green: the
> red proves the test has teeth.)

---

## 2. Observe behaviour — don't describe it

It is remarkably easy to write a confident, precise, **wrong** description of
what code does, because the description is generated from what the code *looks
like it should do* rather than from what it actually does. Documentation and code
comments are the usual victims; the failure is invisible until someone runs it.

**The trap — plausible reasoning that inverts the truth:**

```markdown
<!-- in a SKILL/README, describing a heuristic parser -->
Note: `tool -i.bak FILE` is **missed** by the scanner (it extracts `.bak`,
not `FILE`), but the write is still caught by the separate Write/Edit guard.
```

Both halves can be false at once: the scanner may be end-of-line anchored and
catch `FILE` perfectly, and the "separate guard" may only apply to a different
class of call and not cover this path at all. The sentence *sounds*
authoritative — which is exactly why it survives review by a reader who also
reasons forward instead of running it.

**The fix — and the habit:** Run the thing. Capture the real output. Paste
*that* into the doc.

```console
$ printf '{"command":"tool -i.bak ./in-repo-file"}' | scanner ; echo "decision=$?"
decision=denied        # the doc's claim was backwards — the truth is one command away
```

> **Habit: a claim about behaviour must be backed by an execution you ran**, not
> by a reading of the source. If you're documenting an edge case, the proof of
> the edge case is a transcript. "I traced the regex" is weaker than "I ran it
> and here's what came out."

---

## 3. The environment is an input, not a constant

"It works" and "the warnings are fixed" are statements about a *specific*
environment: a tool version, a platform, a file scope, a particular commit. Treat
any of those as a fixed background and the same command will behave differently
where it actually runs (CI, a colleague's BSD laptop, the post-merge tree).

**The traps — same code, different verdicts:**

```yaml
# CI installs the distro's linter; locally you have a newer one.
- run: apt-get install -y some-linter        # gets v0.9 here...
- run: some-linter $(find . -name '*.sh')    # ...you tested against v0.11 locally
# Newer and older versions disagree on which rules fire, AND many linters exit
# non-zero even on "info" findings. Green locally, red in CI — or worse, vice-versa.
```

```bash
sandbox="$(mktemp -d -p "$BASE")"   # -p is GNU-only; on BSD/macOS this errors,
                                    # a fallback may silently land you somewhere
                                    # the code treats specially -> tests no-op
```

And the one almost everyone learns the hard way: **pull-request CI usually lints
the *merge result* (your branch ⊕ the target), not your branch tip.** Code that
landed on the target *after* you branched is now in scope. A fix scoped to "the
lines I touched" can be defeated by lines you've never seen.

**The fix — and the habit:**

```yaml
- run: |
    VER=0.11.0
    curl -fsSL ".../shellcheck-v$VER.tar.xz" | tar -xJ   # pin it
    ./shellcheck-v$VER/some-linter --version
- run: some-linter --severity=warning $(find . -name '*.sh')  # define the bar explicitly
```

> **Habit: before declaring a gate green, ask three questions —** *what tool
> version runs it, on what input (which files? which commit — my tip or the
> merge?), and what exit condition counts as failure?* Pin versions so local ==
> CI. Prefer portable flags (or feature-detect). When in doubt, reproduce the
> gate against the merge-with-target, not just your branch.

---

## 4. Design the failure path of every destructive operation

Most code is written happy-path first, and for most code that's fine — a wrong
read is recoverable. It is **not** fine for operations that delete, overwrite, or
truncate. There, the failure path *is* the feature, and "I didn't think about
that input" becomes data loss.

**The trap — a cleanup that half-completes into a broken state:**

```bash
set -e
# Step 1: rewrite a config to remove our registration.
jq 'del(.registration)' "$CONFIG" > "$CONFIG"   # (a) truncates BEFORE jq runs;
                                                 #     if jq fails, file is now empty
# Step 2: delete the files the registration pointed at.
rm -f "$HOOK_FILE"
strip_section "$DOC"

# If $CONFIG was malformed, an earlier check might have swallowed the error...
if [ -f "$CONFIG" ] && jq -e . "$CONFIG" >/dev/null 2>&1; then ... ; else
  echo "already clean"   # <- reached on PARSE FAILURE too, then we fall through
fi                       #    and still run Steps 2-3: registration left dangling
```

Three classic failure-path bugs in one: **truncate-before-transform** (`>` opens
and empties the file before `jq` produces its replacement), **swallowed errors**
(`2>&1` + a broad `else` turns "couldn't parse" into "nothing to do"), and
**partial completion** (delete the targets while leaving the pointer to them).
Patching the *instance* you noticed ("handle a missing binary") doesn't fix the
*class* ("any path where the transform doesn't succeed must not proceed to
delete").

**The fix — and the habit:**

```bash
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }   # guard the tool
jq -e . "$CONFIG" >/dev/null || { echo "config not valid JSON; aborting" >&2; exit 1; }

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT          # never leak the temp
jq 'del(.registration)' "$CONFIG" > "$tmp"          # write to temp...
mv "$tmp" "$CONFIG"                                 # ...atomic swap only on success
rm -f "$HOOK_FILE"; strip_section "$DOC"            # delete only after the rewrite stuck
```

> **Habit: for any irreversible step, enumerate the non-happy inputs *first*** —
> tool missing, input malformed, command exits non-zero, partial run interrupted
> — and decide each one's behaviour before you write the success path. Two rules
> that prevent most of the damage: **write-to-temp-then-rename** (never edit a
> file in place by truncating it), and **guard, then act** (validate everything
> you depend on, and abort *loudly* — never half-complete and never report
> success on a swallowed error).

---

## A note on taste (the judgment calls)

These have no single right answer, but the instinct is learnable:

- **Reuse over re-implement.** If a helper already resolves precedence / parses
  config / formats output, call it. A second inline copy works today and silently
  drifts from the original tomorrow.
- **Don't round-trip data through a lossy representation.** Joining a list on `|`
  and splitting it back corrupts any element that contains `|`. If you already
  have the structured form, emit from it directly.
- **A lean entry-point defers; it doesn't re-explain.** When you split a doc into
  "overview" and "reference," the overview should *point at* the reference, not
  duplicate a paragraph of it. Two copies of the same explanation will disagree
  within a month.
- **Put a fix at the altitude that scales.** Suppressing a lint per-line at the
  ten sites you happened to touch is a patch; promoting it to one file-level
  policy is a fix. Ask whether your change handles the *next* occurrence too, or
  just the ones in front of you.

---

## Pre-flight checklist

Run this on yourself before opening a PR:

- [ ] **Tests:** did I watch each new test go **red** (by breaking the code) before trusting its green?
- [ ] **Claims:** is every statement about behaviour (docs, comments) backed by output I actually ran?
- [ ] **Environment:** are tool versions pinned, flags portable, and do I know whether CI lints my branch or the merge result?
- [ ] **Destructive ops:** for each delete/overwrite/truncate, did I enumerate the malformed/missing/failure inputs and ensure no half-completion and no success-on-error?
- [ ] **Reuse:** did I call existing helpers instead of duplicating logic?
- [ ] **Class, not instance:** does my fix cover the next occurrence, or only the one I noticed?

The throughline: **don't tell me it works — show me how you know.** That single
shift turns strong structural work into reliably correct work.

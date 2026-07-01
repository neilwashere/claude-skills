---
title: "Watch every new test fail before you trust it"
dimension: testing
severity: high
occurrences: 1
first_seen: 2026-06-28
last_seen: 2026-06-28
sources: ["seed: closing-the-verification-loop"]
status: active
---

## Principle

A test's only value is its ability to fail. A test that passes when the code is
correct **and** when it's broken is not a test — it's a comment shaped like one.

## Trap

The most common failure mode is a setup bug that disables the thing under test
*before* the assertion runs, so the assertion never exercises it. The test goes
green forever, including against a completely broken implementation.

```bash
# Builds JSON by printf-splicing a raw command — breaks when the command
# contains a double-quote, emitting invalid JSON.
run_tool() {
  local cmd="$1"
  printf '{"command":"%s"}' "$cmd" | my_tool
}

test_allows_arrow() {
  out="$(run_tool 'echo "x -> y"')"  # quotes break the JSON...
  is_denied "$out" \
    && { echo "FAIL"; FAILED=1; } \
    || echo "PASS: tool allows ->"  # ...my_tool sees garbage, bails, always "allow"
}
```

A subtler variant: an assertion that structurally cannot be false.

```bash
test_exits_nonzero_on_bad_input() {
  local rc                         # declared empty, never initialised
  out="$(run_thing)" || rc=$?      # only set when run_thing FAILS
  [ "$rc" != "0" ] && echo "PASS" || { echo "FAIL"; FAILED=1; }
  # On a clean exit rc stays "" and [ "" != "0" ] is TRUE → spurious PASS.
}
```

## Fix

Use robust construction for inputs to the system under test, and initialise all
state that the assertion depends on.

```bash
run_tool() { jq -nc --arg c "$1" '{command:$c}' | my_tool; }  # robust escaping

test_exits_nonzero_on_bad_input() {
  local rc=0                       # initialised — a 0-exit is observable
  out="$(run_thing)" || rc=$?
  [ "$rc" != 0 ] && echo "PASS" || { echo "FAIL"; FAILED=1; }
}
```

## Habit

Watch every new test go **red** before trusting its green. Break the code on
purpose — invert the condition, delete the guard, stub the function to return
the wrong value — and confirm the test fails. A test you've only ever seen
green has not been tested itself. This is the whole point of red-green: the
red proves the test has teeth.

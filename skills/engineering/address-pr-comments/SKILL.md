---
name: address-pr-comments
description: Triage and address PR review comments. Use when the user says "address PR comments", "fix review comments", "copilot has comments", or references review feedback on a pull request.
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Agent
argument-hint: "[PR number or URL]"
---

# Address PR Review Comments

You are triaging and resolving review comments on a pull request. Your workflow is: fetch → triage → fix → test → commit → push → reply inline.

## Step 1: Identify the PR

**Preflight — confirm we're inside a git repo.** Every PR detection path below depends on this, so check once up front:

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1
```

If this fails, tell the user plainly: "This needs to run inside a cloned repository so I can edit the code. Open the project folder first, then re-run." Stop.

Then resolve the target PR in this order:

1. **From `$ARGUMENTS`** — if a PR number or URL is supplied, use it.
2. **From the current branch** — run:
   ```bash
   gh pr view --json number,url,headRefName,title --jq '{number, url, branch: .headRefName, title}'
   ```
   If this succeeds, confirm the title with the user in one line (e.g. "Working on #42 — *Add auth middleware*. Proceed?") and continue once they agree.
3. **Fallback — ask the user to pick from their open PRs.** This is the path for non-developer users who may not know PR numbers, may not be on a PR branch, or may have many PRs open.

   List their open PRs with title, branch, and review status so they can recognise the one they mean. The `--limit 20` cap keeps the per-PR comment-count loop below bounded; for users with many more PRs, a single GraphQL query can fetch counts in bulk — swap that in if the REST loop becomes a bottleneck.

   ```bash
   gh pr list --author @me --state open --limit 20 --json number,title,headRefName,reviewDecision,url \
     --jq '.[] | [.number, .title, .headRefName, (if (.reviewDecision // "") == "" then "—" else .reviewDecision end), .url] | @tsv'
   ```

   Note: `gh` returns `reviewDecision` as an empty string (not `null`) when no review has been requested, so `//` alone won't coalesce — the `if` form above handles both cases.

   For each PR returned, fetch the count of top-level review comments (these are the ones this skill addresses):

   ```bash
   gh api "repos/{owner}/{repo}/pulls/<number>/comments" --paginate \
     --jq '[.[] | select(.in_reply_to_id == null)] | length'
   ```

   Present a numbered table to the user, sorted by comment count descending so the PRs most in need of attention come first. Valid `reviewDecision` values are `APPROVED`, `CHANGES_REQUESTED`, and `REVIEW_REQUIRED`; `gh` returns `""` for PRs without a decision yet, which the jq above renders as `—`:

   ```
   Which PR do you want to address comments on?

   |  # | PR  | Title                          | Branch          | Comments | Review              |
   |----|-----|--------------------------------|-----------------|----------|---------------------|
   |  1 | #42 | Add auth middleware            | feat/auth       |        7 | CHANGES_REQUESTED   |
   |  2 | #39 | Refactor worker pool           | refactor/pool   |        3 | REVIEW_REQUIRED     |
   |  3 | #35 | Docs: getting started guide    | docs/onboarding |        0 | APPROVED            |
   |  4 | #31 | WIP: new dashboard             | feat/dashboard  |        0 | —                   |

   Reply with the row number (1, 2, 3...) or the PR number (#42) or a keyword from the title ("auth").
   ```

   Accept any of those inputs and resolve to a PR number. If the user's reply is ambiguous (matches multiple titles), list just the matches and ask again.

   If the user has **no** open PRs, tell them plainly: "You don't have any open pull requests right now — nothing to address." Stop here.

Once the PR is resolved, check out its branch before doing anything else:

```bash
gh pr checkout <number>
```

## Step 2: Fetch all review comments

```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments --paginate \
  --jq '.[] | select(.in_reply_to_id == null) | {id: .id, path: .path, line: .line, body: .body, user: .user.login}'
```

The `select(.in_reply_to_id == null)` filter gives you only top-level comments — not replies to previous comments. This is critical: without it you will re-process comments you have already addressed.

## Step 3: Triage

Categorise every comment into one of these buckets:

| Bucket | Action |
|--------|--------|
| **Critical bug** | Fix immediately — logic errors, security issues, broken behaviour |
| **Valid improvement** | Fix — the reviewer is right and the change is straightforward |
| **Already addressed** | A previous commit already fixed this. Reply confirming which commit. |
| **Acknowledged** | Valid concern but out of scope, or a design trade-off. Reply explaining why. |
| **Won't fix** | Disagree with the suggestion. Reply with rationale. |

Present the triage to the user as a brief table before making changes. Do NOT start fixing until the user confirms or adjusts the triage. Example:

```
| # | File | Reviewer | Bucket | Summary |
|---|------|----------|--------|---------|
| 1 | worker.ts:338 | Copilot | Critical bug | Hardcoded system prompt instead of computed variable |
| 2 | worker.ts:628 | neilwashere | Valid improvement | File exceeds 500-line limit |
| 3 | tool-registry.ts:83 | Copilot | Already addressed | Unused param removed in previous commit |
```

## Step 4: Apply fixes

Work through fixes grouped by file to avoid edit conflicts. For each fix:
1. Read the current state of the file
2. Find the code the comment describes by searching for the pattern — don't trust the diff line number, the file may have shifted since the review
3. Make the change with Edit or Write
4. Apply all remaining fixes in the same file before switching files

**Copilot suggestions** include `` ```suggestion `` blocks showing proposed replacement code. Read them carefully — they may be wrong or only partially applicable.

## Step 5: Build and test

Run the project's build and test commands (check CLAUDE.md or package.json for the right invocation). If tests fail, fix the failures before proceeding. Do not commit broken code.

## Step 6: Commit and push

Stage only the files you changed. Write a commit message that summarises all fixes:

```bash
git add <specific files> && git commit -m "fix: address PR review comments

- <file>: <what changed and why>
- <file>: <what changed and why>"
```

Push to the PR branch.

## Step 7: Reply inline to every comment

Every top-level comment must get a reply — even ones you didn't fix.

Use the GitHub API to reply. The endpoint for replying to a PR review comment is:

```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments \
  -X POST \
  -f body="<reply text>" \
  -F in_reply_to=<comment_id> \
  --silent
```

Reply format by bucket:
- **Fixed**: `Fixed in {commit_sha} — {brief description of what changed}.`
- **Already addressed**: `Already fixed in {commit_sha}.`
- **Acknowledged**: `Acknowledged — {reason this is deferred or out of scope}. Tracked for follow-up.`
- **Won't fix**: `{Rationale for the current approach}.`

Batch all replies into a single Bash call to avoid round-trip overhead. Use `&&` to chain them.

## Gotchas

- **`in_reply_to` is the comment ID, not the review ID.** The comment `id` field from step 2 is what you need.
- **Don't use `/repos/{owner}/{repo}/pulls/comments/{id}/replies`** — that endpoint does not exist. Use the create comment endpoint with `in_reply_to`.
- **Always use `--paginate` when fetching comments.** The default page size (30) can miss recent comments on PRs with many review rounds.
- **Non-developer users** may not know PR numbers or branch names. Speak to them in terms of PR title and row number, and run `gh pr checkout` for them rather than assuming they'll do it.

## Task: $ARGUMENTS

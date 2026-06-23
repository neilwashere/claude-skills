# tss-git-skills Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carve the three worktree / branch-discipline skills out of `threadsafe` into a new curated domain plugin `tss-git-skills`, hosted in the same marketplace.

**Architecture:** The repo stays one marketplace. `threadsafe` remains the root catch-all plugin (`source: "."`). `tss-git-skills` is a second plugin in its own self-contained subtree (`./tss-git-skills/`) with a flat `skills/` dir, so Claude Code's depth-1 root scan never collides with it. The three skills *move* (not duplicate); branch discipline stays inside `setup-worktree-discipline`.

**Tech Stack:** Claude Code plugin/marketplace manifests (JSON), Markdown skills + READMEs, bash-bundled skill scripts. No application code, no test runner — verification is JSON validity + grep + `git status`.

## Global Constraints

- Namespace = plugin name. New plugin name is exactly `tss-git-skills` → skills invoke as `tss-git-skills:<skill>`. `threadsafe` keeps its name.
- A plugin's `skills/` is auto-scanned at **depth-1**; a flat `skills/` needs **no `skills` array** in its manifest. Never list an auto-scanned path in a manifest (it double-loads — see commit `909c689`). So `tss-git-skills/.claude-plugin/plugin.json` carries **no** `skills`, `hooks`, or `commands` keys.
- The three skills are **moved, not copied** — they must not appear in both plugins.
- Convention for all future domain plugins: `tss-<domain>`, own subtree `./tss-<domain>/`, flat `skills/`, own README. `threadsafe` is the only un-prefixed plugin.
- Commit after each task. Conventional-commit messages, ending with the `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer.

---

### Task 1: Scaffold the `tss-git-skills` plugin and move the three skills

**Files:**
- Create: `tss-git-skills/.claude-plugin/plugin.json`
- Move: `skills/engineering/create-and-enter-worktree/` → `tss-git-skills/skills/create-and-enter-worktree/`
- Move: `skills/engineering/exit-and-dispose-worktree/` → `tss-git-skills/skills/exit-and-dispose-worktree/`
- Move: `skills/engineering/setup-worktree-discipline/` → `tss-git-skills/skills/setup-worktree-discipline/`

**Interfaces:**
- Produces: a plugin rooted at `./tss-git-skills/` whose flat `skills/` holds exactly the three skill dirs (each retaining its bundled `scripts/` / `*.sh`). Later tasks reference this path and the plugin name `tss-git-skills`.

- [ ] **Step 1: Create the plugin dir and git-move the three skills**

```bash
mkdir -p tss-git-skills/skills tss-git-skills/.claude-plugin
git mv skills/engineering/create-and-enter-worktree  tss-git-skills/skills/create-and-enter-worktree
git mv skills/engineering/exit-and-dispose-worktree  tss-git-skills/skills/exit-and-dispose-worktree
git mv skills/engineering/setup-worktree-discipline  tss-git-skills/skills/setup-worktree-discipline
```

- [ ] **Step 2: Verify the move preserved bundled scripts**

Run:
```bash
ls tss-git-skills/skills/create-and-enter-worktree/scripts/wt-new.sh \
   tss-git-skills/skills/exit-and-dispose-worktree/scripts/wt-rm.sh \
   tss-git-skills/skills/setup-worktree-discipline/worktree-discipline.sh
test ! -e skills/engineering/create-and-enter-worktree && echo "OLD PATHS GONE"
```
Expected: all three paths listed, then `OLD PATHS GONE`.

- [ ] **Step 3: Write the plugin manifest**

Create `tss-git-skills/.claude-plugin/plugin.json` — note: **no** `skills`/`hooks`/`commands` keys (flat `skills/` auto-discovers; the setup skill installs its hook to `~/.claude`, not plugin-level):

```json
{
  "name": "tss-git-skills",
  "description": "Curated git/worktree workflow skills — branch discipline, worktree create/enter/dispose. Namespaced as tss-git-skills:<skill>.",
  "author": {
    "name": "Neil Chambers"
  }
}
```

- [ ] **Step 4: Validate the manifest is well-formed JSON**

Run: `python3 -m json.tool tss-git-skills/.claude-plugin/plugin.json >/dev/null && echo OK`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: scaffold tss-git-skills plugin and migrate worktree skills

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Register the plugin in the marketplace and de-list it from threadsafe

**Files:**
- Modify: `.claude-plugin/marketplace.json` (add second plugin entry)
- Modify: `.claude-plugin/plugin.json` (threadsafe — remove the three worktree skill entries)

**Interfaces:**
- Consumes: the `./tss-git-skills/` plugin produced by Task 1.
- Produces: a marketplace listing both plugins; `threadsafe`'s manifest no longer claims the three skills.

- [ ] **Step 1: Add the `tss-git-skills` entry to `marketplace.json`**

Replace the `plugins` array in `.claude-plugin/marketplace.json` so it reads:

```json
  "plugins": [
    {
      "name": "threadsafe",
      "description": "Personal engineering and productivity skills, namespaced as threadsafe:<skill>.",
      "source": ".",
      "category": "development"
    },
    {
      "name": "tss-git-skills",
      "description": "Curated git/worktree workflow skills, namespaced as tss-git-skills:<skill>.",
      "source": "./tss-git-skills",
      "category": "development"
    }
  ]
```

- [ ] **Step 2: Remove the three worktree entries from threadsafe's `plugin.json`**

In `.claude-plugin/plugin.json`, delete these three lines from the `skills` array (and fix the trailing comma so the array stays valid):

```
    "./skills/engineering/setup-worktree-discipline",
    "./skills/engineering/create-and-enter-worktree",
    "./skills/engineering/exit-and-dispose-worktree",
```

The resulting `skills` array is:

```json
  "skills": [
    "./skills/engineering/tdd",
    "./skills/engineering/diagnosing-bugs",
    "./skills/engineering/codebase-design",
    "./skills/engineering/domain-modeling",
    "./skills/engineering/grill-with-docs",
    "./skills/engineering/adversarial-review",
    "./skills/engineering/address-pr-comments",
    "./skills/productivity/grilling"
  ]
```

- [ ] **Step 3: Validate both manifests**

Run:
```bash
python3 -m json.tool .claude-plugin/marketplace.json >/dev/null \
  && python3 -m json.tool .claude-plugin/plugin.json >/dev/null \
  && echo OK
```
Expected: `OK`

- [ ] **Step 4: Verify threadsafe no longer references the moved skills**

Run: `grep -c "worktree-discipline\|create-and-enter-worktree\|exit-and-dispose-worktree" .claude-plugin/plugin.json`
Expected: `0`

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/marketplace.json .claude-plugin/plugin.json
git commit -m "feat: register tss-git-skills in marketplace, de-list from threadsafe

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Write the `tss-git-skills` README

**Files:**
- Create: `tss-git-skills/README.md`

**Interfaces:**
- Consumes: the three migrated skills under `tss-git-skills/skills/`.
- Produces: the plugin's own README, grouped User-invoked / Model-invoked, names linked to each `SKILL.md` (mirrors the bucket-README convention).

- [ ] **Step 1: Write `tss-git-skills/README.md`**

```markdown
# tss-git-skills

Curated git/worktree workflow skills. Every skill here invokes as
`tss-git-skills:<skill>` once the plugin is installed.

## Install

```bash
/plugin marketplace add /home/neil/code/threadsafe/claude-skills
/plugin install tss-git-skills@threadsafe
```

## Reference

Skills are split into **User-invoked** (reachable only when you type them —
`disable-model-invocation: true`) and **Model-invoked** (model- or
user-reachable).

## User-invoked

- **[setup-worktree-discipline](./skills/setup-worktree-discipline/SKILL.md)** — One-time installer: a PreToolUse hook that makes the main checkout read-only in opted-in repos (all writes go through a worktree), plus the global CLAUDE.md branch-discipline rule.

## Model-invoked

- **[create-and-enter-worktree](./skills/create-and-enter-worktree/SKILL.md)** — Create a sibling worktree off `origin/<default>` and relocate the session into it via the `EnterWorktree` tool. Run before writing a feature's spec, plan, or code.
- **[exit-and-dispose-worktree](./skills/exit-and-dispose-worktree/SKILL.md)** — After a PR merges, leave the worktree session (`ExitWorktree({keep})`) then remove the tree with `wt-rm.sh` (refuses if dirty/unpushed).
```

- [ ] **Step 2: Verify the linked SKILL.md targets exist**

Run:
```bash
cd tss-git-skills
for s in setup-worktree-discipline create-and-enter-worktree exit-and-dispose-worktree; do
  test -f "skills/$s/SKILL.md" && echo "ok $s" || echo "MISSING $s"
done
cd ..
```
Expected: `ok` for all three.

- [ ] **Step 3: Commit**

```bash
git add tss-git-skills/README.md
git commit -m "docs: add tss-git-skills plugin README

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Update threadsafe's READMEs to drop the moved skills

**Files:**
- Modify: `README.md` (top-level) — remove the three entries; add a `tss-git-skills` plugin section
- Modify: `skills/engineering/README.md` — remove the three entries

**Interfaces:**
- Consumes: nothing new.
- Produces: top-level README that documents both plugins and no longer lists the moved skills under threadsafe.

- [ ] **Step 1: In top-level `README.md`, update the intro line (line 5)**

Replace:
```
This repo is a **single plugin** named `threadsafe`, so every skill invokes as `threadsafe:<skill>` (e.g. `threadsafe:tdd`, `threadsafe:adversarial-review`). Skills are small, composable, and meant to be hacked on.
```
with:
```
This repo is a **marketplace** hosting `threadsafe` (the general catch-all, skills invoke as `threadsafe:<skill>`) plus one curated **domain** plugin per domain, each named `tss-<domain>` (skills invoke as `tss-<domain>:<skill>`). Skills are small, composable, and meant to be hacked on.
```

- [ ] **Step 2: In top-level `README.md`, remove the two moved Engineering entries**

Delete line 25 (`setup-worktree-discipline`) from the Engineering **User-invoked** list, and lines 35–36 (`create-and-enter-worktree`, `exit-and-dispose-worktree`) from the Engineering **Model-invoked** list.

- [ ] **Step 3: In top-level `README.md`, add a plugin section after the Productivity section (before `### Subsystems`)**

Insert:
```markdown
## tss-git-skills

Install separately: `/plugin install tss-git-skills@threadsafe`. Full list in
[tss-git-skills/README.md](./tss-git-skills/README.md).

**User-invoked**

- **[setup-worktree-discipline](./tss-git-skills/skills/setup-worktree-discipline/SKILL.md)** — One-time installer: a PreToolUse hook making the main checkout read-only in opted-in repos (all writes go through a worktree), plus the global CLAUDE.md rule.

**Model-invoked**

- **[create-and-enter-worktree](./tss-git-skills/skills/create-and-enter-worktree/SKILL.md)** — Create a sibling worktree off `origin/<default>` and relocate the session into it via the `EnterWorktree` tool, before writing a feature's spec, plan, or code.
- **[exit-and-dispose-worktree](./tss-git-skills/skills/exit-and-dispose-worktree/SKILL.md)** — After a PR merges, leave the worktree session then remove the tree.
```

(The `### Engineering` / `### Productivity` headings stay as `###` under the `## Reference` section for threadsafe's own skills; the new plugin gets a top-level `##` heading because it is a separate plugin, not a threadsafe bucket.)

- [ ] **Step 4: In `skills/engineering/README.md`, remove the three moved entries**

Delete line 10 (`setup-worktree-discipline`) from **User-invoked**, and lines 22–23 (`create-and-enter-worktree`, `exit-and-dispose-worktree`) from **Model-invoked**.

- [ ] **Step 5: Verify no threadsafe README still links the moved skills under the old path**

Run:
```bash
grep -rn "skills/engineering/\(create-and-enter\|exit-and-dispose\|setup-worktree\)" README.md skills/engineering/README.md || echo "NO OLD-PATH LINKS"
```
Expected: `NO OLD-PATH LINKS`.

- [ ] **Step 6: Commit**

```bash
git add README.md skills/engineering/README.md
git commit -m "docs: move worktree skills out of threadsafe READMEs into tss-git-skills

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Update the project `CLAUDE.md` to document the marketplace + tss- convention

**Files:**
- Modify: `CLAUDE.md` (project, repo root)

**Interfaces:**
- Consumes: nothing new.
- Produces: project instructions that describe the multi-plugin marketplace, the `tss-<domain>` convention, and the subtree-isolation rule.

- [ ] **Step 1: Replace the opening line of `CLAUDE.md`**

Replace:
```
This repo is a **single Claude Code plugin** named `threadsafe`. Every skill here invokes as `threadsafe:<skill-name>` once the plugin is installed.
```
with:
```
This repo is a Claude Code **marketplace** hosting multiple plugins. `threadsafe` is the general catch-all plugin at the repo root (`source: "."`); its skills invoke as `threadsafe:<skill-name>`. Every **other** domain is its own plugin named `tss-<domain>` (e.g. `tss-git-skills`), living in a self-contained subtree `./tss-<domain>/` with a flat `skills/` and its own `README.md`; its skills invoke as `tss-<domain>:<skill-name>`.

Why the subtree: Claude Code auto-scans each plugin's `skills/` at depth-1. Keeping every `tss-<domain>` plugin in its own subtree means the root `threadsafe` scan never reaches into it, so the two never collide. A flat `skills/` is auto-discovered, so a domain plugin's `plugin.json` needs no `skills` array (and no `hooks`/`commands` keys unless it ships plugin-level ones).
```

- [ ] **Step 2: Add a clause to the bucket-rules paragraph so it scopes to threadsafe**

After the paragraph beginning "Every skill in `engineering/`, `productivity/`, or `misc/` must have a reference…", append a sentence:
```
These bucket rules apply to the `threadsafe` plugin only. A `tss-<domain>` plugin instead uses a flat `skills/` and lists its skills in its own `tss-<domain>/README.md` (no top-level README or threadsafe `plugin.json` entry).
```

- [ ] **Step 3: Verify CLAUDE.md no longer claims a single plugin**

Run: `grep -c "single Claude Code plugin\|single plugin" CLAUDE.md`
Expected: `0`

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document multi-plugin marketplace and tss- domain convention

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Final repo-wide verification

**Files:** none (read-only checks).

- [ ] **Step 1: All manifests valid JSON**

Run:
```bash
for f in .claude-plugin/marketplace.json .claude-plugin/plugin.json tss-git-skills/.claude-plugin/plugin.json; do
  python3 -m json.tool "$f" >/dev/null && echo "ok $f" || echo "BAD $f"
done
```
Expected: `ok` for all three.

- [ ] **Step 2: The three skills live only under tss-git-skills**

Run:
```bash
find . -path ./.git -prune -o -type d \( -name create-and-enter-worktree -o -name exit-and-dispose-worktree -o -name setup-worktree-discipline \) -print
```
Expected: exactly the three `./tss-git-skills/skills/...` paths, nothing under `skills/engineering/`.

- [ ] **Step 3: No dangling references to the old paths anywhere in tracked files**

Run:
```bash
grep -rn "skills/engineering/\(create-and-enter\|exit-and-dispose\|setup-worktree\)" --include="*.md" --include="*.json" . | grep -v "docs/superpowers/" || echo "CLEAN"
```
Expected: `CLEAN` (matches inside `docs/superpowers/` specs/plans are historical and fine).

- [ ] **Step 4: marketplace lists exactly two plugins**

Run: `python3 -c "import json;print([p['name'] for p in json.load(open('.claude-plugin/marketplace.json'))['plugins']])"`
Expected: `['threadsafe', 'tss-git-skills']`

- [ ] **Step 5: (Manual) Re-install and smoke-test**

In a Claude Code session:
```
/plugin marketplace add /home/neil/code/threadsafe/claude-skills
/plugin install tss-git-skills@threadsafe
```
Confirm `tss-git-skills:setup-worktree-discipline` / `:create-and-enter-worktree` / `:exit-and-dispose-worktree` are listed, and the worktree skills no longer appear under `threadsafe:`.

---

## Self-Review

**Spec coverage:**
- Marketplace gains second plugin entry → Task 2. ✓
- `tss-git-skills` plugin name / namespace → Tasks 1–2 (manifest), Global Constraints. ✓
- Flat `skills/`, no `skills`/`hooks`/`commands` keys → Task 1 Step 3. ✓
- Three skills moved (not duplicated), scripts preserved → Task 1 + Task 6 Step 2. ✓
- Branch discipline stays in `setup-worktree-discipline` (no new skill) → no task creates one; intentional. ✓
- threadsafe `plugin.json` de-lists the three → Task 2. ✓
- Top-level README + engineering README updated → Task 4. ✓
- New plugin README → Task 3. ✓
- Project CLAUDE.md reframed (marketplace + tss- convention + subtree rule) → Task 5. ✓
- Verification (JSON valid, no old refs, re-install) → Task 6. ✓
- Out of scope: other domains, global `~/.claude/CLAUDE.md` — not touched. ✓

**Placeholder scan:** No TBD/TODO; every edit shows exact before/after text or full file content.

**Type/name consistency:** Plugin name `tss-git-skills`, source `./tss-git-skills`, and the three skill dir names are identical across all tasks.

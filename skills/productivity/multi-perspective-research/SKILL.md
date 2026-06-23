---
name: multi-perspective-research
description: Research a topic from multiple adaptively-chosen expert lenses in parallel, then map where they agree, clash, and collectively miss. Use when the user wants a multi-perspective, multi-angle, or "red-team / steelman both sides" investigation; wants viewpoints reconciled (practitioner vs academic vs skeptic vs economist vs historian, etc.); asks for a contradiction map, consensus vs blind-spot analysis, or a decision briefing that weighs competing expert views. Prefer this over plain deep-research whenever the value is in the *tension between viewpoints*, not just a single synthesized answer. Triggers on phrasings like "research X from every angle", "what would different experts say", "steelman and attack this", "where do the experts disagree", "give me a briefing that accounts for bias".
---

# Multi-Perspective Research

Investigate a topic the way a good analyst does: not from one vantage point, but from
the several lenses that actually expose its tensions — then reconcile them. The payload
is the **friction between viewpoints**: where every lens agrees (load-bearing truth),
where they clash (the live debate), and where none of them looked (the field's blind spot).

This is a **map-reduce over perspectives**, not a roleplay:

```
adaptive lens selection → parallel grounded research (one worker per lens)
   → reduce: contradiction map + synthesis → adversarial verification gate
```

The defining choice that makes this work: each lens is researched against **real sources
in parallel**, so its "strongest evidence" is *cited*, not imagined. Simulated experts
hallucinate confident evidence; grounded ones can be checked.

## When to reach for this vs. plain research

- Use **`deep-research`** (if available) when the user wants *one* well-sourced answer.
- Use **this skill** when the user wants competing expert views held in tension,
  a contradiction/consensus/blind-spot map, or a briefing that survives "which voice
  is biasing this?". If the topic is a settled factual lookup, this is overkill — say so.

## Step 0 — Scope the topic before fanning out

A vague topic produces five vague perspectives. If the topic is underspecified (audience,
decision at stake, time horizon, geography, or which sub-question matters), ask **2–3**
sharp clarifying questions first. Also surface the user's *role* if relevant — the
actionable output should be tailored to what they'll do with it.

## Step 1 — Select the lenses adaptively (don't default to a fixed roster)

The biggest upgrade over canned multi-perspective prompts: **choose the perspectives that
maximize coverage and tension for *this* topic.** A monetary-policy question rewards an
Economist and a Central-Banker; a clinical question rewards a Bench Researcher, a Frontline
Clinician, and a Patient/Payer; an infra-migration question rewards an Engineer, an SRE,
and a Finance/Procurement lens. Forcing "follow the money" onto a topic with no money in it
wastes a slot.

Pick **3–6 lenses** (default 5) that are:
- **Genuinely adversarial to each other** — if two lenses would just nod along, drop one.
- **Differently *grounded*** — they read different evidence (field experience vs. peer
  review vs. market signals vs. historical record), so they'll surface different facts.
- **At least one true contrarian** — a lens whose job is to argue the mainstream is wrong.

The classic five — Practitioner, Academic, Skeptic, Economist, Historian — are a fine
**fallback** when nothing topic-specific is more generative, not a requirement. For a
catalog of lenses and what each earns its place for, see
`references/perspective-library.md`.

State the chosen lenses and a one-line rationale for each before fanning out, so the user
can veto or swap before the (more expensive) parallel research runs.

## Step 2 — Map: research each lens in parallel

Launch **one subagent per lens, all in a single message** so they run concurrently — this
is the whole point of the parallel architecture; don't serialize them. Use the
`general-purpose` agent. Give each worker the brief below, filled in for its lens.

If the `deep-research` skill is available to the worker, tell it to use that skill for the
grounded search/verify loop. If not, the brief is self-contained.

> **Worker brief (one per lens):**
>
> You are researching **[TOPIC]** through a single lens: **[LENS NAME]** — [one-line
> description of who this is and what they pay attention to].
>
> Ground everything in real sources. Search broadly, fetch the primary/strongest sources
> you find, and prefer evidence this lens would actually cite (field data, peer-reviewed
> work, market/financial signals, historical record — whatever fits the lens). If the
> `deep-research` skill is available, use it for the search-and-verify loop.
>
> Return:
> - **Core position** — what this lens concludes about the topic, and why.
> - **Strongest cited evidence** — the 2–4 best pieces, each with a source link and a
>   one-line note on its quality (and any conflict of interest in the source).
> - **The one thing only this lens sees** — the insight the other lenses would miss.
> - **What this lens concedes** — points it grants to opposing views (this feeds the
>   consensus check downstream).
> - **Confidence + gaps** — how solid its case is, and what evidence would strengthen or
>   break it. Flag any claim you could not source.
>
> Don't strawman. Build this lens's *strongest* version. Be concise; links over prose.

## Step 3 — Reduce: contradiction map + synthesis

Now that all workers have returned, do the analysis in your own context — you can see every
lens at once. This is where the value concentrates:

- **Clashes.** Where do two+ lenses make claims that can't both be true? State each
  conflict with the specific clashing claims and which evidence backs each side.
- **Load-bearing consensus.** What does *every* lens concede — including the contrarian?
  When opponents agree, it's likely true; mark these as the foundation.
- **The blind spot.** What did *no* lens examine? This is the field's gap and is often the
  most valuable finding — name it explicitly rather than letting it stay invisible.
- **The pivotal question.** The single question whose answer would resolve the biggest
  clash. Note what evidence would settle it.
- **Synthesis.** A ranked set of findings ordered by **reliability**, each tagged with
  which lenses support and which challenge it, plus one non-obvious connection that only
  appears when you hold all lenses together.

Let the topic dictate how many findings there are — don't pad to hit a number.

## Step 4 — Verify: adversarial gate (not self-grading theater)

Before delivering, actually pressure-test the load-bearing claims — don't just assign
yourself a grade. For each finding you're leaning on:

- **Re-check it against the cited sources.** Does the source actually support the claim,
  or was it over-read / misattributed? Flag anything unsupported and downgrade it.
- **Calibrate confidence** honestly — distinguish "multiple independent lenses + good
  sources" from "one lens asserted it." Express this as a clear high/medium/low (or 1–10
  if the user prefers numbers), with the *reason* for the level.
- **Bias check.** Did one lens dominate the synthesis? Is a source with a conflict of
  interest doing too much work? Rebalance.
- **Missing lens.** Is there a perspective whose absence would change the conclusions? If
  yes, either run it (loop back to Step 2 for that one lens) or name it as a caveat.

If verification materially weakens a headline finding, fix the synthesis — don't ship a
confident claim you just undercut.

## Output — the briefing

Lead with what a decision-maker needs, details underneath:

1. **60-second summary** — the topic with its nuance intact, not just the headline.
2. **Findings, ranked by reliability** — each with supporting/challenging lenses and a
   calibrated confidence level.
3. **The contradiction map** — clashes, load-bearing consensus, and the blind spot.
4. **What to do differently** — concrete and tailored to the user's role/decision.
5. **The frontier question** — the one unknown that would most change the picture.
6. **Sources** — links gathered across lenses, so claims are checkable.

Keep the prose tight and the structure adaptive: if a section is thin for a given topic,
collapse it rather than padding. The reader should be able to trace any claim to a lens
and a source.

# claude-skills

Skills for Claude Code.

## multi-perspective-research

A rearchitecting of the classic four-prompt "simulate 5 experts → contradiction map →
synthesis → peer review" research workflow for today's reasoning models.

Instead of a linear, parametric roleplay chain with a hardcoded persona roster, it runs a
**map-reduce over adaptively-chosen lenses**:

```
adaptive lens selection → parallel grounded research (one worker per lens)
   → reduce: contradiction map + synthesis → adversarial verification gate
```

Key shifts from the 2024-era prompt:

- **Adaptive lens selection** instead of a fixed Practitioner/Academic/Skeptic/Economist/
  Historian roster — the model picks the perspectives that actually expose *this* topic's
  tensions.
- **Grounded, not simulated** — each lens is researched against real sources in parallel
  (delegating to `deep-research` when available), so its "strongest evidence" is cited and
  checkable.
- **Parallel map step** — perspectives are independent, so they fan out as concurrent
  subagents rather than running in sequence.
- **Real verification gate** instead of self-graded "what would a professor say" theater —
  load-bearing claims are re-checked against their sources and confidence is calibrated.
- **Goal-driven output** instead of arbitrary micro-templates (no forced "exactly 5
  findings, 2 sentences each, rate 1–10").

What's preserved from the original because it's genuinely good: the **contradiction map** —
where every lens agrees is load-bearing, where none looked is the field's blind spot.

See [`multi-perspective-research/SKILL.md`](multi-perspective-research/SKILL.md).

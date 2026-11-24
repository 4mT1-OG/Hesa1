# Response Quality–Time–Token Measurement Feature

Status: proposed feature plan for review. This is an operational measurement framework, not a claim that hidden model reasoning can be observed directly.

## Goal
Reward accurate, useful completion while making task duration and token use visible. A longer task should produce proportionally better verified output; if it is not progressing, return a useful best-effort result and state what remains rather than waiting silently.

## Framework
Use a three-axis Quality–Time–Token (QTT) scorecard. Keep the dimensions visible rather than collapsing them into one score at first.

1. Quality per token: reward supported, task-complete information relative to the tokens used. Efficiency counts only after the answer passes the quality floor.
2. Token use versus elapsed time: record token counts and wall-clock duration. Provider-reported reasoning-token counts or reasoning duration are recorded only if actually exposed; do not infer hidden reasoning time from total latency.
3. Quality versus time: compare verified quality with time-to-first-useful-result and time-to-final-result. For the same scoped task, additional time should improve quality or completion; otherwise identify a plateau and deliver the best result so far.

The integrated view is a Pareto frontier: prefer a run when it is at least as accurate and complete, and no slower or more token-heavy, than alternatives. Do not call a faster/shorter answer better when its quality falls below the gate.

## Per-task measurement record
Capture these fields at the orchestration/tool layer, not by guessing from prose:

- Task ID, task class, acceptance criteria, model/provider, tool strategy, and evaluation rubric version.
- Start timestamp; first useful response timestamp; final response timestamp.
- Wall-clock time to first useful result and to completion.
- Tool-call duration and external wait time where available. Label these separately from model generation time.
- Input tokens, output tokens, total tokens, and provider-reported reasoning tokens/duration if returned. Mark unavailable fields as unavailable; do not estimate them as facts.
- Quality score, evaluator type (gold/reference, automated checks, human review), confidence, and any critical failure flags.
- Scoped acceptance criteria completed and remaining at each two-minute checkpoint.

## Quality rubric (0–100)
Start with a task-specific rubric using these default weights:

- Factual accuracy and evidence support: 40 points.
- Completion against explicit acceptance criteria: 25 points.
- Relevance and usefulness: 15 points.
- Uncertainty calibration and clear limits: 10 points.
- Instruction-following and safety: 10 points.

Quality floor: 85/100 for a result to receive token-efficiency credit. A critical factual error, fabricated evidence, or material safety/instruction failure fails the gate regardless of brevity. Adjust weights by task type before scoring; do not change them after seeing a run's score.

Use a reference answer or executable checks where possible. Use blinded human review on a sample to calibrate automated evaluators. The assistant's self-rating alone is not ground truth.

## Two-minute progress rule
For work with explicit, scorable acceptance criteria, compute progress as the weighted share of criteria completed and verified—not a subjective feeling. At approximately 2 minutes, target at least 85–90% of the scoped deliverable completed, or send a useful interim result with the verified percentage, remaining items, and blocker. Do not invent a completion percentage for open-ended work: report concrete completed milestones instead.

For work likely to exceed 2 minutes, emit a concise checkpoint every 2 minutes with: completed, remaining, current quality risks, and whether more time is likely to improve the outcome. Ask the user to reprioritize only when priorities genuinely affect the next action.

## Derived metrics
Report the underlying measures first. Use ratios as diagnostics, with the quality gate applied:

- Quality per 1,000 output tokens = quality score / output tokens × 1,000, reported only for runs that pass the quality floor.
- Supported-claim density = independently verified supported claims / 1,000 output tokens.
- Quality improvement per extra minute = score difference / additional wall-clock minutes across comparable runs of the same task.
- Token efficiency = output tokens per verified acceptance criterion completed.
- First-useful-result latency and final-completion latency, reported separately.

Never compare unlike tasks or different rubrics as if they were controlled runs. Do not optimize a ratio by omitting required facts or stopping before verification.

Shared precision/accuracy gate: follow [[context-extraction-workflow/WORKING-DESIGN#Precision, accuracy, and scale gate|WORKING-DESIGN]] for source fidelity, conflict handling, independent final checks, and promotion/commit readiness. Efficiency credit follows—not substitutes for—that gate.

## Workflow
1. Scope the task into acceptance criteria and classify it (quick response, research, coding/automation, or high-stakes).
2. Select and freeze the task-specific rubric and the quality floor before starting.
3. Start timing; log token/provider metadata and tool durations when available.
4. Produce the earliest useful answer; label uncertainty and unresolved checks.
5. At each two-minute boundary, calculate verified progress. Deliver a checkpoint if unfinished.
6. Verify against criteria and score quality. If it fails the quality floor, fix critical gaps before claiming completion; if blocked, deliver the best safe partial result and exact blocker.
7. Record metrics and compare against similar tasks. Identify whether extra time improved quality, completion, or confidence.
8. Review Pareto-dominated runs and adjust workflow/tool choice—not the rubric—to improve future performance.

## Task execution framework: Plan → Research → Validate → Correct

Use this loop for each task; keep a live acceptance checklist so progress is measurable rather than summarized vaguely.

### 1. Plan
- State the deliverable, acceptance criteria, risk level, deadline/time budget, and known dependencies.
- Break work into verifiable milestones; estimate the smallest useful first result.
- Choose the fastest safe path and identify what evidence or test will prove completion.
- For ambiguous low-risk tasks, state a reasonable assumption and proceed. Ask only when the answer changes the next action or risk.

### 2. Research
- Gather primary evidence first; capture source paths, URLs, timestamps, and relevant excerpts.
- Separate observed facts, inference, and unknowns. Check freshness and conflicts for material claims.
- Stop broad research when the next lookup is unlikely to change the decision; surface the evidence already sufficient for a best-effort result.
- Track elapsed time and tokens. At the two-minute boundary, report verified progress and the next action if unfinished.

### 3. Validate
- Test every acceptance criterion against evidence, executable checks, or an independent reviewer—not self-confidence alone.
- For code/config, run syntax checks and relevant tests; for factual research, verify claims against sources; for external actions, verify the resulting state.
- Record failures, test coverage, and confidence. Keep validation time separate from research/tool wait time.

### 4. Correct
- Fix the highest-impact failed criterion first; make the smallest targeted change.
- Rerun the failed check and regression checks affected by the change.
- Re-score quality and record added time/tokens. If further work is blocked or has low expected value, deliver the best verified partial result and exact blocker instead of looping.
- After two repeats without new evidence or progress, state plainly that the task cannot be advanced and name the missing dependency/input.

### 5. Deliver and learn
- Deliver the artifact/result first, followed only by verification and unresolved blockers; avoid process recaps.
- Compare quality, completion, latency, and tokens against similar tasks. Keep the quality floor fixed; optimize time/tokens only after it passes.

## Implementation phases

### Phase 1 — Instrumentation and manual rubric
- Add a structured JSONL/CSV record format for timestamps, model/provider, token counts, tool durations, acceptance criteria, and evaluation results.
- Start with a small, human-labeled set spanning quick, research, and multi-step tasks.
- Log missing telemetry explicitly; do not synthesize hidden reasoning metrics.

### Phase 2 — Checkpoint and evaluator
- Add a two-minute checkpoint mechanism for tasks with measurable acceptance criteria.
- Add task-specific automated checks (tests, citation/reference checks, required-field checks) and human review sampling.
- Calibrate the rubric and evaluator agreement before relying on automated scores.

### Phase 3 — Comparison view
- Show quality, time-to-first-useful-result, total latency, input/output tokens, and verified progress separately.
- Plot comparable runs on quality-versus-time and quality-versus-token axes; highlight the Pareto frontier.
- Do not rank tasks by one blended score until evidence shows the weights are stable and useful.

## Acceptance criteria
- Every scored run has a task class, fixed rubric, token/latency availability flags, and an evaluator source.
- The system distinguishes total wall-clock latency, tool time, and provider-reported reasoning metrics.
- Two-minute progress is based on verified acceptance criteria; open-ended work reports milestones without fake percentages.
- No efficiency reward is given below the quality floor or after a critical failure.
- Repeated benchmark runs can show whether an added minute or added tokens improved verified quality/completion.
- A human can inspect the evidence behind every score and progress percentage.

## Known limits and safeguards
- A universal 85–90% completion target within two minutes is not feasible for every task. Apply it to scoped work with measurable criteria; otherwise give concrete milestone updates.
- Hidden reasoning duration is generally unavailable. Wall-clock response time is not reasoning time.
- Automated quality scores can be gamed or miscalibrated. Keep evidence, audit samples, and retain human review for consequential tasks.
- If the environment does not expose token usage or timestamps, say so and collect only what is observable.

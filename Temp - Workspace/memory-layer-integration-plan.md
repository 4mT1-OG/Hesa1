---
title: Memory Layer Integration Plan
tags: [plan, memory, obsidian, workflow]
status: active-review
---

# Memory Layer Integration Plan

## Goal
Create a clear, efficient memory layer that can be shared across Hermes processes, with reviewable work, low duplication, and conductor approval before Git commits. Preserve the rule: never write to `Read - Only/`.

## Current project limit
Active Temp projects: 1 — memory extraction/context management. The QTT plan is its evaluation method, not a second project. Keep at most 3 active Temp projects; archive or promote before starting another.

## Work pattern
Use three files only for significant work:
- `task_plan.md`: goal, phases, decisions, blockers, acceptance checks; update after each phase.
- `findings.md`: source-linked research and observations; do not put unverified research into the plan.
- Deliverable: actual note, code, or verified result.

For small tasks, use a concise checklist instead of creating three files. Keep all reviewable artifacts in `Temp - Workspace/`; ephemeral scratch stays in Hermes scratch.

## Plan and phases

### 1. Inventory and baseline
- [x] Review `Read - Only/`, `Read - Write/`, and `Temp - Workspace/` individually.
- [x] Read built-in `MEMORY.md` and `USER.md` and relevant Obsidian skill/reference.
- [x] Identify duplicate Hermes Agent project overview; remove the duplicate only after confirming exact content.
- [x] Repair the audit script to match current folder names and rerun it.
- [ ] Record current Git branch, working-tree changes, and ignore rules before proposing commits.
- [ ] Confirm the target Hermes Edge host/profile and its actual memory/session paths; do not assume the local default profile is Edge.

### 2. Define canonical ownership and overlap policy
- Built-in Hermes `MEMORY.md`/`USER.md`: compact, operational facts and durable user preferences used directly by Hermes.
- `Read - Only/`: stable, user-approved core principles; read-only for the agent.
- `Read - Write/`: maintained project documentation, decisions, procedures, and approved memory architecture.
- `Temp - Workspace/`: drafts, source extracts, test fixtures, plans, and unapproved candidates; never canonical memory.
- Skills: reusable procedures loaded only when relevant. Keep detailed procedures in one skill/reference; memory should point to the procedure, not duplicate it.
- Skill internal references: keep one authoritative copy; use links rather than copying the same rules into skill, USER.md, Guide.md, and project notes.
- When content overlaps, retain the shortest canonical statement and link to its fuller source. Do not synchronize or symlink live memory until host/profile and approval semantics are verified.

### 3. Separate the workflows
Keep these as distinct components with shared validation rules:
1. Memory extraction: evidence-linked candidate facts, deduplication, conflict checks, redaction, human approval, promotion.
2. Session compaction: transient context reconstruction, cut-point and token-budget validation.
3. Branch summarization: branch-difference summaries, cumulative file tracking, navigation validation.
4. QTT evaluation: accuracy/coverage gate first; report tokens and wall-clock separately; do not reward efficiency below the quality floor.

Do not extend the lexical `context_pack.py` into a compactor or durable-memory writer without separate specifications and tests.

### 4. Consolidate and simplify
- [ ] Keep one `Read - Write/Projects/Hermes Agent/Overview.md`; maintain other active projects in distinct folders.
- [ ] Keep `Read - Write/Memory/Memory Architecture.md` as the provider/ownership decision record; remove duplicated architecture prose from overviews and link to it.
- [ ] Keep one source of detailed extraction policy: the proposed extraction skill/reference after it passes validation. Until then, `WORKING-DESIGN.md` is the Temp source of truth.
- [ ] Reduce skill overlap only after checking each skill's unique triggers and procedures. Do not merge or delete skills based on names alone.
- [ ] Keep workflow templates minimal; generate a task plan only for significant work.

Shared precision/accuracy gate: follow the authoritative scale and double-check requirements in [[context-extraction-workflow/WORKING-DESIGN#Precision, accuracy, and scale gate|WORKING-DESIGN]]. Verify source support and destination consistency before promotion or commit; do not use compression ratio as a quality proxy.

### 5. Validate before elevating skills
Test-first acceptance checks:
- Extraction: exact source spans, atomic facts, unsupported-claim rejection, duplicate/conflict handling, expiry/review hints, redaction, and write-path guard.
- Compaction: legal cut points, recent-context preservation, split turns, tool-call/result integrity, repeated compaction, fallback IDs, and accurate `tokensBefore`.
- Branch summaries: common ancestor, abandoned-branch-only collection, newest-first budget, nested summaries, cumulative read/modified files, and no lost/duplicated entries.
- Serialization: visible messages/tool calls/results only; preserve truncation markers; never infer hidden reasoning or treat omitted output as evidence.
- Efficiency: compare equivalent runs; quality/critical-fact gate must pass before token or latency savings count.
- Operational safety: no writes to `Read - Only/`; all review outputs stay in `Temp - Workspace/`; no live memory/provider changes without explicit approval.

Skill elevation gate: real Hermes-session validation, labeled evaluation, useful precision/recall, redaction checks, repeated QTT measurements, stable entry point, clear module boundaries, troubleshooting guidance, and no unresolved critical defects. Until all pass, keep as a Temp prototype/reference.

### 6. Troubleshoot and correct
For each failure, record symptom, evidence, likely cause, test, and correction in `findings.md`. Fix the highest-impact verified cause first, rerun the failing test and regression set, then update the plan. After two attempts without new evidence/progress, report the blocker instead of repeating the same action.

### 7. Commit gate
- Re-run the vault audit; require 0 duplicate basenames, 0 duplicate content, 0 unresolved links, and 0 likely-secret hits in scanned writable notes.
- Independently inspect files excluded from secret scanning, especially Temp, before promoting anything.
- Review `git status`, `git diff --check`, changed-file list, and exact diff. Confirm ignored Temp artifacts are not accidentally included.
- Ask the conductor to approve the specific changeset before commit/push. No automatic commit or push.

## Current findings and risks
- The two Hermes Agent overviews in `Read - Write/Projects/` and `Read - Write/Projects 1/` were duplicates; the duplicate was removed.
- A root `00 Home.md` duplicated `Read - Write/00 Home.md`; the root duplicate was removed.
- Audit now reports 13 Markdown notes, 0 duplicate basenames/content, 0 likely-secret hits, and 2 unresolved wikilinks involving `context_pack.py`. Fix the link resolver or use an Obsidian-valid link, then rerun.
- The audit report still contains stale statements about no Git repository/commit, old `RO/RW/Temp` paths, and old folder references; update the report generator and rerun before relying on it.
- Git status showed `.obsidian/plugins/git-vault-sync/data.json` modified; inspect that exact diff before commit.
- `Temp - Workspace/` is Git-ignored, so approved deliverables must be deliberately promoted to `Read - Write/` before they can be committed.
- The current local built-in memory path is not verified as the Hermes Edge profile. Confirm before connecting or synchronizing.

## Status
Current phase: baseline and ownership definition. No Read-Only content was changed. No commit or push was made.

## Next actions
1. Fix the audit script's path/link handling and stale report text; rerun it to zero findings.
2. Inspect the modified Obsidian Git plugin settings diff; do not stage it without conductor review.
3. Confirm Edge host/profile and memory path.
4. Process `WORKING-DESIGN.md` into separate extraction, compaction, and branch-summary plans without duplicating the shared validation policy.
5. Build synthetic tests before changing the prototype; keep all results in Temp.

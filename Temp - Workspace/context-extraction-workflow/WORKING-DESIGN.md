# Context extraction and scratch review workflow — working draft

Status: exploratory; no production code or vault/core-memory changes made.
Priority selected: context extraction/compression tools and scratch review workflow.

## Goal
Extract a small, accurate, reviewable set of durable facts and active decisions from long sessions, while reducing prompt context without sacrificing retrieval accuracy.

## Safety and review rules
- Put drafts, source extracts, test outputs, and review candidates under this temporary workspace.
- Do not write into any `Read Only` folder. Read/search is permitted; all writes go elsewhere.
- Keep secrets and credentials out of extracted notes and evaluation fixtures.
- Preserve source references (session/file and message or line range) for every candidate fact.
- Require human approval before promoting candidates into durable memory or the Obsidian vault.

## Proposed pipeline
1. Ingest a transcript or note file; record its provenance and timestamp.
2. Redact secrets/obvious sensitive values before model processing.
3. Extract atomic candidate records: fact, preference, decision, open task, source span, confidence, and expiry/review hint.
4. Deduplicate against existing approved memory; mark conflicts instead of silently choosing one.
5. Compress candidates into a bounded summary with links to the source spans.
6. Stage output in a scratch review folder, separate from durable memory.
7. Human review: approve, edit, reject, or defer each candidate.
8. Promote only approved items to an explicitly writable memory destination.

## Memory-extraction execution framework: Plan → Research → Validate → Correct

Apply this loop to every extraction or context-compaction task. Keep the complete draft packet in `Temp/`; promote nothing until the user approves it.

### Plan
- Define the question, source scope, intended memory destination, sensitivity constraints, and acceptance criteria before extracting.
- Set a time/token budget and the smallest useful deliverable (for example, an evidence-linked candidate list).
- Treat `RO/` as read-only; stage all candidates in `Temp/` and target `RW/` only after approval.

### Research
- Read the specified session/files; record source IDs, timestamps, and exact message/line spans.
- Redact secrets before model processing; separate direct statements from inference.
- Extract atomic candidates: fact/preference/decision/task, source span, confidence, expiry/review date, and proposed destination.
- Check approved memory for duplicates and conflicts; preserve both claims with provenance when unresolved.

### Validate
- Verify every candidate against its cited source span and the current approved memory; reject unsupported or context-stripped claims.
- Score precision, recall against a labeled sample, critical-fact omissions, conflict handling, redaction, and source traceability.
- Report input/output tokens and wall-clock time separately. Use provider-reported reasoning metrics only when available.
- Require human review before any durable write; a high compression ratio never overrides correctness or safety.

### Correct
- Fix the highest-impact issue first: unsupported claim, missed critical fact, bad redaction, duplicate, conflict, or broken source link.
- Rerun the affected checks and the whole candidate audit after material edits.
- If evidence is missing, mark the item unknown or ask for the exact source; do not fill gaps by guessing.
- After two attempts with no new evidence or progress, state the blocker and stop looping.

### Deliver
- Present the candidate packet and verification result first, then only unresolved blockers and the requested approval.
- Keep rejected/uncertain candidates out of durable memory. Apply approved changes to `RW/` only; never write to `RO/`.

## Evaluation: accuracy first, efficiency second
Correctness must pass a minimum gate before token efficiency is rewarded.

- Fact precision: supported extracted claims / all extracted claims.
- Fact recall: correctly retained reference facts / all reference facts.
- Unsupported-claim rate and critical-fact omission count.
- Token reduction: 1 - compressed input tokens / original input tokens.
- Useful accuracy density: supported reference facts retained per 1,000 input tokens.
- Record input/output token counts, model, wall-clock latency, and provider-reported reasoning tokens when available. Do not label total latency as reasoning time; many providers do not expose reasoning duration or tokens.
- Compare only runs with the same task, source, model/settings, and evaluation rubric; report the accuracy/latency/token trade-off rather than collapsing it into one score prematurely.

## Precision, accuracy, and scale gate

Treat this as the shared quality gate for extraction, compression, integration, and any future commit:

1. Preserve provenance for every retained claim: exact source, timestamp or line/message span, and transformation history.
2. Keep atomic facts separate; deduplicate exact repeats, but do not merge near-matches or conflicting claims without evidence. Preserve unresolved alternatives with provenance.
3. Mark facts, decisions, preferences, inference, and unknowns distinctly. Never increase certainty during compression.
4. Validate every compressed statement against its source and the destination context; check that critical constraints, exceptions, dates, and negations survive.
5. Independently re-check the final artifact against the acceptance criteria, links, and source material before promotion or commit. Report checks performed and unresolved issues; do not claim validation from self-confidence.
6. At scale, use deterministic IDs, bounded batches, checksums/versioned inputs, and reversible transformations so omissions and changes can be traced and revalidated.
7. Efficiency is evaluated only after precision, critical-fact recall, conflict handling, and safety pass their acceptance thresholds.

## Initial prototype boundaries
- Start offline/local-first with non-sensitive fixture transcripts.
- Prototype extraction and scoring as small scripts in this temporary workspace.
- Do not alter Hermes source, global config, API credentials, approved memory, or vault contents without a separately approved change.

## Session context management reference: compaction and branch summarization

Status: reference design supplied by the user, based on Pi behavior. Treat Pi types, commands, and source files as unverified for Hermes until checked against Hermes session storage and implementation.

### Compaction behavior
- Find a cut point by walking backward from the newest entry until the recent-message token budget is reached; normally preserve complete turns and tool-call/result pairs.
- Summarize entries before the kept boundary and append a compaction entry containing the summary and `firstKeptEntryId`.
- Rebuild context as system prompt + summary + entries from `firstKeptEntryId` onward.
- On repeated compaction, summarize from the previous kept boundary, falling back to the entry after the previous compaction if that ID is no longer on the path.
- Recalculate `tokensBefore` from the rebuilt context actually being replaced.
- If one turn exceeds the budget, treat it as a split turn: summarize its prefix separately and merge with the history summary.
- Valid cut points: user messages, assistant messages, bash-execution messages, and custom messages; never leave a tool result detached from its call.

### Branch summarization behavior
- Trigger when navigating from an old branch position to a different target branch; carry a summary of the abandoned branch into the target context.
- Find the deepest common ancestor of the old and target positions. Collect entries from the old leaf back to, but not including, that ancestor.
- Select entries newest-first within the token budget, summarize them using the same structured summary format as compaction, then append a branch-summary entry at the navigation point.
- Reference entry fields: type, id, parentId, timestamp, summary, fromId; optional usage/fromHook; implementation-specific details. Default details track `readFiles` and `modifiedFiles`.
- Cumulative file tracking must combine file operations in raw tool calls with file details carried by prior compaction and branch-summary entries, including nested branches.

### Shared summary format
- Goal
- Constraints & Preferences
- Progress: Done, In Progress, Blocked
- Key Decisions
- Next Steps
- Critical Context
- read-files and modified-files lists

### Serialization and evidence limits
- Serialize messages as labeled user text, assistant-visible response, tool calls, and tool results so the summarizer treats them as source material rather than a conversation to continue.
- Preserve explicit truncation markers when tool results are capped (the supplied Pi behavior uses 2,000 characters). Never treat omitted tool output as evidence.
- Do not include or reconstruct hidden assistant reasoning. Summaries must be based on user-visible messages, tool calls/results, and verifiable artifacts.
- File tracking in summaries is a convenience index, not proof of current filesystem state; verify consequential changes against the working tree or Git diff.

### Separation from durable memory
Compaction and branch summaries are transient context-reconstruction mechanisms. They are not approved Hermes MEMORY.md/USER.md updates. Durable memory candidates still require source spans, redaction, conflict checks, human approval, and an explicit promotion step.

### Required validation before implementation
1. Verify Hermes has equivalent branch/path entry semantics and a real branch-navigation trigger; do not assume Pi's `/tree` or TypeScript types exist in Hermes.
2. Build tests first for common-ancestor selection, old-branch-only collection, newest-first budget selection, repeated/nested summaries, missing kept-entry fallback, split turns, tool-call/result integrity, file-operation accumulation, and truncation markers.
3. Check summary placement and rebuilt-context ordering against actual serialized sessions; ensure no message is duplicated or lost.
4. Compare `tokensBefore` with the tokenizer or provider usage for the rebuilt context, and mark unavailable token telemetry explicitly.
5. Run redaction and source-provenance checks; stage all outputs in `Temp/` for review, never `Read Only`.

## Open design choices for the next milestone
- Which Hermes profile/host and session store is the target? The default local memory path alone does not establish the Edge agent's session location.
- Does Hermes expose branch navigation and branch-summary entries, or should this remain a standalone design/prototype?
- First implementation deliverable: a labeled test fixture set and format mapping, before changing the existing lexical `context_pack.py` prototype.

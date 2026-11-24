---
title: Persistent Memory Architecture
tags: [memory, architecture, hermes]
status: evaluating
---

# Persistent Memory Architecture

## Current state
- Hermes built-in `MEMORY.md` and `USER.md` are enabled and profile-scoped.
- No external memory provider is active.
- Installed candidates: ByteRover and RetainDB. Other catalog providers may be evaluated later.
- One external memory provider can be active at a time; built-in memory remains alongside it.

## Intended design
- Built-in memory: compact, stable preferences and operating facts.
- Obsidian vault: human-readable project documentation, decisions, research, and API allowance records.
- External provider (optional): semantic retrieval and cross-profile sharing only if a pilot demonstrates value.

## Pilot criteria
- Save and retrieve a fact in a fresh session.
- Test intended channel/profile continuity and isolation.
- Measure injected context tokens and provider/API usage.
- Verify privacy, retention, export, deletion, and free-tier terms.
- Keep credentials outside notes and version control.

## References
- [Hermes persistent memory](https://hermes-agent.nousresearch.com/docs/user-guide/features/memory)
- [Hermes memory providers](https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers)

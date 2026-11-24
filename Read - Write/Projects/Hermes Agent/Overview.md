---
title: Hermes Agent Development
tags: [project, hermes]
status: active
---

# Hermes Agent Development

## Goal
Build a reliable agentic workflow around Hermes Agent, primarily using free-tier API keys, with local execution where suitable.

## Current environment
- Hermes Agent v0.23.3.
- Default model is remote; local Qwen GGUF is served by llama.cpp at `http://127.0.0.1:8080/v1`.
- Local server context is configured to 64,000 tokens.
- Hermes alias `local-qwen` points to the local server; remote default remains unchanged.
- Built-in memory and user profile are enabled; no external memory provider is active.
- ByteRover and RetainDB plugins are installed but not configured as the memory provider.

## Priorities
1. Verify local model use from Hermes and keep its context cap at 64K without constraining remote models.
2. Audit/update dependencies cautiously and run relevant tests.
3. Evaluate persistent memory providers for free allowances, privacy, cross-platform sharing, and context cost.
4. Track API free-tier quotas and reset windows; never store credentials here.

## Decision log
- Keep built-in memory as the short, curated core until an external memory provider is selected.
- Use this vault as a human-readable project notebook; it is not yet synchronized with Hermes memory.

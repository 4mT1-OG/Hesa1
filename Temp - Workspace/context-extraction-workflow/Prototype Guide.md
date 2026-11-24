# Context extractor MVP

This is a temporary, local-first prototype. It uses only Python's standard library and makes no API calls.

## Run

```sh
python3 context_pack.py INPUT.md [OTHER.jsonl ...] \
  --query 'terms describing needed context' \
  --max-tokens 1800 \
  --output "$HOME/.hermes/cache/scratch/context-extraction-workflow/review/context-packet.md"
```

The script writes generated packets only under `~/.hermes/cache/scratch` and rejects paths inside `RO` or `Read Only`. Copy any packet selected for human review into the Obsidian vault's `Temp/` folder; do not promote unreviewed output to `RW/` or `RO/`.

## What it does

- Reads Markdown as paragraph/heading chunks and JSONL as message records.
- Ranks chunks by deterministic lexical overlap with the query.
- Copies selected text verbatim with source filename and line-number provenance.
- Estimates tokens as roughly one per four characters; this is not a tokenizer or provider usage count.
- Makes no semantic claims, summaries, or memory promotions. A human reviews the output before it is used.

## Limitations / next checks

- Lexical matching can miss relevant paraphrases and may rank repeated terms highly.
- Tested compatibility with one short real Hermes session JSONL export only; broader export variation is not established.
- Heuristic redaction covers common credential labels, authorization headers, bearer/JWT and several token formats, PEM private keys, and email addresses. Synthetic tests pass; this is not comprehensive PII/secret detection, so inspect outputs and never treat it as a security guarantee.
- Parsed the current Hermes JSONL session format (3 records, plain string `content` fields) and generated a scratch packet from one lexical hit. The initial query with unrelated terms correctly produced no packet.
- No gold-labeled accuracy evaluation exists yet.
- Before durable use, test broader Hermes export variations, improve deduplication, and measure precision/recall, token savings, and wall-clock latency separately.

## Verification performed

- Python compilation passed.
- Synthetic Markdown and JSONL inputs produced a source-linked packet; a zero-match unrelated block was excluded.
- Attempts to write outside scratch and inside `Read Only` were rejected.
- A real Hermes session JSONL export generated a packet in scratch without displaying its content in tool output.
- Synthetic secret/email redaction checks passed for API-key labels, authorization headers, bearer tokens, and email addresses.

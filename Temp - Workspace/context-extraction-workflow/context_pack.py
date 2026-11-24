#!/usr/bin/env python3
"""Build a deterministic, source-linked context packet from Markdown or JSONL.

This is retrieval/selection, not semantic summarization. Selected text is copied
verbatim so reviewers can inspect evidence before promoting any memory.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path

SCRATCH_ROOT = (Path.home() / ".hermes" / "cache" / "scratch").resolve()
WORD_RE = re.compile(r"[\w'-]+", re.UNICODE)
STOPWORDS = {
    "about", "after", "again", "also", "and", "are", "because", "been",
    "before", "being", "but", "can", "could", "did", "does", "for",
    "from", "had", "has", "have", "her", "here", "him", "his", "how",
    "into", "its", "just", "like", "may", "more", "most", "not", "our",
    "out", "over", "she", "should", "some", "such", "than", "that",
    "the", "their", "them", "then", "there", "these", "they", "this",
    "those", "through", "under", "use", "used", "using", "was", "were",
    "what", "when", "where", "which", "while", "who", "will", "with",
    "would", "you", "your",
}
SECRET_LABEL_RE = re.compile(
    r"(?i)(\b[\w.-]*(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|"
    r"password|passwd|secret)\b\s*[:=]\s*)(\"[^\"]*\"|'[^']*'|[^\s,;]+)"
)
AUTH_HEADER_RE = re.compile(r"(?im)(\bAuthorization\b\s*[:=]\s*)[^\r\n]+")
BEARER_RE = re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}")
TOKEN_RE = re.compile(r"\b(?:sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{16,}|github_pat_[A-Za-z0-9_]{16,}|xox[baprs]-[A-Za-z0-9-]{10,})\b")
JWT_RE = re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b")
EMAIL_RE = re.compile(r"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b")
PRIVATE_KEY_RE = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.DOTALL)


def redact(text: str) -> str:
    """Heuristically redact common credentials and email addresses before output."""
    text = PRIVATE_KEY_RE.sub("[REDACTED:PRIVATE_KEY]", text)
    text = AUTH_HEADER_RE.sub(r"\1[REDACTED:AUTH]", text)
    text = BEARER_RE.sub("Bearer [REDACTED:TOKEN]", text)
    text = TOKEN_RE.sub("[REDACTED:TOKEN]", text)
    text = JWT_RE.sub("[REDACTED:JWT]", text)
    text = SECRET_LABEL_RE.sub(r"\1[REDACTED:SECRET]", text)
    return EMAIL_RE.sub("[REDACTED:EMAIL]", text)

@dataclass
class Chunk:
    source: str
    start: int
    end: int
    role: str
    text: str

    @property
    def label(self) -> str:
        span = str(self.start) if self.start == self.end else f"{self.start}-{self.end}"
        return f"{self.source}:{span} ({self.role})"


def words(text: str) -> set[str]:
    return {w.casefold() for w in WORD_RE.findall(text) if len(w) > 2 and w.casefold() not in STOPWORDS}


def markdown_chunks(path: Path) -> list[Chunk]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    chunks: list[Chunk] = []
    headings: list[str] = []
    body: list[str] = []
    body_start = 1

    def flush(end_line: int) -> None:
        nonlocal body
        text = "\n".join(body).strip()
        if text:
            prefix = " / ".join(headings)
            if prefix and not text.startswith("#"):
                text = f"[{prefix}]\n{text}"
            chunks.append(Chunk(path.name, body_start, end_line, "note", text))
        body = []

    for i, line in enumerate(lines, 1):
        match = re.match(r"^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$", line)
        if match:
            flush(i - 1)
            level = len(match.group(1))
            headings[:] = headings[:level - 1]
            headings.append(match.group(2).strip())
            body_start = i
            body = [line]
        elif not line.strip():
            flush(i - 1)
            body_start = i + 1
        else:
            if not body:
                body_start = i
            body.append(line)
    flush(len(lines))
    return chunks


def text_value(value: object) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts: list[str] = []
        for item in value:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                for key in ("text", "content", "value"):
                    if isinstance(item.get(key), str):
                        parts.append(item[key])
                        break
        return "\n".join(parts)
    if isinstance(value, dict):
        for key in ("text", "content", "value"):
            if key in value:
                result = text_value(value[key])
                if result:
                    return result
    return ""


def jsonl_chunks(path: Path) -> list[Chunk]:
    chunks: list[Chunk] = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if not raw.strip():
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{path.name}:{line_no}: invalid JSONL: {exc}") from exc
        if not isinstance(obj, dict):
            continue
        msg = obj.get("message")
        record = msg if isinstance(msg, dict) else obj
        role = str(record.get("role") or record.get("speaker") or obj.get("role") or "message")
        content = ""
        for key in ("content", "text", "body", "message"):
            if key in record and not isinstance(record[key], dict):
                content = text_value(record[key])
                if content:
                    break
        if not content:
            content = text_value(obj.get("content")) or text_value(obj.get("text"))
        if content.strip():
            chunks.append(Chunk(path.name, line_no, line_no, role, content.strip()))
    return chunks


def load_chunks(paths: list[Path]) -> list[Chunk]:
    chunks: list[Chunk] = []
    for path in paths:
        if not path.is_file():
            raise ValueError(f"input is not a file: {path}")
        suffix = path.suffix.casefold()
        if suffix in {".jsonl", ".ndjson"}:
            chunks.extend(jsonl_chunks(path))
        else:
            chunks.extend(markdown_chunks(path))
    for chunk in chunks:
        chunk.text = redact(chunk.text)
    return chunks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path, help="Markdown or JSONL transcript/note files")
    parser.add_argument("--query", required=True, help="Terms describing the context you need")
    parser.add_argument("--max-tokens", type=int, default=1800, help="Approximate budget; estimates 1 token per 4 characters")
    parser.add_argument("--output", type=Path, default=SCRATCH_ROOT / "context-extraction-workflow" / "review" / "context-packet.md")
    args = parser.parse_args()

    if args.max_tokens < 1:
        parser.error("--max-tokens must be positive")
    query_terms = words(args.query)
    if not query_terms:
        parser.error("query has no searchable terms after stopword filtering")

    output = args.output.expanduser().resolve()
    if any(part.casefold() in {"ro", "read only"} for part in output.parts):
        parser.error("refusing to write inside protected `RO`/`Read Only` folders")
    if not output.is_relative_to(SCRATCH_ROOT):
        parser.error(f"output must stay under temporary scratch root: {SCRATCH_ROOT}")
    if any(output == p.expanduser().resolve() for p in args.inputs):
        parser.error("output must not overwrite an input file")

    try:
        chunks = load_chunks([p.expanduser().resolve() for p in args.inputs])
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    if not chunks:
        print("error: no readable text chunks found", file=sys.stderr)
        return 2

    ranked: list[tuple[float, Chunk]] = []
    for chunk in chunks:
        terms = words(chunk.text)
        overlap = len(query_terms & terms)
        if overlap:
            score = overlap / len(query_terms)
            ranked.append((score, chunk))
    if not ranked:
        print("No lexical matches found; no packet written.", file=sys.stderr)
        return 1
    ranked.sort(key=lambda item: (-item[0], item[1].source.casefold(), item[1].start))

    budget_chars = args.max_tokens * 4
    selected: list[tuple[float, Chunk, str]] = []
    used_chars = 0
    for score, chunk in ranked:
        text = chunk.text
        cost = len(chunk.label) + len(text) + 24
        if used_chars + cost <= budget_chars:
            selected.append((score, chunk, text))
            used_chars += cost
        elif not selected and budget_chars > len(chunk.label) + 32:
            allowance = budget_chars - len(chunk.label) - 32
            excerpt = text[:allowance].rstrip()
            selected.append((score, chunk, excerpt + "\n[EXCERPT TRUNCATED TO BUDGET]"))
            used_chars = budget_chars
            break

    selected.sort(key=lambda item: (item[1].source.casefold(), item[1].start))
    header = [
        "# Context packet (verbatim excerpts)",
        "",
        f"Query: {redact(args.query)}",
        f"Sources: {len(args.inputs)}; selected chunks: {len(selected)} of {len(chunks)}",
        f"Approx. selected tokens: {math.ceil(used_chars / 4)} (rough character estimate, not tokenizer usage)",
        "Selection: deterministic lexical overlap; text below is copied from sources, not summarized.",
        "",
        "## Selected evidence",
        "",
    ]
    body: list[str] = []
    for score, chunk, text in selected:
        body.extend([f"### {chunk.label} — query overlap {score:.0%}", "", text, ""])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(header + body).rstrip() + "\n", encoding="utf-8")
    print(f"Wrote {len(selected)} source-linked excerpts to {output}")
    print(f"Approx. chars: {used_chars}; rough tokens: {math.ceil(used_chars / 4)}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
